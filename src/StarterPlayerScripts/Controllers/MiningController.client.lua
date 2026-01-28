--!strict
-- SERVICE: MiningController
-- DESCRIPTION: Client-side mining interaction, visuals, Ore Discovery, and Brainrot Egg Popouts.
-- CONTEXT: Brainrot Mining Simulator V4
--
-- FIXED VERSION:
-- - SelectionHighlight is recreated on character respawn
-- - Added CharacterAdded listener to reinitialize visual components

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- MODULES
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))
local PlotController = require(script.Parent:WaitForChild("PlotController"))
local InventoryFullNotification = require(script.Parent:WaitForChild("InventoryFullNotification"))

-- ASSETS
local ASSETS_FOLDER = ReplicatedStorage:WaitForChild("Assets")
local EGGS_FOLDER = ASSETS_FOLDER:FindFirstChild("Eggs")

local MiningController = {}

--------------------------------------------------------------------------------
-- CONFIGURATION & COLORS
--------------------------------------------------------------------------------

local MAX_MINING_DISTANCE = GameConfig.Mining.MaxDistance or 15
local BLOCK_SIZE = GameConfig.Mine.BlockSize

local RARITY_COLORS = {
	[GameConfig.RARITIES.Common] = Color3.fromRGB(200, 200, 200),
	[GameConfig.RARITIES.Uncommon] = Color3.fromRGB(50, 255, 50),
	[GameConfig.RARITIES.Rare] = Color3.fromRGB(50, 150, 255),
	[GameConfig.RARITIES.Epic] = Color3.fromRGB(200, 50, 255),
	[GameConfig.RARITIES.Legendary] = Color3.fromRGB(255, 150, 0),
	[GameConfig.RARITIES.Mythic] = Color3.fromRGB(255, 50, 50),
	[GameConfig.RARITIES.Godly] = Color3.fromRGB(255, 255, 50),
}

--------------------------------------------------------------------------------
-- ORE DISCOVERY STATE
--------------------------------------------------------------------------------

local DiscoveredOres: {[string]: boolean} = {}
local OreDiscoveryCallbacks: {(string) -> ()} = {}

--------------------------------------------------------------------------------
-- TOOLTIP CUSTOMIZATION CONFIG
--------------------------------------------------------------------------------

local TOOLTIP_CONFIG = {
	BackgroundColor = Color3.fromRGB(15, 18, 28),
	BackgroundTransparency = 0.1,
	CornerRadius = UDim.new(0, 12),
	BorderColor = Color3.fromRGB(60, 70, 100),
	BorderThickness = 2,
	BorderTransparency = 0.3,
	Width = 200,
	Height = 75,
	OffsetX = 25,
	OffsetY = 25,
	ShadowEnabled = true,
	ShadowColor = Color3.new(0, 0, 0),
	ShadowTransparency = 0.4,
}

-- UNDISCOVERED ORE THEME
local UNDISCOVERED_THEME = {
	NameGradient = {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 120, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 80, 80)),
	},
	NameColor = Color3.fromRGB(120, 120, 120),
	HealthColor = Color3.fromRGB(100, 100, 100),
	Animation = "none",
	BorderGlow = Color3.fromRGB(60, 60, 60),
}

