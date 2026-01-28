--!strict
--[[
	ClientInit.lua
	Main client initialization script with Ore Discovery System
	Location: StarterPlayerScripts/ClientInit.lua
	
	UPDATED: 
	- Fixed depth tracking (changed > 1 to ~=)
	- Added debug logging for depth changes
	- Animated gradient text for layer notifications
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

print("[ClientInit] ========================================")
print("[ClientInit] BRAINROT MINING SIMULATOR V2 - CLIENT")
print("[ClientInit] ========================================")

local GameConfig = require(ReplicatedStorage.Shared:WaitForChild("GameConfig"))
local Controllers = PlayerScripts:WaitForChild("Controllers")


local PlotController = require(Controllers:WaitForChild("PlotController"))
local MiningController = require(Controllers:WaitForChild("MiningController"))
local LayerProgressController = require(Controllers:WaitForChild("LayerProgressController"))
local CashController = require(Controllers:WaitForChild("CashController"))
local OreDiscoveryPopup = require(Controllers:WaitForChild("OreDiscoveryPopup"))
local StructureController = require(Controllers:WaitForChild("StructureController"))
local TutorialController = require(Controllers:WaitForChild("TutorialController"))

--------------------------------------------------------------------------------
-- LAYER NOTIFICATION SYSTEM (ANIMATED GRADIENT STYLE)
--------------------------------------------------------------------------------

-- Layer flavor text / subtitles
local LAYER_SUBTITLES = {
	[1] = "WHERE IT ALL BEGINS",
	[2] = "ANCIENT STONE AWAITS",
	[3] = "DEPTHS OF THE EARTH",
	[4] = "DARKNESS SURROUNDS",
	[5] = "HEAT OF THE WORLD",
	[6] = "REALITY BREAKS DOWN",
	[7] = "ONLY IN OHIO...",
}

-- Layer gradient colors (left color, right color)
local LAYER_GRADIENTS = {
	[1] = {Color3.fromRGB(139, 90, 43), Color3.fromRGB(210, 180, 140)},   -- Dirt: brown to tan
	[2] = {Color3.fromRGB(128, 128, 128), Color3.fromRGB(200, 200, 200)}, -- Stone: gray gradient
	[3] = {Color3.fromRGB(70, 50, 30), Color3.fromRGB(139, 90, 43)},      -- Deep: dark brown
	[4] = {Color3.fromRGB(30, 30, 50), Color3.fromRGB(80, 80, 120)},      -- Dark: deep blue/purple
	[5] = {Color3.fromRGB(255, 100, 0), Color3.fromRGB(255, 200, 50)},    -- Heat: orange to yellow
	[6] = {Color3.fromRGB(150, 50, 255), Color3.fromRGB(50, 200, 255)},   -- Reality: purple to cyan
	[7] = {Color3.fromRGB(255, 0, 100), Color3.fromRGB(0, 255, 150)},     -- Ohio: chaotic pink to green
}

-- Layer particle styles: {colors, shapes, speed, size, glow}
local LAYER_PARTICLES = {
	[1] = { -- Dirt: falling dust/dirt specks
		Colors = {Color3.fromRGB(139, 90, 43), Color3.fromRGB(180, 140, 90), Color3.fromRGB(110, 70, 30)},
		Symbol = "●",
		Speed = {0.3, 0.6},
		Size = {8, 14},
		Glow = false,
	},
	[2] = { -- Stone: falling pebbles/rocks
		Colors = {Color3.fromRGB(128, 128, 128), Color3.fromRGB(160, 160, 160), Color3.fromRGB(90, 90, 90)},
		Symbol = "◆",
		Speed = {0.4, 0.8},
		Size = {10, 16},
		Glow = false,
	},
	[3] = { -- Deep: dark dust with occasional glints
		Colors = {Color3.fromRGB(70, 50, 30), Color3.fromRGB(100, 80, 50), Color3.fromRGB(50, 35, 20)},
		Symbol = "✦",
		Speed = {0.2, 0.5},
		Size = {8, 12},
		Glow = true,
	},
	[4] = { -- Dark: floating shadow wisps
		Colors = {Color3.fromRGB(50, 50, 80), Color3.fromRGB(80, 80, 120), Color3.fromRGB(30, 30, 60)},
		Symbol = "◯",
		Speed = {0.1, 0.3},
		Size = {12, 20},
		Glow = true,
	},
	[5] = { -- Heat: rising embers/sparks
		Colors = {Color3.fromRGB(255, 100, 0), Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 50, 0)},
		Symbol = "★",
		Speed = {0.5, 1.0},
		Size = {10, 18},
		Glow = true,
		RiseUp = true, -- Special: particles rise instead of fall
	},
	[6] = { -- Reality: glitchy floating fragments
		Colors = {Color3.fromRGB(150, 50, 255), Color3.fromRGB(50, 200, 255), Color3.fromRGB(255, 100, 255)},
		Symbol = "◈",
		Speed = {0.2, 0.6},
		Size = {10, 16},
		Glow = true,
		Glitchy = true, -- Special: random position jumps
	},
	[7] = { -- Ohio: chaotic multi-colored madness
		Colors = {Color3.fromRGB(255, 0, 100), Color3.fromRGB(0, 255, 150), Color3.fromRGB(255, 255, 0), Color3.fromRGB(0, 150, 255)},
		Symbol = "✶",
		Speed = {0.4, 1.2},
		Size = {8, 20},
		Glow = true,
		Chaotic = true, -- Special: random directions
	},
}

local LastShownLayerIndex: number = 0
local IsShowingNotification: boolean = false
local NotificationGui: ScreenGui? = nil
local GradientAnimationConnection: RBXScriptConnection? = nil
local ParticleAnimationConnection: RBXScriptConnection? = nil
local ActiveParticles: {TextLabel} = {}

-- Particle system helper
local function SpawnParticle(container: Frame, particleStyle: typeof(LAYER_PARTICLES[1]), screenWidth: number, screenHeight: number)
	local particle = Instance.new("TextLabel")
	particle.Name = "Particle"
	particle.BackgroundTransparency = 1
	particle.Text = particleStyle.Symbol
	particle.TextColor3 = particleStyle.Colors[math.random(1, #particleStyle.Colors)]
	particle.TextSize = math.random(particleStyle.Size[1], particleStyle.Size[2])
	particle.Font = Enum.Font.GothamBold
	particle.TextTransparency = math.random(30, 60) / 100
	particle.TextStrokeTransparency = 1
	particle.Size = UDim2.new(0, 30, 0, 30)
	particle.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Random starting position across the width
	local startX = math.random(10, 90) / 100
	local startY

	if particleStyle.RiseUp then
		startY = 1.1 -- Start below
	else
		startY = -0.1 -- Start above
	end

	particle.Position = UDim2.new(startX, 0, startY, 0)
	particle.Parent = container

	-- Store particle data for animation
	particle:SetAttribute("SpeedY", math.random(particleStyle.Speed[1] * 100, particleStyle.Speed[2] * 100) / 100)
	particle:SetAttribute("SpeedX", (math.random() - 0.5) * 0.2) -- Slight horizontal drift
	particle:SetAttribute("RiseUp", particleStyle.RiseUp or false)
	particle:SetAttribute("Glitchy", particleStyle.Glitchy or false)
	particle:SetAttribute("Chaotic", particleStyle.Chaotic or false)
	particle:SetAttribute("GlitchTimer", 0)
	particle:SetAttribute("OriginalX", startX)

	if particleStyle.Glow then
		local glow = Instance.new("UIStroke")
		glow.Color = particle.TextColor3
		glow.Thickness = 2
		glow.Transparency = 0.5
		glow.Parent = particle
	end

	table.insert(ActiveParticles, particle)
	return particle
end

-- Creates a gradient TextLabel using UIGradient
local function CreateGradientText(props: {
	Name: string,
	Text: string,
	Size: UDim2,
	Position: UDim2,
	TextSize: number,
	Font: Enum.Font,
	GradientColors: {Color3},
	Parent: Instance
	}): (TextLabel, UIGradient)
	local label = Instance.new("TextLabel")
	label.Name = props.Name
	label.Size = props.Size
	label.Position = props.Position
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text = props.Text
	label.TextColor3 = Color3.new(1, 1, 1) -- Base white, gradient will colorize
	label.TextSize = props.TextSize
	label.Font = props.Font
	label.TextTransparency = 1
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.5
	label.Parent = props.Parent

	local gradient = Instance.new("UIGradient")
	gradient.Name = "TextGradient"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, props.GradientColors[1]),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), -- White center highlight
		ColorSequenceKeypoint.new(1, props.GradientColors[2])
	})
	gradient.Rotation = 0
	gradient.Offset = Vector2.new(-1, 0) -- Start offset for animation
	gradient.Parent = label

	return label, gradient
