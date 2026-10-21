--[[
	Module: Camera
	Description: 战棋俯视镜头，只走 CameraModule.EnableCameraEvent
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local UserInputService = Utils.UserInputService
local CameraModule = Utils.CameraModule

local BoardView = require(script.Parent.BoardView)

local Camera = {}

local EVENT_NAME = "TBS:Overhead"
local MIN_DIST = 28
local MAX_DIST = 120

local _enabled = false
local _starting = false
local _look = Vector3.new(0, 200, 0)
local _dist = 70
local _yaw = 0
local _pitch = 0.85
local _pan = Vector3.zero
local _conns: { RBXScriptConnection } = {}

--[[
	当前相机 CFrame
	@param _t number - 事件时间
	@param _dt number? - 帧间隔
	@return CFrame - 相机位姿
	@return number - FOV
]]
local function _eval(_t: number, _dt: number?): (CFrame?, number?)
	local target = _look + _pan
	local offset = Vector3.new(
		math.sin(_yaw) * math.cos(_pitch),
		math.sin(_pitch),
		math.cos(_yaw) * math.cos(_pitch)
	) * _dist
	return CFrame.lookAt(target + offset, target), 50
end

--[[
	绑缩放/拖移
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
			if gameProcessed or not _enabled then
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
					local right = Vector3.new(math.cos(_yaw), 0, -math.sin(_yaw))
					local fwd = Vector3.new(-math.sin(_yaw), 0, -math.cos(_yaw))
					_pan += right * (-input.Delta.X * 0.12) + fwd * (-input.Delta.Y * 0.12)
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
	_pan = Vector3.zero
	_dist = 70
	if _enabled or _starting then
		return
	end
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
	for _, conn in _conns do
		conn:Disconnect()
	end
	table.clear(_conns)
	CameraModule.DisableCameraEvent(EVENT_NAME)
	CameraModule.FocusPlayer()
end

return Camera
