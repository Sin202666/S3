--[[
	Module: BoardDecor
	Description: 战棋格装饰（树 / 村庄 / 城堡 / 兵营 / 神殿）。只生成表现 Part，
		不写权威、不挡点击。视觉跟 A4_Slap：Glacier + 2022 Big Stud、方块树、厚土边。
		剪影按斜俯视可辨：村=坡屋顶农舍，城=四塔+旗帜，营=长营房+旗，殿=立柱尖顶。
		归属用旗帜/门楣点缀，不整栋染阵营色。
	Author: 程莘
	Created: 2026-10-21
	Last Modified: 2026-10-21

	能力：
	- TileColor / TileMaterial：地砖底色与 Glacier + 2022 Big Stud
	- Apply：在格子上铺对应装饰与厚土；零件 CanQuery=false，避免挡点选
	- EnsureIsland / ResetIsland：海面与岛边

	关系：由 BoardView.Apply 每帧快照重建；占领后 owner 变化会换旗色。

	标准加载：local BoardDecor = require(script.Parent.BoardDecor)

	示例：
		part.Color = BoardDecor.TileColor("C", 2, 2)
		part.Material = BoardDecor.TileMaterial("C")
		part.MaterialVariant = BoardDecor.VARIANT
		BoardDecor.Apply(part, "C", EnumMgr.AEFaction.Player, 2, 2)
]]

local Utils = require(game.ReplicatedFirst.AllSideCode.UtilsSystem)
local EnumMgr = Utils.EnumMgr

local BoardDecor = {}
BoardDecor.MAT = Enum.Material.Glacier
BoardDecor.VARIANT = "2022 Big Stud"
BoardDecor.REACH = Color3.fromRGB(60, 170, 255)
BoardDecor.GOLD = Color3.fromRGB(255, 215, 0)

local TILE_TOP = 0.5
local PI = math.pi
local STYLE_MAT = Enum.Material.Glacier
local STYLE_VARIANT = "2022 Big Stud"
local GRASS_A = Color3.fromRGB(91, 154, 76)
local GRASS_B = Color3.fromRGB(164, 189, 71)
local FOREST_A = Color3.fromRGB(70, 130, 62)
local FOREST_B = Color3.fromRGB(110, 166, 97)
local PATH_A = Color3.fromRGB(235, 184, 127)
local PATH_B = Color3.fromRGB(253, 234, 141)
local STONE_A = Color3.fromRGB(149, 142, 163)
local STONE_B = Color3.fromRGB(175, 170, 185)
local DIRT = Color3.fromRGB(160, 95, 53)
local TRUNK = Color3.fromRGB(143, 76, 42)
local LEAF_A = Color3.fromRGB(164, 189, 71)
local LEAF_B = Color3.fromRGB(174, 196, 93)
local PINK_A = Color3.fromRGB(248, 180, 210)
local PINK_B = Color3.fromRGB(255, 160, 190)
local SEA = Color3.fromRGB(4, 175, 236)
local WOOD = Color3.fromRGB(148, 102, 58)

local _islandKey = ""

--[[
	零件中心 Y（坐在 base 表面上）
	@param height number - 零件高
	@param base number? - 表面相对格中心的 Y，默认砖面
	@return number - 中心 Y
]]
local function _sitY(height: number, base: number?): number
	return (base or TILE_TOP) + height * 0.5
end

--[[
	归属点缀色（旗、门楣）
	@param owner number - 阵营
	@return Color3 - 点缀
]]
local function _accent(owner: number): Color3
	if owner == EnumMgr.AEFaction.Player then
		return Color3.fromRGB(52, 190, 86)
	end
	if owner == EnumMgr.AEFaction.Enemy then
		return Color3.fromRGB(220, 56, 56)
	end
	return Color3.fromRGB(214, 196, 132)
end

--[[
	在格子上放一块装饰（不挡点击）
	@param parent BasePart - 格子
	@param name string - 零件名
	@param size Vector3 - 尺寸
	@param pos Vector3 - 相对格中心
	@param color Color3 - 颜色
	@param material Enum.Material - 材质
	@param kind string? - wedge / ball / cylinder，默认方块
	@param ry number? - 绕 Y 旋转（弧度）
	@return BasePart - 零件
]]
local function _add(
	parent: BasePart,
	name: string,
	size: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material,
	kind: string?,
	ry: number?
): BasePart
	local part: BasePart
	if kind == "wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		if kind == "ball" then
			part.Shape = Enum.PartType.Ball
		elseif kind == "cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
	end
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.Color = color
	if material == Enum.Material.Neon then
		part.Material = material
		part.MaterialVariant = ""
	else
		part.Material = STYLE_MAT
		part.MaterialVariant = STYLE_VARIANT
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = true
	local rotY = ry or 0
	local rotZ = if kind == "cylinder" then PI * 0.5 else 0
	part.CFrame = parent.CFrame * CFrame.new(pos) * CFrame.Angles(0, rotY, rotZ)
	part.Parent = parent
	return part
