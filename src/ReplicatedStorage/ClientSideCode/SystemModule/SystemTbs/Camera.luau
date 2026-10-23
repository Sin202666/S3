--[[
	Module: Camera
	Description: 战棋俯视镜头，只走 CameraModule.EnableCameraEvent。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-23

	能力：
	- FocusBoard：对准棋盘并接管镜头（角色仍由 SystemTbs TransferControlOwner 锁住）
	- 原角色移动键改推镜头：WASD / 方向键 / 手柄左摇杆，相对当前朝向在地面平移
	- 滚轮缩放；右键旋转；中键拖移
	- Release：归还 CameraModule 并 FocusPlayer

	约束：
	- 只写 CameraModule 事件，不写角色 CFrame / WalkSpeed
	- 对局中途快照刷新不重置玩家已推的镜头位置
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local UserInputService = Utils.UserInputService
local CameraModule = Utils.CameraModule

local BoardView = require(script.Parent.BoardView)

local Camera = {}

local EVENT_NAME = "TBS:Overhead"
local MIN_DIST = 28
local MAX_DIST = 120
local PAN_SPEED_AT_DEFAULT = 48
local DEFAULT_DIST = 70
local STICK_DEADZONE = 0.2
local PAN_MARGIN = 24
local KEYS_FORWARD = { Enum.KeyCode.W, Enum.KeyCode.Up }
local KEYS_BACK = { Enum.KeyCode.S, Enum.KeyCode.Down }
local KEYS_LEFT = { Enum.KeyCode.A, Enum.KeyCode.Left }
local KEYS_RIGHT = { Enum.KeyCode.D, Enum.KeyCode.Right }

local _enabled = false
local _starting = false
local _look = Vector3.new(0, 200, 0)
local _dist = DEFAULT_DIST
local _yaw = 0
local _pitch = 0.85
local _pan = Vector3.zero
local _maxPanX = 80
local _maxPanZ = 80
local _stick = Vector2.zero
local _conns: { RBXScriptConnection } = {}

--[[
	任一带键是否按下
	@param keys { Enum.KeyCode } - 键列表
	@return boolean - 有按下
]]
local function _anyKeyDown(keys: { Enum.KeyCode }): boolean
	for _, keyCode in keys do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

--[[
	地面右/前轴，相对当前偏航
	@return Vector3 - 右
	@return Vector3 - 前
]]
local function _groundAxes(): (Vector3, Vector3)
	local right = Vector3.new(math.cos(_yaw), 0, -math.sin(_yaw))
	local fwd = Vector3.new(-math.sin(_yaw), 0, -math.cos(_yaw))
	return right, fwd
end

--[[
	把平移限制在棋盘范围内
	@return nil
]]
local function _clampPan()
	_pan = Vector3.new(
		math.clamp(_pan.X, -_maxPanX, _maxPanX),
		0,
		math.clamp(_pan.Z, -_maxPanZ, _maxPanZ)
	)
end

--[[
	按棋盘尺寸更新平移上限
	@param snap table - MatchSnap
	@return nil
]]
local function _refreshPanLimit(snap: any)
	local w = tonumber(snap.w) or 1
	local h = tonumber(snap.h) or 1
	local c0 = BoardView.CellCenter(0, 0)
	local c1 = BoardView.CellCenter(w - 1, h - 1)
	_maxPanX = math.abs(c1.X - c0.X) * 0.5 + PAN_MARGIN
	_maxPanZ = math.abs(c1.Z - c0.Z) * 0.5 + PAN_MARGIN
end

--[[
	读取原角色移动轴：键盘 + 左摇杆
	@return Vector3 - X 右 / Z 前，模长 ≤ 1
]]
local function _readMoveAxis(): Vector3
	if UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end
	local x = 0
	local z = 0
	if _anyKeyDown(KEYS_FORWARD) then
		z += 1
	end
	if _anyKeyDown(KEYS_BACK) then
		z -= 1
	end
	if _anyKeyDown(KEYS_LEFT) then
		x -= 1
	end
	if _anyKeyDown(KEYS_RIGHT) then
		x += 1
	end
	if _stick.Magnitude >= STICK_DEADZONE then
		x += _stick.X
		z += _stick.Y
	end
	local axis = Vector3.new(x, 0, z)
	local mag = axis.Magnitude
	if mag < 1e-3 then
		return Vector3.zero
	end
	if mag > 1 then
		return axis / mag
	end
	return axis
end

--[[
	用移动键推镜头，速度随缩放变
	@param dt number - 帧间隔
	@return nil
]]
local function _applyMovePan(dt: number)
	if not _enabled or dt <= 0 then
		return
	end
	if dt > 0.1 then
		dt = 0.1
	end
	local axis = _readMoveAxis()
	if axis.Magnitude < 1e-4 then
		return
	end
	local right, fwd = _groundAxes()
	local speed = PAN_SPEED_AT_DEFAULT * (_dist / DEFAULT_DIST)
	_pan += (right * axis.X + fwd * axis.Z) * speed * dt
	_clampPan()
end

--[[
	当前相机 CFrame
	@param _t number - 事件时间
	@param dt number? - 帧间隔
	@return CFrame - 相机位姿
	@return number - FOV
]]
local function _eval(_t: number, dt: number?): (CFrame?, number?)
	_applyMovePan(dt or 0)
	local target = _look + _pan
	local offset = Vector3.new(
		math.sin(_yaw) * math.cos(_pitch),
		math.sin(_pitch),
		math.cos(_yaw) * math.cos(_pitch)
	) * _dist
	return CFrame.lookAt(target + offset, target), 50
end

--[[
	绑缩放 / 旋转 / 中键拖移 / 左摇杆
	@return nil
]]
local function _bindInput()
	for _, conn in _conns do
		conn:Disconnect()
	end
	table.clear(_conns)
	table.insert(
		_conns,
		UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
			if not _enabled then
				return
			end
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				_stick = Vector2.new(input.Position.X, input.Position.Y)
				return
			end
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				_dist = math.clamp(_dist - input.Position.Z * 6, MIN_DIST, MAX_DIST)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				local holdingRight = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
				local holdingMid = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
				if holdingRight then
					_yaw -= input.Delta.X * 0.008
					_pitch = math.clamp(_pitch + input.Delta.Y * 0.006, 0.35, 1.35)
				elseif holdingMid then
					local right, fwd = _groundAxes()
					_pan += right * (-input.Delta.X * 0.12) + fwd * (-input.Delta.Y * 0.12)
					_clampPan()
				end
			end
		end)
	)
end

--[[
	对准棋盘并接管镜头
	@param snap table - MatchSnap
	@return nil
]]
function Camera.FocusBoard(snap: any)
	_look = BoardView.BoardCenter(snap.w, snap.h)
	_refreshPanLimit(snap)
	if _enabled or _starting then
		_clampPan()
		return
	end
	_pan = Vector3.zero
	_dist = DEFAULT_DIST
	_stick = Vector2.zero
	_starting = true
	task.spawn(function()
		for _ = 1, 30 do
			local ok = CameraModule.EnableCameraEvent(EVENT_NAME, 100, 50, _eval, { suppressShake = true })
			if ok then
				_enabled = true
				_starting = false
				_bindInput()
				return
			end
			task.wait(0.1)
		end
		_starting = false
	end)
end

--[[
	归还镜头
	@return nil
]]
function Camera.Release()
	if not _enabled and not _starting then
		return
	end
	_enabled = false
	_starting = false
	_stick = Vector2.zero
	for _, conn in _conns do
		conn:Disconnect()
	end
	table.clear(_conns)
	CameraModule.DisableCameraEvent(EVENT_NAME)
	CameraModule.FocusPlayer()
end

return Camera
