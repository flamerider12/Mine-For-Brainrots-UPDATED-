--!strict
--[[
	MineGenerator.lua
	Handles procedural mine generation for player plots
	Location: ServerScriptService/Services/MineGenerator.lua
	
	INTEGRATION:
	- Uses PlotManager to get MineOrigin reference point
	- Uses GameConfig Layers/Blocks for ore definitions and rarity tables
	- Tags generated blocks with CollectionService for mining system
	
	GENERATION STRATEGY:
	- Column-based generation (fills X-Z grid, layer by layer on Y)
	- Generates initial layers on plot creation
	- Dynamically generates more layers as player mines deeper
	- Uses weighted random selection based on Block.Chance values
	
	TUTORIAL LAYER:
	- First layer (block layer 0) is hardcoded for tutorial
	- Contains ONLY basic/alternate blocks (no ores)
	- Exactly ONE brainrot block spawns at a random position
	- This guides new players to discover the core mechanic
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local MineGenerator = {}

--------------------------------------------------------------------------------
-- PRIVATE STATE
--------------------------------------------------------------------------------

-- Track generated data per player: {[Player] = MineData}
local PlayerMineData: {[Player]: MineData} = {}

-- Random generator per player (seeded for variety)
local RandomGenerators: {[Player]: Random} = {}

--------------------------------------------------------------------------------
-- TUTORIAL CONFIGURATION
--------------------------------------------------------------------------------

local TUTORIAL_CONFIG = {
	-- Which block layer is the tutorial layer (0 = first layer)
	TutorialBlockLayer = 0,

	-- How many brainrot blocks spawn in tutorial layer
	BrainrotCount = 1,

	-- Force a specific rarity for tutorial brainrot (nil = use normal drop rates)
	ForcedRarity = "Common" :: GameConfig.Rarity?,

	-- If true, place brainrot near center for easier discovery
	-- If false, place randomly anywhere in the layer
	PlaceNearCenter = true,

	-- How close to center (in grid units) if PlaceNearCenter is true
	-- e.g., 3 means within 3 blocks of center in X and Z
	CenterRadius = 4,
}

--------------------------------------------------------------------------------
-- TYPE DEFINITIONS
--------------------------------------------------------------------------------

export type MineData = {
	DeepestBlockLayer: number,  -- Deepest block layer index generated (0-based)
	Blocks: {BasePart},         -- All generated blocks
	MineOrigin: Vector3,        -- Reference point (top of mine)
	MineFolder: Folder,         -- Container for all blocks
	TutorialBrainrotBlock: BasePart?,  -- Reference to the tutorial brainrot (for tutorial system)
}

export type MinedBlockData = {
	BlockId: string,
	BlockName: string,
	BlockType: string,          -- "Dirt" | "Stone" | "Ore" | "Brainrot"
	Value: number,
	Health: number,
	MaxHealth: number,
	LayerIndex: number,         -- Which GameConfig layer (1-7)
	LayerName: string,
	GridX: number,
	GridY: number,              -- Block layer (0 = first layer below origin)
	GridZ: number,
	IsTutorialBlock: boolean?,  -- NEW: True if this is the tutorial brainrot
	-- Brainrot-specific
	BrainrotDropRates: {[GameConfig.Rarity]: number}?,
}

--------------------------------------------------------------------------------
-- BLOCK APPEARANCE MAPPING
--------------------------------------------------------------------------------

-- Map block types to colors (fallback if textures not applied)
local BlockColors: {[string]: Color3} = {
	-- Layer 1: Surface
	Grass = Color3.fromRGB(86, 125, 70),
	Dirt = Color3.fromRGB(120, 85, 60),
	Coal = Color3.fromRGB(40, 40, 40),
	Iron = Color3.fromRGB(180, 150, 130),
	Mystery_Box_1 = Color3.fromRGB(200, 180, 100),

	-- Layer 2: Crust
	Stone = Color3.fromRGB(128, 128, 128),
	Gravel = Color3.fromRGB(100, 100, 100),
	Gold = Color3.fromRGB(255, 200, 50),
	Diamond = Color3.fromRGB(100, 200, 255),
	Mystery_Box_2 = Color3.fromRGB(100, 200, 100),

	-- Layer 3: Mantle
	Granite = Color3.fromRGB(160, 140, 130),
	Diorite = Color3.fromRGB(200, 200, 200),
	Emerald = Color3.fromRGB(50, 200, 80),
	Ruby = Color3.fromRGB(200, 50, 80),
	Mystery_Box_3 = Color3.fromRGB(80, 150, 255),

	-- Layer 4: Deep Slate
	Slate = Color3.fromRGB(60, 60, 70),
	Tuff = Color3.fromRGB(80, 75, 70),
	Sapphire = Color3.fromRGB(30, 80, 200),
	Amethyst = Color3.fromRGB(150, 80, 200),
	Mystery_Box_4 = Color3.fromRGB(200, 100, 255),

	-- Layer 5: Core
	Magma = Color3.fromRGB(200, 80, 30),
	Basalt = Color3.fromRGB(50, 50, 55),
	Onyx = Color3.fromRGB(20, 20, 25),
	Painite = Color3.fromRGB(255, 100, 100),
	Mystery_Box_5 = Color3.fromRGB(255, 200, 50),

	-- Layer 6: Glitch
	GlitchBlock = Color3.fromRGB(0, 255, 100),
	Pixel = Color3.fromRGB(255, 0, 255),
	Bitcoin = Color3.fromRGB(255, 150, 0),
	Etherium = Color3.fromRGB(100, 100, 255),
	Mystery_Box_6 = Color3.fromRGB(255, 50, 200),

	-- Layer 7: Ohio
	OhioGrass = Color3.fromRGB(150, 0, 0),
	OhioDirt = Color3.fromRGB(100, 50, 50),
	Unobtainium = Color3.fromRGB(255, 255, 255),
	SkibidiOre = Color3.fromRGB(255, 0, 150),
	Mystery_Box_7 = Color3.fromRGB(255, 215, 0),
}

-- Map block types to materials
local BlockMaterials: {[string]: Enum.Material} = {
	-- Dirt types
	Grass = Enum.Material.Grass,
	Dirt = Enum.Material.Ground,
	OhioGrass = Enum.Material.Grass,
	OhioDirt = Enum.Material.Ground,

	-- Stone types
	Stone = Enum.Material.Slate,
	Gravel = Enum.Material.Pebble,
	Granite = Enum.Material.Granite,
	Diorite = Enum.Material.Limestone,
	Slate = Enum.Material.Basalt,
	Tuff = Enum.Material.Rock,
	Magma = Enum.Material.CrackedLava,
	Basalt = Enum.Material.Basalt,
	GlitchBlock = Enum.Material.Neon,
	Pixel = Enum.Material.Neon,

	-- Ores
	Coal = Enum.Material.Slate,
	Iron = Enum.Material.Metal,
	Gold = Enum.Material.Metal,
	Diamond = Enum.Material.Glass,
	Emerald = Enum.Material.Glass,
	Ruby = Enum.Material.Glass,
	Sapphire = Enum.Material.Glass,
	Amethyst = Enum.Material.Glass,
	Onyx = Enum.Material.Glass,
	Painite = Enum.Material.Glass,
	Bitcoin = Enum.Material.Neon,
	Etherium = Enum.Material.Neon,
	Unobtainium = Enum.Material.ForceField,
	SkibidiOre = Enum.Material.Neon,

	-- Mystery boxes
	Mystery_Box_1 = Enum.Material.SmoothPlastic,
	Mystery_Box_2 = Enum.Material.SmoothPlastic,
	Mystery_Box_3 = Enum.Material.SmoothPlastic,
	Mystery_Box_4 = Enum.Material.SmoothPlastic,
	Mystery_Box_5 = Enum.Material.SmoothPlastic,
	Mystery_Box_6 = Enum.Material.Neon,
	Mystery_Box_7 = Enum.Material.ForceField,
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Creates a seeded random generator for a player
]]
local function GetPlayerRandom(player: Player): Random
	if not RandomGenerators[player] then
		-- Use tick() + UserId for unique random per session
		RandomGenerators[player] = Random.new(tick() + player.UserId)
	end
	return RandomGenerators[player]
end

--[[
	Converts block layer index (0-based) to depth in studs
]]
local function BlockLayerToDepth(blockLayer: number): number
	return blockLayer * GameConfig.Mine.BlockSize
end

--[[
	Selects a block type based on weighted random selection from layer config
]]
local function SelectBlockForDepth(depth: number, rng: Random): (GameConfig.BlockData, GameConfig.LayerData)
	local layer = GameConfig.GetLayerByDepth(depth)

	-- Calculate total weight
	local totalWeight = 0
	for _, block in layer.Blocks do
		totalWeight += block.Chance
	end

	-- Roll random value
	local roll = rng:NextNumber() * totalWeight

	-- Select block based on roll
	local cumulative = 0
	for _, block in layer.Blocks do
		cumulative += block.Chance
		if roll <= cumulative then
			return block, layer
		end
	end

	-- Fallback to Basic block
	return layer.Blocks.Basic, layer
end

--[[
	Selects ONLY basic/alternate blocks (no ores, no brainrots)
	Used for tutorial layer
]]
local function SelectBasicBlockForDepth(depth: number, rng: Random): (GameConfig.BlockData, GameConfig.LayerData)
	local layer = GameConfig.GetLayerByDepth(depth)

	-- Only use Basic and Alternate blocks
	local basicBlocks = {layer.Blocks.Basic, layer.Blocks.Alternate}

	-- Calculate total weight of just these two
	local totalWeight = 0
	for _, block in basicBlocks do
		totalWeight += block.Chance
	end

	-- Roll random value
	local roll = rng:NextNumber() * totalWeight

	-- Select block based on roll
	local cumulative = 0
	for _, block in basicBlocks do
		cumulative += block.Chance
		if roll <= cumulative then
			return block, layer
		end
	end

	-- Fallback to Basic block
	return layer.Blocks.Basic, layer
end

--[[
	Gets the brainrot block data for tutorial layer
]]
local function GetTutorialBrainrotBlock(depth: number): (GameConfig.BlockData, GameConfig.LayerData)
	local layer = GameConfig.GetLayerByDepth(depth)
	return layer.Blocks.BrainrotBlock, layer
end

--[[
	Generates a random position near the center of the grid
]]
local function GetTutorialBrainrotPosition(rng: Random): (number, number)
	local config = GameConfig.Mine
	local centerX = math.floor(config.GridSizeX / 2)
	local centerZ = math.floor(config.GridSizeZ / 2)

	if TUTORIAL_CONFIG.PlaceNearCenter then
		local radius = TUTORIAL_CONFIG.CenterRadius
		local offsetX = rng:NextInteger(-radius, radius)
		local offsetZ = rng:NextInteger(-radius, radius)

		-- Clamp to grid bounds
		local gx = math.clamp(centerX + offsetX, 0, config.GridSizeX - 1)
		local gz = math.clamp(centerZ + offsetZ, 0, config.GridSizeZ - 1)

		return gx, gz
	else
		-- Completely random position
		return rng:NextInteger(0, config.GridSizeX - 1), rng:NextInteger(0, config.GridSizeZ - 1)
	end
end

--[[
	Creates a single block at the specified position
]]
local function CreateBlock(
	blockData: GameConfig.BlockData,
	layerData: GameConfig.LayerData,
	worldPosition: Vector3,
	gridX: number,
	gridY: number,
	gridZ: number,
	parentFolder: Folder,
	isTutorialBlock: boolean?
): BasePart?
	local blockSize = GameConfig.Mine.BlockSize

	-- Create the block
	local block = Instance.new("Part")
	block.Name = `Block_{blockData.Id}_{gridX}_{gridY}_{gridZ}`
	block.Size = Vector3.new(blockSize, blockSize, blockSize)
	block.Position = worldPosition
	block.Anchored = true
	block.CanCollide = true

	-- Apply appearance
	block.Color = BlockColors[blockData.Id] or Color3.fromRGB(128, 128, 128)
	block.Material = BlockMaterials[blockData.Id] or Enum.Material.Slate

	-- Store block data as attributes (for mining system)
	block:SetAttribute("BlockId", blockData.Id)
	block:SetAttribute("BlockName", blockData.Name)
	block:SetAttribute("BlockType", blockData.Type)
	block:SetAttribute("Value", blockData.Value)
	block:SetAttribute("Health", layerData.BaseHealth)
	block:SetAttribute("MaxHealth", layerData.BaseHealth)
	block:SetAttribute("LayerIndex", GameConfig.GetLayerIndexByDepth(BlockLayerToDepth(gridY)))
	block:SetAttribute("LayerName", layerData.LayerName)
	block:SetAttribute("GridX", gridX)
	block:SetAttribute("GridY", gridY)
	block:SetAttribute("GridZ", gridZ)

	-- Store texture references (for client-side application)
	block:SetAttribute("TextureFace", blockData.TextureFace)
	if blockData.TextureOverlay then
		block:SetAttribute("TextureOverlay", blockData.TextureOverlay)
	end

	-- Mark tutorial blocks
	if isTutorialBlock then
		block:SetAttribute("IsTutorialBlock", true)
		CollectionService:AddTag(block, "TutorialBlock")
	end

	-- Tag based on block type
	if blockData.Type == "Brainrot" then
		CollectionService:AddTag(block, "BrainrotBlock")

		-- For tutorial brainrot, optionally force a specific rarity outcome
		local dropRatesJson = {}
		if isTutorialBlock and TUTORIAL_CONFIG.ForcedRarity then
			-- 100% chance for the forced rarity
			dropRatesJson[TUTORIAL_CONFIG.ForcedRarity] = 100
		else
			-- Normal drop rates from layer
			for rarity, chance in layerData.BrainrotDropRates do
				dropRatesJson[rarity] = chance
			end
		end
		block:SetAttribute("BrainrotDropRates", game:GetService("HttpService"):JSONEncode(dropRatesJson))
	elseif blockData.Type == "Ore" then
		CollectionService:AddTag(block, "OreBlock")
	end

	-- All mineable blocks get the generic tag
	CollectionService:AddTag(block, "Mineable")

	block.Parent = parentFolder
	return block
end

--[[
	Generates the tutorial layer (block layer 0)
	- Only basic/alternate blocks
	- Exactly one brainrot block near center
]]
local function GenerateTutorialLayer(
	mineData: MineData,
	rng: Random
): {BasePart}
	local config = GameConfig.Mine
	local blockSize = config.BlockSize
	local origin = mineData.MineOrigin
	local blockLayerIndex = TUTORIAL_CONFIG.TutorialBlockLayer

	local layerBlocks: {BasePart} = {}

	-- Calculate Y position (negative, going down from origin)
	local yPos = origin.Y - (blockLayerIndex + 1) * blockSize + (blockSize / 2)

	-- Calculate depth for this layer
	local depth = BlockLayerToDepth(blockLayerIndex)

	-- Calculate starting corner (centered on origin X/Z)
	local halfGridX = (config.GridSizeX * blockSize) / 2
	local halfGridZ = (config.GridSizeZ * blockSize) / 2
	local startX = origin.X - halfGridX + (blockSize / 2)
	local startZ = origin.Z - halfGridZ + (blockSize / 2)

	-- Determine brainrot position(s)
	local brainrotPositions: {[string]: boolean} = {}
	for i = 1, TUTORIAL_CONFIG.BrainrotCount do
		local bx, bz = GetTutorialBrainrotPosition(rng)
		local key = `{bx}_{bz}`
		-- Avoid duplicates
		while brainrotPositions[key] do
			bx, bz = GetTutorialBrainrotPosition(rng)
			key = `{bx}_{bz}`
		end
		brainrotPositions[key] = true
	end

	print(`[MineGenerator] Tutorial layer: Brainrot at positions:`)
	for pos, _ in brainrotPositions do
		print(`[MineGenerator]   - Grid position: {pos}`)
	end

	-- Generate grid
	for gx = 0, config.GridSizeX - 1 do
		for gz = 0, config.GridSizeZ - 1 do
			local worldX = startX + (gx * blockSize)
			local worldZ = startZ + (gz * blockSize)
			local worldPos = Vector3.new(worldX, yPos, worldZ)

			local posKey = `{gx}_{gz}`
			local isBrainrotPosition = brainrotPositions[posKey] == true

			local blockData: GameConfig.BlockData
			local layerData: GameConfig.LayerData

			if isBrainrotPosition then
				-- Place the tutorial brainrot block
				blockData, layerData = GetTutorialBrainrotBlock(depth)
			else
				-- Place only basic blocks (no ores)
				blockData, layerData = SelectBasicBlockForDepth(depth, rng)
			end

			-- Create block
			local block = CreateBlock(
				blockData,
				layerData,
				worldPos,
				gx,
				blockLayerIndex,
				gz,
				mineData.MineFolder,
				isBrainrotPosition  -- Mark as tutorial block
			)

			if block then
				table.insert(layerBlocks, block)
				table.insert(mineData.Blocks, block)

				-- Store reference to tutorial brainrot
				if isBrainrotPosition then
					mineData.TutorialBrainrotBlock = block
				end
			end
		end
	end

	print(`[MineGenerator] Tutorial layer generated: {#layerBlocks} blocks (1 brainrot, rest basic)`)

	return layerBlocks
end

--[[
	Generates a single layer of blocks at the specified block layer index
	(Normal generation - used for all layers except tutorial)
]]
local function GenerateBlockLayer(
	mineData: MineData,
	blockLayerIndex: number,
	rng: Random
): {BasePart}
	local config = GameConfig.Mine
	local blockSize = config.BlockSize
	local origin = mineData.MineOrigin

	local layerBlocks: {BasePart} = {}

	-- Calculate Y position (negative, going down from origin)
	-- Block layer 0 starts just below origin
	local yPos = origin.Y - (blockLayerIndex + 1) * blockSize + (blockSize / 2)

	-- Calculate depth for this layer (used for block selection)
	local depth = BlockLayerToDepth(blockLayerIndex)

	-- Calculate starting corner (centered on origin X/Z)
	local halfGridX = (config.GridSizeX * blockSize) / 2
	local halfGridZ = (config.GridSizeZ * blockSize) / 2
	local startX = origin.X - halfGridX + (blockSize / 2)
	local startZ = origin.Z - halfGridZ + (blockSize / 2)

	-- Generate grid
	for gx = 0, config.GridSizeX - 1 do
		for gz = 0, config.GridSizeZ - 1 do
			local worldX = startX + (gx * blockSize)
			local worldZ = startZ + (gz * blockSize)
			local worldPos = Vector3.new(worldX, yPos, worldZ)

			-- Select block type based on depth
			local blockData, layerData = SelectBlockForDepth(depth, rng)

			-- Create block
			local block = CreateBlock(
				blockData,
				layerData,
				worldPos,
				gx,
				blockLayerIndex,
				gz,
				mineData.MineFolder,
				false  -- Not a tutorial block
			)

			if block then
				table.insert(layerBlocks, block)
				table.insert(mineData.Blocks, block)
			end
		end
	end

	return layerBlocks
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	Initializes a mine for a player using their plot's MineOrigin
	Called by PlotManager after plot assignment
]]
function MineGenerator.InitializeMine(player: Player, mineOrigin: Vector3, plotModel: Model): MineData?
	if PlayerMineData[player] then
		warn(`[MineGenerator] Mine already exists for {player.Name}`)
		return PlayerMineData[player]
	end

	-- Create mine folder inside plot model
	local mineFolder = Instance.new("Folder")
	mineFolder.Name = "Mine"
	mineFolder.Parent = plotModel

	-- Initialize mine data
	local mineData: MineData = {
		DeepestBlockLayer = -1,
		Blocks = {},
		MineOrigin = mineOrigin,
		MineFolder = mineFolder,
		TutorialBrainrotBlock = nil,
	}

	PlayerMineData[player] = mineData

	-- Generate initial layers
	local rng = GetPlayerRandom(player)
	local initialLayers = GameConfig.Mine.InitialLayers

	print(`[MineGenerator] Generating {initialLayers} initial block layers for {player.Name}`)

	for blockLayer = 0, initialLayers - 1 do
		-- Use tutorial generation for first layer, normal for rest
		if blockLayer == TUTORIAL_CONFIG.TutorialBlockLayer then
			GenerateTutorialLayer(mineData, rng)
		else
			GenerateBlockLayer(mineData, blockLayer, rng)
		end

		mineData.DeepestBlockLayer = blockLayer

		-- Yield occasionally to prevent lag spikes
		if blockLayer % 3 == 0 then
			task.wait()
		end
	end

	local layerAtBottom = GameConfig.GetLayerByDepth(BlockLayerToDepth(initialLayers - 1))
	print(`[MineGenerator] Mine initialized for {player.Name}`)
	print(`[MineGenerator] - {#mineData.Blocks} blocks generated`)
	print(`[MineGenerator] - Deepest layer: "{layerAtBottom.LayerName}" at depth {BlockLayerToDepth(initialLayers - 1)}`)

	if mineData.TutorialBrainrotBlock then
		print(`[MineGenerator] - Tutorial brainrot placed at: {mineData.TutorialBrainrotBlock.Position}`)
	end

	return mineData
