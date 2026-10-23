--[[
	Module: Input
	Description: 战棋按地面格选单位 / 移动；点单位后出环形操作（攻击/占领/待命）。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-23
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local UserInputService = Utils.UserInputService
local Players = Utils.Players
local GuiService = Utils.GuiService
local RunService = Utils.RunService
local AERules = Utils.AERules
local EnumMgr = Utils.EnumMgr

local BoardView = require(script.Parent.BoardView)
local ActionRing = require(script.Parent.ActionRing)

local Input = {}

local _snap: any = nil
local _selectedId: number? = nil
local _onAction: ((string, any) -> ())? = nil
local _onSelect: (() -> ())? = nil
local _conn: RBXScriptConnection? = nil
local _hoverConn: RBXScriptConnection? = nil
local _pathKey = ""
local _attackMode = false

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
	if BoardView.IsBusy() then
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
	射程内敌军
	@param unit table - 己方单位
	@return { any } - { x, y, id }
]]
local function _enemiesInRange(unit: any): { any }
	if not _snap then
		return {}
	end
	local cfg = AERules.GetUnitCfg(unit.unitType)
	local rangeMin = if cfg then tonumber(cfg.RangeMin) or 1 else 1
	local rangeMax = if cfg then tonumber(cfg.RangeMax) or 1 else 1
	local list = {}
	for _, other in _snap.units do
		if other.alive and other.faction ~= unit.faction then
			if AERules.InRange(unit.x, unit.y, other.x, other.y, rangeMin, rangeMax) then
				table.insert(list, { x = other.x, y = other.y, id = other.id })
			end
		end
	end
	return list
end

--[[
	当前格能否占领
	@param unit table - 单位
	@return boolean - 可以
]]
local function _canOccupy(unit: any): boolean
	if not _snap or unit.acted then
		return false
	end
	for _, tile in AERules.CellsFromSnap(_snap) do
		if tile.x == unit.x and tile.y == unit.y then
			return AERules.CanOccupy(tile.legend, tile.owner, unit.faction)
		end
	end
	return false
end

--[[
	刷新高亮
	@return nil
]]
local function _refreshHighlight()
	local unit = _selectedId and _unitById(_selectedId)
	if _attackMode and unit then
		BoardView.HighlightAttack(_enemiesInRange(unit))
		return
	end
	BoardView.Highlight(_reachList(), unit and unit.x, unit and unit.y)
end

--[[
	指针是否在战棋 HUD 实心底上（顶栏/卡/按钮）
	@return boolean - 在 HUD 上
]]
local function _isPointerOverHud(): boolean
	if ActionRing.IsPointerOver() then
		return true
	end
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
	点中环形按钮
	@param actionId string - Attack / Occupy / Wait
	@return nil
]]
local function _onRingPick(actionId: string)
	if not _snap or not _onAction or not _selectedId then
		return
	end
	if actionId == "Attack" then
		_attackMode = true
		_refreshHighlight()
		return
	end
	if actionId == "Occupy" then
		_attackMode = false
		ActionRing.Hide()
		_onAction(EnumMgr.AEAction.Occupy, { unitId = _selectedId })
		return
	end
	if actionId == "Wait" then
		_attackMode = false
		ActionRing.Hide()
		_onAction(EnumMgr.AEAction.Wait, { unitId = _selectedId })
	end
end

--[[
	按选中单位刷新操作环
	@return nil
]]
local function _refreshRing()
	if BoardView.IsBusy() then
		ActionRing.Hide()
		return
	end
	if not _snap or not _selectedId or _snap.turnFaction ~= EnumMgr.AEFaction.Player or _snap.result then
		ActionRing.Hide()
		return
	end
	local unit = _unitById(_selectedId)
	if not unit or not unit.alive or unit.acted or unit.faction ~= EnumMgr.AEFaction.Player then
		ActionRing.Hide()
		return
	end
	local actions = {}
	if #_enemiesInRange(unit) > 0 then
		table.insert(actions, { id = "Attack", key = "攻击" })
	end
	if _canOccupy(unit) then
		table.insert(actions, { id = "Occupy", key = "占领" })
	end
	table.insert(actions, { id = "Wait", key = "待命" })
	ActionRing.Show(unit.id, actions, _onRingPick)
end

--[[
	处理一次点击。只认地面格，避免邻格棋子模型互相挡。
	@return nil
]]
local function _onClick()
	if not _snap or not _onAction then
		return
	end
	if BoardView.IsBusy() then
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
			_attackMode = false
			_refreshHighlight()
			_refreshRing()
			if _onSelect then
				_onSelect()
			end
			return
		end
		if _selectedId and _attackMode then
			_onAction(EnumMgr.AEAction.Attack, { unitId = _selectedId, targetId = occupant.id })
			_attackMode = false
			return
		end
	end
	if _attackMode then
		_attackMode = false
		_refreshHighlight()
		_refreshRing()
		return
	end
	if _selectedId then
		local unit = _unitById(_selectedId)
		if unit and not unit.moved and not unit.acted then
			ActionRing.Hide()
			_onAction(EnumMgr.AEAction.Move, { unitId = _selectedId, x = x, y = y })
		end
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
	BoardView.SetWalkDoneListener(function()
		_refreshHighlight()
		_refreshRing()
	end)
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
	_attackMode = false
	_refreshHighlight()
	_updateHover()
	_refreshRing()
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
	_attackMode = false
	BoardView.SetWalkDoneListener(nil)
	ActionRing.Hide()
	BoardView.ClearHighlights()
	BoardView.ClearHover()
	BoardView.ClearPath()
end

return Input