end

local function ShowLayerNotification(layerIndex: number, layerData: typeof(GameConfig.Layers[1]))
	if layerIndex == LastShownLayerIndex and IsShowingNotification then return end
	LastShownLayerIndex = layerIndex
	IsShowingNotification = true

	-- Clean up previous animation
	if GradientAnimationConnection then
		GradientAnimationConnection:Disconnect()
		GradientAnimationConnection = nil
	end

	if ParticleAnimationConnection then
		ParticleAnimationConnection:Disconnect()
		ParticleAnimationConnection = nil
	end

	-- Clear active particles
	for _, particle in ActiveParticles do
		if particle and particle.Parent then
			particle:Destroy()
		end
	end
	ActiveParticles = {}

	-- Get or create the ScreenGui
	if not NotificationGui or not NotificationGui.Parent then
		NotificationGui = Instance.new("ScreenGui")
		NotificationGui.Name = "LayerNotificationUI"
		NotificationGui.ResetOnSpawn = false
		NotificationGui.DisplayOrder = 100
		NotificationGui.IgnoreGuiInset = true
		NotificationGui.Parent = PlayerGui
	end

	-- Clear existing
	for _, child in NotificationGui:GetChildren() do child:Destroy() end

	local subtitle = LAYER_SUBTITLES[layerIndex] or "UNKNOWN TERRITORY"
	local gradientColors = LAYER_GRADIENTS[layerIndex] or {Color3.new(1, 1, 1), Color3.new(0.8, 0.8, 0.8)}
	local particleStyle = LAYER_PARTICLES[layerIndex]

	-- Particle container (full screen behind text)
	local particleContainer = Instance.new("Frame")
	particleContainer.Name = "ParticleContainer"
	particleContainer.Size = UDim2.new(1, 0, 1, 0)
	particleContainer.Position = UDim2.new(0, 0, 0, 0)
	particleContainer.BackgroundTransparency = 1
	particleContainer.ClipsDescendants = true
	particleContainer.ZIndex = 1
	particleContainer.Parent = NotificationGui

	-- Main container (covers screen center area) - moved higher
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 0, 200)
	container.Position = UDim2.new(0.5, 0, 0.38, 0) -- Moved up from 0.5 to 0.38
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.ZIndex = 2
	container.Parent = NotificationGui

	-- Main title with gradient
	local titleLabel, titleGradient = CreateGradientText({
		Name = "Title",
		Text = string.upper(layerData.LayerName),
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.new(0.5, 0, 0.5, -30),
		TextSize = 64,
		Font = Enum.Font.GothamBlack,
		GradientColors = gradientColors,
		Parent = container
	})

	-- Horizontal line under title (also gradient colored)
	local lineContainer = Instance.new("Frame")
	lineContainer.Name = "LineContainer"
	lineContainer.Size = UDim2.new(0, 0, 0, 3)
	lineContainer.Position = UDim2.new(0.5, 0, 0.5, 15)
	lineContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	lineContainer.BackgroundColor3 = Color3.new(1, 1, 1)
	lineContainer.BackgroundTransparency = 0.3
	lineContainer.BorderSizePixel = 0
	lineContainer.Parent = container

	local lineGradient = Instance.new("UIGradient")
	lineGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, gradientColors[1]),
		ColorSequenceKeypoint.new(1, gradientColors[2])
	})
	lineGradient.Parent = lineContainer

	-- Subtitle with gradient
	local subtitleLabel, subtitleGradient = CreateGradientText({
		Name = "Subtitle",
		Text = subtitle,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0.5, 0, 0.5, 35),
		TextSize = 24,
		Font = Enum.Font.Gotham,
		GradientColors = gradientColors,
		Parent = container
	})
	subtitleLabel.TextStrokeTransparency = 0.7

	-- Depth info line with gradient
	local depthLabel, depthGradient = CreateGradientText({
		Name = "Depth",
		Text = "LAYER " .. layerIndex .. "/" .. #GameConfig.Layers,
		Size = UDim2.new(1, 0, 0, 25),
		Position = UDim2.new(0.5, 0, 0.5, 65),
		TextSize = 18,
		Font = Enum.Font.GothamMedium,
		GradientColors = gradientColors,
		Parent = container
	})
	depthLabel.TextStrokeTransparency = 0.8

	-- Store all gradients for animation
	local allGradients = {titleGradient, subtitleGradient, depthGradient, lineGradient}

	-- ============ GRADIENT ANIMATION (Moving left to right) ============
	local animationTime = 0
	local animationSpeed = 0.8 -- How fast the gradient moves

	GradientAnimationConnection = RunService.RenderStepped:Connect(function(dt)
		animationTime += dt * animationSpeed

		-- Create a smooth wave-like offset that moves left to right
		local offset = math.sin(animationTime * 2) * 0.3 -- Oscillates between -0.3 and 0.3

		for _, grad in allGradients do
			if grad and grad.Parent then
				grad.Offset = Vector2.new(offset, 0)
			end
		end
	end)

	-- ============ PARTICLE SYSTEM ============
	if particleStyle then
		local particleSpawnTimer = 0
		local spawnInterval = 0.15 -- Spawn a particle every 0.15 seconds

		ParticleAnimationConnection = RunService.RenderStepped:Connect(function(dt)
			-- Spawn new particles
			particleSpawnTimer += dt
			if particleSpawnTimer >= spawnInterval and #ActiveParticles < 40 then
				particleSpawnTimer = 0
				SpawnParticle(particleContainer, particleStyle, 1920, 1080)
			end

			-- Update existing particles
			local toRemove = {}
			for i, particle in ActiveParticles do
				if not particle or not particle.Parent then
					table.insert(toRemove, i)
					continue
				end

				local speedY = particle:GetAttribute("SpeedY") or 0.5
				local speedX = particle:GetAttribute("SpeedX") or 0
				local riseUp = particle:GetAttribute("RiseUp") or false
				local glitchy = particle:GetAttribute("Glitchy") or false
				local chaotic = particle:GetAttribute("Chaotic") or false
				local glitchTimer = particle:GetAttribute("GlitchTimer") or 0

				local currentPos = particle.Position
				local newY, newX

				if riseUp then
					newY = currentPos.Y.Scale - (speedY * dt)
				else
					newY = currentPos.Y.Scale + (speedY * dt)
				end

				newX = currentPos.X.Scale + (speedX * dt)

				-- Glitchy effect: random position jumps
				if glitchy then
					glitchTimer += dt
					if glitchTimer > 0.2 and math.random() < 0.1 then
						newX = currentPos.X.Scale + (math.random() - 0.5) * 0.1
						particle:SetAttribute("GlitchTimer", 0)
					else
						particle:SetAttribute("GlitchTimer", glitchTimer)
					end
				end

				-- Chaotic effect: random direction changes
				if chaotic and math.random() < 0.02 then
					particle:SetAttribute("SpeedX", (math.random() - 0.5) * 0.4)
					particle:SetAttribute("SpeedY", math.random(30, 100) / 100)
				end

				particle.Position = UDim2.new(newX, 0, newY, 0)

				-- Remove if off screen
				if riseUp then
					if newY < -0.1 then table.insert(toRemove, i) end
				else
					if newY > 1.1 then table.insert(toRemove, i) end
				end
			end

			-- Clean up off-screen particles
			for j = #toRemove, 1, -1 do
				local idx = toRemove[j]
				if ActiveParticles[idx] and ActiveParticles[idx].Parent then
					ActiveParticles[idx]:Destroy()
				end
				table.remove(ActiveParticles, idx)
			end
		end)
	end

	-- ============ ANIMATION SEQUENCE ============

	-- Title fade in (quick)
	TweenService:Create(titleLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0
	}):Play()

	-- Line expands from center
	task.delay(0.15, function()
		if lineContainer.Parent then
			TweenService:Create(lineContainer, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 400, 0, 3)
			}):Play()
		end
	end)

	-- Subtitle fades in
	task.delay(0.25, function()
		if subtitleLabel.Parent then
			TweenService:Create(subtitleLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 0.1
			}):Play()
		end
	end)

	-- Depth label fades in
	task.delay(0.35, function()
		if depthLabel.Parent then
			TweenService:Create(depthLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 0.2
			}):Play()
		end
	end)

	-- ============ FADE OUT SEQUENCE ============
	task.delay(2.5, function()
		if not container.Parent then return end

		-- Stop gradient animation
		if GradientAnimationConnection then
			GradientAnimationConnection:Disconnect()
			GradientAnimationConnection = nil
		end

		-- Stop particle spawning (but let existing ones fade)
		if ParticleAnimationConnection then
			ParticleAnimationConnection:Disconnect()
			ParticleAnimationConnection = nil
		end

		-- Fade out all particles
		for _, particle in ActiveParticles do
			if particle and particle.Parent then
				TweenService:Create(particle, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextTransparency = 1
				}):Play()
			end
		end

		-- Everything fades out together
		TweenService:Create(titleLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1
		}):Play()

		TweenService:Create(subtitleLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1
		}):Play()

		TweenService:Create(depthLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1
		}):Play()

		-- Line shrinks back to center
		TweenService:Create(lineContainer, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 3),
			BackgroundTransparency = 1
		}):Play()

		task.delay(0.5, function()
			IsShowingNotification = false
			if container.Parent then
				container:Destroy()
			end
			if particleContainer and particleContainer.Parent then
				particleContainer:Destroy()
			end
			-- Clear particle references
			ActiveParticles = {}
		end)
	end)

	print(`[ClientInit] Layer notification: {layerData.LayerName} (Layer {layerIndex})`)