local BLOCK_THEMES = {
	["DIRT"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 90, 43)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 130, 70)), ColorSequenceKeypoint.new(1, Color3.fromRGB(139, 90, 43))},
		NameColor = Color3.fromRGB(180, 130, 70), HealthColor = Color3.fromRGB(120, 80, 40), Animation = "gentle", BorderGlow = Color3.fromRGB(100, 70, 30),
	},
	["GRASS"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 139, 34)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(124, 252, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 139, 34))},
		NameColor = Color3.fromRGB(124, 252, 0), HealthColor = Color3.fromRGB(50, 180, 50), Animation = "gentle", BorderGlow = Color3.fromRGB(50, 200, 50),
	},
	["STONE"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(105, 105, 105)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(169, 169, 169)), ColorSequenceKeypoint.new(1, Color3.fromRGB(105, 105, 105))},
		NameColor = Color3.fromRGB(169, 169, 169), HealthColor = Color3.fromRGB(130, 130, 130), Animation = "none", BorderGlow = Color3.fromRGB(100, 100, 110),
	},
	["GRAVEL"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 85, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(140, 135, 130)), ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 85, 80))},
		NameColor = Color3.fromRGB(140, 135, 130), HealthColor = Color3.fromRGB(110, 105, 100), Animation = "shake", BorderGlow = Color3.fromRGB(80, 75, 70),
	},
	["GRANITE"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 100, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 150, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 100, 80))},
		NameColor = Color3.fromRGB(200, 150, 120), HealthColor = Color3.fromRGB(170, 120, 90), Animation = "gentle", BorderGlow = Color3.fromRGB(180, 130, 100),
	},
	["SLATE"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(47, 79, 79)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 120, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(47, 79, 79))},
		NameColor = Color3.fromRGB(80, 120, 120), HealthColor = Color3.fromRGB(60, 100, 100), Animation = "gentle", BorderGlow = Color3.fromRGB(50, 90, 90),
	},
	["MAGMA"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 69, 0)), ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 140, 0)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 215, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 69, 0))},
		NameColor = Color3.fromRGB(255, 140, 0), HealthColor = Color3.fromRGB(255, 100, 50), Animation = "pulse", BorderGlow = Color3.fromRGB(255, 80, 0),
	},
	["BASALT"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 35)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 70, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 35))},
		NameColor = Color3.fromRGB(90, 90, 100), HealthColor = Color3.fromRGB(60, 60, 70), Animation = "none", BorderGlow = Color3.fromRGB(50, 50, 60),
	},
	["GLITCHBLOCK"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 255)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 0, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 255, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 255))},
		NameColor = Color3.fromRGB(0, 255, 255), HealthColor = Color3.fromRGB(255, 0, 255), Animation = "glitch", BorderGlow = Color3.fromRGB(0, 255, 200),
	},
	["PIXEL"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 128)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(128, 0, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 128))},
		NameColor = Color3.fromRGB(255, 0, 128), HealthColor = Color3.fromRGB(180, 0, 200), Animation = "glitch", BorderGlow = Color3.fromRGB(200, 0, 150),
	},
	["OHIOGRASS"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 0, 0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(139, 0, 0))},
		NameColor = Color3.fromRGB(255, 50, 50), HealthColor = Color3.fromRGB(200, 30, 30), Animation = "pulse", BorderGlow = Color3.fromRGB(255, 0, 0),
	},
	["COAL"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 20)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 60, 60)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))},
		NameColor = Color3.fromRGB(80, 80, 80), HealthColor = Color3.fromRGB(50, 50, 50), Animation = "gentle", BorderGlow = Color3.fromRGB(40, 40, 40),
	},
	["IRON"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 140, 130)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(210, 200, 190)), ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 140, 130))},
		NameColor = Color3.fromRGB(210, 200, 190), HealthColor = Color3.fromRGB(180, 170, 160), Animation = "gentle", BorderGlow = Color3.fromRGB(190, 180, 170),
	},
	["GOLD"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 223, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 0))},
		NameColor = Color3.fromRGB(255, 215, 0), HealthColor = Color3.fromRGB(218, 165, 32), Animation = "wave", BorderGlow = Color3.fromRGB(255, 200, 0),
	},
	["DIAMOND"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 191, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(185, 242, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 191, 255))},
		NameColor = Color3.fromRGB(185, 242, 255), HealthColor = Color3.fromRGB(0, 200, 255), Animation = "wave", BorderGlow = Color3.fromRGB(100, 220, 255),
	},
	["EMERALD"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 128, 0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 128, 0))},
		NameColor = Color3.fromRGB(80, 255, 80), HealthColor = Color3.fromRGB(50, 205, 50), Animation = "wave", BorderGlow = Color3.fromRGB(0, 255, 100),
	},
	["RUBY"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 0, 0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 50, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(139, 0, 0))},
		NameColor = Color3.fromRGB(255, 50, 80), HealthColor = Color3.fromRGB(220, 20, 60), Animation = "pulse", BorderGlow = Color3.fromRGB(255, 0, 50),
	},
	["SAPPHIRE"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 82, 186)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 149, 237)), ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 82, 186))},
		NameColor = Color3.fromRGB(100, 149, 237), HealthColor = Color3.fromRGB(65, 105, 225), Animation = "wave", BorderGlow = Color3.fromRGB(50, 120, 220),
	},
	["AMETHYST"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(128, 0, 128)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 100, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 0, 128))},
		NameColor = Color3.fromRGB(200, 100, 255), HealthColor = Color3.fromRGB(153, 50, 204), Animation = "pulse", BorderGlow = Color3.fromRGB(180, 80, 255),
	},
	["ONYX"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)), ColorSequenceKeypoint.new(0.3, Color3.fromRGB(50, 50, 60)), ColorSequenceKeypoint.new(0.7, Color3.fromRGB(20, 20, 30)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))},
		NameColor = Color3.fromRGB(80, 80, 100), HealthColor = Color3.fromRGB(40, 40, 50), Animation = "pulse", BorderGlow = Color3.fromRGB(60, 60, 80),
	},
	["PAINITE"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 100)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 200)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 100))},
		NameColor = Color3.fromRGB(255, 150, 200), HealthColor = Color3.fromRGB(255, 100, 150), Animation = "rainbow", BorderGlow = Color3.fromRGB(255, 50, 150),
	},
	["BITCOIN"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(242, 169, 0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(242, 169, 0))},
		NameColor = Color3.fromRGB(255, 200, 50), HealthColor = Color3.fromRGB(242, 169, 0), Animation = "pulse", BorderGlow = Color3.fromRGB(255, 180, 0),
	},
	["ETHERIUM"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(98, 126, 234)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 180, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(98, 126, 234))},
		NameColor = Color3.fromRGB(150, 180, 255), HealthColor = Color3.fromRGB(98, 126, 234), Animation = "wave", BorderGlow = Color3.fromRGB(120, 150, 255),
	},
	["UNOBTAINIUM"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 255)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(0, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))},
		NameColor = Color3.fromRGB(255, 255, 255), HealthColor = Color3.fromRGB(200, 200, 255), Animation = "rainbow", BorderGlow = Color3.fromRGB(255, 200, 255),
	},
	["SKIBIDIORE"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 127, 0)), ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 0)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(0.8, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(139, 0, 255))},
		NameColor = Color3.fromRGB(255, 255, 255), HealthColor = Color3.fromRGB(255, 200, 100), Animation = "rainbow", BorderGlow = Color3.fromRGB(255, 255, 255),
	},
	["MYSTERY_BOX"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(148, 0, 211)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(148, 0, 211))},
		NameColor = Color3.fromRGB(255, 100, 255), HealthColor = Color3.fromRGB(200, 50, 200), Animation = "pulse", BorderGlow = Color3.fromRGB(200, 0, 255),
	},
	["DEFAULT"] = {
		NameGradient = {ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 180, 180)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 180))},
		NameColor = Color3.fromRGB(255, 255, 255), HealthColor = Color3.fromRGB(200, 200, 200), Animation = "none", BorderGlow = Color3.fromRGB(150, 150, 150),
	},
}

