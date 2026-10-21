--[[
	Module: TbsManager
	Description: 客户端战棋启动编排，只调 SystemTbs.Init
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21

	本文件为 LocalScript，由引擎自动运行；禁止被 require。
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local SystemGameConfig = Utils.SystemGameConfig
local SystemTbs = Utils.SystemTbs

if SystemGameConfig.GetValue({ "战棋系统", "启用" }) == false then
	return
end

SystemTbs.Init()
