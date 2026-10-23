--[[
	Module: MatchStore
	Description: 战棋会话对局内存：创建、查询、快照。过程态不落盘。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-23
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr
local Copy = Utils.Copy

local MatchStore = {}

local _matches: { [number]: any } = {}

--[[
	取格
	@param match table - 对局
	@param x number - 列
	@param y number - 行
	@return table? - 格
]]
local function _tile(match: any, x: number, y: number): any?
	local cells = match and (match.cells or match.tiles)
	if type(cells) ~= "table" then
		return nil
	end
	local row = cells[y + 1]
	if type(row) ~= "table" then
		return nil
	end
	return row[x + 1]
end

--[[
	在格上找存活单位
	@param match table - 对局
	@param x number - 列
	@param y number - 行
	@return table? - 单位
]]
function MatchStore.UnitAt(match: any, x: number, y: number): any?
	for _, unit in match.units do
		if unit.alive and unit.x == x and unit.y == y then
			return unit
		end
	end
	return nil
end

--[[
	生成单位
	@param match table - 对局
	@param unitType number - 兵种
	@param faction number - 阵营
	@param x number - 列
	@param y number - 行
	@return table? - 新单位
]]
function MatchStore.SpawnUnit(match: any, unitType: number, faction: number, x: number, y: number): any?
	local cfg = AERules.GetUnitCfg(unitType)
	if not cfg then
		return nil
	end
	local maxHp = tonumber(cfg.Hp) or AERules.GetConst("MAX_HP", 100)
	match.nextUnitId += 1
	local unit = {
		id = match.nextUnitId,
		unitType = unitType,
		faction = faction,
		x = x,
		y = y,
		hp = maxHp,
		maxHp = maxHp,
		moved = true,
		acted = true,
		alive = true,
	}
	match.units[unit.id] = unit
	return unit
end

--[[
	创建对局
	@param player Player - 房主（本版单人 PVE）
	@param mapId number - 关卡 Id
	@return table? - 对局
]]
function MatchStore.Create(player: Player, mapId: number): any?
	local parsed = AERules.LoadMap(mapId)
	if not parsed then
		return nil
	end
	local match = {
		userId = player.UserId,
		mapId = mapId,
		zhName = parsed.zhName,
		w = parsed.w,
		h = parsed.h,
		winCond = parsed.winCond,
		allowRecruit = parsed.allowRecruit,
		cellRows = parsed.cellRows,
		cells = AERules.ParseGrid(parsed.w, parsed.h, parsed.cellRows),
		units = {},
		nextUnitId = 0,
		gold = {
			[EnumMgr.AEFaction.Player] = parsed.startGold,
			[EnumMgr.AEFaction.Enemy] = parsed.enemyGold,
		},
		turnFaction = EnumMgr.AEFaction.Player,
		turnIndex = 1,
		result = nil,
	}
	for _, spawn in parsed.playerSpawns do
		local unit = MatchStore.SpawnUnit(match, spawn.unitType, EnumMgr.AEFaction.Player, spawn.x, spawn.y)
		if unit then
			unit.moved = false
			unit.acted = false
		end
	end
	for _, spawn in parsed.enemySpawns do
		MatchStore.SpawnUnit(match, spawn.unitType, EnumMgr.AEFaction.Enemy, spawn.x, spawn.y)
	end
	_matches[player.UserId] = match
	return match
end

--[[
	取玩家对局
	@param player Player - 玩家
	@return table? - 对局
]]
function MatchStore.Get(player: Player): any?
	return _matches[player.UserId]
end

--[[
	移除对局
	@param player Player - 玩家
	@return nil
]]
function MatchStore.Remove(player: Player)
	_matches[player.UserId] = nil
end

--[[
	取格（公开）
	@param match table - 对局
	@param x number - 列
	@param y number - 行
	@return table? - 格
]]
function MatchStore.GetTile(match: any, x: number, y: number): any?
	return _tile(match, x, y)
end

--[[
	记下本帧要播的移动路径（表现提示，不进存档）
	@param match table - 对局
	@param unitId number - 单位
	@param cells { { x: number, y: number } } - 含起终点
	@return nil
]]
function MatchStore.RecordMovePath(match: any, unitId: number, cells: { any })
	if type(match) ~= "table" or type(cells) ~= "table" or #cells < 2 then
		return
	end
	if type(match.lastMovePaths) ~= "table" then
		match.lastMovePaths = {}
	end
	table.insert(match.lastMovePaths, {
		unitId = unitId,
		cells = Copy.deepCopy(cells),
	})
end

--[[
	记下本帧要播的命中（表现提示，不进存档）
	@param match table - 对局
	@param hits { any }? - Combat.ResolveAttack 命中列表
	@return nil
]]
function MatchStore.RecordCombatHits(match: any, hits: { any }?)
	if type(match) ~= "table" or type(hits) ~= "table" then
		return
	end
	if type(match.lastCombatHits) ~= "table" then
		match.lastCombatHits = {}
	end
	for _, hit in hits do
		local attackerId = tonumber(hit and hit.attackerId)
		local defenderId = tonumber(hit and hit.defenderId)
		local damage = tonumber(hit and hit.damage)
		if attackerId and defenderId and damage ~= nil then
			table.insert(match.lastCombatHits, {
				attackerId = attackerId,
				defenderId = defenderId,
				damage = damage,
				remainHp = tonumber(hit.remainHp) or 0,
				alive = hit.alive == true,
				kind = if hit.kind == "Counter" then "Counter" else "Attack",
			})
		end
	end
end

--[[
	可序列化快照
	@param match table - 对局
	@return table - MatchSnap
]]
function MatchStore.Snapshot(match: any): any
	if type(match.cells) ~= "table" then
		match.cells = AERules.ParseGrid(match.w, match.h, match.cellRows)
	end
	local owners = {}
	for y = 0, match.h - 1 do
		for x = 0, match.w - 1 do
			local tile = _tile(match, x, y)
			if tile and tile.owner ~= EnumMgr.AEFaction.None then
				table.insert(owners, {
					x = tile.x,
					y = tile.y,
					owner = tile.owner,
				})
			end
		end
	end
	local units = {}
	for _, unit in match.units do
		table.insert(units, {
			id = unit.id,
			unitType = unit.unitType,
			faction = unit.faction,
			x = unit.x,
			y = unit.y,
			hp = unit.hp,
			maxHp = unit.maxHp,
			moved = unit.moved,
			acted = unit.acted,
			alive = unit.alive,
		})
	end
	local goldP = match.gold[EnumMgr.AEFaction.Player] or 0
	local goldE = match.gold[EnumMgr.AEFaction.Enemy] or 0
	local movePaths = match.lastMovePaths
	match.lastMovePaths = nil
	local combatHits = match.lastCombatHits
	match.lastCombatHits = nil
	return {
		kind = EnumMgr.AENotify.Snapshot,
		mapId = match.mapId,
		w = match.w,
		h = match.h,
		zhName = match.zhName,
		cellRows = Copy.deepCopy(match.cellRows),
		owners = owners,
		units = units,
		goldP = goldP,
		goldE = goldE,
		gold = {
			[EnumMgr.AEFaction.Player] = goldP,
			[EnumMgr.AEFaction.Enemy] = goldE,
			p = goldP,
			e = goldE,
		},
		turnFaction = match.turnFaction,
		turnIndex = match.turnIndex,
		result = match.result,
		allowRecruit = Copy.deepCopy(match.allowRecruit),
		movePaths = movePaths,
		combatHits = combatHits,
	}
end

--[[
	己方是否有存活指挥官
	@param match table - 对局
	@param faction number - 阵营
	@return boolean - 有指挥官
]]
function MatchStore.HasCommander(match: any, faction: number): boolean
	for _, unit in match.units do
		if unit.alive and unit.faction == faction and unit.unitType == EnumMgr.AEUnitId.Commander then
			return true
		end
	end
	return false
end

--[[
	找己方空城堡
	@param match table - 对局
	@param faction number - 阵营
	@return table? - 格
]]
function MatchStore.FindEmptyCastle(match: any, faction: number): any?
	for y = 0, match.h - 1 do
		for x = 0, match.w - 1 do
			local tile = _tile(match, x, y)
			if tile and tile.legend == "C" and tile.owner == faction then
				if not MatchStore.UnitAt(match, x, y) then
					return tile
				end
			end
		end
	end
	return nil
end

return MatchStore
