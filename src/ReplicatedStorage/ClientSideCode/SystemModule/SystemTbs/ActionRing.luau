--[[
	Module: ActionRing
	Description: 远古帝国式单位操作环：点中棋子后在周围几个角度出攻击/占领/待命。
		只做客户端点选，意图仍走 Input → TBS_ACTION。
	Author: 程莘
	Created: 2026-10-23
	Last Modified: 2026-10-23

	能力：
	- Show(unitId, actions, onPick)：在 HumanRootPart 周围按角度摆徽章按钮
	- Hide / IsPointerOver：清环、避免点按钮时落到棋盘

	标准加载：local ActionRing = require(script.Parent.ActionRing)
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Players = Utils.Players
local GuiService = Utils.GuiService
local UserInputService = Utils.UserInputService
local TranslationHelper = Utils.TranslationHelper
local TweenService = Utils.TweenService

local BoardView = require(script.Parent.BoardView)

local ActionRing = {}

local RING_NAME = "TbsActionRing"
local BTN_W = 88
local BTN_H = 112
local FACE_SIZE = 72
local RING_RADIUS = 5.2
local RING_Y = 3.4
local POP_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ACTION_STYLE = {
	Attack = {
		fill = Color3.fromRGB(156, 36, 40),
		fillHi = Color3.fromRGB(228, 88, 78),
		rim = Color3.fromRGB(255, 214, 126),
	},
	Occupy = {
		fill = Color3.fromRGB(32, 108, 74),
		fillHi = Color3.fromRGB(74, 176, 118),
		rim = Color3.fromRGB(255, 214, 126),
	},
	Wait = {
		fill = Color3.fromRGB(52, 62, 80),
		fillHi = Color3.fromRGB(102, 118, 140),
		rim = Color3.fromRGB(214, 220, 232),
	},
}

local _folder: Folder? = nil
local _guis: { BillboardGui } = {}
local _atts: { Attachment } = {}
local _onPick: ((string) -> ())? = nil
local _unitId: number? = nil

--[[
	清掉操作环
	@return nil
]]
function ActionRing.Hide()
	if _folder then
		_folder:Destroy()
		_folder = nil
	end
	for _, gui in _guis do
		gui:Destroy()
	end
	table.clear(_guis)
	for _, att in _atts do
		att:Destroy()
	end
	table.clear(_atts)
	_onPick = nil
	_unitId = nil
end

--[[
	指针是否点在操作环按钮上
	@return boolean - 在按钮上
]]
function ActionRing.IsPointerOver(): boolean
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local hits = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	for _, gui in hits do
		local cursor: Instance? = gui
		while cursor do
			if cursor.Name == RING_NAME then
				return true
			end
			cursor = cursor.Parent
		end
	end
	return false
end

--[[
	圆角色
	@param inst GuiObject - 目标
	@param scale number - 1 为圆
	@return nil
]]
local function _corner(inst: GuiObject, scale: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(scale, 0)
	corner.Parent = inst
end

--[[
	像素圆角
	@param inst GuiObject - 目标
	@param px number - 半径
	@return nil
]]
local function _cornerPx(inst: GuiObject, px: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, px)
	corner.Parent = inst
end

--[[
	色块
	@param parent Instance - 父级
	@param name string - 名
	@param size UDim2 - 尺寸
	@param pos UDim2 - 位置
	@param color Color3 - 底色
	@param z number - Z
	@return Frame - 色块
]]
local function _block(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	color: Color3,
	z: number
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

--[[
	攻击剑标
	@param parent Instance - 图标层
	@return nil
]]
local function _drawAttack(parent: Instance)
	local group = Instance.new("Frame")
	group.Name = "Sword"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.48)
	group.Size = UDim2.fromOffset(40, 40)
	group.Rotation = -32
	group.ZIndex = 6
	group.Parent = parent
	local blade = _block(group, "Blade", UDim2.fromOffset(8, 30), UDim2.fromScale(0.5, 0.36), Color3.fromRGB(244, 238, 220), 7)
	_corner(blade, 1)
	local guard = _block(group, "Guard", UDim2.fromOffset(22, 5), UDim2.fromScale(0.5, 0.68), Color3.fromRGB(255, 214, 126), 8)
	_cornerPx(guard, 2)
	local hilt = _block(group, "Hilt", UDim2.fromOffset(6, 10), UDim2.fromScale(0.5, 0.84), Color3.fromRGB(176, 132, 58), 7)
	_cornerPx(hilt, 2)
end

--[[
	占领旗标
	@param parent Instance - 图标层
	@return nil
]]
local function _drawOccupy(parent: Instance)
	local group = Instance.new("Frame")
	group.Name = "Flag"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.48)
	group.Size = UDim2.fromOffset(40, 40)
	group.ZIndex = 6
	group.Parent = parent
	local pole = _block(group, "Pole", UDim2.fromOffset(4, 32), UDim2.new(0.5, -10, 0.5, 2), Color3.fromRGB(232, 214, 160), 7)
	_corner(pole, 1)
	local cloth = _block(group, "Cloth", UDim2.fromOffset(22, 16), UDim2.new(0.5, 4, 0.5, -6), Color3.fromRGB(248, 244, 228), 8)
	_cornerPx(cloth, 3)
	local stripe = _block(cloth, "Stripe", UDim2.new(1, 0, 0, 4), UDim2.new(0.5, 0, 0, 6), Color3.fromRGB(255, 198, 72), 9)
	stripe.AnchorPoint = Vector2.new(0.5, 0)
end

--[[
	待命暂停标
	@param parent Instance - 图标层
	@return nil
]]
local function _drawWait(parent: Instance)
	local group = Instance.new("Frame")
	group.Name = "Pause"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.48)
	group.Size = UDim2.fromOffset(40, 40)
	group.ZIndex = 6
	group.Parent = parent
	local left = _block(group, "Left", UDim2.fromOffset(8, 22), UDim2.new(0.5, -8, 0.5, 0), Color3.fromRGB(236, 240, 248), 7)
	_cornerPx(left, 3)
	local right = _block(group, "Right", UDim2.fromOffset(8, 22), UDim2.new(0.5, 8, 0.5, 0), Color3.fromRGB(236, 240, 248), 7)
	_cornerPx(right, 3)
end

local ICON_DRAW = {
	Attack = _drawAttack,
	Occupy = _drawOccupy,
	Wait = _drawWait,
}

--[[
	悬停放大、离开复原
	@param scale UIScale - 缩放
	@param stroke UIStroke - 描边
	@param hover boolean - 悬停
	@return nil
]]
local function _setHover(scale: UIScale, stroke: UIStroke, hover: boolean)
	local goal = if hover then 1.1 else 1
	local thick = if hover then 3 else 2
	TweenService:Create(scale, HOVER_INFO, { Scale = goal }):Play()
	TweenService:Create(stroke, HOVER_INFO, { Thickness = thick }):Play()
end

--[[
	建一颗环形徽章按钮
	@param parent Instance - 环 Folder
	@param root BasePart - HumanRootPart
	@param actionId string - Attack / Occupy / Wait
	@param key string - 翻译键
	@param angle number - 弧度
	@param index number - 弹出错开
	@return nil
]]
local function _makeBtn(parent: Instance, root: BasePart, actionId: string, key: string, angle: number, index: number)
	local style = ACTION_STYLE[actionId] or ACTION_STYLE.Wait
	local att = Instance.new("Attachment")
	att.Name = actionId
	att.Position = Vector3.new(math.cos(angle) * RING_RADIUS, RING_Y, math.sin(angle) * RING_RADIUS)
	att.Parent = root
	table.insert(_atts, att)

	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local gui = Instance.new("BillboardGui")
	gui.Name = RING_NAME
	gui.Size = UDim2.fromOffset(BTN_W, BTN_H)
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.LightInfluence = 0
	gui.MaxDistance = 180
	gui.ResetOnSpawn = false
	gui.Adornee = att
	gui.Parent = playerGui or parent
	table.insert(_guis, gui)

	local btn = Instance.new("TextButton")
	btn.Name = actionId
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.35
	scale.Parent = btn

	local shadow = _block(
		btn,
		"Shadow",
		UDim2.fromOffset(FACE_SIZE + 6, FACE_SIZE + 6),
		UDim2.new(0.5, 0, 0, 44),
		Color3.fromRGB(8, 10, 12),
		1
	)
	shadow.BackgroundTransparency = 0.45
	_corner(shadow, 1)

	local bezel = _block(btn, "Bezel", UDim2.fromOffset(FACE_SIZE + 6, FACE_SIZE + 6), UDim2.new(0.5, 0, 0, 40), style.rim, 2)
	_corner(bezel, 1)

	local face = _block(btn, "Face", UDim2.fromOffset(FACE_SIZE, FACE_SIZE), UDim2.new(0.5, 0, 0, 40), style.fill, 3)
	_corner(face, 1)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, style.fillHi),
		ColorSequenceKeypoint.new(1, style.fill),
	})
	grad.Rotation = 90
	grad.Parent = face

	local sheen = _block(face, "Sheen", UDim2.new(0.72, 0, 0.28, 0), UDim2.new(0.5, 0, 0.22, 0), Color3.new(1, 1, 1), 4)
	sheen.BackgroundTransparency = 0.78
	_corner(sheen, 1)

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.ZIndex = 5
	icon.Parent = face
	local draw = ICON_DRAW[actionId]
	if draw then
		draw(icon)
	end

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(18, 16, 12)
	stroke.Thickness = 2
	stroke.Parent = bezel

	local caption = _block(btn, "Caption", UDim2.new(1, -8, 0, 24), UDim2.new(0.5, 0, 1, -14), Color3.fromRGB(12, 16, 18), 4)
	caption.BackgroundTransparency = 0.12
	_cornerPx(caption, 8)
	local capStroke = Instance.new("UIStroke")
	capStroke.Color = style.rim
	capStroke.Thickness = 1
	capStroke.Transparency = 0.25
	capStroke.Parent = caption
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(255, 248, 230)
	label.TextStrokeTransparency = 0.55
	label.ZIndex = 5
	label.Parent = caption
	TranslationHelper.SetText(label, key)

	btn.MouseEnter:Connect(function()
		_setHover(scale, stroke, true)
	end)
	btn.MouseLeave:Connect(function()
		_setHover(scale, stroke, false)
	end)
	btn.MouseButton1Click:Connect(function()
		if _onPick then
			_onPick(actionId)
		end
	end)

	task.delay((index - 1) * 0.05, function()
		if btn.Parent then
			TweenService:Create(scale, POP_INFO, { Scale = 1 }):Play()
		end
	end)
