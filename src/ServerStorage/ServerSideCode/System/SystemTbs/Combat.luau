--[[
	Module: Combat
	Description: 战棋伤害与反击结算（服务端唯一写 HP）
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-23
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local MatchStore = require(script.Parent.MatchStore)

local Combat = {}

local KIND_ATTACK = "Attack"
local KIND_COUNTER = "Counter"

--[[
	对目标扣血，死亡则标记
	@param unit table - 单位
	@param damage number - 伤害
	@return number - 实际扣血
]]
local function _applyDamage(unit: any, damage: number): number
	local before = tonumber(unit.hp) or 0
	unit.hp = math.max(0, before - damage)
	if unit.hp <= 0 then
		unit.alive = false
		unit.hp = 0
	end
	return before - unit.hp
end

--[[
	一条命中记录（给客户端回放，不进存档）
	@param attackerId number - 出手方
	@param defenderId number - 受击方
	@param damage number - 实际扣血
	@param remainHp number - 受击后生命
	@param alive boolean - 受击后是否存活
	@param kind string - Attack / Counter
	@return table - combatHit
]]
local function _hit(
	attackerId: number,
	defenderId: number,
	damage: number,
	remainHp: number,
	alive: boolean,
	kind: string
): any
	return {
		attackerId = attackerId,
		defenderId = defenderId,
		damage = damage,
		remainHp = remainHp,
		alive = alive,
		kind = kind,
	}
end

--[[
	执行攻击（含近战反击）
	@param match table - 对局
	@param attacker table - 攻击方
	@param defender table - 防御方
	@return boolean - 是否结算
	@return string? - 失败码
	@return { any }? - 命中列表（表现提示）
]]
function Combat.ResolveAttack(match: any, attacker: any, defender: any): (boolean, string?, { any }?)
	local atkCfg = AERules.GetUnitCfg(attacker.unitType)
	local defCfg = AERules.GetUnitCfg(defender.unitType)
	if not atkCfg or not defCfg then
		return false, "NO_CFG", nil
	end
	local tile = MatchStore.GetTile(match, defender.x, defender.y)
	local defBonus = tile and (tonumber(tile.defBonus) or 0) or 0
	local typeMul = AERules.GetTypeMul(atkCfg.Kind, defCfg.Kind, attacker.unitType, defender.unitType)
	local maxHp = AERules.GetConst("MAX_HP", 100)
	local damage = AERules.CalcDamage(
		tonumber(atkCfg.Atk) or 0,
		attacker.hp / maxHp,
		typeMul,
		1,
		tonumber(defCfg.Def) or 0,
		defBonus / 100
	)
	local applied = _applyDamage(defender, damage)
	local hits = {
		_hit(attacker.id, defender.id, applied, defender.hp, defender.alive == true, KIND_ATTACK),
	}

	local rangeMax = tonumber(atkCfg.RangeMax) or 1
	if defender.alive and rangeMax <= 1 then
		local defRangeMax = tonumber(defCfg.RangeMax) or 1
		if
			defRangeMax <= 1
			and AERules.InRange(defender.x, defender.y, attacker.x, attacker.y, 1, defRangeMax)
		then
			local atkTile = MatchStore.GetTile(match, attacker.x, attacker.y)
			local atkBonus = atkTile and (tonumber(atkTile.defBonus) or 0) or 0
			local backMul = AERules.GetTypeMul(defCfg.Kind, atkCfg.Kind, defender.unitType, attacker.unitType)
			local back = AERules.CalcDamage(
				tonumber(defCfg.Atk) or 0,
				defender.hp / maxHp,
				backMul,
				1,
				tonumber(atkCfg.Def) or 0,
				atkBonus / 100
			)
			local backApplied = _applyDamage(attacker, AERules.CalcCounter(back))
			table.insert(
				hits,
				_hit(defender.id, attacker.id, backApplied, attacker.hp, attacker.alive == true, KIND_COUNTER)
			)
		end
	end

	attacker.acted = true
	attacker.moved = true
	return true, nil, hits
end

--[[
	刷新胜负到 match.result
	@param match table - 对局
	@return string? - Win/Lose/nil
]]
function Combat.RefreshResult(match: any): string?
	if type(match.cells) ~= "table" then
		match.cells = AERules.ParseGrid(match.w, match.h, match.cellRows)
	end
	local commanderCfg = AERules.GetUnitCfg(EnumMgr.AEUnitId.Commander)
	local price = commanderCfg and (tonumber(commanderCfg.Price) or 400) or 400
	local snap = {
		units = match.units,
		mapId = match.mapId,
		w = match.w,
		h = match.h,
		cellRows = match.cellRows,
		cells = match.cells,
		tiles = AERules.FlattenCells(match.cells),
		gold = match.gold,
	}
	match.result = AERules.JudgeResult(snap, EnumMgr.AEFaction.Player, price)
	return match.result
end

return Combat