end

--[[
	插一面归属旗
	@param parent BasePart - 格子
	@param px number - 旗杆 X
	@param pz number - 旗杆 Z
	@param poleBase number - 旗杆底 Y（相对格中心）
	@param owner number - 阵营
	@return nil
]]
local function _flag(parent: BasePart, px: number, pz: number, poleBase: number, owner: number)
	local poleH = 1.7
	_add(
		parent,
		"FlagPole",
		Vector3.new(0.12, poleH, 0.12),
		Vector3.new(px, _sitY(poleH, poleBase), pz),
		Color3.fromRGB(70, 58, 42),
		Enum.Material.Wood
	)
	_add(
		parent,
		"Flag",
		Vector3.new(1.15, 0.7, 0.08),
		Vector3.new(px + 0.62, poleBase + poleH - 0.42, pz),
		_accent(owner),
		STYLE_MAT
	)
end

--[[
	森林：A4 方块树（偶发粉叶）
	@param parent BasePart - 格子
	@param x number - 列
	@param y number - 行
	@return nil
]]
local function _tree(parent: BasePart, x: number, y: number)
	local pink = (x * 7 + y * 13) % 5 == 0
	local leafA = if pink then PINK_A else LEAF_A
	local leafB = if pink then PINK_B else LEAF_B
	local leafC = if pink then PINK_A else FOREST_A
	local tall = (x + y) % 2 == 0
	local h = if tall then 4.4 else 3.5
	_add(parent, "Trunk", Vector3.new(1.55, h, 1.55), Vector3.new(0, _sitY(h), 0), TRUNK, STYLE_MAT)
	_add(parent, "Leaf", Vector3.new(4.2, 2.5, 4.2), Vector3.new(0, TILE_TOP + h + 0.85, 0), leafA, STYLE_MAT)
	_add(parent, "LeafMid", Vector3.new(3.1, 1.9, 3.1), Vector3.new(0, TILE_TOP + h + 2.3, 0), leafB, STYLE_MAT)
	if tall or pink then
		_add(parent, "LeafTop", Vector3.new(2.1, 1.4, 2.1), Vector3.new(0, TILE_TOP + h + 3.5, 0), leafC, STYLE_MAT)
	end
end

--[[
	村庄：坡顶农舍 + 烟囱 + 水井，靠格后侧给棋子留位
	@param parent BasePart - 格子
	@param owner number - 阵营
	@return nil
]]
local function _village(parent: BasePart, owner: number)
	local wood = Color3.fromRGB(148, 102, 58)
	local plaster = Color3.fromRGB(214, 196, 160)
	local roof = Color3.fromRGB(168, 64, 46)
	local bodyH = 1.55
	local bodyTop = TILE_TOP + bodyH
	_add(parent, "House", Vector3.new(2.7, bodyH, 2.15), Vector3.new(-0.55, _sitY(bodyH), -1.25), plaster, Enum.Material.SmoothPlastic)
	_add(parent, "Sill", Vector3.new(2.85, 0.18, 2.3), Vector3.new(-0.55, TILE_TOP + 0.09, -1.25), wood, Enum.Material.Wood)
	_add(
		parent,
		"RoofBack",
		Vector3.new(3.05, 1.2, 1.2),
		Vector3.new(-0.55, _sitY(1.2, bodyTop), -1.79),
		roof,
		Enum.Material.Slate,
		"wedge"
	)
	_add(
		parent,
		"RoofFront",
		Vector3.new(3.05, 1.2, 1.2),
		Vector3.new(-0.55, _sitY(1.2, bodyTop), -0.71),
		roof,
		Enum.Material.Slate,
		"wedge",
		PI
	)
	_add(parent, "Chimney", Vector3.new(0.42, 1.15, 0.42), Vector3.new(0.45, bodyTop + 1.05, -1.85), Color3.fromRGB(110, 78, 68), Enum.Material.Brick)
	_add(parent, "Door", Vector3.new(0.7, 1.05, 0.1), Vector3.new(-0.55, TILE_TOP + 0.62, -0.12), wood, Enum.Material.Wood)
	_add(parent, "Lintel", Vector3.new(0.9, 0.16, 0.12), Vector3.new(-0.55, TILE_TOP + 1.2, -0.1), _accent(owner), Enum.Material.SmoothPlastic)
	_add(
		parent,
		"Well",
		Vector3.new(0.95, 0.55, 0.95),
		Vector3.new(1.85, _sitY(0.55), -0.85),
		Color3.fromRGB(120, 120, 128),
		Enum.Material.Slate,
		"cylinder"
	)
	_add(
		parent,
		"WellWater",
		Vector3.new(0.62, 0.2, 0.62),
		Vector3.new(1.85, TILE_TOP + 0.48, -0.85),
		Color3.fromRGB(64, 120, 168),
		Enum.Material.Glass,
		"cylinder"
	)
