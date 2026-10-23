--[[
	Module: BoardView
	Description: 按快照生成棋盘与棋子；只插值，不回写权威、不写玩家角色。
	棋盘视觉走 BoardDecor。水面贴近地面；非飞行兵下水陷入固定深度，飞龙贴水面。移动按路径逐格走并播 WalkForward。
	攻击表现走 CombatFx；棋子转向/前冲仍只写本模块 HumanRootPart。
	棋子主节点统一为 HumanRootPart（PrimaryPart），所有落点/走路只写该零件 CFrame。
	我方指挥官按本地玩家 UserId 生成完整人模整模挂上，不拆零件、不套兵种配置衣服。
	其余兵种用经典 Noob 底色 + 配置衬衫/裤子/帽子。指挥官与普通士兵右手持剑。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-23

	能力：
	- Apply：地砖与棋子；有 movePaths 时按格走，有 combatHits 时走完再打
	- Highlight / ShowPath / SetHover：可达、预览路径、悬浮
	- GetUnitModel / GetRootPart：给操作环取棋子根
	- CellFromScreen：点选按地面格平面取格
	- IsBusy：走路或攻击播放中

	约束：棋子 CFrame 只由本模块写；HumanRootPart 保持锚定；不写玩家角色。
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
local CombatFx = require(script.Parent.CombatFx)

local MOVE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local LUNGE_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LUNGE_BACK = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local LUNGE_DIST = 1.8
local PATH_COLOR = Color3.fromRGB(255, 230, 90)
local TILE_HALF = 0.5
local DEFAULT_HIP = 3
local ROOT_NAME = "HumanRootPart"
local HUM_ROOT_NAME = "HumanoidRootPart"
local SWORD_NAME = "TbsSword"
local NOOB_YELLOW = Color3.fromRGB(245, 205, 48)
local NOOB_BLUE = Color3.fromRGB(13, 105, 172)
local NOOB_GREEN = Color3.fromRGB(164, 189, 71)
local SWORD_STEEL = Color3.fromRGB(220, 224, 232)
local SWORD_GUARD = Color3.fromRGB(86, 86, 94)
local SWORD_HILT = Color3.fromRGB(168, 118, 58)

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
local _onWalkDone: (() -> ())? = nil

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
	走路或攻击播放中（点格 / 发意图应停）
	@return boolean - 忙碌
]]
function BoardView.IsBusy(): boolean
	return _walkBusy
end

--[[
	走路结束后回调（给操作环用）
	@param fn (() -> ())? - 回调；nil 清除
	@return nil
]]
function BoardView.SetWalkDoneListener(fn: (() -> ())?)
	_onWalkDone = fn
end

--[[
	取棋子模型
	@param unitId number - 单位 Id
	@return Model? - 棋子
]]
function BoardView.GetUnitModel(unitId: number): Model?
	return _units[unitId]
end

--[[
	取棋子主节点 HumanRootPart
	@param model Model - 棋子
	@return BasePart? - 根
]]
function BoardView.GetRootPart(model: Model): BasePart?
	local named = model:FindFirstChild(ROOT_NAME)
	if named and named:IsA("BasePart") then
		return named
	end
	return model.PrimaryPart
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
	棋子主节点：优先 HumanRootPart，没有则用 HumanoidRootPart。
	@param model Model - 棋子
	@return BasePart? - 根零件
]]
local function _rootOf(model: Model): BasePart?
	local named = model:FindFirstChild(ROOT_NAME)
	if named and named:IsA("BasePart") then
		return named
	end
	local hrp = model:FindFirstChild(HUM_ROOT_NAME, true)
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return nil
end

