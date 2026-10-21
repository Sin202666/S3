local SystemTbs = {}

export type TileSnap = {
	x: number,
	y: number,
	legend: string,
	terrainId: number,
	owner: number,
}

export type UnitSnap = {
	id: number,
	unitType: number,
	faction: number,
	x: number,
	y: number,
	hp: number,
	maxHp: number,
	moved: boolean,
	acted: boolean,
	alive: boolean,
}

export type MovePathSnap = {
	unitId: number,
	cells: { { x: number, y: number } },
}

export type MatchSnap = {
	kind: string,
	mapId: number,
	w: number,
	h: number,
	zhName: string,
	tiles: { TileSnap },
	units: { UnitSnap },
	gold: { [number]: number },
	turnFaction: number,
	turnIndex: number,
	result: string?,
	allowRecruit: { number },
	movePaths: { MovePathSnap }?,
}

--[[
	服务端进程 Init；只保证 Remote 已注册
	@return nil
]]
function SystemTbs.Init()
end

--[[
	玩家入服后开默认关卡（1-1）
	@param player Player - 已完成读档的玩家
	@return boolean - 是否开局成功
]]
function SystemTbs.SetupPlayer(player: Player): boolean
	return false
end

--[[
	玩家离服清会话对局
	@param player Player - 离服玩家
	@return nil
]]
function SystemTbs.OnPlayerRemoving(player: Player)
end

--[[
	注册 TBS_ACTION / 限频
	@return nil
]]
function SystemTbs.RegisterNetWork()
end

return SystemTbs
