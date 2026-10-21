--[[
	Module: BoardView
	Description: 按快照生成棋盘 Part 与棋子表现；只插值，不回写权威
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local SystemGameConfig = Utils.SystemGameConfig
local EnumMgr = Utils.EnumMgr
local AERules = Utils.AERules

local MOVE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BoardView = {}

local FOLDER_NAME = "TbsBoard"
local TILE_ATTR = "TbsTile"
local UNIT_ATTR = "TbsUnit"

local _folder: Folder? = nil
local _tiles: { [string]: BasePart } = {}
local _units: { [number]: Model } = {}
local _highlights: { BasePart } = {}
local _selected: BasePart? = nil
local _unitCell: { [number]: string } = {}

--[[
	格子边长
	@return number - studs
]]
local function _tileSize(): number
	return tonumber(SystemGameConfig.GetValue({ "战棋系统", "格子边长" })) or 8
end

--[[
	棋盘世界高度
	@return number - Y
]]
local function _boardY(): number
	return tonumber(SystemGameConfig.GetValue({ "战棋系统", "棋盘高度" })) or 200
end

--[[
	格中心世界坐标
	@param x number - 列
	@param y number - 行
	@return Vector3 - 中心
]]
function BoardView.CellCenter(x: number, y: number): Vector3
	local size = _tileSize()
	return Vector3.new(x * size, _boardY(), y * size)
end

--[[
	世界坐标反推格
	@param pos Vector3 - 世界点
	@return number? - 列
	@return number? - 行
]]
function BoardView.WorldToCell(pos: Vector3): (number?, number?)
	local size = _tileSize()
	local x = math.floor(pos.X / size + 0.5)
	local y = math.floor(pos.Z / size + 0.5)
	return x, y
end

--[[
	棋盘中心
	@param w number - 宽
	@param h number - 高
	@return Vector3 - 中心
]]
function BoardView.BoardCenter(w: number, h: number): Vector3
	return BoardView.CellCenter((w - 1) * 0.5, (h - 1) * 0.5)
end

--[[
	地形颜色
	@param legend string - 图例
	@return Color3 - 颜色
]]
local function _tileColor(legend: string): Color3
	if legend == "T" then
		return Color3.fromRGB(36, 92, 42)
	end
	if legend == "V" then
		return Color3.fromRGB(186, 154, 86)
	end
	if legend == "C" then
		return Color3.fromRGB(128, 128, 140)
	end
	return Color3.fromRGB(118, 160, 78)
end

--[[
	保证棋盘 Folder
	@return Folder - workspace.TbsBoard
]]
local function _ensureFolder(): Folder
	if _folder and _folder.Parent then
		return _folder
	end
	local exist = Workspace:FindFirstChild(FOLDER_NAME)
	if exist and exist:IsA("Folder") then
		_folder = exist
		return exist
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	_folder = folder
	return folder
end

--[[
	清高亮
	@return nil
]]
function BoardView.ClearHighlights()
	for _, part in _highlights do
		part:Destroy()
	end
	table.clear(_highlights)
	if _selected then
		_selected:Destroy()
		_selected = nil
	end
end

--[[
	清棋盘
	@return nil
]]
function BoardView.Clear()
	BoardView.ClearHighlights()
	for _, part in _tiles do
		part:Destroy()
	end
	table.clear(_tiles)
	for _, model in _units do
		model:Destroy()
	end
	table.clear(_units)
	table.clear(_unitCell)
	if _folder then
		_folder:ClearAllChildren()
	end
end

--[[
	铺一颗装饰（树/房/堡）
	@param parent BasePart - 格子
	@param legend string - 图例
	@param owner number - 归属
	@return nil
]]
local function _decorate(parent: BasePart, legend: string, owner: number)
	if legend == "T" then
		local trunk = Instance.new("Part")
		trunk.Name = "Tree"
		trunk.Anchored = true
		trunk.CanCollide = false
		trunk.Material = Enum.Material.Wood
		trunk.Color = Color3.fromRGB(90, 58, 32)
		trunk.Size = Vector3.new(0.7, 3, 0.7)
		trunk.CFrame = parent.CFrame * CFrame.new(0, 2, 0)
		trunk.Parent = parent
		local leaf = Instance.new("Part")
		leaf.Name = "Leaf"
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.Material = Enum.Material.Grass
		leaf.Color = Color3.fromRGB(28, 110, 46)
		leaf.Size = Vector3.new(2.4, 2.2, 2.4)
		leaf.CFrame = parent.CFrame * CFrame.new(0, 4.2, 0)
		leaf.Parent = parent
		return
	end
	if legend == "V" or legend == "C" then
		local house = Instance.new("Part")
		house.Name = if legend == "C" then "Keep" else "House"
		house.Anchored = true
		house.CanCollide = false
		house.Material = Enum.Material.Brick
		house.Color = if owner == EnumMgr.AEFaction.Player
			then Color3.fromRGB(70, 140, 80)
			elseif owner == EnumMgr.AEFaction.Enemy then Color3.fromRGB(160, 60, 60)
			else Color3.fromRGB(170, 150, 120)
		local h = if legend == "C" then 4.5 else 2.4
		house.Size = Vector3.new(3.2, h, 3.2)
		house.CFrame = parent.CFrame * CFrame.new(0, h * 0.5 + 0.4, 0)
		house.Parent = parent
	end
end

--[[
	建棋子模型
	@param unit table - UnitSnap
	@return Model - 表现
]]
local function _makeUnit(unit: any): Model
	local model = Instance.new("Model")
	model.Name = "Unit_" .. tostring(unit.id)
	model:SetAttribute(UNIT_ATTR, unit.id)
	local height = if unit.unitType == EnumMgr.AEUnitId.Commander then 4.2 else 3.2
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = if unit.faction == EnumMgr.AEFaction.Player
		then Color3.fromRGB(64, 180, 96)
		else Color3.fromRGB(200, 64, 64)
	body.Size = Vector3.new(2.2, height, 2.2)
	body.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.CanCollide = false
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.SmoothPlastic
	head.Color = body.Color:Lerp(Color3.new(1, 1, 1), 0.2)
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Parent = model
	model.PrimaryPart = body
	local folder = _ensureFolder()
	model.Parent = folder
	local center = BoardView.CellCenter(unit.x, unit.y)
	body.CFrame = CFrame.new(center + Vector3.new(0, height * 0.5 + 0.6, 0))
	head.CFrame = CFrame.new(center + Vector3.new(0, height + 1.1, 0))
	return model
end

--[[
	把棋子摆到格上（坐标变了才插值）
	@param model Model - 棋子
	@param unit table - UnitSnap
	@param instant boolean - 新棋子直接落点
	@return nil
]]
local function _placeUnit(model: Model, unit: any, instant: boolean)
	local key = unit.x .. "," .. unit.y
	if not instant and _unitCell[unit.id] == key then
		return
	end
	local height = if unit.unitType == EnumMgr.AEUnitId.Commander then 4.2 else 3.2
	local center = BoardView.CellCenter(unit.x, unit.y)
	local body = model:FindFirstChild("Body")
	local head = model:FindFirstChild("Head")
	local bodyCf = CFrame.new(center + Vector3.new(0, height * 0.5 + 0.6, 0))
	local headCf = CFrame.new(center + Vector3.new(0, height + 1.1, 0))
	local shouldTween = not instant and _unitCell[unit.id] ~= nil
	_unitCell[unit.id] = key
	if body and body:IsA("BasePart") then
		if shouldTween then
			TweenService:Create(body, MOVE_TWEEN, { CFrame = bodyCf }):Play()
		else
			body.CFrame = bodyCf
		end
	end
	if head and head:IsA("BasePart") then
		if shouldTween then
			TweenService:Create(head, MOVE_TWEEN, { CFrame = headCf }):Play()
		else
			head.CFrame = headCf
		end
	end
end

--[[
	应用快照
	@param snap table - MatchSnap
	@return nil
]]
function BoardView.Apply(snap: any)
	local folder = _ensureFolder()
	local tileList = AERules.CellsFromSnap(snap)
	for _, tile in tileList do
		local key = tile.x .. "," .. tile.y
		local part = _tiles[key]
		if not part then
			part = Instance.new("Part")
			part.Name = "Tile_" .. key
			part.Anchored = true
			part.CanCollide = false
			part.Material = Enum.Material.Grass
			part.Size = Vector3.new(_tileSize() - 0.2, 1, _tileSize() - 0.2)
			part:SetAttribute(TILE_ATTR, key)
			part:SetAttribute("X", tile.x)
			part:SetAttribute("Y", tile.y)
			part.Parent = folder
			_tiles[key] = part
		end
		part.Color = _tileColor(tile.legend)
		part.CFrame = CFrame.new(BoardView.CellCenter(tile.x, tile.y))
		for _, child in part:GetChildren() do
			child:Destroy()
		end
		_decorate(part, tile.legend, tile.owner)
	end

	local alive = {}
	for _, unit in snap.units do
		if unit.alive then
			alive[unit.id] = true
			local model = _units[unit.id]
			local created = false
			if not model then
				model = _makeUnit(unit)
				_units[unit.id] = model
				created = true
			end
			_placeUnit(model, unit, created)
		end
	end
	for id, model in _units do
		if not alive[id] then
			model:Destroy()
			_units[id] = nil
			_unitCell[id] = nil
		end
	end
end

--[[
	高亮可走格与选中格
	@param cells { { x: number, y: number } } - 可走
	@param selectedX number? - 选中列
	@param selectedY number? - 选中行
	@return nil
]]
function BoardView.Highlight(cells: { any }, selectedX: number?, selectedY: number?)
	BoardView.ClearHighlights()
	local folder = _ensureFolder()
	for _, cell in cells do
		local mark = Instance.new("Part")
		mark.Name = "Reach"
		mark.Anchored = true
		mark.CanCollide = false
		mark.Material = Enum.Material.Neon
		mark.Color = Color3.fromRGB(70, 180, 255)
		mark.Transparency = 0.55
		mark.Size = Vector3.new(_tileSize() - 1.2, 0.2, _tileSize() - 1.2)
		mark.CFrame = CFrame.new(BoardView.CellCenter(cell.x, cell.y) + Vector3.new(0, 0.62, 0))
		mark.Parent = folder
		table.insert(_highlights, mark)
	end
	if selectedX ~= nil and selectedY ~= nil then
		local sel = Instance.new("Part")
		sel.Name = "Selected"
		sel.Anchored = true
		sel.CanCollide = false
		sel.Material = Enum.Material.Neon
		sel.Color = Color3.fromRGB(255, 220, 70)
		sel.Transparency = 0.35
		sel.Size = Vector3.new(_tileSize() - 0.6, 0.22, _tileSize() - 0.6)
		sel.CFrame = CFrame.new(BoardView.CellCenter(selectedX, selectedY) + Vector3.new(0, 0.7, 0))
		sel.Parent = folder
		_selected = sel
	end
end

--[[
	从 Part 读格坐标
	@param inst Instance? - 点到的实例
	@return number? - 列
	@return number? - 行
]]
function BoardView.CellFromInstance(inst: Instance?): (number?, number?)
	local cursor: Instance? = inst
	while cursor do
		if cursor:IsA("BasePart") then
			local x = cursor:GetAttribute("X")
			local y = cursor:GetAttribute("Y")
			if typeof(x) == "number" and typeof(y) == "number" then
				return x, y
			end
			local parent = cursor.Parent
			if parent and parent:IsA("BasePart") then
				local px = parent:GetAttribute("X")
				local py = parent:GetAttribute("Y")
				if typeof(px) == "number" and typeof(py) == "number" then
					return px, py
				end
			end
		end
		if cursor:IsA("Model") then
			local id = cursor:GetAttribute(UNIT_ATTR)
			if typeof(id) == "number" then
				return nil, nil, id
			end
		end
		cursor = cursor.Parent
	end
	return nil, nil
end

--[[
	点到的棋子 Id
	@param inst Instance? - 实例
	@return number? - 单位 Id
]]
function BoardView.UnitIdFromInstance(inst: Instance?): number?
	local cursor: Instance? = inst
	while cursor do
		if cursor:IsA("Model") then
			local id = cursor:GetAttribute(UNIT_ATTR)
			if typeof(id) == "number" then
				return id
			end
		end
		cursor = cursor.Parent
	end
	return nil
end

return BoardView