--[[
	把主节点钉成 HumanRootPart，并让 HumanoidRootPart 焊在上面。
	@param model Model - 棋子
	@return BasePart? - HumanRootPart
]]
local function _bindRoot(model: Model): BasePart?
	local root = model:FindFirstChild(ROOT_NAME)
	if not (root and root:IsA("BasePart")) then
		local hrp = model:FindFirstChild(HUM_ROOT_NAME, true)
		if hrp and hrp:IsA("BasePart") then
			root = Instance.new("Part")
			root.Name = ROOT_NAME
			root.Size = hrp.Size
			root.CFrame = hrp.CFrame
			root.Transparency = 1
			root.CanCollide = false
			root.CanQuery = false
			root.CanTouch = false
			root.Massless = true
			root.Anchored = true
			root.Parent = model
		end
	end
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	model.PrimaryPart = root
	model.WorldPivot = root.CFrame
	local humRoot = model:FindFirstChild(HUM_ROOT_NAME, true)
	if humRoot and humRoot:IsA("BasePart") and humRoot ~= root then
		humRoot.Anchored = false
		humRoot.Massless = true
		humRoot.CanCollide = false
		if (humRoot.Position - root.Position).Magnitude > 0.05 then
			humRoot.CFrame = root.CFrame
		end
		local hasWeld = false
		for _, inst in humRoot:GetChildren() do
			if inst:IsA("WeldConstraint") and (inst.Part0 == root or inst.Part1 == root) then
				hasWeld = true
				break
			end
		end
		if not hasWeld then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "RootBind"
			weld.Part0 = root
			weld.Part1 = humRoot
			weld.Parent = root
		end
	end
	return root
end

--[[
	根到脚底的距离。只认相对主节点的几何，不认 HipHeight / WorldPivot。
	@param model Model - 棋子
	@return number - 根中心到脚底
]]
local function _footLift(model: Model): number
	local root = _rootOf(model)
	if not root then
		return DEFAULT_HIP
	end
	local originY = root.Position.Y
	local lowest = originY
	local found = false
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst ~= root and inst.Name ~= ROOT_NAME then
			local holder = inst.Parent
			if not (holder and (holder:IsA("Accoutrement") or holder:IsA("Tool"))) then
				local bottom = inst.Position.Y - inst.Size.Y * 0.5
				if not found or bottom < lowest then
					lowest = bottom
					found = true
				end
			end
		end
	end
	if not found then
		return DEFAULT_HIP
	end
	local lift = originY - lowest
	if lift < 0.4 then
		return DEFAULT_HIP
	end
	return lift
end

--[[
	格图例
	@param x number - 列
	@param y number - 行
	@return string - 图例，缺格为平地
]]
local function _legendAt(x: number, y: number): string
	local part = _tiles[x .. "," .. y]
	if not part then
		return "."
	end
	local legend = part:GetAttribute("Legend")
	if typeof(legend) ~= "string" then
		return "."
	end
	return legend
end

--[[
	棋子相对棋盘的站位下沉（水面：非飞行陷入，飞龙贴水面）
	@param x number - 列
	@param y number - 行
	@param unitType number? - 兵种 Id
	@return number - Y 偏移
]]
local function _standOffset(x: number, y: number, unitType: number?): number
	local cfg = if unitType then AERules.GetUnitCfg(unitType) else nil
	return BoardDecor.StandOffset(_legendAt(x, y), AERules.IsFlyer(cfg))
end

--[[
	棋子落点（脚踩格面，可指定朝向）
	@param x number - 列
	@param y number - 行
	@param model Model - 棋子
	@param lookX number? - 朝向列；缺省按阵营
	@param lookY number? - 朝向行
	@param faction number? - 阵营（无朝向时用）
	@param unitType number? - 兵种 Id；缺省按非飞行
	@return CFrame - HumanRootPart 位姿
]]
local function _pivotAt(
	x: number,
	y: number,
	model: Model,
	lookX: number?,
	lookY: number?,
	faction: number?,
	unitType: number?
): CFrame
	local center = BoardView.CellCenter(x, y)
	local pos = Vector3.new(center.X, _boardY() + _standOffset(x, y, unitType) + TILE_HALF + _footLift(model), center.Z)
	if lookX ~= nil and lookY ~= nil and (lookX ~= x or lookY ~= y) then
		local look = BoardView.CellCenter(lookX, lookY)
		return CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z))
	end
	local yaw = if faction == EnumMgr.AEFaction.Player then math.pi else 0
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
end

--[[
	只写 HumanRootPart，避免 WorldPivot / 身体零件把整模拖飞。
	@param model Model - 棋子
	@param cf CFrame - 根部位姿
	@return BasePart? - 根
]]
local function _setRootCFrame(model: Model, cf: CFrame): BasePart?
	local root = _bindRoot(model)
	if not root then
		return nil
	end
	root.CFrame = cf
	model.WorldPivot = cf
	return root
