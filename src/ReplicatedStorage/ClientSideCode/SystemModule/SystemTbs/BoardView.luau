--[[
	Module: BoardView
	Description: 按快照生成棋盘与 R6 棋子；只插值，不回写权威、不写玩家角色。
	棋盘视觉走 BoardDecor。移动按路径逐格走并播 WalkForward。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21

	能力：
	- Apply：地砖与棋子；有 movePaths 时按格走，否则落点
	- Highlight / ShowPath / SetHover：可达、预览路径、悬浮
	- CellFromScreen：点选按地面格平面取格

	约束：棋子 CFrame 只由本模块写；HRP 保持锚定；不写玩家角色。
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Players = Utils.Players
local SystemGameConfig = Utils.SystemGameConfig
local EnumMgr = Utils.EnumMgr
local AERules = Utils.AERules
local AnimationModule = Utils.AnimationModule
local Log = Utils.Log

local BoardDecor = require(script.Parent.BoardDecor)

local MOVE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local PATH_COLOR = Color3.fromRGB(255, 230, 90)

local BoardView = {}

local FOLDER_NAME = "TbsBoard"
local TILE_ATTR = "TbsTile"
local UNIT_ATTR = "TbsUnit"

local _folder: Folder? = nil
local _tiles: { [string]: BasePart } = {}
local _units: { [number]: Model } = {}
local _highlights: { BasePart } = {}
local _pathMarks: { BasePart } = {}
local _selected: BasePart? = nil
local _hover: BasePart? = nil
local _hoverKey = ""
local _unitCell: { [number]: string } = {}
local _unitSnap: { [number]: any } = {}
local _walking: { [number]: boolean } = {}
local _walkTween: { [number]: Tween } = {}
local _walkGen = 0
local _walkBusy = false

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
	清路径标记
	@return nil
]]
function BoardView.ClearPath()
	for _, part in _pathMarks do
		part:Destroy()
	end
	table.clear(_pathMarks)
end

--[[
	清高亮（不含路径）
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
	清悬浮格
	@return nil
]]
function BoardView.ClearHover()
	if _hover then
		_hover:Destroy()
		_hover = nil
	end
	_hoverKey = ""
end

--[[
	是否正在按路径走
	@return boolean - 走路中
]]
function BoardView.IsWalking(): boolean
	return _walkBusy
end

--[[
	画移动路径（金点 + 连线，不挡点选）
	@param cells { { x: number, y: number } } - 含起终点
	@return nil
]]
function BoardView.ShowPath(cells: { any })
	BoardView.ClearPath()
	if type(cells) ~= "table" or #cells < 2 then
		return
	end
	local folder = _ensureFolder()
	local size = _tileSize()
	for i, cell in cells do
		local mark = Instance.new("Part")
		mark.Name = "PathDot"
		mark.Anchored = true
		mark.CanCollide = false
		mark.CanQuery = false
		mark.CanTouch = false
		mark.Material = Enum.Material.Neon
		mark.Color = PATH_COLOR
		mark.Transparency = if i == #cells then 0.15 else 0.4
		mark.Size = Vector3.new(size - 2.6, 0.16, size - 2.6)
		mark.CFrame = CFrame.new(BoardView.CellCenter(cell.x, cell.y) + Vector3.new(0, 0.76, 0))
		mark.Parent = folder
		table.insert(_pathMarks, mark)
		if i < #cells then
			local nxt = cells[i + 1]
			local a = BoardView.CellCenter(cell.x, cell.y)
			local b = BoardView.CellCenter(nxt.x, nxt.y)
			local mid = (a + b) * 0.5 + Vector3.new(0, 0.82, 0)
			local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local len = math.max(1.2, delta.Magnitude - 2.2)
			local bar = Instance.new("Part")
			bar.Name = "PathLink"
			bar.Anchored = true
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CanTouch = false
			bar.Material = Enum.Material.Neon
			bar.Color = PATH_COLOR
			bar.Transparency = 0.25
			bar.Size = Vector3.new(0.42, 0.12, len)
			bar.CFrame = CFrame.lookAt(mid, mid + delta)
			bar.Parent = folder
			table.insert(_pathMarks, bar)
		end
	end
end