local HEALTH_COLORS = {
	High = Color3.fromRGB(100, 255, 100),
	Medium = Color3.fromRGB(255, 255, 100),
	Low = Color3.fromRGB(255, 80, 80),
	Critical = Color3.fromRGB(255, 0, 0),
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local IsInitialized = false
local IsMining = false
local IsInventoryFull = false
local CurrentTarget: BasePart? = nil
local SelectionHighlight: Highlight? = nil
local MiningJob: thread? = nil
local CurrentDepth: number = 0
local DepthListeners: { (number) -> () } = {}

local TooltipGui: ScreenGui? = nil
local TooltipFrame: Frame? = nil
local NameLabel: TextLabel? = nil
local NameGradient: UIGradient? = nil
local HealthLabel: TextLabel? = nil
local HealthBar: Frame? = nil
local HealthBarFill: Frame? = nil
local TooltipStroke: UIStroke? = nil
local ValueLabel: TextLabel? = nil

local CurrentAnimationType: string = "none"
local AnimationConnection: RBXScriptConnection? = nil
local AnimationStartTime: number = 0
local DepthLabel: TextLabel? = nil

local Remotes: {[string]: RemoteEvent} = {}

-- ✅ NEW: Track hover connection for cleanup
local HoverTrackingConnection: RBXScriptConnection? = nil

--------------------------------------------------------------------------------
-- ORE DISCOVERY HELPERS
--------------------------------------------------------------------------------

local function IsOreDiscovered(oreId: string): boolean
	if not oreId then return true end
	return DiscoveredOres[oreId] == true
end

local function MarkOreAsDiscovered(oreId: string)
	if not oreId then return end
	DiscoveredOres[oreId] = true
	print(`[MiningController] Ore marked as discovered: {oreId}`)
	for _, callback in ipairs(OreDiscoveryCallbacks) do
		task.spawn(callback, oreId)
	end
end

local function GetOreIdFromBlock(block: BasePart): string?
	if not block then return nil end
	return block:GetAttribute("BlockId") or block:GetAttribute("BlockName")
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function GetBlockTheme(blockName: string): typeof(BLOCK_THEMES["DEFAULT"])
	local upperName = string.upper(blockName or "")
	if BLOCK_THEMES[upperName] then return BLOCK_THEMES[upperName] end
	for key, theme in pairs(BLOCK_THEMES) do
		if string.find(upperName, key) then return theme end
	end
	if string.find(upperName, "MYSTERY") or string.find(upperName, "BOX") then
		return BLOCK_THEMES["MYSTERY_BOX"]
	end
	return BLOCK_THEMES["DEFAULT"]
end

local function GetHealthColor(healthPercent: number): Color3
	if healthPercent < 0.1 then return HEALTH_COLORS.Critical
	elseif healthPercent < 0.25 then return HEALTH_COLORS.Low
	elseif healthPercent < 0.5 then return HEALTH_COLORS.Medium
	else return HEALTH_COLORS.High end
end

--------------------------------------------------------------------------------
-- BRAINROT POPOUT VISUALS
--------------------------------------------------------------------------------

local function PlayBrainrotPopout(data)
	local position = data.Position
	local rarity = data.Rarity or GameConfig.RARITIES.Common
	local variant = data.Variant or "Normal"

	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS[GameConfig.RARITIES.Common]

	local eggName = `Egg_{rarity}`
	local modelTemplate = EGGS_FOLDER and EGGS_FOLDER:FindFirstChild(eggName)
	local visualModel = nil

	if modelTemplate then
		visualModel = modelTemplate:Clone()
	else
		local part = Instance.new("Part")
		part.Size = Vector3.new(2, 3, 2)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.SmoothPlastic
		part.Color = rarityColor
		visualModel = part
	end

	if not visualModel then return end

	if variant == "Gold" then
		if visualModel:IsA("BasePart") then 
			visualModel.Color = Color3.fromRGB(255, 215, 0)
			visualModel.Material = Enum.Material.Metal 
		end
		for _, v in visualModel:GetDescendants() do 
			if v:IsA("BasePart") then 
				v.Color = Color3.fromRGB(255, 215, 0)
				v.Material = Enum.Material.Metal 
			end 
		end
	elseif variant == "Void" then
		if visualModel:IsA("BasePart") then 
			visualModel.Color = Color3.fromRGB(50, 0, 100)
			visualModel.Material = Enum.Material.Neon 
		end
		for _, v in visualModel:GetDescendants() do 
			if v:IsA("BasePart") then 
				v.Color = Color3.fromRGB(50, 0, 100)
				v.Material = Enum.Material.Neon 
			end 
		end
	end

	if visualModel:IsA("Model") then
		visualModel:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0,360)), 0))
		if visualModel.ScaleTo then visualModel:ScaleTo(0.1) end
	else
		visualModel.CFrame = CFrame.new(position)
		visualModel.Size = Vector3.new(0.1, 0.1, 0.1)
	end
	

	visualModel.Parent = workspace
	Debris:AddItem(visualModel, 4)

	local attachment = Instance.new("Attachment")
	attachment.Parent = (visualModel:IsA("Model") and visualModel.PrimaryPart or visualModel)

	local burst = Instance.new("ParticleEmitter")
	burst.Parent = attachment
	burst.Texture = "rbxassetid://5021159599"
	burst.Color = ColorSequence.new(rarityColor)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, .2),
		NumberSequenceKeypoint.new(1, 0.000001)
	})
	burst.Acceleration = Vector3.new(0, -30, 0)
	burst.Lifetime = NumberRange.new(0.5, 1)
	burst.Speed = NumberRange.new(10, 20)
	burst.SpreadAngle = Vector2.new(360, 360)
	burst.Drag = 5
	burst:Emit(30)

	task.spawn(function()
		local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local targetCFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(180), 0)

		if visualModel:IsA("Model") then
			local startScale = 0.1
			local endScale = 0.5
			local startCFrame = visualModel:GetPivot()
			local startTime = tick()

			while (tick() - startTime) < 0.5 do
				local alpha = (tick() - startTime) / 0.5
				local scaleAlpha = TweenService:GetValue(alpha, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				if visualModel.ScaleTo then visualModel:ScaleTo(startScale + (endScale - startScale) * scaleAlpha) end
				visualModel:PivotTo(startCFrame:Lerp(targetCFrame, scaleAlpha))
				RunService.RenderStepped:Wait()
			end
			if visualModel.ScaleTo then visualModel:ScaleTo(endScale) end
			visualModel:PivotTo(targetCFrame)
		else
			local t1 = TweenService:Create(visualModel, tweenInfo, {
				CFrame = targetCFrame,
				Size = Vector3.new(3,3,3)
			})
			t1:Play()
			t1.Completed:Wait()
		end

		local spinStart = tick()
		while (tick() - spinStart) < 1.5 do
			if not visualModel or not visualModel.Parent then break end
			local angle = (tick() - spinStart) * 2
			local bob = math.sin((tick() - spinStart) * 3) * 0.5

			local currentPos = position + Vector3.new(0, 4 + bob, 0)
			local rot = CFrame.Angles(0, angle, 0)

			if visualModel:IsA("Model") then
				visualModel:PivotTo(CFrame.new(currentPos) * rot)
			else
				visualModel.CFrame = CFrame.new(currentPos) * rot
			end
			RunService.RenderStepped:Wait()
		end

		local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if visualModel:IsA("Model") then
			local startTime = tick()
			while (tick() - startTime) < 0.5 do
				local alpha = (tick() - startTime) / 0.5
				if visualModel.ScaleTo then visualModel:ScaleTo(1.0 - alpha) end
				RunService.RenderStepped:Wait()
			end
		else
			TweenService:Create(visualModel, fadeInfo, {Size = Vector3.new(0,0,0), Transparency = 1}):Play()
		end

		if visualModel then visualModel:Destroy() end
	end)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(4, 1)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Parent = (visualModel:IsA("Model") and visualModel.PrimaryPart or visualModel)

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1,1)
	txt.BackgroundTransparency = 1
	txt.Text = `{variant == "Normal" and "" or variant .. " "}{rarity} Egg!`
	txt.TextColor3 = rarityColor
	txt.TextStrokeTransparency = 0
	txt.Font = Enum.Font.FredokaOne
	txt.TextScaled = true
	txt.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1), {StudsOffset = Vector3.new(0, 5, 0)}):Play()
