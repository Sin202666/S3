--[[
	Module: Combat
	Description: 战棋伤害与反击结算（服务端唯一写 HP）
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local MatchStore = require(script.Parent.MatchStore)

local Combat = {}

--[[
	对目标扣血，死亡则标记
	@param unit table - 单位
	@param damage number - 伤害
	@return nil
]]
local function _applyDamage(unit: any, damage: number)
	unit.hp = math.max(0, unit.hp - damage)
	if unit.hp <= 0 then
		unit.alive = false
		unit.hp = 0
	end
end

--[[
	执行攻击（含近战反击）
	@param match table - 对局
	@param attacker table - 攻击方
	@param defender table - 防御方
	@return boolean - 是否结算
	@return string? - 失败码
]]
function Combat.ResolveAttack(match: any, attacker: any, defender: any): (boolean, string?)
	local atkCfg = AERules.GetUnitCfg(attacker.unitType)
	local defCfg = AERules.GetUnitCfg(defender.unitType)
	if not atkCfg or not defCfg then
		return false, "NO_CFG"
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
	_applyDamage(defender, damage)

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
			_applyDamage(attacker, AERules.CalcCounter(back))
		end
	end

	attacker.acted = true
	attacker.moved = true
	return true, nil
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