end

--[[
	棋子落到单位当前格
	@param unit table - UnitSnap
	@param model Model - 棋子
	@return CFrame - 根部位姿
]]
local function _unitPivot(unit: any, model: Model): CFrame
	return _pivotAt(unit.x, unit.y, model, nil, nil, unit.faction, unit.unitType)
end

--[[
	取模型 Animator，没有则建
	@param model Model - 棋子
	@return Animator? - 动画器
]]
local function _animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
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
				_setRootCFrame(model, _unitPivot(unit, model))
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
	local root = _bindRoot(model)
	if not root then
		_walking[unit.id] = nil
		return
	end
	local start = cells[1]
	_setRootCFrame(
		model,
		_pivotAt(start.x, start.y, model, cells[2].x, cells[2].y, unit.faction, unit.unitType)
	)
	root = _rootOf(model)
	if not root then
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
			unit.faction,
			unit.unitType
		)
		local tween = TweenService:Create(root, MOVE_TWEEN, { CFrame = target })
		_walkTween[unit.id] = tween
		tween:Play()
		tween.Completed:Wait()
		_walkTween[unit.id] = nil
		if root.Parent then
			model.WorldPivot = root.CFrame
		end
	end
	if gen == _walkGen and model.Parent then
		_setRootCFrame(model, _unitPivot(unit, model))
		_setWalkAnim(model, false)
	end
	_walking[unit.id] = nil
end

--[[
	棋子转向目标格（只写 HumanRootPart）
	@param model Model - 棋子
	@param unit table - UnitSnap
	@param lookX number - 朝向列
	@param lookY number - 朝向行
	@return nil
]]
local function _faceToward(model: Model, unit: any, lookX: number, lookY: number)
	if not model.Parent or type(unit) ~= "table" then
		return
	end
	_setRootCFrame(model, _pivotAt(unit.x, unit.y, model, lookX, lookY, unit.faction, unit.unitType))
end

--[[
	前冲到峰值（只写 HumanRootPart）
	@param model Model - 棋子
	@param unit table - UnitSnap
	@param lookX number - 目标列
	@param lookY number - 目标行
	@param gen number - 播放代数
	@return CFrame? - 冲出前的根部位姿
]]
local function _lungeOut(model: Model, unit: any, lookX: number, lookY: number, gen: number): CFrame?
	if gen ~= _walkGen or not model.Parent then
		return nil
	end
	local start = _pivotAt(unit.x, unit.y, model, lookX, lookY, unit.faction, unit.unitType)
	local root = _setRootCFrame(model, start)
	if not root then
		return nil
	end
	local look = BoardView.CellCenter(lookX, lookY)
	local dir = Vector3.new(look.X - start.Position.X, 0, look.Z - start.Position.Z)
	if dir.Magnitude < 0.05 then
		return start
	end
	local peak = start + dir.Unit * LUNGE_DIST
	local tween = TweenService:Create(root, LUNGE_OUT, { CFrame = peak })
	_walkTween[unit.id] = tween
	tween:Play()
	tween.Completed:Wait()
	_walkTween[unit.id] = nil
	if gen ~= _walkGen or not model.Parent then
		return nil
	end
	return start
end

--[[
	前冲收回原格
	@param model Model - 棋子
	@param unit table - UnitSnap
	@param startCf CFrame - 冲出前位姿
	@param gen number - 播放代数
	@return nil
]]
local function _lungeBack(model: Model, unit: any, startCf: CFrame, gen: number)
	if gen ~= _walkGen or not model.Parent then
		return
	end
	local root = _bindRoot(model)
	if not root then
		return
	end
	local tween = TweenService:Create(root, LUNGE_BACK, { CFrame = startCf })
	_walkTween[unit.id] = tween
	tween:Play()
	tween.Completed:Wait()
	_walkTween[unit.id] = nil
	if gen == _walkGen and model.Parent then
		_setRootCFrame(model, startCf)
	end
end