end

--------------------------------------------------------------------------------
-- TEXT ANIMATIONS
--------------------------------------------------------------------------------

local function StopAnimation()
	if AnimationConnection then AnimationConnection:Disconnect(); AnimationConnection = nil end
end

local function StartAnimation(animationType: string, nameLabel: TextLabel, gradient: UIGradient?, theme: typeof(BLOCK_THEMES["DEFAULT"]))
	StopAnimation()
	if animationType == "none" then
		if gradient then gradient.Rotation = 0; gradient.Offset = Vector2.new(0, 0) end
		nameLabel.Rotation = 0; nameLabel.Position = UDim2.new(0, 10, 0, 8)
		return
	end
	CurrentAnimationType = animationType
	AnimationStartTime = tick()
	AnimationConnection = RunService.RenderStepped:Connect(function()
		if not nameLabel or not nameLabel.Parent then StopAnimation(); return end
		local elapsed = tick() - AnimationStartTime
		if animationType == "gentle" then
			if gradient then gradient.Offset = Vector2.new(math.sin(elapsed * 1.5) * 0.2, 0); gradient.Rotation = math.sin(elapsed) * 10 end
		elseif animationType == "pulse" then
			local pulse = (math.sin(elapsed * 4) + 1) / 2
			nameLabel.TextSize = 24 + pulse * 4
			if gradient then gradient.Offset = Vector2.new(math.sin(elapsed * 3) * 0.3, 0) end
		elseif animationType == "shake" then
			nameLabel.Position = UDim2.new(0, 10 + math.sin(elapsed * 20) * 1.5, 0, 8 + math.cos(elapsed * 25) * 1)
		elseif animationType == "rainbow" then
			if gradient then gradient.Rotation = (elapsed * 180) % 360; gradient.Offset = Vector2.new(math.sin(elapsed * 2) * 0.5, 0) end
			nameLabel.TextSize = 24 + (math.sin(elapsed * 3) + 1) / 2 * 3
		elseif animationType == "glitch" then
			if math.random() < 0.1 then
				nameLabel.Position = UDim2.new(0, 10 + math.random(-5, 5), 0, 8 + math.random(-3, 3))
				if gradient then gradient.Offset = Vector2.new(math.random() * 0.6 - 0.3, 0) end
			end
			if math.random() < 0.05 and gradient then gradient.Rotation = math.random(0, 360) end
		elseif animationType == "wave" then
			if gradient then gradient.Offset = Vector2.new(math.sin(elapsed * 2) * 0.4, 0); gradient.Rotation = math.sin(elapsed * 1.5) * 20 end
			nameLabel.Position = UDim2.new(0, 10, 0, 8 + math.sin(elapsed * 2.5) * 2)
		end
	end)
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function FindManualUI()
	local pg = LocalPlayer:WaitForChild("PlayerGui")
	local dGui = pg:FindFirstChild("DepthGui")
	if dGui then DepthLabel = dGui:FindFirstChild("DepthText", true) :: TextLabel? end
