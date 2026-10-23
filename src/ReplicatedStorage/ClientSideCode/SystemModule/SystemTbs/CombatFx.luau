--[[
	Module: CombatFx
	Description: 战棋攻击表现：攻击/受击/死亡轨、受击闪光与粒子、掉血飘字。不写棋子 CFrame，不结算。
	Author: 程莘
	Created: 2026-10-23
	Last Modified: 2026-10-23

	能力：
	- PlayAttack：占位时长（攻击动作由 BoardView 前冲）；PlayHit / PlayDeath 经 AnimationModule 播轨
	- PlayHitFx / PlaySlash：本地 Highlight + 粒子 + 刀光，不插工具箱
	- ShowDamage：头顶 Billboard 飘字，数字走 MathMgr.getNumStr

	加载：
		local CombatFx = require(script.Parent.CombatFx)
		CombatFx.ShowDamage(model, 12, false)
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AnimationModule = Utils.AnimationModule
local MathMgr = Utils.MathMgr
local TweenService = Utils.TweenService
local Debris = Utils.Debris

local CombatFx = {}

local ANIM_HIT = "人型受击R6-1"
local ANIM_DEATH = "人型死亡R6"
local KIND_COUNTER = "Counter"
local FLOAT_TIME = 0.72
local HIT_FX_LIFE = 0.55
local SLASH_TIME = 0.22

--[[
	取棋子根零件
	@param model Model - 棋子
	@return BasePart? - HumanRootPart / PrimaryPart
]]
local function _rootOf(model: Model): BasePart?
	local named = model:FindFirstChild("HumanRootPart")
	if named and named:IsA("BasePart") then
		return named
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

--[[
	播配置轨并夹紧等待时长
	@param model Model? - 棋子
	@param animName string - Animation.luau 键
	@param fallback number - 无轨时的默认秒
	@param maxWait number - 上限秒
	@return number - 建议等待秒
]]
local function _playAnim(model: Model?, animName: string, fallback: number, maxWait: number): number
	if not model or not model.Parent then
		return fallback
	end
	local len = AnimationModule.PlayAnimByModel(
		model,
		animName,
		1,
		nil,
		nil,
		Enum.AnimationPriority.Action,
		0.06
	)
	if type(len) ~= "number" or len <= 0 then
		return fallback
	end
	return math.clamp(len, 0.12, maxWait)
end

--[[
	播攻击轨。TbsAttack 尚未入库时不调 PlayAnim，避免每击刷「未找到动画配置」。
	@param _model Model? - 攻击方；现由 BoardView 前冲补动作
	@return number - 建议等待秒
]]
function CombatFx.PlayAttack(_model: Model?): number
	return 0.2
end

--[[
	播受击轨
	@param model Model? - 受击方
	@return number - 建议等待秒
]]
function CombatFx.PlayHit(model: Model?): number
	return _playAnim(model, ANIM_HIT, 0.28, 0.55)
end

--[[
	播死亡轨
	@param model Model? - 阵亡方
	@return number - 建议等待秒
]]
function CombatFx.PlayDeath(model: Model?): number
	return _playAnim(model, ANIM_DEATH, 0.7, 1.2)
end

--[[
	受击闪光与粒子（本地几何，不写棋子 CFrame）
	@param model Model? - 受击方
	@return nil
]]
function CombatFx.PlayHitFx(model: Model?)
	if not model or not model.Parent then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "TbsHitFlash"
	highlight.FillColor = Color3.fromRGB(255, 56, 48)
	highlight.OutlineColor = Color3.fromRGB(255, 190, 170)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	Debris:AddItem(highlight, 0.28)

	local root = _rootOf(model)
	if not root then
		return
	end
	local burst = Instance.new("Part")
	burst.Name = "TbsHitBurst"
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.Massless = true
	burst.Transparency = 1
	burst.Size = Vector3.new(0.35, 0.35, 0.35)
	burst.CFrame = root.CFrame * CFrame.new(0, 1.15, 0)
	burst.Parent = model.Parent or model
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 210, 90)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.18, 0.36)
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.LightEmission = 0.6
	emitter.Parent = burst
	emitter:Emit(18)
	Debris:AddItem(burst, HIT_FX_LIFE)
end

--[[
	攻击方向短刀光（本地 Part，不写棋子 CFrame）
	@param fromModel Model? - 攻击方
	@param toModel Model? - 受击方
	@return nil
]]
function CombatFx.PlaySlash(fromModel: Model?, toModel: Model?)
	if not fromModel or not toModel or not fromModel.Parent or not toModel.Parent then
		return
	end
	local a = _rootOf(fromModel)
	local b = _rootOf(toModel)
	if not a or not b then
		return
	end
	local ap = a.Position + Vector3.new(0, 1.2, 0)
	local bp = b.Position + Vector3.new(0, 1.2, 0)
	local delta = bp - ap
	if delta.Magnitude < 0.2 then
		return
	end
	local mid = (ap + bp) * 0.5
	local len = math.max(0.8, delta.Magnitude * 0.62)
	local slash = Instance.new("Part")
	slash.Name = "TbsSlash"
	slash.Anchored = true
	slash.CanCollide = false
	slash.CanQuery = false
	slash.CanTouch = false
	slash.Massless = true
	slash.Material = Enum.Material.Neon
	slash.Color = Color3.fromRGB(255, 230, 150)
	slash.Size = Vector3.new(0.2, 0.08, len)
	slash.CFrame = CFrame.lookAt(mid, mid + delta)
	slash.Parent = fromModel.Parent or fromModel
	TweenService:Create(slash, TweenInfo.new(SLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.04, 0.04, len * 1.12),
	}):Play()
	Debris:AddItem(slash, SLASH_TIME + 0.05)
end

--[[
	掉血飘字（只用服务端下发的 damage）
	@param model Model? - 受击方
	@param damage number - 实际扣血
	@param kind string? - Attack / Counter
	@return nil
]]
function CombatFx.ShowDamage(model: Model?, damage: number, kind: string?)
	if not model or not model.Parent then
		return
	end
	local root = _rootOf(model)
	if not root then
		return
	end
	local amount = tonumber(damage) or 0
	local gui = Instance.new("BillboardGui")
	gui.Name = "TbsDmg"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(90, 38)
	gui.StudsOffset = Vector3.new(0, 3.1, 0)
	gui.Adornee = root
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.25
	label.TextStrokeColor3 = Color3.fromRGB(30, 10, 10)
	if kind == KIND_COUNTER then
		label.TextColor3 = Color3.fromRGB(255, 176, 72)
	else
		label.TextColor3 = Color3.fromRGB(255, 72, 64)
	end
	label.Text = "-" .. MathMgr.getNumStr(amount)
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 5.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(gui, FLOAT_TIME + 0.05)
end

return CombatFx