--[[
	播一条命中：转向、前冲、特效、飘字、受击/死亡
	@param hit table - CombatHitSnap
	@param unitById { [number]: any } - 含阵亡单位
	@param gen number - 播放代数
	@return nil
]]
local function _playCombatHit(hit: any, unitById: { [number]: any }, gen: number)
	if gen ~= _walkGen then
		return
	end
	local attacker = unitById[hit.attackerId]
	local defender = unitById[hit.defenderId]
	local atkModel = _units[hit.attackerId]
	local defModel = _units[hit.defenderId]
	if attacker and atkModel and atkModel.Parent and defender then
		_faceToward(atkModel, attacker, defender.x, defender.y)
	end
	if defender and defModel and defModel.Parent and attacker then
		_faceToward(defModel, defender, attacker.x, attacker.y)
	end
	CombatFx.PlayAttack(atkModel)
	local startCf: CFrame? = nil
	if attacker and atkModel and atkModel.Parent and defender then
		startCf = _lungeOut(atkModel, attacker, defender.x, defender.y, gen)
	end
	if gen ~= _walkGen then
		return
	end
	CombatFx.PlaySlash(atkModel, defModel)
	if defModel and defModel.Parent then
		CombatFx.PlayHitFx(defModel)
		CombatFx.ShowDamage(defModel, hit.damage, hit.kind)
		if hit.alive then
			CombatFx.PlayHit(defModel)
		else
			CombatFx.PlayDeath(defModel)
		end
	end
	if attacker and atkModel and startCf then
		_lungeBack(atkModel, attacker, startCf, gen)
	end
	if gen ~= _walkGen then
		return
	end
	if hit.alive then
		task.wait(0.12)
	else
		task.wait(0.55)
	end
end

--[[
	按命中顺序穿插走路与攻击，剩余路径再补走
	@param pendingWalk { [number]: any } - unitId → { model, unit, cells }
	@param pathOrder { number } - 服务端路径顺序
	@param combatHits { any } - CombatHitSnap 列表
	@param unitById { [number]: any } - 单位表
	@param alive { [number]: boolean } - 结算后仍存活
	@param gen number - 播放代数
	@return nil
]]
local function _runPresentation(
	pendingWalk: { [number]: any },
	pathOrder: { number },
	combatHits: { any },
	unitById: { [number]: any },
	alive: { [number]: boolean },
	gen: number
)
	if gen ~= _walkGen then
		return
	end
	_walkBusy = true
	local consumed: { [number]: boolean } = {}

	local function playWalk(unitId: number)
		if consumed[unitId] then
			return
		end
		local job = pendingWalk[unitId]
		if not job then
			return
		end
		consumed[unitId] = true
		if gen ~= _walkGen then
			return
		end
		BoardView.ShowPath(job.cells)
		_walkUnit(job.model, job.unit, job.cells, gen)
		BoardView.ClearPath()
	end

	for _, hit in combatHits do
		if gen ~= _walkGen then
			return
		end
		playWalk(hit.attackerId)
		_playCombatHit(hit, unitById, gen)
	end
	for _, id in pathOrder do
		if gen ~= _walkGen then
			return
		end
		playWalk(id)
	end
	for id in pendingWalk do
		if gen ~= _walkGen then
			return
		end
		playWalk(id)
	end
	if gen ~= _walkGen then
		return
	end
	BoardView.ClearPath()
	for id, model in _units do
		if not alive[id] then
			_walking[id] = nil
			model:Destroy()
			_units[id] = nil
			_unitCell[id] = nil
			_unitSnap[id] = nil
		end
	end
	_walkBusy = false
	if _onWalkDone then
		_onWalkDone()
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
	return tonumber(unit.unitType) == EnumMgr.AEUnitId.Commander
		and tonumber(unit.faction) == EnumMgr.AEFaction.Player
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
	按兵种+阵营填 HumanoidDescription：Noob 底色 + 配置装饰
	@param unit table - UnitSnap
	@return HumanoidDescription - 外观
]]
local function _descFromCfg(unit: any): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local cfg = AERules.GetUnitCfg(unit.unitType)
	local enemy = tonumber(unit.faction) == EnumMgr.AEFaction.Enemy
	if type(cfg) == "table" then
		desc.GraphicTShirt = _lookId(cfg, enemy, "GraphicTShirt", "EnemyGraphicTShirt")
		desc.Shirt = _lookId(cfg, enemy, "Shirt", "EnemyShirt")
		desc.Pants = _lookId(cfg, enemy, "Pants", "EnemyPants")
		desc.HatAccessory = _hatList(cfg, enemy)
	end
	desc.HeadColor = NOOB_YELLOW
	desc.LeftArmColor = NOOB_YELLOW
	desc.RightArmColor = NOOB_YELLOW
	desc.TorsoColor = NOOB_BLUE
	desc.LeftLegColor = NOOB_GREEN
	desc.RightLegColor = NOOB_GREEN
	return desc