end

--[[
	Generates additional block layers when player mines deeper
]]
function MineGenerator.GenerateMoreLayers(player: Player, targetBlockLayer: number)
	local mineData = PlayerMineData[player]
	if not mineData then
		warn(`[MineGenerator] No mine data for {player.Name}`)
		return
	end

	local config = GameConfig.Mine
	local maxBlockLayers = math.floor(config.MaxDepth / config.BlockSize)
	local rng = GetPlayerRandom(player)

	-- Generate layers up to target (plus buffer)
	local generateTo = math.min(targetBlockLayer + config.GenerateAheadLayers, maxBlockLayers - 1)

	if generateTo <= mineData.DeepestBlockLayer then
		return -- Already generated
	end

	print(`[MineGenerator] Generating block layers {mineData.DeepestBlockLayer + 1} to {generateTo} for {player.Name}`)

	for blockLayer = mineData.DeepestBlockLayer + 1, generateTo do
		GenerateBlockLayer(mineData, blockLayer, rng)
		mineData.DeepestBlockLayer = blockLayer

		-- Yield to prevent lag
		if blockLayer % 2 == 0 then
			task.wait()
		end
	end

	local layerAtBottom = GameConfig.GetLayerByDepth(BlockLayerToDepth(generateTo))
	print(`[MineGenerator] Now at "{layerAtBottom.LayerName}" (depth {BlockLayerToDepth(generateTo)})`)
