--[[
	Module: Input
	Description: 战棋点格选单位 / 移动 / 攻击；意图发服务端
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local UserInputService = Utils.UserInputService
local Players = Utils.Players
local Workspace = game:GetService("Workspace")
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local BoardView = require(script.Parent.BoardView)

local Input = {}

local _snap: any = nil
local _selectedId: number? = nil
local _onAction: ((string, any) -> ())? = nil
local _onSelect: (() -> ())? = nil
local _conn: RBXScriptConnection? = nil

--[[
	按 Id 取单位
	@param unitId number - 单位
	@return table? - UnitSnap
]]
local function _unitById(unitId: number): any?
	if not _snap then
		return nil
	end
	for _, unit in _snap.units do
		if unit.id == unitId then
			return unit
		end
	end
	return nil
end

--[[
	格上单位
	@param x number - 列
	@param y number - 行
	@return table? - 存活单位
]]
local function _unitAt(x: number, y: number): any?
	if not _snap then
		return nil
	end
	for _, unit in _snap.units do
		if unit.alive and unit.x == x and unit.y == y then
			return unit
		end
	end
	return nil
end

--[[
	当前选中单位可达格
	@return { any } - 格子列表
]]
local function _reachList(): { any }
	if not _snap or not _selectedId then
		return {}
	end
	local unit = _unitById(_selectedId)
	if not unit or unit.moved or unit.acted or not unit.alive then
		return {}
	end
	local cfg = AERules.GetUnitCfg(unit.unitType)
	if not cfg then
		return {}
	end
	local tileIndex: { [string]: any } = {}
	for _, tile in AERules.CellsFromSnap(_snap) do
		tileIndex[tile.x .. "," .. tile.y] = tile
	end
	local reach = AERules.FindReachable({
		w = _snap.w,
		h = _snap.h,
		startX = unit.x,
		startY = unit.y,
		movePoints = tonumber(cfg.Move) or 0,
		getCost = function(x: number, y: number): number
			local tile = tileIndex[x .. "," .. y]
			local terrain = tile and AERules.GetTerrainById(tile.terrainId)
			if terrain and not AERules.CanEnterTerrain(cfg, terrain) then
				return 99
			end
			return terrain and (tonumber(terrain.MoveCost) or 1) or 1
		end,
		isBlocked = function(x: number, y: number): boolean
			local other = _unitAt(x, y)
			return other ~= nil and other.id ~= unit.id
		end,
	})
	local list = {}
	for _, cell in reach do
		table.insert(list, cell)
	end
	return list
end

--[[
	刷新高亮
	@return nil
]]
local function _refreshHighlight()
	local unit = _selectedId and _unitById(_selectedId)
	BoardView.Highlight(_reachList(), unit and unit.x, unit and unit.y)
end

--[[
	射线点到的实例
	@return Instance? - 命中
]]
local function _hit(): Instance?
	local camera = Workspace.CurrentCamera
	local localPlayer = Players.LocalPlayer
	if not camera or not localPlayer then
		return nil
	end
	local mouse = localPlayer:GetMouse()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if localPlayer.Character then
		params.FilterDescendantsInstances = { localPlayer.Character }
	end
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 800, params)
	return result and result.Instance
end

--[[
	处理一次点击
	@return nil
]]
local function _onClick()
	if not _snap or not _onAction then
		return
	end
	if _snap.result or _snap.turnFaction ~= EnumMgr.AEFaction.Player then
		return
	end
	local inst = _hit()
	local unitId = BoardView.UnitIdFromInstance(inst)
	local x, y = BoardView.CellFromInstance(inst)
	if unitId then
		local unit = _unitById(unitId)
		if unit and unit.faction == EnumMgr.AEFaction.Player then
			_selectedId = unitId
			_refreshHighlight()
			if _onSelect then
				_onSelect()
			end
			return
		end
		if unit and unit.faction ~= EnumMgr.AEFaction.Player and _selectedId then
			_onAction(EnumMgr.AEAction.Attack, { unitId = _selectedId, targetId = unitId })
			return
		end
	end
	if x ~= nil and y ~= nil and _selectedId then
		local occupant = _unitAt(x, y)
		if occupant and occupant.faction ~= EnumMgr.AEFaction.Player then
			_onAction(EnumMgr.AEAction.Attack, { unitId = _selectedId, targetId = occupant.id })
			return
		end
		_onAction(EnumMgr.AEAction.Move, { unitId = _selectedId, x = x, y = y })
	end
end

--[[
	启动点击
	@param onAction (string, any) -> () - 发意图
	@return nil
]]
function Input.Start(onAction: (string, any) -> (), onSelect: (() -> ())?)
	_onAction = onAction
	_onSelect = onSelect
	if _conn then
		return
	end
	_conn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			_onClick()
		end
	end)
end

--[[
	同步快照
	@param snap table - MatchSnap
	@return nil
]]
function Input.SetSnap(snap: any)
	_snap = snap
	if _selectedId then
		local unit = _unitById(_selectedId)
		if not unit or not unit.alive then
			_selectedId = nil
		end
	end
	_refreshHighlight()
end

--[[
	当前选中单位
	@return table? - UnitSnap
]]
function Input.GetSelected(): any?
	if not _selectedId then
		return nil
	end
	return _unitById(_selectedId)
end

--[[
	停止
	@return nil
]]
function Input.Stop()
	if _conn then
		_conn:Disconnect()
		_conn = nil
	end
	_onAction = nil
	_selectedId = nil
	_snap = nil
	BoardView.ClearHighlights()
end

return Input
