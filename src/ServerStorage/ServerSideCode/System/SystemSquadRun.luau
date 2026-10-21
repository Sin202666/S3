--[[
	Module: SystemSquadRun
	Description: 局内会话与小队根节点唯一写口：推进 Z、夹紧车道 X
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21

	写口：小队根节点 CFrame 仅本模块；不写玩家角色位姿
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Players = Utils.Players
local RunService = Utils.RunService
local NetWork = Utils.NetWork
local NetMsg = Utils.NetMsg
local RequestRateLimit = Utils.RequestRateLimit
local EnumMgr = Utils.EnumMgr
local Log = Utils.Log
local GateRunConfig = Utils.GateRunConfig
local SystemLevelBuild = Utils.SystemLevelBuild
local SystemGate = Utils.SystemGate
local SystemSquadCombat = Utils.SystemSquadCombat
local SystemRunSettle = Utils.SystemRunSettle

local SystemSquadRun = {}
local ROOT_NAME = "SquadRoot"
local _sessions: { [number]: any } = {}
local _heartbeat: RBXScriptConnection? = nil
local _playerRemoving: RBXScriptConnection? = nil
local _netRegistered = false

local function _ensureRoot(world: Folder, player: Player): BasePart
	local name = ROOT_NAME .. "_" .. tostring(player.UserId)
	local existing = world:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Part")
	root.Name = name
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Parent = world
	return root
end

local function _cloneCombatants(): ({ any }, { any })
	local gates = {}
	for _, gate in GateRunConfig.GetGates() do
		table.insert(gates, { id = gate.Id, z = gate.Z, x = gate.X, width = gate.Width, op = gate.Op, value = gate.Value, consumed = false })
	end
	local enemies = {}
	for _, enemy in GateRunConfig.GetEnemies() do
		table.insert(enemies, { id = enemy.Id, z = enemy.Z, x = enemy.X, hp = enemy.Hp, maxHp = enemy.Hp, radius = enemy.Radius, dead = false })
	end
	return gates, enemies
end

local function _publish(session: any)
	local state = SystemLevelBuild.GetState()
	if not state then
		return
	end
	local progress = if session.finishZ > 0 then math.clamp(session.z / session.finishZ, 0, 1) else 0
	state:SetAttribute("Count", session.count)
	state:SetAttribute("Z", session.z)
	state:SetAttribute("X", session.x)
	state:SetAttribute("Phase", session.phase)
	state:SetAttribute("TargetId", session.targetId or 0)
	state:SetAttribute("TargetHp", session.targetHp or 0)
	state:SetAttribute("Progress", progress)
	state:SetAttribute("VisualCap", session.runCfg.VisualCap)
	state:SetAttribute("OwnerUserId", session.player.UserId)
end

local function _fireState(session: any)
	NetWork.FireClient(session.player, NetMsg.GATE_RUN_STATE, {
		phase = session.phase,
		count = session.count,
		z = session.z,
		x = session.x,
		targetId = session.targetId or 0,
		progress = if session.finishZ > 0 then math.clamp(session.z / session.finishZ, 0, 1) else 0,
	})
end

--[[
	清会话：取消待重开线程并销毁小队根。
	不可 task.cancel 当前正在执行的线程（重开 delay 回调里会再调 Start）。

	@param userId number - 玩家 UserId
	@return nil
]]
local function _clearSession(userId: number)
	local session = _sessions[userId]
	if not session then
		return
	end
	local restartThread = session.restartThread
	session.restartThread = nil
	if restartThread and restartThread ~= coroutine.running() then
		pcall(task.cancel, restartThread)
	end
	if session.root then
		session.root:Destroy()
	end
	_sessions[userId] = nil
end

local function _writeRoot(session: any)
	local origin = session.origin
	session.root.CFrame = CFrame.new(origin.X + session.x, origin.Y + session.runCfg.RootHeight, origin.Z + session.z)
end

local function _step(session: any, dt: number)
	if session.phase ~= EnumMgr.RunPhase.Running then
		return
	end
	local runCfg = session.runCfg
	local prevZ = session.z
	session.z += runCfg.ForwardSpeed * dt
	local maxStep = runCfg.MaxSteerSpeed * dt
	local deltaX = session.desiredX - session.x
	if math.abs(deltaX) <= maxStep then
		session.x = session.desiredX
	else
		session.x += math.sign(deltaX) * maxStep
	end
	session.x = math.clamp(session.x, -runCfg.RoadHalfWidth, runCfg.RoadHalfWidth)
	_writeRoot(session)
	SystemSquadCombat.Tick(session, dt)
	SystemGate.TryConsume(session, prevZ)
	SystemRunSettle.Evaluate(session)
	_publish(session)
	if session.phase ~= EnumMgr.RunPhase.Running then
		_fireState(session)
		session.restartThread = task.delay(runCfg.RestartDelay, function()
			-- 先摘掉引用，避免 Start/_clearSession 取消正在跑的本线程
			session.restartThread = nil
			if session.player.Parent then
				SystemSquadRun.Start(session.player)
			end
		end)
	end
end

local function _onSteer(player: Player, payload: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local session = _sessions[player.UserId]
	if not session or session.phase ~= EnumMgr.RunPhase.Running then
		return
	end
	if type(payload) ~= "table" or type(payload.x) ~= "number" then
		return
	end
	if payload.x ~= payload.x or payload.x == math.huge or payload.x == -math.huge then
		return
	end
	if math.abs(payload.x) > 1000 then
		return
	end
	session.desiredX = math.clamp(payload.x, -session.runCfg.RoadHalfWidth, session.runCfg.RoadHalfWidth)
end

function SystemSquadRun.Start(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	_clearSession(player.UserId)
	local world = SystemLevelBuild.EnsureWorld()
	local runCfg = GateRunConfig.GetRun()
	if not runCfg or not runCfg.StartCount then
		Log.warn("[SystemSquadRun] missing gaterunConf")
		return
	end
	SystemLevelBuild.ResetCombatants()
	local gates, enemies = _cloneCombatants()
	local root = _ensureRoot(world, player)
	local session = {
		player = player,
		root = root,
		origin = GateRunConfig.GetOrigin(runCfg),
		z = 0,
		x = 0,
		desiredX = 0,
		count = runCfg.StartCount,
		phase = EnumMgr.RunPhase.Running,
		fireAcc = 0,
		targetId = 0,
		targetHp = 0,
		gates = gates,
		enemies = enemies,
		finishZ = runCfg.FinishZ,
		runCfg = runCfg,
		restartThread = nil,
	}
	_sessions[player.UserId] = session
	_writeRoot(session)
	_publish(session)
	_fireState(session)
end

function SystemSquadRun.Init()
	if not _netRegistered then
		_netRegistered = true
		RequestRateLimit.SetRateLimitConfig(NetMsg.GATE_RUN_STEER, { maxRequests = 24, timeWindow = 1 })
		RequestRateLimit.SetCheatDetectionConfig(NetMsg.GATE_RUN_STEER, { enabled = false })
		NetWork.RegisterServerRemoteEvent(NetMsg.GATE_RUN_STEER, _onSteer, { skipCheatDetection = true })
	end
	if not _heartbeat then
		_heartbeat = RunService.Heartbeat:Connect(function(dt: number)
			for _, session in _sessions do
				_step(session, dt)
			end
		end)
	end
	if not _playerRemoving then
		_playerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
			_clearSession(player.UserId)
		end)
	end
end

return SystemSquadRun