--[[
	棋子落点（脚踩格面，可指定朝向）
	@param x number - 列
	@param y number - 行
	@param model Model - 棋子
	@param lookX number? - 朝向列；缺省按阵营
	@param lookY number? - 朝向行
	@param faction number? - 阵营（无朝向时用）
	@return CFrame - 根部位姿
]]
local function _pivotAt(x: number, y: number, model: Model, lookX: number?, lookY: number?, faction: number?): CFrame
	local center = BoardView.CellCenter(x, y)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local hip = if humanoid then humanoid.HipHeight else 2
	local hrpY = if hrp and hrp:IsA("BasePart") then hrp.Size.Y * 0.5 else 1
	local pos = Vector3.new(center.X, _boardY() + 0.5 + hip + hrpY, center.Z)
	if lookX ~= nil and lookY ~= nil and (lookX ~= x or lookY ~= y) then
		local look = BoardView.CellCenter(lookX, lookY)
		return CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z))
	end
	local yaw = if faction == EnumMgr.AEFaction.Player then math.pi else 0
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
end

--[[
	棋子落到单位当前格
	@param unit table - UnitSnap
	@param model Model - 棋子
	@return CFrame - 根部位姿
]]
local function _unitPivot(unit: any, model: Model): CFrame
	return _pivotAt(unit.x, unit.y, model, nil, nil, unit.faction)
end

--[[
	取模型 Animator，没有则建
	@param model Model - 棋子
	@return Animator? - 动画器
]]
local function _animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

--[[
	播或停走路
	@param model Model - 棋子
	@param walking boolean - 走路中
	@return nil
]]
local function _setWalkAnim(model: Model, walking: boolean)
	local animator = _animatorOf(model)
	if not animator then
		return
	end
	if walking then
		local track = AnimationModule.LoadAnimationTrack(
			animator,
			"WalkForward",
			1,
			nil,
			nil,
			Enum.AnimationPriority.Movement
		)
		if track then
			track.Looped = true
			if not track.IsPlaying then
				track:Play(0.1)
			end
		end
		return
	end
	AnimationModule.StopAnim(animator, "WalkForward", 0.12)
	AnimationModule.PlayAnim(animator, "Idle", 1, nil, nil, Enum.AnimationPriority.Idle, 0.12)
end

--[[
	打断全部走路并钉到逻辑格
	@return nil
]]
local function _cancelWalks()
	_walkGen += 1
	_walkBusy = false
	for _, tween in _walkTween do
		tween:Cancel()
	end
	table.clear(_walkTween)
	for id, model in _units do
		if _walking[id] then
			_setWalkAnim(model, false)
			local unit = _unitSnap[id]
			if unit and model.Parent then
				model:PivotTo(_unitPivot(unit, model))
			end
		end
	end
	table.clear(_walking)
end

--[[
	按路径逐格走（仅写本棋子 HRP）
	@param model Model - 棋子
	@param unit table - UnitSnap
	@param cells { any } - 路径
	@param gen number - 走路代数
	@return nil
]]
local function _walkUnit(model: Model, unit: any, cells: { any }, gen: number)
	if gen ~= _walkGen or not model.Parent or type(cells) ~= "table" or #cells < 2 then
		return
	end
	_walking[unit.id] = true
	_setWalkAnim(model, true)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		_walking[unit.id] = nil
		return
	end
	for i = 2, #cells do
		if gen ~= _walkGen or not model.Parent then
			break
		end
		local dest = cells[i]
		local prev = cells[i - 1]
		local target = _pivotAt(
			dest.x,
			dest.y,
			model,
			dest.x + (dest.x - prev.x),
			dest.y + (dest.y - prev.y),
			unit.faction
		)
		local tween = TweenService:Create(hrp, MOVE_TWEEN, { CFrame = target })
		_walkTween[unit.id] = tween
		tween:Play()
		tween.Completed:Wait()
		_walkTween[unit.id] = nil
	end
	if gen == _walkGen and model.Parent then
		model:PivotTo(_unitPivot(unit, model))
		_setWalkAnim(model, false)
	end
	_walking[unit.id] = nil
end

--[[
	串行走路队列
	@param jobs { any } - { model, unit, cells }
	@param gen number - 走路代数
	@return nil
]]
local function _runWalkJobs(jobs: { any }, gen: number)
	if gen ~= _walkGen then
		return
	end
	_walkBusy = true
	for _, job in jobs do
		if gen ~= _walkGen then
			return
		end
		BoardView.ShowPath(job.cells)
		_walkUnit(job.model, job.unit, job.cells, gen)
	end
	if gen == _walkGen then
		BoardView.ClearPath()
		_walkBusy = false
	end
end