end

local function UpdateDepthMeter(depth: number)
	if not DepthLabel then DepthLabel = FindManualUI() and DepthLabel end
	if DepthLabel then
		DepthLabel.Text = `{depth}M`
		if depth % 10 == 0 then
			local t = TweenService:Create(DepthLabel, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {TextSize = 38, Rotation = math.random(-5, 5)})
			t:Play()
			t.Completed:Connect(function() TweenService:Create(DepthLabel, TweenInfo.new(0.2), {TextSize = 32, Rotation = 0}):Play() end)
		end
	end
end

local function CreateTooltipUI()
	-- Clean up existing tooltip if any
	if TooltipGui then
		TooltipGui:Destroy()
		TooltipGui = nil
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiningTooltip"; gui.ResetOnSpawn = false; gui.Enabled = false; gui.DisplayOrder = 10; gui.IgnoreGuiInset = true; gui.Parent = playerGui

	local shadowFrame = Instance.new("Frame")
	shadowFrame.Name = "ShadowFrame"; shadowFrame.Size = UDim2.fromOffset(TOOLTIP_CONFIG.Width + 8, TOOLTIP_CONFIG.Height + 8)
	shadowFrame.AnchorPoint = Vector2.new(0, 0); shadowFrame.BackgroundColor3 = TOOLTIP_CONFIG.ShadowColor
	shadowFrame.BackgroundTransparency = TOOLTIP_CONFIG.ShadowTransparency; shadowFrame.BorderSizePixel = 0; shadowFrame.Parent = gui
	Instance.new("UICorner", shadowFrame).CornerRadius = TOOLTIP_CONFIG.CornerRadius

	local frame = Instance.new("Frame")
	frame.Name = "Container"; frame.Size = UDim2.fromOffset(TOOLTIP_CONFIG.Width, TOOLTIP_CONFIG.Height)
	frame.Position = UDim2.fromOffset(-4, -4); frame.BackgroundColor3 = TOOLTIP_CONFIG.BackgroundColor
	frame.BackgroundTransparency = TOOLTIP_CONFIG.BackgroundTransparency; frame.BorderSizePixel = 0; frame.Parent = shadowFrame
	Instance.new("UICorner", frame).CornerRadius = TOOLTIP_CONFIG.CornerRadius

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BorderStroke"; stroke.Color = TOOLTIP_CONFIG.BorderColor; stroke.Thickness = TOOLTIP_CONFIG.BorderThickness
	stroke.Transparency = TOOLTIP_CONFIG.BorderTransparency; stroke.Parent = frame
	TooltipStroke = stroke

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "BlockName"; nameLbl.Size = UDim2.new(1, -20, 0, 28); nameLbl.Position = UDim2.new(0, 10, 0, 8)
	nameLbl.BackgroundTransparency = 1; nameLbl.Text = "BLOCK NAME"; nameLbl.Font = Enum.Font.GothamBlack; nameLbl.TextSize = 24
	nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255); nameLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); nameLbl.TextStrokeTransparency = 0
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.ZIndex = 2; nameLbl.Parent = frame

	local gradient = Instance.new("UIGradient"); gradient.Name = "NameGradient"; gradient.Rotation = 0; gradient.Parent = nameLbl

	local hpLbl = Instance.new("TextLabel")
	hpLbl.Name = "Health"; hpLbl.Size = UDim2.new(0.5, -15, 0, 18); hpLbl.Position = UDim2.new(0, 10, 0, 38)
	hpLbl.BackgroundTransparency = 1; hpLbl.Text = "100 / 100 HP"; hpLbl.Font = Enum.Font.GothamBold; hpLbl.TextSize = 14
	hpLbl.TextColor3 = Color3.fromRGB(200, 200, 200); hpLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); hpLbl.TextStrokeTransparency = 0.5
	hpLbl.TextXAlignment = Enum.TextXAlignment.Left; hpLbl.ZIndex = 2; hpLbl.Parent = frame

	local valLbl = Instance.new("TextLabel")
	valLbl.Name = "Value"; valLbl.Size = UDim2.new(0.5, -15, 0, 18); valLbl.Position = UDim2.new(0.5, 5, 0, 38)
	valLbl.BackgroundTransparency = 1; valLbl.Text = "$10"; valLbl.Font = Enum.Font.GothamBold; valLbl.TextSize = 14
	valLbl.TextColor3 = Color3.fromRGB(100, 255, 100); valLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); valLbl.TextStrokeTransparency = 0.5
	valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.ZIndex = 2; valLbl.Parent = frame

	local hpBarBg = Instance.new("Frame")
	hpBarBg.Name = "HealthBarBg"; hpBarBg.Size = UDim2.new(1, -20, 0, 8); hpBarBg.Position = UDim2.new(0, 10, 0, 58)
	hpBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40); hpBarBg.BorderSizePixel = 0; hpBarBg.ZIndex = 2; hpBarBg.Parent = frame
	Instance.new("UICorner", hpBarBg).CornerRadius = UDim.new(0, 4)

	local hpBarFill = Instance.new("Frame")
	hpBarFill.Name = "Fill"; hpBarFill.Size = UDim2.new(1, 0, 1, 0); hpBarFill.Position = UDim2.new(0, 0, 0, 0)
	hpBarFill.BackgroundColor3 = HEALTH_COLORS.High; hpBarFill.BorderSizePixel = 0; hpBarFill.ZIndex = 3; hpBarFill.Parent = hpBarBg
	Instance.new("UICorner", hpBarFill).CornerRadius = UDim.new(0, 4)

	TooltipGui = gui; TooltipFrame = shadowFrame; NameLabel = nameLbl; NameGradient = gradient
	HealthLabel = hpLbl; HealthBar = hpBarBg; HealthBarFill = hpBarFill; ValueLabel = valLbl