end

--[[
	本地玩家 UserId；Studio 未登录时为负，不能拉形象
	@return number - UserId，缺省 0
]]
local function _localUserId(): number
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return 0
	end
	return tonumber(localPlayer.UserId) or 0
end

--[[
	取玩家目录形象；UserId 无效再读当前角色已套描述
	@return HumanoidDescription? - 外观
]]
local function _playerDesc(): HumanoidDescription?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	local userId = _localUserId()
	if userId > 0 then
		local okUser, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
		end)
		if okUser and desc then
			return desc
		end
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, applied = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok and applied then
			return applied:Clone()
		end
	end
	return nil
end

--[[
	按 UserId / 描述生成完整人模（优先 R6，失败再 R15）
	@param desc HumanoidDescription? - 外观
	@return Model? - 人模
]]
local function _createPlayerAvatar(desc: HumanoidDescription?): Model?
	local userId = _localUserId()
	if userId > 0 then
		local createUser = (Players :: any).CreateHumanoidModelFromUserIdAsync
		if typeof(createUser) == "function" then
			local okUser, model = pcall(function()
				return Players:CreateHumanoidModelFromUserIdAsync(userId)
			end)
			if okUser and typeof(model) == "Instance" and model:IsA("Model") then
				return model
			end
		end
	end
	if not desc then
		return nil
	end
	local rigTypes = { Enum.HumanoidRigType.R6, Enum.HumanoidRigType.R15 }
	for _, rigType in rigTypes do
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, rigType)
		end)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return model
		end
	end
	return nil
end

--[[
	外观加载后再克隆角色，并清掉战棋锁人留下的隐藏
	@return Model? - 克隆体
]]
local function _cloneDressedPlayer(): Model?
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	if not character or not localPlayer:HasAppearanceLoaded() then
		return nil
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or typeof(clone) ~= "Instance" or not clone:IsA("Model") then
		return nil
	end
	for _, inst in clone:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 0
		end
	end
	local desc = _playerDesc()
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if desc and humanoid then
		pcall(function()
			local applyAsync = (humanoid :: any).ApplyDescriptionAsync
			if typeof(applyAsync) == "function" then
				humanoid:ApplyDescriptionAsync(desc, Enum.AssetTypeVerification.Default)
			else
				humanoid:ApplyDescription(desc)
			end
		end)
		if desc.Parent == nil then
			desc:Destroy()
		end
	end
	return clone
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
	钉住棋子：只锚 HumanRootPart，不写玩家角色
	@param model Model - 棋子
	@return nil
]]
local function _freezeRig(model: Model)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.Massless = true
			inst.Anchored = inst.Name == ROOT_NAME
		end
	end
	_bindRoot(model)
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
	指挥官与普通士兵持剑
	@param unit table - UnitSnap
	@return boolean - 要持剑
]]
local function _holdsSword(unit: any): boolean
	local unitType = tonumber(unit.unitType)
	return unitType == EnumMgr.AEUnitId.Commander or unitType == EnumMgr.AEUnitId.Soldier
end