--[[
	从旧格兜底还原路径
	@param snap table - MatchSnap
	@param unit table - 已在终点的单位
	@param oldKey string - 旧 "x,y"
	@return { any }? - 路径
]]
local function _fallbackPath(snap: any, unit: any, oldKey: string): { any }?
	local sx, sy = string.match(oldKey, "^(%-?%d+),(%-?%d+)$")
	local startX = tonumber(sx)
	local startY = tonumber(sy)
	if startX == nil or startY == nil then
		return nil
	end
	if startX == unit.x and startY == unit.y then
		return nil
	end
	local ghost = {
		id = unit.id,
		unitType = unit.unitType,
		faction = unit.faction,
		x = startX,
		y = startY,
		alive = true,
	}
	local spec = AERules.MoveSpecFromSnap(snap, ghost, unit.x, unit.y)
	if not spec then
		return nil
	end
	return AERules.FindPath(spec)
end

--[[
	清棋盘
	@return nil
]]
function BoardView.Clear()
	_cancelWalks()
	BoardView.ClearHighlights()
	BoardView.ClearHover()
	BoardView.ClearPath()
	for _, part in _tiles do
		part:Destroy()
	end
	table.clear(_tiles)
	for _, model in _units do
		model:Destroy()
	end
	table.clear(_units)
	table.clear(_unitCell)
	table.clear(_unitSnap)
	BoardDecor.ResetIsland()
	if _folder then
		_folder:ClearAllChildren()
	end
end

--[[
	是否我方指挥官（用玩家形象）
	@param unit table - UnitSnap
	@return boolean - 是
]]
local function _isPlayerCommander(unit: any): boolean
	return unit.unitType == EnumMgr.AEUnitId.Commander and unit.faction == EnumMgr.AEFaction.Player
end

--[[
	读配置里的服装 Id
	@param cfg table - 兵种行
	@param enemy boolean - 敌方用敌方列
	@param field string - 我方字段
	@param enemyField string - 敌方字段
	@return number - 资产 Id，缺省 0
]]
local function _lookId(cfg: any, enemy: boolean, field: string, enemyField: string): number
	local raw = if enemy then cfg[enemyField] else cfg[field]
	if (raw == nil or raw == 0 or raw == "") and enemy then
		raw = cfg[field]
	end
	return tonumber(raw) or 0
end

--[[
	读配置帽子串
	@param cfg table - 兵种行
	@param enemy boolean - 敌方
	@return string - 逗号分隔 Id
]]
local function _hatList(cfg: any, enemy: boolean): string
	local raw = if enemy then cfg.EnemyHatAccessory else cfg.HatAccessory
	if (raw == nil or raw == "") and enemy then
		raw = cfg.HatAccessory
	end
	if type(raw) ~= "string" then
		return ""
	end
	return raw
end

--[[
	按兵种+阵营填 HumanoidDescription（T恤 / 衬衫 / 裤子 / 帽子）
	@param unit table - UnitSnap
	@return HumanoidDescription - 外观
]]
local function _descFromCfg(unit: any): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local cfg = AERules.GetUnitCfg(unit.unitType)
	local enemy = unit.faction == EnumMgr.AEFaction.Enemy
	if type(cfg) == "table" then
		desc.GraphicTShirt = _lookId(cfg, enemy, "GraphicTShirt", "EnemyGraphicTShirt")
		desc.Shirt = _lookId(cfg, enemy, "Shirt", "EnemyShirt")
		desc.Pants = _lookId(cfg, enemy, "Pants", "EnemyPants")
		desc.HatAccessory = _hatList(cfg, enemy)
	end
	if enemy then
		desc.HeadColor = Color3.fromRGB(232, 190, 176)
		desc.LeftArmColor = Color3.fromRGB(232, 190, 176)
		desc.RightArmColor = Color3.fromRGB(232, 190, 176)
		desc.TorsoColor = Color3.fromRGB(140, 48, 48)
		desc.LeftLegColor = Color3.fromRGB(90, 40, 40)
		desc.RightLegColor = Color3.fromRGB(90, 40, 40)
	else
		desc.HeadColor = Color3.fromRGB(204, 142, 105)
		desc.LeftArmColor = Color3.fromRGB(204, 142, 105)
		desc.RightArmColor = Color3.fromRGB(204, 142, 105)
		desc.TorsoColor = Color3.fromRGB(70, 140, 90)
		desc.LeftLegColor = Color3.fromRGB(50, 80, 60)
		desc.RightLegColor = Color3.fromRGB(50, 80, 60)
	end
	return desc
end

--[[
	取本地玩家当前形象；失败再拉 UserId 形象
	@return HumanoidDescription? - 可套到 R6
]]
local function _playerDesc(): HumanoidDescription?
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, applied = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok and applied then
			return applied:Clone()
		end
	end
	if not localPlayer then
		return nil
	end
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(localPlayer.UserId)
	end)
	if ok and desc then
		return desc
	end
	return nil
end