end

--[[
	城堡：主楼 + 四角塔 + 城门 + 旗帜，靠格后侧
	@param parent BasePart - 格子
	@param owner number - 阵营
	@return nil
]]
local function _castle(parent: BasePart, owner: number)
	local stone = Color3.fromRGB(148, 148, 158)
	local dark = Color3.fromRGB(92, 92, 104)
	local merlon = Color3.fromRGB(72, 72, 84)
	local keepH = 3.15
	local towerH = 4.55
	local keepZ = -1.45
	local keepTop = TILE_TOP + keepH
	local towerTop = TILE_TOP + towerH
	_add(parent, "Keep", Vector3.new(2.25, keepH, 2.05), Vector3.new(0, _sitY(keepH), keepZ), stone, Enum.Material.Slate)
	_add(parent, "Gate", Vector3.new(0.95, 1.55, 0.18), Vector3.new(0, TILE_TOP + 0.82, keepZ + 1.1), Color3.fromRGB(36, 32, 30), Enum.Material.SmoothPlastic)
	_add(parent, "Lintel", Vector3.new(1.25, 0.28, 0.22), Vector3.new(0, TILE_TOP + 1.72, keepZ + 1.12), _accent(owner), Enum.Material.SmoothPlastic)
	local towers = {
		{ "T_BL", -1.55, keepZ - 1.15 },
		{ "T_BR", 1.55, keepZ - 1.15 },
		{ "T_FL", -1.55, keepZ + 1.15 },
		{ "T_FR", 1.55, keepZ + 1.15 },
	}
	for _, spec in towers do
		local name, tx, tz = spec[1], spec[2], spec[3]
		_add(parent, name, Vector3.new(1.15, towerH, 1.15), Vector3.new(tx, _sitY(towerH), tz), stone, Enum.Material.Concrete)
		_add(parent, name .. "Cap", Vector3.new(1.4, 0.32, 1.4), Vector3.new(tx, _sitY(0.32, towerTop), tz), dark, Enum.Material.Slate)
		_add(parent, name .. "M1", Vector3.new(0.32, 0.38, 0.32), Vector3.new(tx - 0.42, _sitY(0.38, towerTop + 0.32), tz - 0.42), merlon, Enum.Material.Slate)
		_add(parent, name .. "M2", Vector3.new(0.32, 0.38, 0.32), Vector3.new(tx + 0.42, _sitY(0.38, towerTop + 0.32), tz + 0.42), merlon, Enum.Material.Slate)
	end
	_add(parent, "KeepMerlonL", Vector3.new(0.38, 0.4, 0.38), Vector3.new(-0.7, _sitY(0.4, keepTop), keepZ), merlon, Enum.Material.Slate)
	_add(parent, "KeepMerlonR", Vector3.new(0.38, 0.4, 0.38), Vector3.new(0.7, _sitY(0.4, keepTop), keepZ), merlon, Enum.Material.Slate)
	_add(parent, "WallL", Vector3.new(0.35, 1.7, 1.9), Vector3.new(-1.55, _sitY(1.7), keepZ), dark, Enum.Material.Slate)
	_add(parent, "WallR", Vector3.new(0.35, 1.7, 1.9), Vector3.new(1.55, _sitY(1.7), keepZ), dark, Enum.Material.Slate)
	_flag(parent, 1.55, keepZ + 1.15, towerTop + 0.7, owner)
end