end

local function UpdateTooltip(target: BasePart?)
	if not TooltipGui or not TooltipFrame or not NameLabel or not HealthLabel then return end
	if not target then TooltipGui.Enabled = false; StopAnimation(); return end

	local name = target:GetAttribute("BlockName") or "Unknown"
	local oreId = GetOreIdFromBlock(target)
	local currentHp = target:GetAttribute("Health")
	local maxHp = target:GetAttribute("MaxHealth")
	local value = target:GetAttribute("Value") or 0

	if not maxHp then maxHp = 100 end
	if not currentHp then currentHp = maxHp end
	local healthPercent = currentHp / maxHp

	local isDiscovered = IsOreDiscovered(oreId)
	local theme

	if isDiscovered then
		NameLabel.Text = string.upper(name)
		theme = GetBlockTheme(name)
		if NameGradient then NameGradient.Color = ColorSequence.new(theme.NameGradient) end
		HealthLabel.Text = string.format("%d / %d HP", math.max(0, math.floor(currentHp)), math.floor(maxHp))
		HealthLabel.TextColor3 = GetHealthColor(healthPercent)
		if ValueLabel then
			ValueLabel.Text = "$" .. tostring(value)
			if value >= 1000 then ValueLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
			elseif value >= 100 then ValueLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
			else ValueLabel.TextColor3 = Color3.fromRGB(100, 255, 100) end
		end
	else
		NameLabel.Text = "???"
		theme = UNDISCOVERED_THEME
		if NameGradient then NameGradient.Color = ColorSequence.new(theme.NameGradient) end
		HealthLabel.Text = "??? / ??? HP"
		HealthLabel.TextColor3 = theme.HealthColor
		if ValueLabel then
			ValueLabel.Text = "$???"
			ValueLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
		end
	end

	if HealthBarFill then
		TweenService:Create(HealthBarFill, TweenInfo.new(0.15), {
			Size = UDim2.new(math.max(0, healthPercent), 0, 1, 0),
			BackgroundColor3 = GetHealthColor(healthPercent)
		}):Play()
	end

	if TooltipStroke then TooltipStroke.Color = theme.BorderGlow end
	StartAnimation(theme.Animation, NameLabel, NameGradient, theme)

	local mousePos = UserInputService:GetMouseLocation()
	TooltipFrame.Position = UDim2.fromOffset(mousePos.X + TOOLTIP_CONFIG.OffsetX, mousePos.Y + TOOLTIP_CONFIG.OffsetY)
	TooltipGui.Enabled = true
end

--------------------------------------------------------------------------------
-- SELECTION HIGHLIGHT
--------------------------------------------------------------------------------

-- ✅ FIX: Separate function to create highlight so it can be called on respawn
local function CreateSelectionHighlight(): Highlight
	-- Clean up existing highlight if any
	if SelectionHighlight then
		SelectionHighlight:Destroy()
		SelectionHighlight = nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "BlockSelection"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0
	highlight.Parent = LocalPlayer:WaitForChild("PlayerGui")

	SelectionHighlight = highlight
	return highlight
end

local function ShowHighlight(block: BasePart)
	-- ✅ FIX: Recreate highlight if it doesn't exist or was destroyed
	if not SelectionHighlight or not SelectionHighlight.Parent then
		CreateSelectionHighlight()
	end

	if SelectionHighlight then
		SelectionHighlight.Adornee = block
		SelectionHighlight.Enabled = true
		local oreId = GetOreIdFromBlock(block)
		if IsInventoryFull then
			SelectionHighlight.OutlineColor = Color3.fromRGB(255, 80, 80)
		elseif not IsOreDiscovered(oreId) then
			SelectionHighlight.OutlineColor = Color3.fromRGB(120, 120, 120)
		else
			local name = block:GetAttribute("BlockName") or "Unknown"
			local theme = GetBlockTheme(name)
			SelectionHighlight.OutlineColor = theme.BorderGlow
		end
	end
end

local function HideHighlight()
	if SelectionHighlight then 
		SelectionHighlight.Enabled = false
		SelectionHighlight.Adornee = nil 
	end
end

--------------------------------------------------------------------------------
-- BREAK EFFECTS
--------------------------------------------------------------------------------

