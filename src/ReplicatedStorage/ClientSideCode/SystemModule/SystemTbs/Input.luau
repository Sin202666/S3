--[[
	Module: Input
	Description: 战棋按地面格选单位 / 移动 / 攻击；意图发服务端。悬浮高亮当前格，可走格预览路径。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local UserInputService = Utils.UserInputService
local Players = Utils.Players
local GuiService = Utils.GuiService
local RunService = Utils.RunService
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local BoardView = require(script.Parent.BoardView)

local Input = {}

local _snap: any = nil
local _selectedId: number? = nil
local _onAction: ((string, any) -> ())? = nil
local _onSelect: (() -> ())? = nil
local _conn: RBXScriptConnection? = nil
local _hoverConn: RBXScriptConnection? = nil
local _pathKey = ""

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
	local spec = AERules.MoveSpecFromSnap(_snap, unit)
	if not spec then
		return {}
	end
	local reach = AERules.FindReachable(spec)
	local list = {}
	for _, cell in reach do
		table.insert(list, cell)
	end
	return list
end

--[[
	悬停可走格时画路径；走路中不改 BoardView 的路径
	@param x number? - 列
	@param y number? - 行
	@return nil
]]
local function _refreshPathPreview(x: number?, y: number?)
	if BoardView.IsWalking() then
		return
	end
	if x == nil or y == nil or not _snap or not _selectedId then
		if _pathKey ~= "" then
			_pathKey = ""
			BoardView.ClearPath()
		end
		return
	end
	local unit = _unitById(_selectedId)
	if not unit or unit.moved or unit.acted or not unit.alive then
		if _pathKey ~= "" then
			_pathKey = ""
			BoardView.ClearPath()
		end
		return
	end
	local key = unit.id .. ":" .. x .. "," .. y
	if key == _pathKey then
		return
	end
	_pathKey = key
	if x == unit.x and y == unit.y then
		BoardView.ClearPath()
		return
	end
	local spec = AERules.MoveSpecFromSnap(_snap, unit, x, y)
	local path = spec and AERules.FindPath(spec)
	if path and #path >= 2 then
		BoardView.ShowPath(path)
		return
	end
	BoardView.ClearPath()
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
	指针是否在战棋 HUD 实心底上（顶栏/卡/按钮）
	@return boolean - 在 HUD 上
]]
local function _isPointerOverHud(): boolean
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local hits = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	for _, gui in hits do
		if gui:IsA("GuiObject") and gui.Visible and gui.BackgroundTransparency < 1 then
			local root: Instance? = gui
			while root and root.Name ~= "TbsHud" do
				root = root.Parent
			end
			if root and root.Name == "TbsHud" then
				return true
			end
		end
	end
	return false
end

--[[
	鼠标投影到的地面格
	@return number? - 列
	@return number? - 行
]]
local function _cellFromMouse(): (number?, number?)
	if not _snap then
		return nil, nil
	end
	return BoardView.CellFromScreen(UserInputService:GetMouseLocation())
end

--[[
	刷新悬浮高亮
	@return nil
]]
local function _updateHover()
	if not _snap or _isPointerOverHud() then
		BoardView.ClearHover()
		_refreshPathPreview(nil, nil)
		return
	end
	local x, y = _cellFromMouse()
	if x == nil or y == nil then
		BoardView.ClearHover()
		_refreshPathPreview(nil, nil)
		return
	end
	local occupant = _unitAt(x, y)
	BoardView.SetHover(occupant and occupant.id, x, y)
	_refreshPathPreview(x, y)
end

--[[
	处理一次点击。只认地面格，避免邻格棋子模型互相挡。
	@return nil
]]
local function _onClick()
	if not _snap or not _onAction then
		return
	end
	if _snap.result or _snap.turnFaction ~= EnumMgr.AEFaction.Player then
		return
	end
	if _isPointerOverHud() then
		return
	end
	local x, y = _cellFromMouse()
	if x == nil or y == nil then
		return
	end
	local occupant = _unitAt(x, y)
	if occupant then
		if occupant.faction == EnumMgr.AEFaction.Player then
			_selectedId = occupant.id
			_refreshHighlight()
			if _onSelect then
				_onSelect()
			end
			return
		end
		if _selectedId then
			_onAction(EnumMgr.AEAction.Attack, { unitId = _selectedId, targetId = occupant.id })
			return
		end
	end
	if _selectedId then
		_onAction(EnumMgr.AEAction.Move, { unitId = _selectedId, x = x, y = y })
	end
end

--[[
	启动点击与悬浮
	@param onAction (string, any) -> () - 发意图
	@param onSelect (() -> ())? - 选中后刷新 HUD
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
	if not _hoverConn then
		_hoverConn = RunService.Heartbeat:Connect(_updateHover)
	end
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
	_pathKey = ""
	_refreshHighlight()
	_updateHover()
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
	if _hoverConn then
		_hoverConn:Disconnect()
		_hoverConn = nil
	end
	_onAction = nil
	_selectedId = nil
	_snap = nil
	_pathKey = ""
	BoardView.ClearHighlights()
	BoardView.ClearHover()
	BoardView.ClearPath()
end

return Input
