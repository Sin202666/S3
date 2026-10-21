--[[
	Module: TbsHud
	Description: 战棋 HUD：金币、回合、单位卡、占领/招募/结束回合、胜负。缺 Studio 树时自建 ScreenGui。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Players = Utils.Players
local GuiService = Utils.GuiService
local TranslationHelper = Utils.TranslationHelper
local MathMgr = Utils.MathMgr
local EnumMgr = Utils.EnumMgr
local AERules = Utils.AERules

local TbsHud = {}

local GUI_NAME = "TbsHud"
local TOP_CONTENT_H = 72
local TOP_GAP = 8

local _gui: ScreenGui? = nil
local _top: Frame? = nil
local _gold: TextLabel? = nil
local _turn: TextLabel? = nil
local _goal: TextLabel? = nil
local _insetBound = false
local _unitName: TextLabel? = nil
local _unitStat: TextLabel? = nil
local _occupy: TextButton? = nil
local _recruitSoldier: TextButton? = nil
local _recruitCommander: TextButton? = nil
local _endTurn: TextButton? = nil
local _result: Frame? = nil
local _resultTitle: TextLabel? = nil
local _onAction: ((string, any) -> ())? = nil
local _getSelected: (() -> any?)? = nil
local _snap: any = nil
local _clicksBound = false

--[[
	建 TextLabel
	@param parent Instance - 父级
	@param name string - 名
	@param pos UDim2 - 位置
	@param size UDim2 - 尺寸
	@return TextLabel - 标签
]]
local function _label(parent: Instance, name: string, pos: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = pos
	label.Size = size
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

--[[
	建按钮
	@param parent Instance - 父级
	@param name string - 名
	@param pos UDim2 - 位置
	@param size UDim2 - 尺寸
	@param key string - 翻译键
	@return TextButton - 按钮
]]
local function _button(parent: Instance, name: string, pos: UDim2, size: UDim2, key: string): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Position = pos
	btn.Size = size
	btn.BackgroundColor3 = Color3.fromRGB(42, 92, 64)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.AutoButtonColor = true
	btn.Text = ""
	btn.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = btn
	TranslationHelper.SetText(label, key)
	return btn
end

--[[
	Roblox 顶栏高度（新顶栏优先 TopbarInset）
	@return number - 像素
]]
local function _topInsetY(): number
	local inset = GuiService.TopbarInset
	if inset and inset.Height > 0 then
		return inset.Height
	end
	return GuiService:GetGuiInset().Y
end

--[[
	把 Top 贴到系统栏下方。ScreenGui 已避让时不再叠加上移。
	@return nil
]]
local function _applyTopInset()
	local top = _top
	local gui = _gui
	if not top or not gui then
		return
	end
	local y = math.max(0, _topInsetY() + TOP_GAP - gui.AbsolutePosition.Y)
	top.Position = UDim2.fromOffset(0, y)
	top.Size = UDim2.new(1, 0, 0, TOP_CONTENT_H)
end

--[[
	监听顶栏高度变化（只绑一次）
	@return nil
]]
local function _bindTopInset()
	if _insetBound then
		_applyTopInset()
		return
	end
	_insetBound = true
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(_applyTopInset)
	local gui = _gui
	if gui then
		gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(_applyTopInset)
	end
	_applyTopInset()
end

--[[
	从已有树绑控件
	@param gui ScreenGui - TbsHud
	@return nil
]]
local function _bindRefs(gui: ScreenGui)
	local top = gui:FindFirstChild("Top")
	if top and top:IsA("Frame") then
		_top = top
		_turn = top:FindFirstChild("Turn") :: TextLabel?
		_gold = top:FindFirstChild("Gold") :: TextLabel?
		_goal = top:FindFirstChild("Goal") :: TextLabel?
	end
	local card = gui:FindFirstChild("UnitCard")
	if card then
		_unitName = card:FindFirstChild("UnitName") :: TextLabel?
		_unitStat = card:FindFirstChild("UnitStat") :: TextLabel?
	end
	_occupy = gui:FindFirstChild("Occupy") :: TextButton?
	_recruitSoldier = gui:FindFirstChild("RecruitSoldier") :: TextButton?
	_recruitCommander = gui:FindFirstChild("RecruitCommander") :: TextButton?
	_endTurn = gui:FindFirstChild("EndTurn") :: TextButton?
	_result = gui:FindFirstChild("Result") :: Frame?
	if _result then
		_resultTitle = _result:FindFirstChild("Title") :: TextLabel?
	end
	local function bindBtnKey(btn: TextButton?, key: string)
		if not btn then
			return
		end
		local label = btn:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			TranslationHelper.SetText(label, key)
		end
	end
	bindBtnKey(_occupy, "占领")
	bindBtnKey(_recruitSoldier, "招募")
	bindBtnKey(_recruitCommander, "指挥官")
	bindBtnKey(_endTurn, "结束回合")
	if _result then
		bindBtnKey(_result:FindFirstChild("Again") :: TextButton?, "再来一局")
	end
end

--[[
	绑按钮（只一次）
	@param gui ScreenGui - TbsHud
	@return nil
]]
local function _bindClicks(_guiInst: ScreenGui)
	if _clicksBound then
		return
	end
	_clicksBound = true
	local again = nil
	if _result then
		again = _result:FindFirstChild("Again")
	end
	if again and again:IsA("TextButton") then
		again.MouseButton1Click:Connect(function()
			if _onAction then
				_onAction(EnumMgr.AEAction.Restart, {})
			end
		end)
	end
	if _occupy then
		_occupy.MouseButton1Click:Connect(function()
			local selected = _getSelected and _getSelected()
			if selected and _onAction then
				_onAction(EnumMgr.AEAction.Occupy, { unitId = selected.id })
			end
		end)
	end
	if _recruitSoldier then
		_recruitSoldier.MouseButton1Click:Connect(function()
			if _onAction then
				_onAction(EnumMgr.AEAction.Recruit, { unitType = EnumMgr.AEUnitId.Soldier })
			end
		end)
	end
	if _recruitCommander then
		_recruitCommander.MouseButton1Click:Connect(function()
			if _onAction then
				_onAction(EnumMgr.AEAction.Recruit, { unitType = EnumMgr.AEUnitId.Commander })
			end
		end)
	end
	if _endTurn then
		_endTurn.MouseButton1Click:Connect(function()
			if _onAction then
				_onAction(EnumMgr.AEAction.EndTurn, {})
			end
		end)
	end
end

--[[
	保证 HUD 树
	@return ScreenGui - TbsHud
]]
local function _ensureGui(): ScreenGui
	if _gui and _gui.Parent then
		return _gui
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui")
	local exist = playerGui and playerGui:FindFirstChild(GUI_NAME)
	if exist and exist:IsA("ScreenGui") then
		_gui = exist
		exist.IgnoreGuiInset = true
		if exist:FindFirstChild("Top") then
			_bindRefs(exist)
			_bindClicks(exist)
			_bindTopInset()
			return exist
		end
	end
	local gui = exist and exist:IsA("ScreenGui") and exist or Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundColor3 = Color3.fromRGB(16, 22, 18)
	top.BackgroundTransparency = 0.25
	top.BorderSizePixel = 0
	top.Size = UDim2.new(1, 0, 0, TOP_CONTENT_H)
	top.Parent = gui
	_top = top

	_turn = _label(top, "Turn", UDim2.new(0, 24, 0, 8), UDim2.new(0.4, 0, 0, 28))
	_gold = _label(top, "Gold", UDim2.new(0.42, 0, 0, 8), UDim2.new(0.3, 0, 0, 28))
	_goal = _label(top, "Goal", UDim2.new(0, 24, 0, 38), UDim2.new(0.7, 0, 0, 24))
	_goal.TextSize = 18

	local card = Instance.new("Frame")
	card.Name = "UnitCard"
	card.BackgroundColor3 = Color3.fromRGB(16, 22, 18)
	card.BackgroundTransparency = 0.2
	card.BorderSizePixel = 0
	card.Position = UDim2.new(0, 20, 1, -168)
	card.Size = UDim2.new(0, 280, 0, 148)
	card.Parent = gui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card
	_unitName = _label(card, "UnitName", UDim2.new(0, 16, 0, 12), UDim2.new(1, -32, 0, 28))
	_unitStat = _label(card, "UnitStat", UDim2.new(0, 16, 0, 48), UDim2.new(1, -32, 0, 88))
	_unitStat.TextSize = 18
	_unitStat.TextYAlignment = Enum.TextYAlignment.Top
	_unitStat.TextWrapped = true

	_occupy = _button(gui, "Occupy", UDim2.new(1, -360, 1, -168), UDim2.new(0, 150, 0, 48), "占领")
	_recruitSoldier = _button(gui, "RecruitSoldier", UDim2.new(1, -360, 1, -110), UDim2.new(0, 150, 0, 44), "招募")
	_recruitCommander = _button(gui, "RecruitCommander", UDim2.new(1, -200, 1, -110), UDim2.new(0, 180, 0, 44), "指挥官")
	_endTurn = _button(gui, "EndTurn", UDim2.new(1, -200, 1, -168), UDim2.new(0, 180, 0, 48), "结束回合")
	_endTurn.BackgroundColor3 = Color3.fromRGB(160, 90, 32)

	local result = Instance.new("Frame")
	result.Name = "Result"
	result.BackgroundColor3 = Color3.fromRGB(8, 10, 12)
	result.BackgroundTransparency = 0.25
	result.Size = UDim2.fromScale(1, 1)
	result.Visible = false
	result.Parent = gui
	_result = result
	_resultTitle = _label(result, "Title", UDim2.new(0.5, -200, 0.38, 0), UDim2.new(0, 400, 0, 64))
	_resultTitle.TextXAlignment = Enum.TextXAlignment.Center
	_resultTitle.TextSize = 40
	_button(result, "Again", UDim2.new(0.5, -110, 0.52, 0), UDim2.new(0, 220, 0, 52), "再来一局")

	_gui = gui
	_bindClicks(gui)
	_bindTopInset()
	return gui
end

--[[
	刷新 HUD
	@param snap table - MatchSnap
	@return nil
]]
function TbsHud.Apply(snap: any)
	_snap = snap
	_ensureGui()
	if _gold then
		local gold = snap.goldP
			or (snap.gold and (snap.gold[EnumMgr.AEFaction.Player] or snap.gold["1"] or snap.gold.p))
			or 0
		TranslationHelper.SetRawText(_gold, TranslationHelper.TranslateByKey("金币") .. "  " .. MathMgr.getNumStr(gold))
	end
	if _turn then
		if snap.turnFaction == EnumMgr.AEFaction.Player then
			TranslationHelper.SetText(_turn, "你的回合")
		else
			TranslationHelper.SetText(_turn, "敌方回合")
		end
	end
	if _goal then
		TranslationHelper.SetText(_goal, "击败敌军")
	end

	local selected = _getSelected and _getSelected()
	if _unitName and _unitStat then
		if selected then
			local cfg = AERules.GetUnitCfg(selected.unitType)
			TranslationHelper.SetText(_unitName, cfg and cfg.ZhName or "士兵")
			local hpText = TranslationHelper.TranslateByKey("生命")
				.. " "
				.. MathMgr.getNumStr(selected.hp)
				.. "/"
				.. MathMgr.getNumStr(selected.maxHp)
			local atk = cfg and tonumber(cfg.Atk) or 0
			local def = cfg and tonumber(cfg.Def) or 0
			TranslationHelper.SetRawText(_unitStat, hpText .. "\nATK " .. atk .. "  DEF " .. def)
		else
			TranslationHelper.SetRawText(_unitName, "")
			TranslationHelper.SetRawText(_unitStat, "")
		end
	end

	local canOccupy = false
	if selected and snap.turnFaction == EnumMgr.AEFaction.Player and not selected.acted then
		for _, tile in AERules.CellsFromSnap(snap) do
			if tile.x == selected.x and tile.y == selected.y then
				canOccupy = AERules.CanOccupy(tile.legend, tile.owner, selected.faction)
				break
			end
		end
	end
	if _occupy then
		_occupy.Visible = canOccupy
	end
	local myTurn = snap.turnFaction == EnumMgr.AEFaction.Player and snap.result == nil
	if _recruitSoldier then
		_recruitSoldier.Visible = myTurn
	end
	if _recruitCommander then
		_recruitCommander.Visible = myTurn
	end
	if _endTurn then
		_endTurn.Visible = myTurn
	end
	if _result and _resultTitle then
		if snap.result == "Win" then
			_result.Visible = true
			TranslationHelper.SetText(_resultTitle, "胜利")
		elseif snap.result == "Lose" then
			_result.Visible = true
			TranslationHelper.SetText(_resultTitle, "失败")
		else
			_result.Visible = false
		end
	end
end

--[[
	绑定回调并显示
	@param onAction (string, any) -> () - 发意图
	@param getSelected () -> any? - 当前选中单位
	@return nil
]]
function TbsHud.Init(onAction: (string, any) -> (), getSelected: () -> any?)
	_onAction = onAction
	_getSelected = getSelected
	_ensureGui()
end

return TbsHud