end

--[[
	在单位周围显示可操作按钮
	@param unitId number - 单位
	@param actions { { id: string, key: string } } - 按钮
	@param onPick (string) -> () - 点中动作 Id
	@return nil
]]
function ActionRing.Show(unitId: number, actions: { any }, onPick: (string) -> ())
	ActionRing.Hide()
	if type(actions) ~= "table" or #actions == 0 then
		return
	end
	local model = BoardView.GetUnitModel(unitId)
	if not model then
		return
	end
	local root = BoardView.GetRootPart(model)
	if not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = RING_NAME
	folder.Parent = model
	_folder = folder
	_onPick = onPick
	_unitId = unitId
	local count = #actions
	local start = -math.pi * 0.5
	local step = if count > 1 then (math.pi * 1.2) / (count - 1) else 0
	if count == 1 then
		start = math.pi * 0.15
	elseif count == 2 then
		start = -math.pi * 0.15
		step = math.pi * 0.55
	else
		start = -math.pi * 0.15
	end
	for i, action in actions do
		local angle = start + (i - 1) * step
		_makeBtn(folder, root, action.id, action.key, angle, i)
	end
end

--[[
	当前环挂在哪个单位
	@return number? - 单位 Id
]]
function ActionRing.GetUnitId(): number?
	return _unitId
end

return ActionRing
