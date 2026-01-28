--!strict
--[[
	OreDiscoveryPopup.lua
	Shows a cool animated popup when player discovers a new ore for the first time
	Location: StarterPlayerScripts/Controllers/OreDiscoveryPopup.lua
	
	UPDATED: Responsive scaling for mobile, tablet, and desktop devices
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local OreDiscoveryPopup = {}

--------------------------------------------------------------------------------
-- ORE THEMES
--------------------------------------------------------------------------------

local ORE_POPUP_THEMES = {
	["GRASS"] = { Primary = Color3.fromRGB(124, 252, 0), Secondary = Color3.fromRGB(180, 255, 160), Icon = "🌱" },
	["DIRT"] = { Primary = Color3.fromRGB(180, 130, 70), Secondary = Color3.fromRGB(220, 180, 120), Icon = "🟤" },
	["STONE"] = { Primary = Color3.fromRGB(169, 169, 169), Secondary = Color3.fromRGB(220, 220, 220), Icon = "🪨" },
	["GRAVEL"] = { Primary = Color3.fromRGB(140, 135, 130), Secondary = Color3.fromRGB(180, 175, 170), Icon = "⚪" },
	["GRANITE"] = { Primary = Color3.fromRGB(200, 150, 120), Secondary = Color3.fromRGB(240, 200, 170), Icon = "🟠" },
	["DIORITE"] = { Primary = Color3.fromRGB(200, 200, 200), Secondary = Color3.fromRGB(240, 240, 240), Icon = "⬜" },
	["SLATE"] = { Primary = Color3.fromRGB(80, 120, 120), Secondary = Color3.fromRGB(120, 160, 160), Icon = "🔷" },
	["TUFF"] = { Primary = Color3.fromRGB(100, 100, 90), Secondary = Color3.fromRGB(150, 150, 140), Icon = "⬛" },
	["MAGMA"] = { Primary = Color3.fromRGB(255, 140, 0), Secondary = Color3.fromRGB(255, 200, 100), Icon = "🔥" },
	["BASALT"] = { Primary = Color3.fromRGB(70, 70, 80), Secondary = Color3.fromRGB(120, 120, 130), Icon = "🖤" },
	["GLITCHBLOCK"] = { Primary = Color3.fromRGB(0, 255, 255), Secondary = Color3.fromRGB(255, 0, 255), Icon = "⚡" },
	["PIXEL"] = { Primary = Color3.fromRGB(255, 0, 128), Secondary = Color3.fromRGB(255, 150, 200), Icon = "📺" },
	["OHIOGRASS"] = { Primary = Color3.fromRGB(255, 50, 50), Secondary = Color3.fromRGB(255, 150, 150), Icon = "💀" },
	["OHIODIRT"] = { Primary = Color3.fromRGB(100, 30, 30), Secondary = Color3.fromRGB(150, 80, 80), Icon = "☠️" },
	["COAL"] = { Primary = Color3.fromRGB(60, 60, 60), Secondary = Color3.fromRGB(100, 100, 100), Icon = "⚫" },
	["IRON"] = { Primary = Color3.fromRGB(210, 200, 190), Secondary = Color3.fromRGB(240, 230, 220), Icon = "🔩" },
	["GOLD"] = { Primary = Color3.fromRGB(255, 215, 0), Secondary = Color3.fromRGB(255, 240, 100), Icon = "🥇" },
	["DIAMOND"] = { Primary = Color3.fromRGB(185, 242, 255), Secondary = Color3.fromRGB(220, 250, 255), Icon = "💎" },
	["EMERALD"] = { Primary = Color3.fromRGB(80, 255, 80), Secondary = Color3.fromRGB(150, 255, 150), Icon = "💚" },
	["RUBY"] = { Primary = Color3.fromRGB(255, 50, 80), Secondary = Color3.fromRGB(255, 150, 170), Icon = "❤️" },
	["SAPPHIRE"] = { Primary = Color3.fromRGB(100, 149, 237), Secondary = Color3.fromRGB(170, 200, 255), Icon = "💙" },
	["AMETHYST"] = { Primary = Color3.fromRGB(200, 100, 255), Secondary = Color3.fromRGB(230, 180, 255), Icon = "💜" },
	["ONYX"] = { Primary = Color3.fromRGB(50, 50, 60), Secondary = Color3.fromRGB(100, 100, 120), Icon = "🖤" },
	["PAINITE"] = { Primary = Color3.fromRGB(255, 150, 200), Secondary = Color3.fromRGB(255, 200, 230), Icon = "💗" },
	["BITCOIN"] = { Primary = Color3.fromRGB(255, 200, 50), Secondary = Color3.fromRGB(255, 230, 120), Icon = "₿" },
	["ETHERIUM"] = { Primary = Color3.fromRGB(150, 180, 255), Secondary = Color3.fromRGB(200, 220, 255), Icon = "Ξ" },
	["UNOBTAINIUM"] = { Primary = Color3.fromRGB(255, 200, 255), Secondary = Color3.fromRGB(255, 255, 255), Icon = "✨" },
	["SKIBIDIORE"] = { Primary = Color3.fromRGB(255, 255, 255), Secondary = Color3.fromRGB(255, 200, 100), Icon = "🚽" },
	["MYSTERY_BOX_1"] = { Primary = Color3.fromRGB(200, 100, 255), Secondary = Color3.fromRGB(255, 150, 255), Icon = "📦" },
	["MYSTERY_BOX_2"] = { Primary = Color3.fromRGB(100, 200, 255), Secondary = Color3.fromRGB(150, 230, 255), Icon = "📦" },
	["MYSTERY_BOX_3"] = { Primary = Color3.fromRGB(255, 200, 100), Secondary = Color3.fromRGB(255, 230, 150), Icon = "📦" },
	["MYSTERY_BOX_4"] = { Primary = Color3.fromRGB(255, 100, 100), Secondary = Color3.fromRGB(255, 180, 180), Icon = "📦" },
	["MYSTERY_BOX_5"] = { Primary = Color3.fromRGB(255, 215, 0), Secondary = Color3.fromRGB(255, 240, 100), Icon = "📦" },
	["MYSTERY_BOX_6"] = { Primary = Color3.fromRGB(255, 100, 255), Secondary = Color3.fromRGB(255, 180, 255), Icon = "📦" },
	["MYSTERY_BOX_7"] = { Primary = Color3.fromRGB(255, 50, 50), Secondary = Color3.fromRGB(255, 150, 150), Icon = "📦" },
	["DEFAULT"] = { Primary = Color3.fromRGB(200, 200, 200), Secondary = Color3.fromRGB(255, 255, 255), Icon = "❓" },
}

--------------------------------------------------------------------------------
-- RESPONSIVE UI CONFIGURATION
--------------------------------------------------------------------------------

-- Desktop config (default)
local UI_CONFIG_DESKTOP = {
	ContainerWidth = 320,
	ContainerHeight = 145,
	ContainerExpandedWidth = 340,
	ContainerExpandedHeight = 155,
	CornerRadius = 16,
	StrokeThickness = 3,

	HeaderTextSize = 18,
	HeaderHeight = 30,
	HeaderPaddingTop = 12,

	IconSize = 50,
	IconExpandedSize = 58,
	IconTextSize = 28,
	IconPaddingTop = 48,
	IconStrokeThickness = 2,

	NameTextSize = 24,
	NameHeight = 30,
	NamePaddingTop = 105,

	PositionY = 0.4, -- Vertical position on screen
}

-- Tablet config (medium screens)
local UI_CONFIG_TABLET = {
	ContainerWidth = 240,
	ContainerHeight = 110,
	ContainerExpandedWidth = 252,
	ContainerExpandedHeight = 116,
	CornerRadius = 12,
	StrokeThickness = 2,

	HeaderTextSize = 13,
	HeaderHeight = 22,
	HeaderPaddingTop = 8,

	IconSize = 36,
	IconExpandedSize = 42,
	IconTextSize = 20,
	IconPaddingTop = 34,
	IconStrokeThickness = 2,

	NameTextSize = 18,
	NameHeight = 24,
	NamePaddingTop = 76,

	PositionY = 0.32,
}

-- Mobile config (very compact for small screens)
local UI_CONFIG_MOBILE = {
	ContainerWidth = 160,
	ContainerHeight = 75,
	ContainerExpandedWidth = 168,
	ContainerExpandedHeight = 80,
	CornerRadius = 8,
	StrokeThickness = 2,

	HeaderTextSize = 9,
	HeaderHeight = 14,
	HeaderPaddingTop = 6,

	IconSize = 22,
	IconExpandedSize = 26,
	IconTextSize = 12,
	IconPaddingTop = 22,
	IconStrokeThickness = 1,

	NameTextSize = 11,
	NameHeight = 16,
	NamePaddingTop = 50,

	PositionY = 0.22, -- Much higher on mobile
}

-- Active config
local UI_CONFIG = UI_CONFIG_DESKTOP
local CurrentDeviceType = "Desktop"

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local IsInitialized = false
local ScreenGui: ScreenGui? = nil
local IsShowingPopup = false
local PopupQueue: {string} = {}
local RecentlyShown: {[string]: number} = {}
local DUPLICATE_COOLDOWN = 2

--------------------------------------------------------------------------------
-- DEVICE DETECTION
--------------------------------------------------------------------------------

local function DetectDeviceType(): string
	local isTouchDevice = UserInputService.TouchEnabled
	local camera = workspace.CurrentCamera
	if not camera then return "Desktop" end

	local viewportSize = camera.ViewportSize
	local screenHeight = viewportSize.Y
	local screenWidth = viewportSize.X
	local aspectRatio = screenWidth / screenHeight

	if isTouchDevice then
		if screenHeight < 500 or (screenHeight < 700 and aspectRatio > 1.8) then
			return "Mobile"
		elseif screenHeight < 900 then
			return "Tablet"
		else
			return "Tablet"
		end
	else
		if screenHeight < 600 then
			return "Mobile"
		elseif screenHeight < 900 then
			return "Tablet"
		else
			return "Desktop"
		end
	end
end

local function GetConfigForDevice(deviceType: string)
	if deviceType == "Mobile" then
		return UI_CONFIG_MOBILE
	elseif deviceType == "Tablet" then
		return UI_CONFIG_TABLET
	else
		return UI_CONFIG_DESKTOP
	end
end

local function UpdateDeviceConfig()
	local newDeviceType = DetectDeviceType()
	CurrentDeviceType = newDeviceType
	UI_CONFIG = GetConfigForDevice(newDeviceType)
	return newDeviceType
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function GetOreTheme(oreId: string): {Primary: Color3, Secondary: Color3, Icon: string}
	local upperName = string.upper(oreId or "")
	if ORE_POPUP_THEMES[upperName] then return ORE_POPUP_THEMES[upperName] end
	for key, theme in pairs(ORE_POPUP_THEMES) do
		if string.find(upperName, key) then return theme end
	end
	return ORE_POPUP_THEMES["DEFAULT"]
end

local function GetDisplayName(oreId: string): string
	for _, layer in pairs(GameConfig.Layers) do
		for _, block in pairs(layer.Blocks) do
			if block.Id == oreId then return block.Name end
		end
	end
	local name = oreId:gsub("_", " ")
	name = name:gsub("(%a)([%w]*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
	return name
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function CreateScreenGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "OreDiscoveryUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui
	ScreenGui = gui
	return gui
end

local function ShowDiscoveryPopup(oreId: string)
	if not ScreenGui then return end

	-- Update config for current device
	UpdateDeviceConfig()

	IsShowingPopup = true

	local theme = GetOreTheme(oreId)
	local displayName = GetDisplayName(oreId)
	local config = UI_CONFIG

	-- Main container
	local container = Instance.new("Frame")
	container.Name = "DiscoveryContainer"
	container.Size = UDim2.new(0, 0, 0, 0)
	container.Position = UDim2.new(0.5, 0, config.PositionY, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = ScreenGui

	Instance.new("UICorner", container).CornerRadius = UDim.new(0, config.CornerRadius)

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.Primary
	stroke.Thickness = config.StrokeThickness
	stroke.Parent = container

	local bgGradient = Instance.new("UIGradient")
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 18, 28)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 35, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 18, 28)),
	})
	bgGradient.Rotation = 45
	bgGradient.Parent = container

	-- Header
	local headerLabel = Instance.new("TextLabel")
	headerLabel.Name = "Header"
	headerLabel.Size = UDim2.new(1, 0, 0, config.HeaderHeight)
	headerLabel.Position = UDim2.new(0, 0, 0, config.HeaderPaddingTop)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = "✨ NEW ORE DISCOVERED! ✨"
	headerLabel.TextColor3 = theme.Secondary
	headerLabel.TextSize = config.HeaderTextSize
	headerLabel.Font = Enum.Font.GothamBlack
	headerLabel.TextScaled = CurrentDeviceType == "Mobile" -- Scale on mobile
	headerLabel.Parent = container

	local headerGradient = Instance.new("UIGradient")
	headerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.Primary),
		ColorSequenceKeypoint.new(0.5, theme.Secondary),
		ColorSequenceKeypoint.new(1, theme.Primary),
	})
	headerGradient.Parent = headerLabel

	-- Icon frame
	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.new(0, 0, 0, 0)
	iconFrame.Position = UDim2.new(0.5, 0, 0, config.IconPaddingTop)
	iconFrame.AnchorPoint = Vector2.new(0.5, 0)
	iconFrame.BackgroundColor3 = theme.Primary
	iconFrame.BackgroundTransparency = 0.5
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = container
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(1, 0)

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = theme.Secondary
	iconStroke.Thickness = config.IconStrokeThickness
	iconStroke.Parent = iconFrame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = theme.Icon
	iconLabel.TextSize = config.IconTextSize
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextScaled = true
	iconLabel.Parent = iconFrame

	-- Ore name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "OreName"
	nameLabel.Size = UDim2.new(1, -20, 0, config.NameHeight)
	nameLabel.Position = UDim2.new(0.5, 0, 0, config.NamePaddingTop)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = string.upper(displayName)
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextSize = config.NameTextSize
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextScaled = true -- Always scale name to fit
	nameLabel.Parent = container

	-- Add text size constraint for name
	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = config.NameTextSize
	nameConstraint.MinTextSize = math.floor(config.NameTextSize * 0.6)
	nameConstraint.Parent = nameLabel

	local nameGradient = Instance.new("UIGradient")
	nameGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.Primary),
		ColorSequenceKeypoint.new(0.5, theme.Secondary),
		ColorSequenceKeypoint.new(1, theme.Primary),
	})
	nameGradient.Parent = nameLabel

	-- Gradient animation
	local animConnection
	animConnection = RunService.RenderStepped:Connect(function()
		if not container.Parent then
			animConnection:Disconnect()
			return
		end
		local t = tick()
		nameGradient.Offset = Vector2.new(math.sin(t * 3) * 0.3, 0)
		headerGradient.Offset = Vector2.new(math.sin(t * 4) * 0.4, 0)
		bgGradient.Offset = Vector2.new(math.sin(t * 2) * 0.15, 0)
	end)

	-- ============ SNAPPY POP IN ============
	local popIn = TweenService:Create(container, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, config.ContainerWidth, 0, config.ContainerHeight)
	})
	popIn:Play()

	-- Icon bounce in
	task.delay(0.1, function()
		if iconFrame.Parent then
			TweenService:Create(iconFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, config.IconSize, 0, config.IconSize)
			}):Play()
		end
	end)

	-- Single quick pulse
	task.delay(0.35, function()
		if iconFrame.Parent then
			TweenService:Create(iconFrame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, config.IconExpandedSize, 0, config.IconExpandedSize)
			}):Play()
			task.wait(0.08)
			if iconFrame.Parent then
				TweenService:Create(iconFrame, TweenInfo.new(0.12, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
					Size = UDim2.new(0, config.IconSize, 0, config.IconSize)
				}):Play()
			end
		end
	end)

	-- ============ BUBBLY POP OUT ============
	task.delay(1.2, function()
		if not container.Parent then return end

		-- Scale up slightly
		local scaleUp = TweenService:Create(container, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, config.ContainerExpandedWidth, 0, config.ContainerExpandedHeight)
		})
		scaleUp:Play()

		scaleUp.Completed:Connect(function()
			if not container.Parent then return end

			-- Pop out
			local popOut = TweenService:Create(container, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1
			})
			popOut:Play()

			TweenService:Create(stroke, TweenInfo.new(0.12), {Transparency = 1}):Play()

			popOut.Completed:Connect(function()
				animConnection:Disconnect()
				container:Destroy()
				IsShowingPopup = false

				if #PopupQueue > 0 then
					local next = table.remove(PopupQueue, 1)
					task.wait(0.12)
					ShowDiscoveryPopup(next)
				end
			end)
		end)
	end)

	print(`[OreDiscoveryPopup] Showing: {displayName} (Device: {CurrentDeviceType})`)