--[[
	去掉会走路/回血的脚本，保留站立
	@param model Model - R6
	@return nil
]]
local function _stripScripts(model: Model)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BaseScript") and inst.Name ~= "Animate" then
			inst:Destroy()
		end
	end
end

--[[
	钉住棋子：只锚 HRP，不写玩家角色
	@param model Model - R6
	@return nil
]]
local function _freezeRig(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		model.PrimaryPart = hrp
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.Massless = true
			inst.Anchored = inst.Name == "HumanoidRootPart"
		end
	end
end

--[[
	用描述生成 R6（Async API 优先）
	@param desc HumanoidDescription - 外观
	@return Model? - 人模
]]
local function _createR6(desc: HumanoidDescription): Model?
	local ok, model = pcall(function()
		local asyncFn = (Players :: any).CreateHumanoidModelFromDescriptionAsync
		if typeof(asyncFn) == "function" then
			return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R6)
		end
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	Log.warn("BoardView 创建 R6 失败", model)
	return nil
end

--[[
	异步把占位换成穿衣 R6
	@param model Model - 棋子容器
	@param unit table - UnitSnap
	@return nil
]]
local function _fillR6(model: Model, unit: any)
	task.spawn(function()
		local desc: HumanoidDescription? = nil
		if _isPlayerCommander(unit) then
			desc = _playerDesc()
		end
		if not desc then
			desc = _descFromCfg(unit)
		end
		local rig = _createR6(desc)
		if desc and desc.Parent == nil then
			desc:Destroy()
		end
		if not rig or not model.Parent then
			if rig then
				rig:Destroy()
			end
			return
		end
		_stripScripts(rig)
		_freezeRig(rig)
		local stub = model:FindFirstChild("HumanoidRootPart")
		for _, child in rig:GetChildren() do
			child.Parent = model
		end
		rig:Destroy()
		if stub and stub.Parent == model and #model:GetChildren() > 1 then
			local real = nil
			for _, child in model:GetChildren() do
				if child.Name == "HumanoidRootPart" and child ~= stub then
					real = child
					break
				end
			end
			if real then
				stub:Destroy()
			end
		end
		_freezeRig(model)
		if model.Parent and not _walking[unit.id] then
			local live = _unitSnap[unit.id] or unit
			model:PivotTo(_unitPivot(live, model))
		end
	end)
end

--[[
	建棋子：先占位，再异步套 R6 衣服/玩家形象
	@param unit table - UnitSnap
	@return Model - 表现
]]
local function _makeUnit(unit: any): Model
	local model = Instance.new("Model")
	model.Name = "Unit_" .. tostring(unit.id)
	model:SetAttribute(UNIT_ATTR, unit.id)
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.CanQuery = false
	hrp.CanTouch = false
	hrp.Transparency = 1
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Parent = model
	model.PrimaryPart = hrp
	local folder = _ensureFolder()
	model.Parent = folder
	model:PivotTo(_unitPivot(unit, model))
	_fillR6(model, unit)
	return model
end

--[[
	把棋子摆到格上（坐标变了才落点；路径走不走这里）
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
	local target = _unitPivot(unit, model)
	local shouldTween = not instant and _unitCell[unit.id] ~= nil
	_unitCell[unit.id] = key
	if _walking[unit.id] then
		return
	end
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		if shouldTween then
			TweenService:Create(hrp, MOVE_TWEEN, { CFrame = target }):Play()
		else
			model:PivotTo(target)
		end
		return
	end
	model:PivotTo(target)
end

--[[
	应用快照
	@param snap table - MatchSnap
	@return nil
]]
function BoardView.Apply(snap: any)
	local folder = _ensureFolder()
	local tileList = AERules.CellsFromSnap(snap)
	local size = _tileSize()
	BoardDecor.EnsureIsland(folder, tonumber(snap.w) or 10, tonumber(snap.h) or 8, size, BoardView.CellCenter, _boardY())
	for _, tile in tileList do
		local key = tile.x .. "," .. tile.y
		local part = _tiles[key]
		if not part then
			part = Instance.new("Part")
			part.Name = "Tile_" .. key
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = true
			part.Material = BoardDecor.MAT
			part.MaterialVariant = BoardDecor.VARIANT
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Size = Vector3.new(size - 0.08, 1, size - 0.08)
			part:SetAttribute(TILE_ATTR, key)
			part:SetAttribute("X", tile.x)
			part:SetAttribute("Y", tile.y)
			part.Parent = folder
			_tiles[key] = part
		end
		part.Material = BoardDecor.MAT
		part.MaterialVariant = BoardDecor.VARIANT
		part.Color = BoardDecor.TileColor(tile.legend, tile.x, tile.y)
		part.CFrame = CFrame.new(BoardView.CellCenter(tile.x, tile.y))
		local decorKey = tostring(tile.legend) .. ":" .. tostring(tile.owner)
		if part:GetAttribute("DecorKey") ~= decorKey then
			part:SetAttribute("DecorKey", decorKey)
			BoardDecor.Apply(part, tile.legend, tile.owner, tile.x, tile.y)
		end
	end

	local pathById: { [number]: { any } } = {}
	local pathOrder: { number } = {}
	if type(snap.movePaths) == "table" then
		for _, entry in snap.movePaths do
			local id = tonumber(entry and entry.unitId)
			if id and type(entry.cells) == "table" and #entry.cells >= 2 then
				pathById[id] = entry.cells
				table.insert(pathOrder, id)
			end
		end
	end
	if #pathOrder > 0 then
		_cancelWalks()
	end

	local pendingWalk: { [number]: any } = {}
	local alive = {}
	for _, unit in snap.units do
		if unit.alive then
			alive[unit.id] = true
			_unitSnap[unit.id] = unit
			local model = _units[unit.id]
			local created = false
			if not model then
				model = _makeUnit(unit)
				_units[unit.id] = model
				created = true
			end
			local key = unit.x .. "," .. unit.y
			local path = pathById[unit.id]
			if not path and not created then
				local oldKey = _unitCell[unit.id]
				if oldKey and oldKey ~= key then
					path = _fallbackPath(snap, unit, oldKey)
				end
			end
			if path and not created then
				_unitCell[unit.id] = key
				pendingWalk[unit.id] = { model = model, unit = unit, cells = path }
			else
				_placeUnit(model, unit, created)
			end
		end
	end
	local walkJobs = {}
	for _, id in pathOrder do
		local job = pendingWalk[id]
		if job then
			table.insert(walkJobs, job)
			pendingWalk[id] = nil
		end
	end
	for _, job in pendingWalk do
		table.insert(walkJobs, job)
	end
	for id, model in _units do
		if not alive[id] then
			_walking[id] = nil
			model:Destroy()
			_units[id] = nil
			_unitCell[id] = nil
			_unitSnap[id] = nil
		end
	end
	if #walkJobs > 0 then
		local gen = _walkGen
		task.spawn(_runWalkJobs, walkJobs, gen)
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
		mark.CanQuery = false
		mark:SetAttribute("X", cell.x)
		mark:SetAttribute("Y", cell.y)
		mark.Material = Enum.Material.Neon
		mark.Color = BoardDecor.REACH
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
		sel.CanQuery = false
		sel:SetAttribute("X", selectedX)
		sel:SetAttribute("Y", selectedY)
		sel.Material = Enum.Material.Neon
		sel.Color = BoardDecor.GOLD
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
				return nil, nil
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

--[[
	屏幕点投影到棋盘地面格
	@param screenPos Vector2 - GetMouseLocation，含 inset
	@return number? - 列
	@return number? - 行
]]
function BoardView.CellFromScreen(screenPos: Vector2): (number?, number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local origin = ray.Origin
	local dir = ray.Direction
	if math.abs(dir.Y) < 1e-4 then
		return nil, nil
	end
	local t = (_boardY() - origin.Y) / dir.Y
	if t < 0 then
		return nil, nil
	end
	local hit = origin + dir * t
	local x, y = BoardView.WorldToCell(hit)
	if x == nil or y == nil then
		return nil, nil
	end
	if _tiles[x .. "," .. y] then
		return x, y
	end
	return nil, nil
end

--[[
	刷新鼠标悬浮格
	@param _unitId number? - 格上单位；本版只亮格
	@param x number? - 列；nil 清除
	@param y number? - 行
	@return nil
]]
function BoardView.SetHover(_unitId: number?, x: number?, y: number?)
	if x == nil or y == nil then
		BoardView.ClearHover()
		return
	end
	local key = x .. "," .. y
	if _hoverKey == key and _hover and _hover.Parent then
		return
	end
	BoardView.ClearHover()
	local folder = _ensureFolder()
	local mark = Instance.new("Part")
	mark.Name = "Hover"
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.Material = Enum.Material.Neon
	mark.Color = Color3.fromRGB(255, 255, 255)
	mark.Transparency = 0.65
	mark.Size = Vector3.new(_tileSize() - 0.9, 0.16, _tileSize() - 0.9)
	mark.CFrame = CFrame.new(BoardView.CellCenter(x, y) + Vector3.new(0, 0.58, 0))
	mark.Parent = folder
	_hover = mark
	_hoverKey = key
end

return BoardView
