--!strict
--[[
	MegaBrainrotConfig.lua
	Configuration for the Mega Brainrot system

	ADD THIS TO YOUR EXISTING GameConfig.lua IN ROBLOX STUDIO:
	GameConfig.MegaBrainrot = require(script.Parent.MegaBrainrotConfig)

	OR copy these values directly into your GameConfig
]]

local MegaBrainrotConfig = {}

--------------------------------------------------------------------------------
-- TIMING CONFIGURATION
--------------------------------------------------------------------------------

MegaBrainrotConfig.SpawnInterval = 15 * 60 -- 15 minutes in seconds (global timer)
MegaBrainrotConfig.DespawnTime = 3 * 60    -- 3 minutes in seconds (despawn timer)

--------------------------------------------------------------------------------
-- SPAWN CONFIGURATION
--------------------------------------------------------------------------------

-- Which layers the Mega Brainrot can spawn in (4-7)
MegaBrainrotConfig.SpawnLayers = {4, 5, 6, 7}

-- DataStore key for global timer persistence
MegaBrainrotConfig.DataStoreKey = "MegaBrainrot_GlobalTimer_V1"

--------------------------------------------------------------------------------
-- BLOCK DEFINITION
--------------------------------------------------------------------------------

MegaBrainrotConfig.Block = {
	Id = "MegaBrainrot",
	Name = "Mega Brainrot",
	Type = "Brainrot",
	Value = 0,  -- Value comes from egg, not block
	Chance = 0, -- Never spawns naturally, only via timer

	-- Visual properties
	Color = Color3.fromRGB(255, 0, 255),  -- Bright magenta
	Material = Enum.Material.Neon,

	-- Texture (set your asset ID)
	TextureFace = "rbxassetid://0",  -- REPLACE with your MegaBrainrot texture
	TextureOverlay = nil,
}

--------------------------------------------------------------------------------
-- REWARD CONFIGURATION
--------------------------------------------------------------------------------

-- Guaranteed minimum rarity (Godly or higher)
MegaBrainrotConfig.MinimumRarity = "Godly"

-- Higher variant chances (compared to normal ~1% Void, ~5% Gold)
MegaBrainrotConfig.VariantChances = {
	Void = 10,   -- 10% chance for Void variant
	Gold = 25,   -- 25% chance for Gold variant
	Normal = 65, -- 65% chance for Normal variant
}

-- Rarity weights for Godly+ only
MegaBrainrotConfig.RarityWeights = {
	Godly = 100, -- 100% chance since it's guaranteed Godly minimum
}

--------------------------------------------------------------------------------
-- HIGHLIGHT CONFIGURATION
--------------------------------------------------------------------------------

MegaBrainrotConfig.Highlight = {
	DetectionRange = 20,  -- Blocks away to start highlighting (20 * BlockSize in studs)

	-- Rainbow colors for cycling
	Colors = {
		Color3.fromRGB(255, 0, 0),    -- Red
		Color3.fromRGB(255, 127, 0),  -- Orange
		Color3.fromRGB(255, 255, 0),  -- Yellow
		Color3.fromRGB(0, 255, 0),    -- Green
		Color3.fromRGB(0, 0, 255),    -- Blue
		Color3.fromRGB(75, 0, 130),   -- Indigo
		Color3.fromRGB(148, 0, 211),  -- Violet
	},

	-- How fast the colors cycle (seconds per full cycle)
	CycleSpeed = 2,

	-- Outline thickness
	OutlineTransparency = 0,
	FillTransparency = 0.5,
}

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

MegaBrainrotConfig.UI = {
	-- Timer display format
	TimerFormat = "%02d:%02d", -- MM:SS

	-- Popup duration when mined
	MiningPopupDuration = 5,

	-- Animation durations
	FadeInTime = 0.3,
	FadeOutTime = 0.5,
}

return MegaBrainrotConfig