local BREAK_STAGES = {
	[1] = "rbxassetid://74031517990240", [2] = "rbxassetid://80903762007022",
	[3] = "rbxassetid://86641233862224", [4] = "rbxassetid://118715472089654",
	[5] = "rbxassetid://83525812287811", [6] = "rbxassetid://128219346904336",
	[7] = "rbxassetid://135764506072789", [8] = "rbxassetid://116722357404874",
	[9] = "rbxassetid://89093230455846", [10] = "rbxassetid://135606870304528",
}

local function UpdateBreakVisuals(block: BasePart, stage: number)
	if not block or not block.Parent then return end
	if not stage or stage < 1 then
		for _, child in block:GetChildren() do if child.Name == "BreakOverlay" then child:Destroy() end end
		return
	end
	local textureId = BREAK_STAGES[stage]; if not textureId then return end
	if not block:FindFirstChild("BreakOverlay") then
		for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
			local tex = Instance.new("Texture"); tex.Name = "BreakOverlay"; tex.Face = face; tex.Parent = block
			tex.Transparency = 0; tex.StudsPerTileU = block.Size.X; tex.StudsPerTileV = block.Size.Y; tex.ZIndex = 2
		end
	end
	for _, child in block:GetChildren() do if child.Name == "BreakOverlay" then (child :: Texture).Texture = textureId end end
end

local function PlayHitWobble(block: BasePart, stage: number)
	if not block or not block.Parent then return end
	UpdateBreakVisuals(block, stage)
	local originalSize = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	local tweenInfo = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true)
	local goal = {Size = originalSize * 0.9, Orientation = block.Orientation + Vector3.new(math.random(-5,5), math.random(-5,5), math.random(-5,5))}
	TweenService:Create(block, tweenInfo, goal):Play()
end

local function PlayBreakEffect(position: Vector3, color: Color3)
	local attachment = Instance.new("Attachment"); 
	attachment.Position = position; 
	attachment.Parent = workspace.Terrain
	local emitter = Instance.new("ParticleEmitter"); 
	emitter.Texture = "rbxassetid://12623531687"
	emitter.Lifetime = NumberRange.new(0.5, 1); 
	emitter.Speed = NumberRange.new(10, 25)
	emitter.Size = NumberSequence.new(.2,.3);
	emitter.SpreadAngle = Vector2.new(360, 360);
	emitter.Drag = 2;
	emitter.Acceleration = Vector3.new(0, -30, 0);
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color); 
	emitter.Parent = attachment; 
	emitter:Emit(30)
	Debris:AddItem(attachment, 3)
	task.wait(.1)
	emitter.Enabled = false
end

--------------------------------------------------------------------------------
-- TARGETING
--------------------------------------------------------------------------------

local function IsOwnBlock(target: BasePart?): boolean
	if not target then return false end
	if not CollectionService:HasTag(target, "Mineable") then return false end
	local current: Instance? = target.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("OwnerUserId") == LocalPlayer.UserId then return true end
		current = current.Parent
	end
	return false
end

local function IsValidTarget(target: BasePart?): boolean
	if not target or not IsOwnBlock(target) then return false end
	local character = LocalPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return false end
	return (character.HumanoidRootPart.Position - target.Position).Magnitude <= MAX_MINING_DISTANCE
end

--------------------------------------------------------------------------------
-- MINING LOOP
--------------------------------------------------------------------------------

local function GetMiningCooldown(): number
	local level = LocalPlayer:GetAttribute("PickaxeLevel") or 1
	local pickaxe = GameConfig.GetPickaxe(level)
	return pickaxe and pickaxe.Cooldown or 0.1
end

local function MiningLoop()
	while IsMining do
		local target = Mouse.Target
		if target and IsValidTarget(target) then
			Remotes.RequestMineHit:FireServer(target)
			task.wait(GetMiningCooldown())
		else
			task.wait(GameConfig.Mining.IdleCheckRate or 0.1)
		end
	end
	if IsInventoryFull then InventoryFullNotification.Hide() end
end

local function StartMining()
	if IsMining then return end
	IsMining = true
	MiningJob = task.spawn(MiningLoop)
end

local function StopMining()
	IsMining = false
	if MiningJob then task.cancel(MiningJob); MiningJob = nil end
	InventoryFullNotification.Hide()
end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

local function OnBlockDamaged(data)
	if data.Health >= data.MaxHealth then UpdateBreakVisuals(data.Block, 0)
	else
		local progress = data.Health / data.MaxHealth
		local stage = math.clamp(math.ceil((1 - progress) * 10), 1, 10)
		PlayHitWobble(data.Block, stage)
	end
	if Mouse.Target == data.Block then UpdateTooltip(data.Block) end
end

local function OnBlockDestroyed(data)
	PlayBreakEffect(data.Position, Color3.fromRGB(200,200,200))
	if data.CurrentStorage and data.MaxStorage then
		print(`[Mining] +${data.CashAwarded} Cash! Storage: {data.CurrentStorage}/{data.MaxStorage}`)
	else print(`[Mining] +${data.CashAwarded} Cash!`) end
	IsInventoryFull = false
end

local function OnInventoryFull()
	IsInventoryFull = true
	print("[Mining] Inventory is FULL! Cannot mine.")
	if IsMining then InventoryFullNotification.Show() end
end

local function OnOreDiscovered(data)
	if data and data.OreId then
		MarkOreAsDiscovered(data.OreId)
	end
end