--[[
	建一把短剑（握把为主节点，刃沿 +Y）
	@return Model - 剑
]]
local function _makeSword(): Model
	local sword = Instance.new("Model")
	sword.Name = SWORD_NAME
	local function part(name: string, size: Vector3, color: Color3, cf: CFrame, shape: Enum.PartType?): BasePart
		local inst = Instance.new("Part")
		inst.Name = name
		inst.Anchored = false
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CanTouch = false
		inst.Massless = true
		inst.Material = Enum.Material.Metal
		inst.Color = color
		inst.Size = size
		inst.CFrame = cf
		if shape then
			inst.Shape = shape
		end
		inst.Parent = sword
		return inst
	end
	local handle = part("Handle", Vector3.new(0.18, 0.72, 0.18), SWORD_HILT, CFrame.new(0, 0, 0))
	handle.Material = Enum.Material.Wood
	part("Pommel", Vector3.new(0.26, 0.26, 0.26), SWORD_GUARD, CFrame.new(0, -0.42, 0), Enum.PartType.Ball)
	part("Guard", Vector3.new(0.9, 0.12, 0.22), SWORD_GUARD, CFrame.new(0, 0.4, 0))
	local blade = part("Blade", Vector3.new(0.22, 2.15, 0.08), SWORD_STEEL, CFrame.new(0, 1.52, 0))
	blade.Material = Enum.Material.SmoothPlastic
	part("Tip", Vector3.new(0.2, 0.28, 0.08), SWORD_STEEL, CFrame.new(0, 2.68, 0) * CFrame.Angles(0, 0, math.rad(45)))
	sword.PrimaryPart = handle
	return sword
end

--[[
	把剑焊到右手
	@param model Model - 棋子
	@return nil
]]
local function _equipSword(model: Model)
	local old = model:FindFirstChild(SWORD_NAME, true)
	if old then
		old:Destroy()
	end
	local hold = model:FindFirstChild("Right Arm", true) or model:FindFirstChild("RightHand", true)
	if not (hold and hold:IsA("BasePart")) then
		return
	end
	local sword = _makeSword()
	local grip: CFrame
	if hold.Name == "RightHand" then
		grip = hold.CFrame * CFrame.new(0, -0.08, 0.02) * CFrame.Angles(math.rad(-90), 0, 0)
	else
		grip = hold.CFrame * CFrame.new(0, -0.95, -0.42)
	end
	sword:PivotTo(grip)
	sword.Parent = model
	local handle = sword.PrimaryPart
	if handle then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "SwordBind"
		weld.Part0 = hold
		weld.Part1 = handle
		weld.Parent = handle
	end
end

--[[
	把人模整模挂进棋子容器，主节点保持 HumanRootPart。
	指挥官不拆零件，避免 Humanoid 换父级把衣服/配件拆掉。
	@param model Model - 棋子容器
	@param rig Model - 人模
	@param unit table - UnitSnap
	@param nest boolean - 整模挂入；false 则仍拆零件（兵种配置人模）
	@return nil
]]
local function _attachRig(model: Model, rig: Model, unit: any, nest: boolean)
	_stripScripts(rig)
	local keep = _bindRoot(model)
	if not keep then
		rig:Destroy()
		return
	end
	local keepCf = keep.CFrame
	if nest then
		rig.Name = "Avatar"
		rig.Parent = model
	else
		for _, child in rig:GetChildren() do
			if child.Name ~= ROOT_NAME then
				child.Parent = model
			end
		end
		rig:Destroy()
	end
	_freezeRig(model)
	_setRootCFrame(model, keepCf)
	if model.Parent and not _walking[unit.id] then
		local live = _unitSnap[unit.id] or unit
		_setRootCFrame(model, _unitPivot(live, model))
	end
end

--[[
	异步套人模；我方指挥官只走玩家 UserId 形象，失败不回退配置衣服
	@param model Model - 棋子容器
	@param unit table - UnitSnap
	@return nil
]]
local function _fillR6(model: Model, unit: any)
	task.spawn(function()
		local rig: Model? = nil
		local desc: HumanoidDescription? = nil
		if _isPlayerCommander(unit) then
			for _ = 1, 24 do
				desc = _playerDesc()
				rig = _createPlayerAvatar(desc)
				if desc and desc.Parent == nil then
					desc:Destroy()
				end
				desc = nil
				if not rig then
					rig = _cloneDressedPlayer()
				end
				if rig then
					break
				end
				task.wait(0.25)
			end
			if not rig then
				Log.warn("BoardView 指挥官套玩家形象失败", unit.id)
				return
			end
			if not model.Parent then
				rig:Destroy()
				return
			end
			_attachRig(model, rig, unit, true)
			if _holdsSword(unit) then
				_equipSword(model)
			end
			return
		end
		desc = _descFromCfg(unit)
		rig = _createR6(desc)
		if desc.Parent == nil then
			desc:Destroy()
		end
		if not rig or not model.Parent then
			if rig then
				rig:Destroy()
			end
			return
		end
		_attachRig(model, rig, unit, true)
		if _holdsSword(unit) then
			_equipSword(model)
		end
	end)