end

--------------------------------------------------------------------------------
-- DEPTH TRACKING
--------------------------------------------------------------------------------

local DepthUpdateCount = 0

local function CheckLayerChange(depthBlocks: number)
	local depthStuds = depthBlocks * GameConfig.Mine.BlockSize
	local newLayerIndex = GameConfig.GetLayerIndexByDepth(depthStuds)
	if newLayerIndex ~= CurrentTrackedLayerIndex then
		CurrentTrackedLayerIndex = newLayerIndex
		local layerData = GameConfig.Layers[newLayerIndex]
		if layerData then ShowLayerNotification(newLayerIndex, layerData) end
	end
end

local function StartImmediateDepthTracking()
	if DepthTrackingConnection then DepthTrackingConnection:Disconnect() end

	DepthTrackingConnection = RunService.RenderStepped:Connect(function()
		local character = LocalPlayer.Character
		if not character then return end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local plotData = PlotController.GetPlotData()
		if not plotData then return end

		local depthStuds = plotData.MineOrigin.Y - hrp.Position.Y
		local depthBlocks = math.max(0, math.floor(depthStuds / GameConfig.Mine.BlockSize))

		if depthBlocks ~= LastTrackedDepth then
			LastTrackedDepth = depthBlocks
			LayerProgressController.SetDepth(depthBlocks)
			CheckLayerChange(depthBlocks)
			
			if TutorialController and TutorialController.IsTutorialActive() then
				-- Notify server of depth change for tutorial tracking
				local actionRemote = ReplicatedStorage.Remotes:FindFirstChild("TutorialAction")
				if actionRemote and depthBlocks >= 10 then
					-- Server will handle this via attribute change on player
				end
			end

			-- ✅ DEBUG: Log depth updates (remove after confirming it works)
			DepthUpdateCount += 1
			if DepthUpdateCount % 10 == 0 then -- Log every 10th update to reduce spam
				print(`[ClientInit] Depth updated: {depthBlocks} blocks (update #{DepthUpdateCount})`)
			end
		end
	end)

	print("[ClientInit] Depth tracking started via RenderStepped")
