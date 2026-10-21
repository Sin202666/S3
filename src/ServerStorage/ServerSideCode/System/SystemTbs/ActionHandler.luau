--[[
	Module: ActionHandler
	Description: 校验并执行客户端战棋意图；只改 MatchStore
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local MatchStore = require(script.Parent.MatchStore)
local Combat = require(script.Parent.Combat)
local Economy = require(script.Parent.Economy)
local AI = require(script.Parent.AI)

local ActionHandler = {}

--[[
	取己方未结束行动的单位
	@param match table - 对局
	@param unitId number - 单位
	@return table? - 单位
	@return string? - 失败码
]]
local function _ownActiveUnit(match: any, unitId: number): (any?, string?)
	if match.result then
		return nil, "MATCH_OVER"
	end
	if match.turnFaction ~= EnumMgr.AEFaction.Player then
		return nil, "NOT_YOUR_TURN"
	end
	local unit = match.units[unitId]
	if not unit or not unit.alive or unit.faction ~= EnumMgr.AEFaction.Player then
		return nil, "BAD_UNIT"
	end
	return unit, nil
end

--[[
	单位可走格
	@param match table - 对局
	@param unit table - 单位
	@return { [string]: any } - 可达
]]
local function _reachable(match: any, unit: any): { [string]: any }
	local cfg = AERules.GetUnitCfg(unit.unitType)
	return AERules.FindReachable({
		w = match.w,
		h = match.h,
		startX = unit.x,
		startY = unit.y,
		movePoints = cfg and (tonumber(cfg.Move) or 0) or 0,
		getCost = function(x: number, y: number): number
			local tile = MatchStore.GetTile(match, x, y)
			local terrain = tile and AERules.GetTerrainById(tile.terrainId)
			if terrain and not AERules.CanEnterTerrain(cfg, terrain) then
				return 99
			end
			return tile and (tonumber(tile.moveCost) or 1) or 1
		end,
		isBlocked = function(x: number, y: number): boolean
			local other = MatchStore.UnitAt(match, x, y)
			return other ~= nil and other.id ~= unit.id
		end,
	})
end

--[[
	移动
	@param match table - 对局
	@param payload any - { unitId, x, y }
	@return boolean - 成功
	@return string? - 失败码
]]
function ActionHandler.Move(match: any, payload: any): (boolean, string?)
	local unitId = tonumber(payload and payload.unitId)
	local x = tonumber(payload and payload.x)
	local y = tonumber(payload and payload.y)
	if not unitId or x == nil or y == nil then
		return false, "BAD_PAYLOAD"
	end
	local unit, err = _ownActiveUnit(match, unitId)
	if not unit then
		return false, err
	end
	if unit.moved or unit.acted then
		return false, "ALREADY_MOVED"
	end
	if x == unit.x and y == unit.y then
		unit.moved = true
		return true, nil
	end
	local reach = _reachable(match, unit)
	if not reach[x .. "," .. y] then
		return false, "UNREACHABLE"
	end
	unit.x = x
	unit.y = y
	unit.moved = true
	return true, nil
end

--[[
	攻击
	@param match table - 对局
	@param payload any - { unitId, targetId }
	@return boolean - 成功
	@return string? - 失败码
]]
function ActionHandler.Attack(match: any, payload: any): (boolean, string?)
	local unitId = tonumber(payload and payload.unitId)
	local targetId = tonumber(payload and payload.targetId)
	if not unitId or not targetId then
		return false, "BAD_PAYLOAD"
	end
	local unit, err = _ownActiveUnit(match, unitId)
	if not unit then
		return false, err
	end
	if unit.acted then
		return false, "ALREADY_ACTED"
	end
	local target = match.units[targetId]
	if not target or not target.alive or target.faction == unit.faction then
		return false, "BAD_TARGET"
	end
	local cfg = AERules.GetUnitCfg(unit.unitType)
	if not cfg then
		return false, "NO_CFG"
	end
	if
		not AERules.InRange(
			unit.x,
			unit.y,
			target.x,
			target.y,
			tonumber(cfg.RangeMin) or 1,
			tonumber(cfg.RangeMax) or 1
		)
	then
		return false, "OUT_OF_RANGE"
	end
	local ok, combatErr = Combat.ResolveAttack(match, unit, target)
	if ok then
		Combat.RefreshResult(match)
	end
	return ok, combatErr
end

--[[
	占领
	@param match table - 对局
	@param payload any - { unitId }
	@return boolean - 成功
	@return string? - 失败码
]]
function ActionHandler.Occupy(match: any, payload: any): (boolean, string?)
	local unitId = tonumber(payload and payload.unitId)
	if not unitId then
		return false, "BAD_PAYLOAD"
	end
	local unit, err = _ownActiveUnit(match, unitId)
	if not unit then
		return false, err
	end
	if unit.acted then
		return false, "ALREADY_ACTED"
	end
	local tile = MatchStore.GetTile(match, unit.x, unit.y)
	if not tile or not AERules.CanOccupy(tile.legend, tile.owner, unit.faction) then
		return false, "CANNOT_OCCUPY"
	end
	tile.owner = unit.faction
	unit.acted = true
	unit.moved = true
	return true, nil
end

--[[
	招募
	@param match table - 对局
	@param payload any - { unitType }
	@return boolean - 成功
	@return string? - 失败码
]]
function ActionHandler.Recruit(match: any, payload: any): (boolean, string?)
	if match.result then
		return false, "MATCH_OVER"
	end
	if match.turnFaction ~= EnumMgr.AEFaction.Player then
		return false, "NOT_YOUR_TURN"
	end
	local unitType = tonumber(payload and payload.unitType)
	if not unitType then
		return false, "BAD_PAYLOAD"
	end
	local cfg = AERules.GetUnitCfg(unitType)
	if not cfg then
		return false, "NO_CFG"
	end
	local ok, why = AERules.CanRecruit(
		unitType,
		match.allowRecruit,
		match.gold[EnumMgr.AEFaction.Player] or 0,
		tonumber(cfg.Price) or 0,
		MatchStore.HasCommander(match, EnumMgr.AEFaction.Player)
	)
	if not ok then
		return false, why
	end
	local castle = MatchStore.FindEmptyCastle(match, EnumMgr.AEFaction.Player)
	if not castle then
		return false, "NO_EMPTY_CASTLE"
	end
	local unit = MatchStore.SpawnUnit(match, unitType, EnumMgr.AEFaction.Player, castle.x, castle.y)
	if not unit then
		return false, "SPAWN_FAILED"
	end
	match.gold[EnumMgr.AEFaction.Player] -= tonumber(cfg.Price) or 0
	return true, nil
end

--[[
	结束玩家回合并跑敌军
	@param match table - 对局
	@return boolean - 成功
	@return string? - 失败码
]]
function ActionHandler.EndTurn(match: any): (boolean, string?)
	if match.result then
		return false, "MATCH_OVER"
	end
	if match.turnFaction ~= EnumMgr.AEFaction.Player then
		return false, "NOT_YOUR_TURN"
	end
	match.turnFaction = EnumMgr.AEFaction.Enemy
	match.turnIndex += 1
	Economy.BeginTurn(match, EnumMgr.AEFaction.Enemy)
	AI.PlayEnemyTurn(match)
	if match.result then
		return true, nil
	end
	match.turnFaction = EnumMgr.AEFaction.Player
	match.turnIndex += 1
	Economy.BeginTurn(match, EnumMgr.AEFaction.Player)
	Combat.RefreshResult(match)
	return true, nil
end

return ActionHandler