--[[
	兵营：长营房 + 训练桩 + 旗帜
	@param parent BasePart - 格子
	@param owner number - 阵营
	@return nil
]]
local function _barracks(parent: BasePart, owner: number)
	local wood = Color3.fromRGB(112, 78, 48)
	local wall = Color3.fromRGB(168, 140, 108)
	local roof = Color3.fromRGB(78, 62, 50)
	local hallH = 2.35
	local hallZ = -1.15
	local hallTop = TILE_TOP + hallH
	_add(parent, "Hall", Vector3.new(4.7, hallH, 2.2), Vector3.new(0, _sitY(hallH), hallZ), wall, Enum.Material.Wood)
	_add(parent, "Roof", Vector3.new(5, 0.32, 2.5), Vector3.new(0, _sitY(0.32, hallTop), hallZ), roof, Enum.Material.Slate)
	_add(parent, "Door", Vector3.new(0.8, 1.35, 0.12), Vector3.new(0, TILE_TOP + 0.78, hallZ + 1.16), wood, Enum.Material.Wood)
	_add(parent, "WinL", Vector3.new(0.7, 0.55, 0.1), Vector3.new(-1.55, TILE_TOP + 1.45, hallZ + 1.16), Color3.fromRGB(80, 140, 170), Enum.Material.Glass)
	_add(parent, "WinR", Vector3.new(0.7, 0.55, 0.1), Vector3.new(1.55, TILE_TOP + 1.45, hallZ + 1.16), Color3.fromRGB(80, 140, 170), Enum.Material.Glass)
	_add(parent, "Stripe", Vector3.new(4.75, 0.18, 0.08), Vector3.new(0, TILE_TOP + 2.05, hallZ + 1.14), _accent(owner), Enum.Material.SmoothPlastic)
	_flag(parent, 2.2, hallZ, hallTop + 0.32, owner)
end

--[[
	神殿：台基 + 立柱 + 尖顶 + 光球
	@param parent BasePart - 格子
	@param owner number - 阵营
	@return nil
]]
local function _shrine(parent: BasePart, owner: number)
	local marble = Color3.fromRGB(232, 226, 210)
	local gold = Color3.fromRGB(214, 176, 72)
	local glow = Color3.fromRGB(120, 220, 255)
	_add(parent, "Plinth", Vector3.new(3.4, 0.5, 3.4), Vector3.new(0, _sitY(0.5), -0.7), marble, Enum.Material.Marble)
	_add(parent, "Step", Vector3.new(2.1, 0.28, 1.2), Vector3.new(0, _sitY(0.28), 1.05), marble, Enum.Material.Marble)
	local colH = 2.35
	local colY = _sitY(colH, TILE_TOP + 0.5)
	local cols = {
		{ -1.15, -1.7 },
		{ 1.15, -1.7 },
		{ -1.15, 0.3 },
		{ 1.15, 0.3 },
	}
	for i, spec in cols do
		_add(
			parent,
			"Col" .. i,
			Vector3.new(0.52, colH, 0.52),
			Vector3.new(spec[1], colY, spec[2]),
			marble,
			Enum.Material.Marble,
			"cylinder"
		)
	end
	local beamY = TILE_TOP + 0.5 + colH
	_add(parent, "Entablature", Vector3.new(2.7, 0.28, 2.4), Vector3.new(0, _sitY(0.28, beamY), -0.85), gold, Enum.Material.Metal)
	_add(
		parent,
		"Pediment",
		Vector3.new(2.85, 1.15, 2.5),
		Vector3.new(0, _sitY(1.15, beamY + 0.28), -0.85),
		_accent(owner),
		Enum.Material.SmoothPlastic,
		"wedge",
		-PI * 0.5
	)
	local spireH = 1.6
	local spireBase = beamY + 0.28 + 0.7
	_add(parent, "Spire", Vector3.new(0.28, spireH, 0.28), Vector3.new(0, _sitY(spireH, spireBase), -0.85), gold, Enum.Material.Metal)
	_add(
		parent,
		"Orb",
		Vector3.new(0.7, 0.7, 0.7),
		Vector3.new(0, spireBase + spireH + 0.28, -0.85),
		glow,
		Enum.Material.Neon,
		"ball"
	)
end

--[[
	地形底色
	@param legend string - 图例
	@return Color3 - 颜色
]]
function BoardDecor.TileColor(legend: string, x: number?, y: number?): Color3
	local dark = ((x or 0) + (y or 0)) % 2 == 0
	if legend == "T" then
		return if dark then FOREST_A else FOREST_B
	end
	if legend == "V" then
		return if dark then PATH_A else PATH_B
	end
	if legend == "C" then
		return if dark then STONE_A else STONE_B
	end
	if legend == "B" then
		return if dark then PATH_A else WOOD
	end
	if legend == "R" then
		return if dark then STONE_B else PATH_B
	end
	return if dark then GRASS_A else GRASS_B
end

--[[
	地形材质
	@param legend string - 图例
	@return Enum.Material - 材质
]]
function BoardDecor.TileMaterial(_legend: string): Enum.Material
	return STYLE_MAT
end