end

print("[ClientInit] Initializing controllers...")

PlotController.Initialize()

PlotController.OnReady(function()
	local plotData = PlotController.GetPlotData()
	if plotData then
		print("[ClientInit] Plot ready, MineOrigin.Y =", plotData.MineOrigin.Y)
		local character = LocalPlayer.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local depthStuds = plotData.MineOrigin.Y - hrp.Position.Y
				local depthBlocks = math.max(0, math.floor(depthStuds / GameConfig.Mine.BlockSize))
				print("[ClientInit] Initial depth:", depthBlocks, "blocks")
				LayerProgressController.SetDepth(depthBlocks)
				LastTrackedDepth = depthBlocks
				CurrentTrackedLayerIndex = GameConfig.GetLayerIndexByDepth(depthBlocks * GameConfig.Mine.BlockSize)
			end
		end
	end
	StartImmediateDepthTracking()
	ShowLayerNotification(CurrentTrackedLayerIndex, GameConfig.Layers[CurrentTrackedLayerIndex])
end)

MiningController.Initialize()
LayerProgressController.Initialize()
OreDiscoveryPopup.Initialize()
StructureController.Initialize()
TutorialController.Initialize()

local CurrentTrackedLayerIndex: number = 1
local LastTrackedDepth: number = -1
local DepthTrackingConnection: RBXScriptConnection? = nil