end

--------------------------------------------------------------------------------
-- RESPONSIVE LISTENER
--------------------------------------------------------------------------------

local function SetupResponsiveListener()
	if not workspace.CurrentCamera then return end

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local newType = DetectDeviceType()
		if newType ~= CurrentDeviceType then
			CurrentDeviceType = newType
			UI_CONFIG = GetConfigForDevice(newType)
			print(`[OreDiscoveryPopup] Device changed to: {newType}`)
		end
	end)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function OreDiscoveryPopup.Initialize()
	if IsInitialized then return end
	IsInitialized = true
	UpdateDeviceConfig()
	CreateScreenGui()
	SetupResponsiveListener()
	print(`[OreDiscoveryPopup] Initialized - Device: {CurrentDeviceType}`)
end

function OreDiscoveryPopup.Show(oreId: string)
	if not IsInitialized then
		OreDiscoveryPopup.Initialize()
	end

	-- Prevent duplicates
	local now = tick()
	if RecentlyShown[oreId] and (now - RecentlyShown[oreId]) < DUPLICATE_COOLDOWN then
		print(`[OreDiscoveryPopup] Skipping duplicate: {oreId}`)
		return
	end
	RecentlyShown[oreId] = now

	-- Cleanup old entries
	for id, time in pairs(RecentlyShown) do
		if (now - time) > DUPLICATE_COOLDOWN * 2 then
			RecentlyShown[id] = nil
		end
	end

	if IsShowingPopup then
		for _, queued in ipairs(PopupQueue) do
			if queued == oreId then return end
		end
		table.insert(PopupQueue, oreId)
	else
		ShowDiscoveryPopup(oreId)
	end
end

function OreDiscoveryPopup.SetTheme(oreId: string, theme: {Primary: Color3, Secondary: Color3, Icon: string})
	ORE_POPUP_THEMES[string.upper(oreId)] = theme
end

function OreDiscoveryPopup.GetDeviceType(): string
	return CurrentDeviceType
end

return OreDiscoveryPopup