--[[
	岛标记作废
	@return nil
]]
function BoardDecor.ResetIsland()
	_islandKey = ""
end

--[[
	铺海面与岛边
	@param folder Folder - TbsBoard
	@param w number - 宽
	@param h number - 高
	@param tileSize number - 格边
	@param cellCenter (number, number) -> Vector3 - 格中心
	@param boardY number - 棋盘高度
	@return nil
]]
function BoardDecor.EnsureIsland(
	folder: Folder,
	w: number,
	h: number,
	tileSize: number,
	cellCenter: (number, number) -> Vector3,
	boardY: number
)
	local key = w .. "x" .. h .. ":stud"
	if _islandKey == key then
		return
	end
	local old = folder:FindFirstChild("Island")
	if old then
		old:Destroy()
	end
	local island = Instance.new("Folder")
	island.Name = "Island"
	island.Parent = folder
	local mid = cellCenter((w - 1) * 0.5, (h - 1) * 0.5)
	local sea = Instance.new("Part")
	sea.Name = "Sea"
	sea.Anchored = true
	sea.CanCollide = false
	sea.CanQuery = false
	sea.Material = STYLE_MAT
	sea.MaterialVariant = STYLE_VARIANT
	sea.Size = Vector3.new((w + 20) * tileSize, 1, (h + 20) * tileSize)
	sea.CFrame = CFrame.new(mid.X, boardY - 4.2, mid.Z)
	sea.Color = SEA
	sea.Parent = island
	for x = -1, w do
		for y = -1, h do
			local inside = x >= 0 and x < w and y >= 0 and y < h
			if not inside then
				local cf = CFrame.new(cellCenter(x, y))
				local grass = if (x + y) % 2 == 0 then GRASS_A else GRASS_B
				local rim = Instance.new("Part")
				rim.Name = "Rim"
				rim.Anchored = true
				rim.CanCollide = false
				rim.CanQuery = false
				rim.Material = STYLE_MAT
				rim.MaterialVariant = STYLE_VARIANT
				rim.Size = Vector3.new(tileSize - 0.08, 1, tileSize - 0.08)
				rim.CFrame = cf
				rim.Color = grass
				rim.Parent = island
				local cliff = Instance.new("Part")
				cliff.Name = "Cliff"
				cliff.Anchored = true
				cliff.CanCollide = false
				cliff.CanQuery = false
				cliff.Material = STYLE_MAT
				cliff.MaterialVariant = STYLE_VARIANT
				cliff.Size = Vector3.new(tileSize - 0.08, 3.2, tileSize - 0.08)
				cliff.CFrame = cf * CFrame.new(0, -2.1, 0)
				cliff.Color = DIRT
				cliff.Parent = island
			end
		end
	end
	_islandKey = key
end

--[[
	按图例铺装饰
	@param parent BasePart - 格子
	@param legend string - 图例
	@param owner number - 归属
	@return nil
]]
function BoardDecor.Apply(parent: BasePart, legend: string, owner: number, x: number?, y: number?)
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end
	local size = parent.Size
	_add(parent, "Cliff", Vector3.new(size.X, 3.2, size.Z), Vector3.new(0, -2.1, 0), DIRT, STYLE_MAT)
	local col = x or 0
	local row = y or 0
	if legend == "T" then
		_tree(parent, col, row)
		return
	end
	if legend == "V" then
		_village(parent, owner)
		return
	end
	if legend == "C" then
		_castle(parent, owner)
		return
	end
	if legend == "B" then
		_barracks(parent, owner)
		return
	end
	if legend == "R" then
		_shrine(parent, owner)
		return
	end
	if (col * 3 + row * 5) % 4 == 0 then
		local palette = {
			Color3.fromRGB(248, 248, 248),
			Color3.fromRGB(255, 89, 89),
			Color3.fromRGB(255, 160, 190),
			Color3.fromRGB(255, 220, 80),
		}
		local color = palette[((col * 11 + row) % #palette) + 1]
		local ox = ((col % 3) - 1) * 1.6
		local oz = ((row % 3) - 1) * 1.6
		_add(parent, "Flower", Vector3.new(0.45, 0.45, 0.45), Vector3.new(ox, TILE_TOP + 0.22, oz), color, STYLE_MAT)
	elseif (col * 5 + row * 7) % 6 == 0 then
		local ox = ((col % 3) - 1) * 1.8
		local oz = ((row % 3) - 1) * 1.8
		_add(parent, "Stone", Vector3.new(1.15, 0.7, 1.35), Vector3.new(ox, TILE_TOP + 0.35, oz), STONE_A, STYLE_MAT)
	end
end

return BoardDecor