end

--[[
	Extracts block data before destruction (called when mined)
]]
function MineGenerator.GetBlockData(block: BasePart): MinedBlockData?
	if not block or not block:GetAttribute("BlockId") then
		return nil
	end

	local blockData: MinedBlockData = {
		BlockId = block:GetAttribute("BlockId"),
		BlockName = block:GetAttribute("BlockName"),
		BlockType = block:GetAttribute("BlockType"),
		Value = block:GetAttribute("Value"),
		Health = block:GetAttribute("Health"),
		MaxHealth = block:GetAttribute("MaxHealth"),
		LayerIndex = block:GetAttribute("LayerIndex"),
		LayerName = block:GetAttribute("LayerName"),
		GridX = block:GetAttribute("GridX"),
		GridY = block:GetAttribute("GridY"),
		GridZ = block:GetAttribute("GridZ"),
		IsTutorialBlock = block:GetAttribute("IsTutorialBlock") or false,
	}

	-- Parse brainrot drop rates if present
	local dropRatesJson = block:GetAttribute("BrainrotDropRates")
	if dropRatesJson then
		local success, decoded = pcall(function()
			return game:GetService("HttpService"):JSONDecode(dropRatesJson)
		end)
		if success then
			blockData.BrainrotDropRates = decoded
		end
	end

	return blockData