-- ✅ DEBUG: Track if depth updates are happening




PlotController.OnLayerChanged(function(layerIndex, layerData)
	if layerIndex ~= CurrentTrackedLayerIndex then
		CurrentTrackedLayerIndex = layerIndex
		ShowLayerNotification(layerIndex, layerData)
	end
end)

-- ✅ FIX: Changed from > 1 to ~= to catch all depth changes
MiningController.OnDepthChanged(function(newDepth: number)
	print("[ClientInit] MiningController.OnDepthChanged fired:", newDepth) -- DEBUG
	if newDepth ~= LastTrackedDepth then -- ✅ FIXED: was "math.abs(newDepth - LastTrackedDepth) > 1"
		LastTrackedDepth = newDepth
		LayerProgressController.SetDepth(newDepth)
		CheckLayerChange(newDepth)
	end
end)

--------------------------------------------------------------------------------
-- ORE DISCOVERY SYSTEM
--------------------------------------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local oreDiscoveredRemote = remotesFolder:WaitForChild("OreDiscovered", 5)
if oreDiscoveredRemote then
	oreDiscoveredRemote.OnClientEvent:Connect(function(data)
		if data and data.OreId then
			print(`[ClientInit] NEW ORE DISCOVERED: {data.OreId}`)
			OreDiscoveryPopup.Show(data.OreId)
		end
	end)
