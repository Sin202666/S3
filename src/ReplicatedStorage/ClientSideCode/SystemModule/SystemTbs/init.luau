--[[
	Module: SystemTbs
	Description: 战棋客户端：收快照、画棋盘、点格发意图、俯视镜头、锁人。不结算。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21

	功能：
	- Init 后注册 TBS_NOTIFY，Sync 拉快照
	- 角色 TransferControlOwner，不写 CFrame / WalkSpeed
	- 镜头走 CameraModule.EnableCameraEvent
	- HUD 走 TbsHud

	加载：
		local SystemTbs = Utils.SystemTbs
		SystemTbs.Init()
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Players = Utils.Players
local NetWork = Utils.NetWork
local NetMsg = Utils.NetMsg
local SystemGameConfig = Utils.SystemGameConfig
local SystemInput = Utils.SystemInput
local CharacterControl = Utils.CharacterControl
local UIMgr = Utils.UIMgr
local EnumMgr = Utils.EnumMgr
local ReplicatedStorage = Utils.ReplicatedStorage
local Log = Utils.Log
local TipsModule = Utils.TipsModule

local BoardView = require(script.BoardView)
local Camera = require(script.Camera)
local Input = require(script.Input)

local SystemTbs = {}

local SESSION_OWNER = "TBS:Session"
local HUD_NAME = "TbsHud"

local _inited = false
local _hud: any = nil
local _inputToken: string? = nil
local _snap: any = nil

--[[
	战棋是否启用
	@return boolean - 开关
]]
local function _tbsOn(): boolean
	return SystemGameConfig.GetValue({ "战棋系统", "启用" }) == true
end

--[[
	应用快照到表现
	@param snap any - MatchSnap
	@return nil
]]
local function _applySnap(snap: any)
	if type(snap) ~= "table" or snap.kind ~= EnumMgr.AENotify.Snapshot then
		return
	end
	_snap = snap
	BoardView.Apply(snap)
	Camera.FocusBoard(snap)
	Input.SetSnap(snap)
	if _hud and _hud.Apply then
		_hud.Apply(snap)
	end
end

--[[
	发意图
	@param action string - 动作
	@param payload any - 参数
	@return nil
]]
local function _send(action: string, payload: any)
	local ok, data = NetWork.InvokeServer(NetMsg.TBS_ACTION, action, payload)
	if type(ok) == "table" then
		_applySnap(ok)
		return
	end
	if type(data) == "table" then
		_applySnap(data)
	end
	if ok ~= true and (data == "START_FAILED" or data == "NO_MATCH" or data == "DISABLED") then
		local player = Players.LocalPlayer
		if player then
			TipsModule.ErrorTips(player, "无法开始对局")
		end
	end
end

--[[
	锁本地角色
	@param character Model? - 角色
	@return nil
]]
local function _lockCharacter(character: Model?)
	if not character then
		return
	end
	task.spawn(function()
		for _ = 1, 20 do
			local ctrl = CharacterControl.GetForCharacter(character)
			if ctrl then
				ctrl:TransferControlOwner(SESSION_OWNER)
				break
			end
			task.wait(0.1)
		end
	end)
	for _, inst in character:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 1
		end
	end
end

--[[
	启动客户端
	@return nil
]]
function SystemTbs.Init()
	if _inited or not _tbsOn() then
		return
	end
	_inited = true

	local ok, hud = pcall(function()
		return require(ReplicatedStorage.ClientSideCode.GuiScripts.ModuleScript.TbsHud)
	end)
	if ok and hud and hud.Init then
		_hud = hud
		hud.Init(_send, function()
			return Input.GetSelected()
		end)
	else
		Log.warn("SystemTbs 加载 HUD 失败", hud)
	end

	UIMgr.HideAllBut(HUD_NAME)
	_inputToken = SystemInput.PushContext(SystemInput.ContextIds.UIModal)

	Input.Start(_send, function()
		if _hud and _hud.Apply and _snap then
			_hud.Apply(_snap)
		end
	end)
	NetWork.RegisterClientRemoteEvent(NetMsg.TBS_NOTIFY, function(snap: any)
		_applySnap(snap)
	end)

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		localPlayer.CharacterAdded:Connect(_lockCharacter)
		if localPlayer.Character then
			_lockCharacter(localPlayer.Character)
		end
	end

	_send(EnumMgr.AEAction.Sync, {})
end

return SystemTbs
