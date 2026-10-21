--[[
	Module: Economy
	Description: 战棋回合开始：产金、驻军回血、重置行动标记
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local AERules = Utils.AERules

local MatchStore = require(script.Parent.MatchStore)

local Economy = {}

--[[
	某阵营回合开始结算
	@param match table - 对局
	@param faction number - 开始行动的阵营
	@return nil
]]
function Economy.BeginTurn(match: any, faction: number)
	local income = 0
	for y = 0, match.h - 1 do
		for x = 0, match.w - 1 do
			local tile = MatchStore.GetTile(match, x, y)
			if tile and tile.owner == faction then
				income += AERules.IncomeOf(tile.legend)
			end
		end
	end
	match.gold[faction] = (match.gold[faction] or 0) + income

	local heal = AERules.GetConst("BUILDING_HEAL", 20)
	for _, unit in match.units do
		if unit.faction == faction then
			unit.moved = false
			unit.acted = false
			if unit.alive then
				local tile = MatchStore.GetTile(match, unit.x, unit.y)
				if tile and tile.owner == faction and AERules.IsBuilding(tile.legend) then
					unit.hp = math.min(unit.maxHp, unit.hp + heal)
				end
			end
		else
			unit.moved = true
			unit.acted = true
		end
	end
end

return Economy