end

--------------------------------------------------------------------------------
-- CASH CONTROLLER
--------------------------------------------------------------------------------

CashController.Initialize()

CashController.OnCashChanged(function(newCash, delta, reason)
	if reason == "Sell" then
		print(`[ClientInit] SOLD! Earned ${delta} - Total: {CashController.FormatCashDetailed(newCash)}`)
	elseif reason == "Purchase" then
		print(`[ClientInit] Spent ${math.abs(delta)} - Remaining: {CashController.FormatCashDetailed(newCash)}`)
	end
end)

--------------------------------------------------------------------------------
-- CASH POPUP UI
--------------------------------------------------------------------------------

local function ShowCashPopup(delta: number, reason: string)
	local screenGui = PlayerGui:FindFirstChild("CashPopup")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "CashPopup"
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 50
		screenGui.Parent = PlayerGui
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 300, 0, 50)
	label.Position = UDim2.new(0.5, 0, 0.3, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 32
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)

	if delta >= 0 then
		label.Text = "+" .. CashController.FormatCashDetailed(delta)
		label.TextColor3 = Color3.fromRGB(100, 255, 100)
	else
		label.Text = "-" .. CashController.FormatCashDetailed(math.abs(delta))
		label.TextColor3 = Color3.fromRGB(255, 100, 100)
	end

	label.Parent = screenGui

	local moveUp = TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.2, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1
	})
	moveUp:Play()
	moveUp.Completed:Connect(function() label:Destroy() end)
end

CashController.OnCashChanged(function(newCash, delta, reason)
	if reason == "Sell" or reason == "Reward" or reason == "Purchase" then
		ShowCashPopup(delta, reason)
	end
end)

--------------------------------------------------------------------------------
-- DEBUG COMMANDS
--------------------------------------------------------------------------------