end

--[[
	建棋子：先占位 HumanRootPart，再异步套衣服/玩家形象
	@param unit table - UnitSnap
	@return Model - 表现
]]
local function _makeUnit(unit: any): Model
	local model = Instance.new("Model")
	model.Name = "Unit_" .. tostring(unit.id)
	model:SetAttribute(UNIT_ATTR, unit.id)
	local root = Instance.new("Part")
	root.Name = ROOT_NAME
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = model
	model.PrimaryPart = root
	local folder = _ensureFolder()
	model.Parent = folder
	_setRootCFrame(model, _unitPivot(unit, model))
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
	local root = _bindRoot(model)
	if not root then
		return
	end
	if shouldTween then
		TweenService:Create(root, MOVE_TWEEN, { CFrame = target }):Play()
		return
	end
	_setRootCFrame(model, target)
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
		part:SetAttribute("Legend", tile.legend)
		part.CFrame = CFrame.new(BoardView.CellCenter(tile.x, tile.y) + Vector3.new(0, BoardDecor.SurfaceOffset(tile.legend), 0))
		local decorKey = tostring(tile.legend) .. ":" .. tostring(tile.owner) .. ":shore"
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
	local combatHits = {}
	local keepDead: { [number]: boolean } = {}
	if type(snap.combatHits) == "table" then
		for _, hit in snap.combatHits do
			local attackerId = tonumber(hit and hit.attackerId)
			local defenderId = tonumber(hit and hit.defenderId)
			if attackerId and defenderId then
				table.insert(combatHits, {
					attackerId = attackerId,
					defenderId = defenderId,
					damage = tonumber(hit.damage) or 0,
					remainHp = tonumber(hit.remainHp) or 0,
					alive = hit.alive == true,
					kind = if hit.kind == "Counter" then "Counter" else "Attack",
				})
				keepDead[defenderId] = true
			end
		end
	end
	if #pathOrder > 0 or #combatHits > 0 then
		_cancelWalks()
	end

	local unitById: { [number]: any } = {}
	for _, unit in snap.units do
		unitById[unit.id] = unit
	end

	local pendingWalk: { [number]: any } = {}
	local alive: { [number]: boolean } = {}
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
		elseif keepDead[unit.id] then
			_unitSnap[unit.id] = unit
		end
	end
	for id, model in _units do
		if not alive[id] and not keepDead[id] then
			_walking[id] = nil
			model:Destroy()
			_units[id] = nil
			_unitCell[id] = nil
			_unitSnap[id] = nil
		end
	end
	local hasWalk = next(pendingWalk) ~= nil
	if hasWalk or #combatHits > 0 then
		_walkBusy = true
		local gen = _walkGen
		task.spawn(_runPresentation, pendingWalk, pathOrder, combatHits, unitById, alive, gen)
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
	高亮可攻击格（红格）
	@param cells { { x: number, y: number } } - 目标格
	@return nil
]]
function BoardView.HighlightAttack(cells: { any })
	BoardView.ClearHighlights()
	local folder = _ensureFolder()
	for _, cell in cells do
		local mark = Instance.new("Part")
		mark.Name = "Attack"
		mark.Anchored = true
		mark.CanCollide = false
		mark.CanQuery = false
		mark:SetAttribute("X", cell.x)
		mark:SetAttribute("Y", cell.y)
		mark.Material = Enum.Material.Neon
		mark.Color = Color3.fromRGB(220, 48, 48)
		mark.Transparency = 0.45
		mark.Size = Vector3.new(_tileSize() - 1.2, 0.2, _tileSize() - 1.2)
		mark.CFrame = CFrame.new(BoardView.CellCenter(cell.x, cell.y) + Vector3.new(0, 0.64, 0))
		mark.Parent = folder
		table.insert(_highlights, mark)
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