end

--[[
	Gets mine data for a player
]]
function MineGenerator.GetMineData(player: Player): MineData?
	return PlayerMineData[player]
end

--[[
	Gets the deepest block layer generated
]]
function MineGenerator.GetDeepestBlockLayer(player: Player): number
	local mineData = PlayerMineData[player]
	return mineData and mineData.DeepestBlockLayer or 0
end

--[[
	Gets the tutorial brainrot block reference (for tutorial system)
]]
function MineGenerator.GetTutorialBrainrotBlock(player: Player): BasePart?
	local mineData = PlayerMineData[player]
	return mineData and mineData.TutorialBrainrotBlock
end

--[[
	Checks if a block is the tutorial brainrot
]]
function MineGenerator.IsTutorialBlock(block: BasePart): boolean
	return block:GetAttribute("IsTutorialBlock") == true
end

--[[
	Cleans up mine when player leaves
]]
function MineGenerator.CleanupMine(player: Player)
	local mineData = PlayerMineData[player]
	if mineData then
		if mineData.MineFolder then
			mineData.MineFolder:Destroy()
		end
		PlayerMineData[player] = nil
		RandomGenerators[player] = nil
		print(`[MineGenerator] Cleaned up mine for {player.Name}`)
	end
end

--[[
	Calculates which block layer a Y position corresponds to
]]
function MineGenerator.GetBlockLayerFromYPosition(player: Player, yPosition: number): number?
	local mineData = PlayerMineData[player]
	if not mineData then
		return nil
	end

	local blockSize = GameConfig.Mine.BlockSize
	local origin = mineData.MineOrigin

	-- Calculate block layer (0 = first layer below origin)
	local relativeY = origin.Y - yPosition
	local blockLayer = math.floor(relativeY / blockSize)

	return math.max(0, blockLayer)