LocalPlayer.Chatted:Connect(function(message)
	local lower = message:lower()

	if lower == "/plot" then
		PlotController.TeleportToPlot()

	elseif lower == "/layer" then
		local layer = PlotController.GetCurrentLayerData()
		local progressLayer = LayerProgressController.GetCurrentLayer()
		local progress = LayerProgressController.GetLayerProgress()
		if layer then
			print("[Debug] Current Layer: " .. layer.LayerName .. " (Index: " .. progressLayer .. ")")
			print("[Debug]   Progress: " .. math.floor(progress * 100) .. "%")
		end

	elseif lower == "/depth" then
		local depth = MiningController.GetCurrentDepth()
		print("[Debug] Current Depth: " .. depth .. " blocks")
		print("[Debug] LastTrackedDepth: " .. LastTrackedDepth)
		print("[Debug] Depth updates received: " .. DepthUpdateCount)

	elseif lower == "/mining" then
		print("[Debug] Mining System:")
		print("[Debug]   Currently Mining: " .. tostring(MiningController.IsMining()))
		print("[Debug]   Inventory Full: " .. tostring(MiningController.IsInventoryFull()))

	elseif lower == "/stats" or lower == "/storage" then
		local cash = CashController.GetCash()
		local storageUsed, capacity = CashController.GetStorage()
		print("[Debug] === Player Stats ===")
		print("[Debug]   Cash: " .. CashController.FormatCashDetailed(cash))
		print("[Debug]   Storage: " .. storageUsed .. "/" .. capacity)

	elseif lower == "/sell" then
		local success, cashEarned, itemsSold = CashController.SellInventory()
		if success then
			print("[Debug] SOLD " .. itemsSold .. " items for $" .. cashEarned)
		else
			print("[Debug] Nothing to sell!")
		end

	elseif lower == "/discovered" then
		local discovered = MiningController.GetDiscoveredOres()
		print("[Debug] === Discovered Ores ===")
		local count = 0
		for oreId, _ in pairs(discovered) do
			count += 1
			print("[Debug]   - " .. oreId)
		end
		print("[Debug] Total: " .. count .. " ores discovered")

	elseif lower:match("^/testdiscover%s+(.+)$") then
		local oreId = lower:match("^/testdiscover%s+(.+)$")
		if oreId then
			print("[Debug] Testing discovery popup for: " .. oreId)
			OreDiscoveryPopup.Show(oreId)
		end

	elseif lower:match("^/testlayer%s+(%d+)$") then
		local layerNum = tonumber(lower:match("^/testlayer%s+(%d+)$"))
		if layerNum and layerNum >= 1 and layerNum <= #GameConfig.Layers then
			local layerData = GameConfig.Layers[layerNum]
			LastShownLayerIndex = 0
			IsShowingNotification = false
			ShowLayerNotification(layerNum, layerData)
		end

	elseif lower == "/testprogress" then
		-- Test the layer progress UI directly
		print("[Debug] Testing LayerProgressController...")
		print("[Debug]   Current Layer: " .. LayerProgressController.GetCurrentLayer())
		print("[Debug]   Progress: " .. string.format("%.1f%%", LayerProgressController.GetLayerProgress() * 100))
		print("[Debug]   Max Layer Reached: " .. LayerProgressController.GetMaxLayerReached())
		print("[Debug]   Device Type: " .. LayerProgressController.GetDeviceType())
		print("[Debug]   Scale: " .. LayerProgressController.GetCurrentScale())
		-- Force a depth update
		LayerProgressController.SetDepth(LastTrackedDepth + 1)
		task.wait(0.5)
		LayerProgressController.SetDepth(LastTrackedDepth)

	elseif lower == "/help" then
		print("[Debug] ========== AVAILABLE COMMANDS ==========")
		print("[Debug] /plot - Teleport to your plot")
		print("[Debug] /layer - Show current layer info")
		print("[Debug] /depth - Show current depth")
		print("[Debug] /mining - Show mining system status")
		print("[Debug] /stats - Show player stats & storage")
		print("[Debug] /sell - SELL ALL ITEMS FOR CASH")
		print("[Debug] /discovered - Show all discovered ores")
		print("[Debug] /testdiscover [oreid] - Test discovery popup")
		print("[Debug] /testlayer [1-7] - Test layer notification")
		print("[Debug] /testprogress - Test layer progress UI")
		print("[Debug] --- SERVER DEBUG COMMANDS ---")
		print("[Debug] /resetores - Reset discovered ores")
		print("[Debug] /discoveredores - List discovered ores (server)")
		print("[Debug] /nextbackpack - Upgrade backpack")
		print("[Debug] /givecash - Give $1000")
		print("[Debug] ==========================================")
	elseif lower == "/eggs" then
		-- Test: Show available eggs
		local eggs = Remotes.GetAvailableEggs:InvokeServer()
		print("[Debug] === Available Eggs ===")
		for i, egg in ipairs(eggs) do
			print(`[Debug] {i}. {egg.Variant} {egg.Rarity} Egg (GUID: {egg.GUID})`)
		end
		print(`[Debug] Total: {#eggs} eggs`)

	elseif lower == "/units" or lower == "/brainrots" then
		-- Test: Show available units
		local units = Remotes.GetAvailableUnits:InvokeServer()
		print("[Debug] === Available Brainrots ===")
		for i, unit in ipairs(units) do
			print(`[Debug] {i}. {unit.Variant} {unit.Name} ({unit.Rarity}) - ${unit.IncomePerSecond}/s`)
		end
		print(`[Debug] Total: {#units} brainrots`)

	elseif lower == "/structures" then
		-- Test: Show all structure states
		local states = Remotes.GetAllStructureStates:InvokeServer()
		print("[Debug] === Structure States ===")
		print("[Debug] Incubators:")
		for id, data in pairs(states.Incubators) do
			local remaining = data.IsReady and "READY" or `{data.TimeRemaining}s`
			print(`[Debug]   {id}: {data.State.EggData.Rarity} Egg - {remaining}`)
		end
		print("[Debug] Pens:")
		for id, data in pairs(states.Pens) do
			print(`[Debug]   {id}: {data.State.UnitData.Name} - ${data.CurrentIncome} accumulated (+${data.IncomeRate}/s)`)
		end	
		
	elseif lower == "/tutorial" then
		local state = Remotes.GetTutorialState:InvokeServer()
		print("[Debug] === Tutorial State ===")
		print("[Debug]   Current Step:", state.CurrentStepIndex, "/", state.TotalSteps)
		print("[Debug]   Completed:", state.TutorialCompleted)
		print("[Debug]   Skipped:", state.TutorialSkipped)
		if state.CurrentStep then
			print("[Debug]   Step ID:", state.CurrentStep.Id)
			print("[Debug]   Step Title:", state.CurrentStep.Title)
		end

	elseif lower == "/skiptutorial" then
		local TutorialController = require(Controllers:WaitForChild("TutorialController"))
		TutorialController.SkipEntireTutorial()																																
		print("[Debug] Skipped tutorial")

	elseif lower == "/resettutorial" then
		-- You'd need to add a server-side reset function
		print("[Debug] Tutorial reset not implemented - use DataStore to clear")
	end

	
end)

