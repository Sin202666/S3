local inst = game.ServerStorage.ServerSideCode.System.SystemTbs
if not inst then error("missing") end
inst.Source = [TBS_SRC[--[[
	Module: SystemTbs
	Description: 战棋服务端权威：开局、意图校验、结算、快照下推。对局在会话内存。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-23

	功能：
	- SetupPlayer 按 GameConfig 默认关卡开 1-1
	- TBS_ACTION：Sync / Move / Attack / Occupy / Wait / Recruit / EndTurn / Restart
	- 客户端只报意图；伤害、金币、胜负只在本模块改
	- 通关写 SaveMetaData.Tbs.Stage1Clear

	加载：
		local SystemTbs = Utils.SystemTbs
		SystemTbs.Init()
		SystemTbs.SetupPlayer(player)
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local Players = Utils.Players
local NetWork = Utils.NetWork
local NetMsg = Utils.NetMsg
local RequestRateLimit = Utils.RequestRateLimit
local SystemGameConfig = Utils.SystemGameConfig
local SystemSave = Utils.SystemSave
local EnumMgr = Utils.EnumMgr
local Log = Utils.Log

local MatchStore = require(script.MatchStore)
local ActionHandler = require(script.ActionHandler)

local SystemTbs = {}

local RATE_MAX = 20
local RATE_WINDOW = 2
local _netRegistered = false

--[[
	战棋是否启用
	@return boolean - GameConfig 战棋系统.启用
]]
local function _tbsOn(): boolean
	return SystemGameConfig.GetValue({ "战棋系统", "启用" }) == true
end

--[[
	玩家是否仍在场
	@param player Player? - 玩家
	@return boolean - 有效
]]
local function _validPlayer(player: Player?): boolean
	return player ~= nil and player:IsA("Player") and player.Parent == Players
end

--[[
	默认关卡 Id
	@return number - 关卡
]]
local function _defaultMapId(): number
	return tonumber(SystemGameConfig.GetValue({ "战棋系统", "默认关卡" })) or 1
end

--[[
	下推快照
	@param player Player - 玩家
	@param match table - 对局
	@return table - 快照
]]
local function _notify(player: Player, match: any): any
	local snap = MatchStore.Snapshot(match)
	NetWork.FireClient(player, NetMsg.TBS_NOTIFY, snap)
	return snap
end

--[[
	通关落盘（仅 Stage1Clear）
	@param player Player - 玩家
	@param match table - 对局
	@return nil
]]
local function _trySaveClear(player: Player, match: any)
	if match.result ~= "Win" or match.mapId ~= 1 then
		return
	end
	SystemSave.ChangeStat(player, { "Tbs", "Stage1Clear" }, 1)
end

--[[
	开或重开对局
	@param player Player - 玩家
	@param mapId number - 关卡
	@return table? - 对局
]]
local function _startMatch(player: Player, mapId: number): any?
	MatchStore.Remove(player)
	local match = MatchStore.Create(player, mapId)
	if not match then
		Log.warn("SystemTbs 开局失败", player.UserId, mapId)
		return nil
	end
	return match
end

--[[
	分发意图
	@param player Player - 玩家
	@param action any - 动作名
	@param payload any - 参数表
	@return boolean - 成功
	@return any - 快照或失败码
]]
local function _dispatch(player: Player, action: any, payload: any): (boolean, any)
	if type(action) ~= "string" then
		return false, "BAD_ACTION"
	end
	if payload ~= nil and type(payload) ~= "table" then
		return false, "BAD_PAYLOAD"
	end
	payload = payload or {}

	if action == EnumMgr.AEAction.Restart then
		local match = _startMatch(player, _defaultMapId())
		if not match then
			return false, "START_FAILED"
		end
		return true, _notify(player, match)
	end

	local match = MatchStore.Get(player)
	if action == EnumMgr.AEAction.Sync then
		if not match then
			match = _startMatch(player, _defaultMapId())
		end
		if not match then
			return false, "NO_MATCH"
		end
		return true, _notify(player, match)
	end
	if not match then
		return false, "NO_MATCH"
	end

	local ok = false
	local err: string? = nil
	if action == EnumMgr.AEAction.Move then
		ok, err = ActionHandler.Move(match, payload)
	elseif action == EnumMgr.AEAction.Attack then
		ok, err = ActionHandler.Attack(match, payload)
	elseif action == EnumMgr.AEAction.Occupy then
		ok, err = ActionHandler.Occupy(match, payload)
	elseif action == EnumMgr.AEAction.Wait then
		ok, err = ActionHandler.Wait(match, payload)
	elseif action == EnumMgr.AEAction.Recruit then
		ok, err = ActionHandler.Recruit(match, payload)
	elseif action == EnumMgr.AEAction.EndTurn then
		ok, err = ActionHandler.EndTurn(match)
	else
		return false, "UNKNOWN_ACTION"
	end
	if not ok then
		Log.print("SystemTbs 拒绝", player.UserId, action, err)
		return false, err
	end
	_trySaveClear(player, match)
	return true, _notify(player, match)
end

--[[
	注册 Remote
	@return nil
]]
function SystemTbs.RegisterNetWork()
	if _netRegistered then
		return
	end
	_netRegistered = true
	RequestRateLimit.SetRateLimitConfig(NetMsg.TBS_ACTION, {
		maxRequests = RATE_MAX,
		timeWindow = RATE_WINDOW,
	})
	NetWork.RegisterServerRemoteFunction(NetMsg.TBS_ACTION, function(player: Player, action: any, payload: any)
		if not _validPlayer(player) then
			return false, "INVALID_PLAYER"
		end
		if not _tbsOn() then
			return false, "DISABLED"
		end
		return _dispatch(player, action, payload)
	end, {
		skipCheatDetection = true,
	})
end

--[[
	进程 Init
	@return nil
]]
function SystemTbs.Init()
	SystemTbs.RegisterNetWork()
end

--[[
	入服开 1-1
	@param player Player - 玩家
	@return boolean - 是否开局
]]
function SystemTbs.SetupPlayer(player: Player): boolean
	if not _tbsOn() or not _validPlayer(player) then
		return false
	end
	local match = _startMatch(player, _defaultMapId())
	if not match then
		return false
	end
	_notify(player, match)
	return true
end

--[[
	离服清对局
	@param player Player - 玩家
	@return nil
]]
function SystemTbs.OnPlayerRemoving(player: Player)
	MatchStore.Remove(player)
end

SystemTbs.RegisterNetWork()

return SystemTbs
]TBS_SRC]
return { name = inst.Name, lines = select(2, string.gsub(inst.Source, "\n", "\n")) }
