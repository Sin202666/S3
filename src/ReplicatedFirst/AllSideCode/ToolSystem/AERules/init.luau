--[[
	Module: AERules
	Description: 远古帝国2 战棋纯规则：读表、寻路、伤害、占领/招募合法性。无会话态、不写存档。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21

	功能：
	- 读 aeunit / aeterrain / aemap / aeconst（深拷贝，不挂 ItemType）
	- 解析 1-1 网格（含 C1/C2 归属）
	- 四向 BFS 移动、曼哈顿射程、策划案伤害公式
	- 占领 / 招募 / 胜负条件判定（调用方传入对局快照字段）

	与 SystemTbs：本模块只算，不改 MatchStore。服务端结算必须再跑一遍。

	加载：
		local AERules = Utils.AERules
		local dmg = AERules.CalcDamage(35, 1, 1, 1, 25, 0.10)
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local CfgFind = Utils.CfgFind
local EnumMgr = Utils.EnumMgr

local AERules = {}

local CONF_UNIT = "aeunitConf"
local CONF_TERRAIN = "aeterrainConf"
local CONF_MAP = "aemapConf"
local CONF_CONST = "aeconstConf"

local DIR4 = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
}

local _legendIndex: { [string]: any }? = nil

--[[
	建地形图例索引（模块内缓存深拷贝行）
	@return { [string]: table } - legend → 地形行
]]
local function _ensureLegendIndex(): { [string]: any }
	if _legendIndex then
		return _legendIndex
	end
	local index: { [string]: any } = {}
	local all = CfgFind.GetCfgByName(CONF_TERRAIN)
	if type(all) == "table" then
		for id, row in pairs(all) do
			if type(row) == "table" and type(row.Legend) == "string" then
				index[row.Legend] = row
				row.Id = tonumber(id) or row.Id
			end
		end
	end
	_legendIndex = index
	return index
end

--[[
	取常量数值
	@param key string - aeconstConf 主键
	@param fallback number - 缺行时回退
	@return number - 常量值
]]
function AERules.GetConst(key: string, fallback: number): number
	local row = CfgFind.GetCfgByNameAndID(CONF_CONST, key)
	if type(row) ~= "table" then
		return fallback
	end
	local value = tonumber(row.Value)
	if value == nil then
		return fallback
	end
	return value
end

--[[
	取兵种行
	@param unitId number - aeunitConf Id
	@return table? - 兵种配置深拷贝
]]
function AERules.GetUnitCfg(unitId: number): any?
	return CfgFind.GetCfgByNameAndID(CONF_UNIT, unitId)
end

--[[
	按 Id 取地形
	@param terrainId number - aeterrainConf Id
	@return table? - 地形行深拷贝
]]
function AERules.GetTerrainById(terrainId: number): any?
	return CfgFind.GetCfgByNameAndID(CONF_TERRAIN, terrainId)
end

--[[
	按图例取地形
	@param legend string - `.` / `T` / `V` / `C` 等
	@return table? - 地形行深拷贝（含 Id）
]]
function AERules.GetTerrainByLegend(legend: string): any?
	local row = _ensureLegendIndex()[legend]
	if type(row) ~= "table" then
		return nil
	end
	local copy = table.clone(row)
	return copy
end

--[[
	解析格 token：C1/C2 拆成城堡 + 归属
	@param token string - 网格单元
	@return string - 地形图例
	@return number - 归属 AEFaction
]]
function AERules.ParseToken(token: string): (string, number)
	if token == "C1" then
		return "C", EnumMgr.AEFaction.Player
	end
	if token == "C2" then
		return "C", EnumMgr.AEFaction.Enemy
	end
	if token == "B1" then
		return "B", EnumMgr.AEFaction.Player
	end
	if token == "B2" then
		return "B", EnumMgr.AEFaction.Enemy
	end
	return token, EnumMgr.AEFaction.None
end

--[[
	解析 "unitType:x,y" 刷怪串
	@param list {string}? - 导表 string[]
	@return { { unitType: number, x: number, y: number } } - 出生点
]]
function AERules.ParseSpawns(list: any): { { unitType: number, x: number, y: number } }
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, item in list do
		if type(item) == "string" then
			local unitType, x, y = string.match(item, "^(%d+):(%d+),(%d+)$")
			if unitType and x and y then
				table.insert(out, {
					unitType = tonumber(unitType) :: number,
					x = tonumber(x) :: number,
					y = tonumber(y) :: number,
				})
			end
		end
	end
	return out
end

--[[
	把每行图例解析成二维格子
	@param w number - 宽
	@param h number - 高
	@param cellRows {string}? - 每行空格分隔图例
	@return {{any}} - cells[y+1][x+1]
]]
function AERules.ParseGrid(w: number, h: number, cellRows: any): { { any } }
	local cells = {}
	if type(cellRows) ~= "table" or w <= 0 or h <= 0 then
		return cells
	end
	for y = 0, h - 1 do
		local line = cellRows[y + 1]
		local row = {}
		if type(line) == "string" then
			local x = 0
			for token in string.gmatch(line, "%S+") do
				local legend, owner = AERules.ParseToken(token)
				local terrain = AERules.GetTerrainByLegend(legend)
				row[x + 1] = {
					x = x,
					y = y,
					legend = legend,
					terrainId = terrain and tonumber(terrain.Id) or EnumMgr.AETerrain.Plains,
					owner = owner,
					defBonus = terrain and (tonumber(terrain.DefBonus) or 0) or 0,
					moveCost = terrain and (tonumber(terrain.MoveCost) or 1) or 1,
				}
				x += 1
			end
		end
		cells[y + 1] = row
	end
	return cells
end

--[[
	把二维格压成快照列表，并套归属
	@param cells {{any}} - 二维格
	@param owners {any}? - { { x, y, owner } }
	@return {any} - 扁平格
]]
function AERules.FlattenCells(cells: any, owners: any): { any }
	local list = {}
	if type(cells) ~= "table" then
		return list
	end
	local ownerAt: { [string]: number } = {}
	if type(owners) == "table" then
		for _, item in owners do
			if type(item) == "table" and item.x ~= nil and item.y ~= nil then
				ownerAt[tostring(item.x) .. "," .. tostring(item.y)] = tonumber(item.owner) or 0
			end
		end
	end
	for _, row in cells do
		if type(row) == "table" then
			for _, tile in row do
				if type(tile) == "table" then
					local owner = ownerAt[tostring(tile.x) .. "," .. tostring(tile.y)]
					table.insert(list, {
						x = tile.x,
						y = tile.y,
						legend = tile.legend,
						terrainId = tile.terrainId,
						owner = if owner ~= nil then owner else tile.owner,
						defBonus = tile.defBonus,
						moveCost = tile.moveCost,
					})
				end
			end
		end
	end
	return list
end

--[[
	加载关卡行并解析网格
	@param mapId number - aemapConf Id
	@return table? - 解析后的关卡（cells[y+1][x+1]，另带 cellRows）
]]
function AERules.LoadMap(mapId: number): any?
	local cfg = CfgFind.GetCfgByNameAndID(CONF_MAP, mapId)
	if type(cfg) ~= "table" then
		return nil
	end
	local w = tonumber(cfg.W) or 0
	local h = tonumber(cfg.H) or 0
	local grid = cfg.Grid
	if type(grid) ~= "table" or w <= 0 or h <= 0 then
		return nil
	end
	local cellRows = {}
	for y = 1, h do
		local line = grid[y]
		cellRows[y] = if type(line) == "string" then line else ""
	end
	return {
		mapId = mapId,
		zhName = cfg.ZhName,
		w = w,
		h = h,
		winCond = cfg.WinCond,
		startGold = tonumber(cfg.StartGold) or 0,
		enemyGold = tonumber(cfg.EnemyGold) or 0,
		allowRecruit = cfg.AllowRecruit or {},
		playerSpawns = AERules.ParseSpawns(cfg.PlayerUnits),
		enemySpawns = AERules.ParseSpawns(cfg.EnemyUnits),
		cellRows = cellRows,
		cells = AERules.ParseGrid(w, h, cellRows),
	}
end

--[[
	从快照还原扁平格子（缺 tiles 时用 cellRows / 再读表）
	@param snap table - 对局快照
	@return {any} - 扁平格
]]
function AERules.CellsFromSnap(snap: any): { any }
	if type(snap) ~= "table" then
		return {}
	end
	if type(snap.tiles) == "table" and #snap.tiles > 0 then
		return snap.tiles
	end
	local w = tonumber(snap.w) or 0
	local h = tonumber(snap.h) or 0
	local cells = nil
	if type(snap.cellRows) == "table" then
		cells = AERules.ParseGrid(w, h, snap.cellRows)
	end
	if type(cells) ~= "table" or #cells == 0 then
		local parsed = AERules.LoadMap(tonumber(snap.mapId) or 1)
		if parsed then
			w = parsed.w
			h = parsed.h
			cells = parsed.cells or AERules.ParseGrid(parsed.w, parsed.h, parsed.cellRows)
		end
	end
	return AERules.FlattenCells(cells, snap.owners)
end

--[[
	格是否在地图内
	@param x number - 列
	@param y number - 行
	@param w number - 宽
	@param h number - 高
	@return boolean - 是否合法
]]
function AERules.InBounds(x: number, y: number, w: number, h: number): boolean
	return x >= 0 and y >= 0 and x < w and y < h
end

--[[
	曼哈顿距离
	@param ax number - 起点列
	@param ay number - 起点行
	@param bx number - 终点列
	@param by number - 终点行
	@return number - 距离
]]
function AERules.Manhattan(ax: number, ay: number, bx: number, by: number): number
	return math.abs(ax - bx) + math.abs(ay - by)
end

--[[
	目标是否在射程（含最小）
	@param ax number - 攻击方列
	@param ay number - 攻击方行
	@param bx number - 目标列
	@param by number - 目标行
	@param rangeMin number - 最小射程
	@param rangeMax number - 最大射程
	@return boolean - 是否可打
]]
function AERules.InRange(ax: number, ay: number, bx: number, by: number, rangeMin: number, rangeMax: number): boolean
	local dist = AERules.Manhattan(ax, ay, bx, by)
	return dist >= rangeMin and dist <= rangeMax
end

--[[
	是否建筑格
	@param legend string - 图例
	@return boolean - 村/城/兵营/神殿
]]
function AERules.IsBuilding(legend: string): boolean
	return legend == "V" or legend == "C" or legend == "B" or legend == "R"
end

--[[
	建筑每回合产金
	@param legend string - 图例
	@return number - 金币
]]
function AERules.IncomeOf(legend: string): number
	if legend == "V" then
		return AERules.GetConst("VILLAGE_GOLD", 30)
	end
	if legend == "C" then
		return AERules.GetConst("CASTLE_GOLD", 50)
	end
	return 0
end

--[[
	单位能否进入该地形（1-1 陆地兵可进平地/林/村/城）
	@param unitCfg table - 兵种行
	@param terrainCfg table - 地形行
	@return boolean - 可否进入
]]
function AERules.CanEnterTerrain(unitCfg: any, terrainCfg: any): boolean
	if type(terrainCfg) ~= "table" then
		return false
	end
	local flyOnly = tonumber(terrainCfg.FlyOnly) or 0
	if flyOnly == 1 then
		return unitCfg and unitCfg.Kind == "Flyer"
	end
	local cost = tonumber(terrainCfg.MoveCost) or 1
	if cost >= 99 then
		return false
	end
	return true
end

--[[
	四向 BFS：返回可到达格及剩余移动力
	@param spec table - w/h/startX/startY/movePoints/getCost(x,y)/isBlocked(x,y)
	@return { [string]: { x: number, y: number, left: number } } - 键 "x,y"
]]
function AERules.FindReachable(spec: any): { [string]: { x: number, y: number, left: number } }
	local w = spec.w
	local h = spec.h
	local startX = spec.startX
	local startY = spec.startY
	local movePoints = spec.movePoints
	local getCost = spec.getCost
	local isBlocked = spec.isBlocked
	local result: { [string]: { x: number, y: number, left: number } } = {}
	local queue = { { x = startX, y = startY, left = movePoints } }
	local best: { [string]: number } = {}
	best[startX .. "," .. startY] = movePoints
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, d in DIR4 do
			local nx = cur.x + d[1]
			local ny = cur.y + d[2]
			if AERules.InBounds(nx, ny, w, h) then
				local cost = getCost(nx, ny)
				local left = cur.left - cost
				local key = nx .. "," .. ny
				if left >= 0 and not isBlocked(nx, ny) then
					local prev = best[key]
					if prev == nil or left > prev then
						best[key] = left
						result[key] = { x = nx, y = ny, left = left }
						table.insert(queue, { x = nx, y = ny, left = left })
					end
				end
			end
		end
	end
	return result
end

--[[
	策划案伤害：Atk*(HP/100)*克制*暴击 - Def*(1-地形防%)，向下取整，至少 MIN_DAMAGE
	@param atk number - 攻击
	@param hpRatio number - 当前 HP / 100
	@param typeMul number - 克制
	@param critMul number - 暴击（1 或 1.5）
	@param def number - 防御
	@param terrainDefPct number - 0~0.15
	@return number - 最终伤害
]]
function AERules.CalcDamage(
	atk: number,
	hpRatio: number,
	typeMul: number,
	critMul: number,
	def: number,
	terrainDefPct: number
): number
	local raw = atk * hpRatio * typeMul * critMul - def * (1 - terrainDefPct)
	local minDmg = AERules.GetConst("MIN_DAMAGE", 1)
	return math.max(minDmg, math.floor(raw))
end

--[[
	反击伤害
	@param damage number - 正打伤害
	@return number - 反击（至少 0）
]]
function AERules.CalcCounter(damage: number): number
	local mul = AERules.GetConst("COUNTER_MUL", 0.75)
	return math.max(0, math.floor(damage * mul))
end

--[[
	克制倍率（1-1 近战互打为 1）
	@param atkKind string - 攻击方 Kind
	@param defKind string - 防御方 Kind
	@param atkId number - 攻击方兵种
	@param defId number - 防御方兵种
	@return number - 0.75 / 1 / 1.5
]]
function AERules.GetTypeMul(atkKind: string, defKind: string, atkId: number, defId: number): number
	local adv = AERules.GetConst("ADVANTAGE_MUL", 1.5)
	local dis = AERules.GetConst("DISADVANTAGE_MUL", 0.75)
	if atkKind == "Melee" and defKind == "Ranged" then
		return adv
	end
	if atkId == EnumMgr.AEUnitId.Archer and defId == EnumMgr.AEUnitId.Dragon then
		return adv
	end
	if atkId == EnumMgr.AEUnitId.Wisp and defId == EnumMgr.AEUnitId.Skeleton then
		return adv
	end
	if defId == EnumMgr.AEUnitId.Golem and atkKind == "Ranged" then
		return dis
	end
	return 1
end

--[[
	是否可占领：站在非己方村/城上
	@param legend string - 当前格图例
	@param owner number - 当前归属
	@param faction number - 行动方
	@return boolean - 可以占领
]]
function AERules.CanOccupy(legend: string, owner: number, faction: number): boolean
	if not AERules.IsBuilding(legend) then
		return false
	end
	return owner ~= faction
end

--[[
	是否允许招募该兵种
	@param unitId number - 要招的兵
	@param allowList {number} - 本关白名单
	@param gold number - 当前金币
	@param price number - 价格
	@param commanderAlive boolean - 己方指挥官仍存活
	@return boolean - 可否招
	@return string? - 失败码
]]
function AERules.CanRecruit(
	unitId: number,
	allowList: { number },
	gold: number,
	price: number,
	commanderAlive: boolean
): (boolean, string?)
	local allowed = false
	for _, id in allowList do
		if id == unitId then
			allowed = true
			break
		end
	end
	if not allowed then
		return false, "UNIT_NOT_ALLOWED"
	end
	if unitId == EnumMgr.AEUnitId.Commander and commanderAlive then
		return false, "COMMANDER_ALIVE"
	end
	if gold < price then
		return false, "NOT_ENOUGH_GOLD"
	end
	return true, nil
end

--[[
	胜负：全灭敌军为胜；指挥官阵亡且无城堡或金币不够招募为负
	@param snap table - units / tiles / gold / turn 无关
	@param playerFaction number - 玩家阵营
	@param commanderPrice number - 指挥官价格
	@return string? - "Win" / "Lose" / nil
]]
function AERules.JudgeResult(snap: any, playerFaction: number, commanderPrice: number): string?
	if type(snap) ~= "table" or type(snap.units) ~= "table" then
		return nil
	end
	local enemyAlive = false
	local commanderAlive = false
	for _, unit in snap.units do
		if unit.alive then
			if unit.faction ~= playerFaction then
				enemyAlive = true
			elseif unit.unitType == EnumMgr.AEUnitId.Commander then
				commanderAlive = true
			end
		end
	end
	if not enemyAlive then
		return "Win"
	end
	if commanderAlive then
		return nil
	end
	local hasCastle = false
	for _, tile in AERules.CellsFromSnap(snap) do
		if tile.legend == "C" and tile.owner == playerFaction then
			hasCastle = true
			break
		end
	end
	local goldTbl = type(snap.gold) == "table" and snap.gold or {}
	local gold = goldTbl[playerFaction] or goldTbl["1"] or goldTbl.p or goldTbl.goldP or 0
	if hasCastle and gold >= commanderPrice then
		return nil
	end
	return "Lose"
end

return AERules