print("[ClientInit] Controllers initialized with Animated Gradient Layer UI")
print("[ClientInit] Type /help for all commands")
print("[ClientInit] ========================================")

--[[
============================================================
IMPORTANT: You also need to update LayerProgressController.lua!

Find the SetupDataListeners function and replace it with:

local function SetupDataListeners()
	local rf = ReplicatedStorage:WaitForChild("Remotes")
	
	-- DataLoaded remote (required)
	local dataLoadedRemote = rf:FindFirstChild("DataLoaded")
	if dataLoadedRemote then
		dataLoadedRemote.OnClientEvent:Connect(function(data)
			if data.MaxLayerReached and data.MaxLayerReached > MaxLayerReached then
				MaxLayerReached = data.MaxLayerReached
				RefreshAllCircleLockStates()
			end
		end)
	else
		warn("[LayerProgressController] DataLoaded remote not found")
	end
	
	-- DataUpdated remote (optional - use FindFirstChild with timeout)
	task.spawn(function()
		local dataUpdatedRemote = rf:FindFirstChild("DataUpdated")
		if not dataUpdatedRemote then
			dataUpdatedRemote = rf:WaitForChild("DataUpdated", 3) -- 3 second timeout instead of infinite
		end
		
		if dataUpdatedRemote then
			dataUpdatedRemote.OnClientEvent:Connect(function(data)
				if data.Field == "MaxLayerReached" and data.Value and data.Value > MaxLayerReached then
					MaxLayerReached = data.Value
					PlayUnlockAnimation(data.Value)
				end
			end)
		else
			warn("[LayerProgressController] DataUpdated remote not found (layer unlock animations may not work)")
		end
	end)
end

============================================================
]]
