--[[
	Module: AI
	Description: 1-1 敌军简单 AI：能打就打（残血/指挥官优先），否则朝最近玩家走近
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local MatchStore = require(script.Parent.MatchStore)
local Combat = require(script.Parent.Combat)

local AI = {}

--[[
	列出存活单位
	@param match table - 对局
	@param faction number - 阵营
	@return {table} - 单位列表
]]
local function _alive(match: any, faction: number): { any }
	local list = {}
	for _, unit in match.units do
		if unit.alive and unit.faction == faction then
			table.insert(list, unit)
		end
	end
	return list
end

--[[
	可走格查询上下文
	@param match table - 对局
	@param unit table - 当前单位
	@return table - FindReachable spec
]]
local function _reachSpec(match: any, unit: any): any
	local cfg = AERules.GetUnitCfg(unit.unitType)
	return {
		w = match.w,
		h = match.h,
		startX = unit.x,
		startY = unit.y,
		movePoints = cfg and (tonumber(cfg.Move) or 0) or 0,
		getCost = function(x: number, y: number): number
			local tile = MatchStore.GetTile(match, x, y)
			return tile and (tonumber(tile.moveCost) or 1) or 1
		end,
		isBlocked = function(x: number, y: number): boolean
			local other = MatchStore.UnitAt(match, x, y)
			return other ~= nil and other.id ~= unit.id
		end,
	}
end

--[[
	选攻击目标：残血优先，其次指挥官
	@param enemies {table} - 敌方（对 AI 而言是玩家）
	@return table? - 目标
]]
local function _pickTarget(enemies: { any }): any?
	local best = nil
	local bestScore = math.huge
	for _, enemy in enemies do
		local score = enemy.hp
		if enemy.unitType == EnumMgr.AEUnitId.Commander then
			score -= 20
		end
		if score < bestScore then
			bestScore = score
			best = enemy
		end
	end
	return best
end

--[[
	为一名敌军行动
	@param match table - 对局
	@param unit table - 敌军
	@return nil
]]
local function _actUnit(match: any, unit: any)
	if not unit.alive or match.result then
		return
	end
	local cfg = AERules.GetUnitCfg(unit.unitType)
	if not cfg then
		return
	end
	local rangeMin = tonumber(cfg.RangeMin) or 1
	local rangeMax = tonumber(cfg.RangeMax) or 1
	local players = _alive(match, EnumMgr.AEFaction.Player)

	local function tryAttackFromHere(): boolean
		local inRange = {}
		for _, enemy in players do
			if AERules.InRange(unit.x, unit.y, enemy.x, enemy.y, rangeMin, rangeMax) then
				table.insert(inRange, enemy)
			end
		end
		local target = _pickTarget(inRange)
		if target then
			Combat.ResolveAttack(match, unit, target)
			Combat.RefreshResult(match)
			return true
		end
		return false
	end

	if tryAttackFromHere() then
		return
	end

	local nearest = nil
	local nearestDist = math.huge
	for _, enemy in players do
		local dist = AERules.Manhattan(unit.x, unit.y, enemy.x, enemy.y)
		if dist < nearestDist then
			nearestDist = dist
			nearest = enemy
		end
	end
	if nearest then
		local reach = AERules.FindReachable(_reachSpec(match, unit))
		local best = nil
		local bestDist = nearestDist
		for _, cell in reach do
			local dist = AERules.Manhattan(cell.x, cell.y, nearest.x, nearest.y)
			if dist < bestDist then
				bestDist = dist
				best = cell
			end
		end
		if best then
			local spec = _reachSpec(match, unit)
			spec.destX = best.x
			spec.destY = best.y
			local path = AERules.FindPath(spec)
			unit.x = best.x
			unit.y = best.y
			unit.moved = true
			if path and #path >= 2 then
				MatchStore.RecordMovePath(match, unit.id, path)
			end
		end
	end
	if not unit.acted then
		if not tryAttackFromHere() then
			unit.acted = true
		end
	end
end

--[[
	跑完整敌军回合
	@param match table - 对局
	@return nil
]]
function AI.PlayEnemyTurn(match: any)
	for _, unit in _alive(match, EnumMgr.AEFaction.Enemy) do
		if match.result then
			return
		end
		_actUnit(match, unit)
	end
end

return AI