local function StartHoverTracking()
	-- ✅ FIX: Clean up existing connection if any
	if HoverTrackingConnection then
		HoverTrackingConnection:Disconnect()
		HoverTrackingConnection = nil
	end

	HoverTrackingConnection = RunService.RenderStepped:Connect(function()
		local target = Mouse.Target
		if target and IsValidTarget(target) then
			if not IsMining then CurrentTarget = target end
			ShowHighlight(target)
			UpdateTooltip(target)
		else 
			HideHighlight()
			UpdateTooltip(nil) 
		end

		local character = LocalPlayer.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local origin = PlotController.GetMineOrigin()
			if origin then
				local diffY = origin.Y - character.HumanoidRootPart.Position.Y
				local depthMeters = math.max(0, math.floor(diffY / BLOCK_SIZE))
				if depthMeters ~= CurrentDepth then
					CurrentDepth = depthMeters; UpdateDepthMeter(CurrentDepth)
					for _, callback in ipairs(DepthListeners) do task.spawn(callback, CurrentDepth) end
				end
			end
		end

		local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
		if leaderstats then
			local storage = leaderstats:FindFirstChild("Storage")
			local capacity = leaderstats:FindFirstChild("Capacity")
			if storage and capacity then
				local wasFull = IsInventoryFull
				IsInventoryFull = storage.Value >= capacity.Value
				if wasFull and not IsInventoryFull then InventoryFullNotification.Hide() end
			end
		end
	end)
end

-- ✅ NEW: Function to reinitialize visual components on respawn
local function OnCharacterAdded(character)
	-- Wait for character to be fully loaded
	character:WaitForChild("HumanoidRootPart")

	-- Recreate the selection highlight
	task.wait(0.1) -- Small delay to ensure PlayerGui is ready
	CreateSelectionHighlight()

	-- Recreate tooltip UI
	CreateTooltipUI()

	-- Find depth UI again
	FindManualUI()

	print("[MiningController] Visual components reinitialized after respawn")
end

function MiningController.Initialize()
	if IsInitialized then return end
	IsInitialized = true

	SelectionHighlight = CreateSelectionHighlight()
	CreateTooltipUI()
	FindManualUI()
	InventoryFullNotification.Initialize()

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	Remotes.RequestMineHit = remotesFolder:WaitForChild("RequestMineHit")
	Remotes.BlockDamaged = remotesFolder:WaitForChild("BlockDamaged")
	Remotes.BlockDestroyed = remotesFolder:WaitForChild("BlockDestroyed")
	Remotes.BrainrotDropped = remotesFolder:WaitForChild("BrainrotDropped")

	local inventoryFullRemote = remotesFolder:WaitForChild("InventoryFull", 5)
	if inventoryFullRemote then
		Remotes.InventoryFull = inventoryFullRemote
		Remotes.InventoryFull.OnClientEvent:Connect(OnInventoryFull)
	end

	local oreDiscoveredRemote = remotesFolder:WaitForChild("OreDiscovered", 5)
	if oreDiscoveredRemote then
		Remotes.OreDiscovered = oreDiscoveredRemote
		Remotes.OreDiscovered.OnClientEvent:Connect(OnOreDiscovered)
	end

	local dataLoadedRemote = remotesFolder:WaitForChild("DataLoaded", 5)
	if dataLoadedRemote then
		dataLoadedRemote.OnClientEvent:Connect(function(data)
			if data and data.DiscoveredOres then
				for oreId, _ in pairs(data.DiscoveredOres) do
					DiscoveredOres[oreId] = true
				end
				print(`[MiningController] Loaded {#data.DiscoveredOres} discovered ores`)
			end
		end)
	end

	Remotes.BlockDamaged.OnClientEvent:Connect(OnBlockDamaged)
	Remotes.BlockDestroyed.OnClientEvent:Connect(OnBlockDestroyed)
	Remotes.BrainrotDropped.OnClientEvent:Connect(PlayBrainrotPopout)

	Mouse.Button1Down:Connect(StartMining)
	Mouse.Button1Up:Connect(StopMining)

	StartHoverTracking()

	-- ✅ FIX: Listen for character respawns to reinitialize visual components
	LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)

	-- If character already exists, ensure components are ready
	if LocalPlayer.Character then
		task.spawn(function()
			OnCharacterAdded(LocalPlayer.Character)
		end)
	end

	print("[MiningController] Initialized with Ore Discovery & Brainrot Popouts (Fixed Respawn)")
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function MiningController.GetCurrentDepth(): number return CurrentDepth end
function MiningController.OnDepthChanged(callback: (number) -> ()) table.insert(DepthListeners, callback) end
function MiningController.IsMining(): boolean return IsMining end
function MiningController.GetCurrentTarget(): BasePart? return CurrentTarget end
function MiningController.IsInventoryFull(): boolean return IsInventoryFull end
function MiningController.SetBlockTheme(blockName: string, theme: typeof(BLOCK_THEMES["DEFAULT"])) BLOCK_THEMES[string.upper(blockName)] = theme end
function MiningController.GetBlockTheme(blockName: string): typeof(BLOCK_THEMES["DEFAULT"]) return GetBlockTheme(blockName) end
function MiningController.SetTooltipConfig(config: typeof(TOOLTIP_CONFIG)) for key, value in pairs(config) do if TOOLTIP_CONFIG[key] ~= nil then TOOLTIP_CONFIG[key] = value end end end

-- Ore Discovery API
function MiningController.IsOreDiscovered(oreId: string): boolean return IsOreDiscovered(oreId) end
function MiningController.GetDiscoveredOres(): {[string]: boolean} return DiscoveredOres end
function MiningController.OnOreDiscovered(callback: (string) -> ()) table.insert(OreDiscoveryCallbacks, callback) end

return MiningController