end

--[[
	Gets the current GameConfig layer based on player's Y position
]]
function MineGenerator.GetCurrentLayer(player: Player, yPosition: number): GameConfig.LayerData?
	local blockLayer = MineGenerator.GetBlockLayerFromYPosition(player, yPosition)
	if not blockLayer then
		return nil
	end

	local depth = BlockLayerToDepth(blockLayer)
	return GameConfig.GetLayerByDepth(depth)
end

--[[
	Checks if more layers need generation based on player position
]]
function MineGenerator.CheckGenerationNeeded(player: Player, playerYPosition: number): boolean
	local mineData = PlayerMineData[player]
	if not mineData then
		return false
	end

	local currentBlockLayer = MineGenerator.GetBlockLayerFromYPosition(player, playerYPosition)
	if not currentBlockLayer then
		return false
	end

	local buffer = GameConfig.Mine.GenerateAheadLayers

	if currentBlockLayer + buffer >= mineData.DeepestBlockLayer then
		MineGenerator.GenerateMoreLayers(player, currentBlockLayer + buffer)
		return true
	end

	return false
end

--[[
	Rolls for a brainrot drop from a mystery box
	Returns the BrainrotUnit if successful, nil if no drop
]]
function MineGenerator.RollBrainrotDrop(dropRates: {[GameConfig.Rarity]: number}, rng: Random?): GameConfig.BrainrotUnit?
	rng = rng or Random.new()

	-- Roll for rarity (0-100)
	local roll = rng:NextNumber() * 100

	local cumulative = 0
	local selectedRarity: GameConfig.Rarity? = nil

	for rarity, chance in dropRates do
		cumulative += chance
		if roll <= cumulative then
			selectedRarity = rarity :: GameConfig.Rarity
			break
		end
	end

	if not selectedRarity then
		return nil
	end

	-- Get all brainrots of this rarity
	local brainrotsOfRarity = GameConfig.GetBrainrotsByRarity(selectedRarity)
	if #brainrotsOfRarity == 0 then
		return nil
	end

	-- Pick random brainrot of this rarity
	local index = rng:NextInteger(1, #brainrotsOfRarity)
	return brainrotsOfRarity[index]
end

return MineGenerator
