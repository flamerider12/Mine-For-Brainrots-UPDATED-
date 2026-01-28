--!strict
--[[
	LayerProgressController.lua
	UPDATED: Responsive scaling for mobile and desktop devices
	Fixes UI going off screen on mobile by detecting device type and scaling appropriately
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local LayerProgressController = {}

-- CONFIG
local LAYERS_PER_PAGE = 4 
local PAGE_STRIDE = LAYERS_PER_PAGE - 1 
local LOCK_ICON_ASSET = "rbxassetid://13476648701"
local TOOLTIP_OFFSET_PUSHED = -90
local TOOLTIP_OFFSET_SNUG = -50
local PUSHER_THRESHOLD = 50

local LAYER_ICONS = {
	[1] = "rbxassetid://130149584036149", [2] = "rbxassetid://82634535092012",
	[3] = "rbxassetid://86686659615218", [4] = "rbxassetid://120731916075931",
	[5] = "rbxassetid://0", [6] = "rbxassetid://0", [7] = "rbxassetid://0",
}
local LAYER_EMOJI = {[1]="🌱",[2]="🪨",[3]="⛏️",[4]="🌑",[5]="🔥",[6]="⚡",[7]="💀"}
local LAYER_ORES = {
	[1]="Dirt, Stone, Coal",[2]="Stone, Iron, Copper",[3]="Iron, Gold, Diamond",
	[4]="Obsidian, Emerald, Mithril",[5]="Magma Rock, Ruby, Titanium",
	[6]="Electrum, Cobalt, Uranium",[7]="Void Stone, Onyx, Soul Gem",
}
local LAYER_THEMES = {
	[1]={Primary=Color3.fromRGB(100,200,80),Glow=Color3.fromRGB(180,255,160),Dark=Color3.fromRGB(35,70,25)},
	[2]={Primary=Color3.fromRGB(140,140,150),Glow=Color3.fromRGB(220,220,240),Dark=Color3.fromRGB(50,50,60)},
	[3]={Primary=Color3.fromRGB(190,140,100),Glow=Color3.fromRGB(255,210,160),Dark=Color3.fromRGB(70,50,30)},
	[4]={Primary=Color3.fromRGB(80,100,160),Glow=Color3.fromRGB(150,180,255),Dark=Color3.fromRGB(20,25,45)},
	[5]={Primary=Color3.fromRGB(255,120,40),Glow=Color3.fromRGB(255,200,100),Dark=Color3.fromRGB(90,25,5)},
	[6]={Primary=Color3.fromRGB(0,255,200),Glow=Color3.fromRGB(150,255,240),Dark=Color3.fromRGB(5,50,45)},
	[7]={Primary=Color3.fromRGB(255,50,50),Glow=Color3.fromRGB(255,150,150),Dark=Color3.fromRGB(70,10,10)},
}

--------------------------------------------------------------------------------
-- RESPONSIVE UI CONFIG SYSTEM
--------------------------------------------------------------------------------

-- Desktop base config
local UI_CONFIG_DESKTOP = {
	ContainerWidth = 180,
	ContainerPadding = 30,
	CircleSize = 80,
	CircleSizeActive = 100,
	CircleSpacing = 120,
	AvatarSize = 48,
	LineWidth = 32,
	ScreenMarginRight = 25,
	ScreenMarginTop = 50,
	TitleSize = 16,
	TitleHeight = 28,
	LayerNameSize = 11,
	LayerNameHeight = 16,
	BadgeSize = 24,
	BadgeFontSize = 12,
	EmojiSize = 32,
	DepthBranchWidth = 40,
	DepthBranchHeight = 10,
	DepthTagWidth = 70,
	DepthTagHeight = 20,
	DepthFontSize = 12,
	TooltipWidth = 160,
	TooltipHeight = 60,
	TooltipTitleSize = 14,
	TooltipBodySize = 12,
	StrokeThickness = 6,
	StrokeThicknessActive = 8,
	StrokeThicknessPulse = 12,
}

-- Mobile config (compact layout for smaller screens)
local UI_CONFIG_MOBILE = {
	ContainerWidth = 100,
	ContainerPadding = 12,
	CircleSize = 44,
	CircleSizeActive = 54,
	CircleSpacing = 55,
	AvatarSize = 28,
	LineWidth = 16,
	ScreenMarginRight = 8,
	ScreenMarginTop = 80, -- Account for top UI elements on mobile
	TitleSize = 11,
	TitleHeight = 20,
	LayerNameSize = 8,
	LayerNameHeight = 12,
	BadgeSize = 16,
	BadgeFontSize = 9,
	EmojiSize = 18,
	DepthBranchWidth = 25,
	DepthBranchHeight = 6,
	DepthTagWidth = 45,
	DepthTagHeight = 14,
	DepthFontSize = 9,
	TooltipWidth = 120,
	TooltipHeight = 50,
	TooltipTitleSize = 11,
	TooltipBodySize = 10,
	StrokeThickness = 4,
	StrokeThicknessActive = 5,
	StrokeThicknessPulse = 8,
}

-- Tablet config (medium screens)
local UI_CONFIG_TABLET = {
	ContainerWidth = 140,
	ContainerPadding = 20,
	CircleSize = 60,
	CircleSizeActive = 75,
	CircleSpacing = 85,
	AvatarSize = 36,
	LineWidth = 24,
	ScreenMarginRight = 15,
	ScreenMarginTop = 60,
	TitleSize = 14,
	TitleHeight = 24,
	LayerNameSize = 10,
	LayerNameHeight = 14,
	BadgeSize = 20,
	BadgeFontSize = 10,
	EmojiSize = 26,
	DepthBranchWidth = 32,
	DepthBranchHeight = 8,
	DepthTagWidth = 58,
	DepthTagHeight = 17,
	DepthFontSize = 10,
	TooltipWidth = 140,
	TooltipHeight = 55,
	TooltipTitleSize = 12,
	TooltipBodySize = 11,
	StrokeThickness = 5,
	StrokeThicknessActive = 6,
	StrokeThicknessPulse = 10,
}

-- Active config (determined at runtime)
local UI_CONFIG = UI_CONFIG_DESKTOP
local CurrentDeviceType = "Desktop" -- "Desktop", "Tablet", "Mobile"
local CurrentScale = 1

local BLOCK_SIZE = GameConfig.Mine.BlockSize

-- STATE
local IsInitialized = false
local IsTransitioning = false
local TotalLayers = 7
local CurrentLayerIndex = 1
local MaxLayerReached = 1 
local CurrentDepth = 0
local CurrentPage = 1
local ActiveAvatarTween: Tween? = nil
local ActiveLineTween: Tween? = nil

-- UI References
local ScreenGui, MainContainer, MainUIScale, ProgressLineBack, ProgressLineFill
local AvatarFrame, AvatarImage, TooltipFrame, TooltipTitle, TooltipBody
local LayerCircles = {}
local LayerCircleImages = {}
local DepthLabel, LayerNameLabel
local ActiveSpinConnection
local DataLoadedRemote, DataUpdatedRemote

--------------------------------------------------------------------------------
-- DEVICE DETECTION AND SCALING
--------------------------------------------------------------------------------

local function DetectDeviceType(): string
	-- Check for touch capability (mobile/tablet)
	local isTouchDevice = UserInputService.TouchEnabled

	-- Get viewport size
	local camera = workspace.CurrentCamera
	if not camera then return "Desktop" end

	local viewportSize = camera.ViewportSize
	local screenHeight = viewportSize.Y
	local screenWidth = viewportSize.X
	local aspectRatio = screenWidth / screenHeight

	-- Get safe area insets (for notches, etc.)
	local insetTop = GuiService:GetGuiInset().Y

	-- Determine device type based on multiple factors
	if isTouchDevice then
		-- Mobile phones typically have height < 500 in landscape or < 900 in portrait
		-- and aspect ratios > 1.7 in landscape
		if screenHeight < 500 or (screenHeight < 700 and aspectRatio > 1.8) then
			return "Mobile"
		elseif screenHeight < 900 then
			return "Tablet"
		else
			-- Large tablet or desktop with touch
			return "Tablet"
		end
	else
		-- Non-touch device
		if screenHeight < 600 then
			return "Mobile" -- Small window
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

local function CalculateAdaptiveScale(): number
	local camera = workspace.CurrentCamera
	if not camera then return 1 end

	local viewportSize = camera.ViewportSize
	local screenHeight = viewportSize.Y

	-- Calculate how much space we need vs how much we have
	local config = UI_CONFIG
	local headerHeight = config.TitleHeight + config.LayerNameHeight + 10
	local circlesHeight = config.CircleSize * LAYERS_PER_PAGE + config.CircleSpacing * (LAYERS_PER_PAGE - 1)
	local totalNeededHeight = headerHeight + circlesHeight + config.ContainerPadding * 2 + config.ScreenMarginTop

	-- Available height (accounting for safe areas)
	local safeInset = GuiService:GetGuiInset().Y
	local availableHeight = screenHeight - safeInset - 20 -- 20px bottom margin

	-- Calculate scale to fit
	local fitScale = availableHeight / totalNeededHeight

	-- Clamp scale between reasonable bounds
	local minScale = 0.5
	local maxScale = 1.2

	return math.clamp(fitScale, minScale, maxScale)
end

local function UpdateDeviceConfig()
	local newDeviceType = DetectDeviceType()
	local configChanged = newDeviceType ~= CurrentDeviceType

	CurrentDeviceType = newDeviceType
	UI_CONFIG = GetConfigForDevice(newDeviceType)
	CurrentScale = CalculateAdaptiveScale()

	if MainUIScale then
		MainUIScale.Scale = CurrentScale
	end

	return configChanged
end

local function GetScaledValue(baseValue: number): number
	return baseValue -- Scale is applied via UIScale, so return raw values
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function GetPageForLayer(idx)
	if idx <= 1 then return 1 end
	return math.floor((idx-1)/PAGE_STRIDE)+1
end

local function GetLayersOnPage(page)
	local s = (page-1)*PAGE_STRIDE+1
	local e = math.min(s+LAYERS_PER_PAGE-1, TotalLayers)
	return s, e
end

local function GetRelativeIndex(idx, page)
	local s = GetLayersOnPage(page)
	return idx - s + 1
end

local function GetCircleYPosition(relIdx)
	local cs = UI_CONFIG.CircleSize
	local sp = UI_CONFIG.CircleSpacing
	local pd = UI_CONFIG.ContainerPadding
	local headerOffset = UI_CONFIG.TitleHeight + UI_CONFIG.LayerNameHeight + 10
	local lineStartY = pd + headerOffset
	local firstY = lineStartY + cs/2
	return firstY + (relIdx-1)*(cs+sp)
end

local function GetLayerDepthRange(idx)
	local cur = GameConfig.Layers[idx]
	local nxt = GameConfig.Layers[idx+1]
	if not cur then return 0, 50 end
	local startD = cur.DepthStart
	local endD = nxt and nxt.DepthStart or (startD+300)
	return startD, endD
end

local function GetLayerFromDepth(depthM)
	local depthS = depthM * BLOCK_SIZE
	for i = #GameConfig.Layers, 1, -1 do
		if depthS >= GameConfig.Layers[i].DepthStart then return i end
	end
	return 1
end

local function CalculateLayerProgress(depthM, idx)
	local depthS = depthM * BLOCK_SIZE
	local startD, endD = GetLayerDepthRange(idx)
	local range = endD - startD
	if range <= 0 then return 0 end
	return math.clamp((depthS-startD)/range, 0, 1)
end

--------------------------------------------------------------------------------
-- LOCK STATE
--------------------------------------------------------------------------------

local function UpdateCircleLockState(idx, circle)
	local unlocked = idx <= MaxLayerReached
	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
	local bg = circle:FindFirstChild("CircleBackground")
	local inner = bg and bg:FindFirstChild("InnerCircle")
	local badge = circle:FindFirstChild("LayerBadge")
	local lock = circle:FindFirstChild("LockOverlay")

	if unlocked then
		if bg then bg.BackgroundColor3 = theme.Dark end
		if inner then inner.BackgroundColor3 = theme.Dark end
		if badge then badge.BackgroundColor3 = theme.Primary; badge.Visible = true end
		if lock then lock.Visible = false end
		local icon = inner and inner:FindFirstChild("LayerIcon")
		local emoji = inner and inner:FindFirstChild("EmojiIcon")
		if icon then icon.ImageTransparency = 0 end
		if emoji then emoji.TextTransparency = 0 end
	else
		local locked = Color3.fromRGB(25,25,30)
		if bg then bg.BackgroundColor3 = locked end
		if inner then inner.BackgroundColor3 = locked end
		if badge then badge.BackgroundColor3 = Color3.fromRGB(60,60,60) end
		if lock then lock.Visible=true; lock.ImageTransparency=0; lock.Size=UDim2.new(0.7,0,0.7,0) end
		local icon = inner and inner:FindFirstChild("LayerIcon")
		local emoji = inner and inner:FindFirstChild("EmojiIcon")
		if icon then icon.ImageTransparency = 0.8 end
		if emoji then emoji.TextTransparency = 0.8 end
	end
end

local function RefreshAllCircleLockStates()
	for idx, c in pairs(LayerCircles) do UpdateCircleLockState(idx, c) end
end

local function PlayUnlockAnimation(idx)
	local circle = LayerCircles[idx]
	if not circle then return end
	local lock = circle:FindFirstChild("LockOverlay")
	if not lock or not lock.Visible then return end
	task.spawn(function()
		for i=1,6 do lock.Rotation=(i%2==0)and 10 or -10; task.wait(0.05) end
		lock.Rotation=0
		TweenService:Create(lock,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.new(1.5,0,1.5,0),ImageTransparency=1,Rotation=math.random(-45,45)}):Play()
		task.wait(0.4)
		lock.Visible=false; lock.Size=UDim2.new(0.7,0,0.7,0); lock.ImageTransparency=0
		local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
		local bg = circle:FindFirstChild("CircleBackground")
		local inner = bg and bg:FindFirstChild("InnerCircle")
		local icon = inner and inner:FindFirstChild("LayerIcon")
		if bg then TweenService:Create(bg,TweenInfo.new(0.5),{BackgroundColor3=theme.Dark}):Play() end
		if inner then TweenService:Create(inner,TweenInfo.new(0.5),{BackgroundColor3=theme.Dark}):Play() end
		if icon then TweenService:Create(icon,TweenInfo.new(0.5),{ImageTransparency=0}):Play() end
	end)
end

--------------------------------------------------------------------------------
-- TOOLTIP
--------------------------------------------------------------------------------

local function ShowTooltip(idx, circleFrame)
	if not TooltipFrame or not TooltipTitle or not TooltipBody then return end

	-- Hide tooltip on mobile to save space
	if CurrentDeviceType == "Mobile" then return end

	local unlocked = idx <= MaxLayerReached
	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
	if unlocked then
		local ld = GameConfig.Layers[idx]
		TooltipTitle.Text = string.upper(ld and ld.LayerName or "Layer "..idx)
		TooltipTitle.TextColor3 = theme.Glow
		TooltipBody.Text = LAYER_ORES[idx] or "No ores data."
		TooltipBody.TextColor3 = Color3.fromRGB(200,200,200)
	else
		TooltipTitle.Text = "???"
		TooltipTitle.TextColor3 = Color3.fromRGB(150,150,150)
		TooltipBody.Text = "Undiscovered"
		TooltipBody.TextColor3 = Color3.fromRGB(100,100,100)
	end
	local offset = TOOLTIP_OFFSET_SNUG
	if AvatarFrame and AvatarFrame.Visible then
		if math.abs(AvatarFrame.AbsolutePosition.Y - circleFrame.AbsolutePosition.Y) < PUSHER_THRESHOLD then
			offset = TOOLTIP_OFFSET_PUSHED
		end
	end
	TooltipFrame.Position = UDim2.new(0, offset, 0, circleFrame.Position.Y.Offset)
	TooltipFrame.Visible = true
	TooltipFrame.GroupTransparency = 1
	TweenService:Create(TooltipFrame, TweenInfo.new(0.2), {GroupTransparency=0}):Play()
end

local function HideTooltip()
	if TooltipFrame then TooltipFrame.Visible = false end
end

--------------------------------------------------------------------------------
-- CREATE CIRCLE
--------------------------------------------------------------------------------

local function CreateLayerCircle(idx, yPos)
	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
	local cs = UI_CONFIG.CircleSize

	local container = Instance.new("Frame")
	container.Name = "LayerCircle_"..idx
	container.Size = UDim2.new(0,cs,0,cs)
	container.Position = UDim2.new(0.5,0,0,yPos)
	container.AnchorPoint = Vector2.new(0.5,0.5)
	container.BackgroundTransparency = 1
	container.ZIndex = 10
	container.MouseEnter:Connect(function() ShowTooltip(idx,container) end)
	container.MouseLeave:Connect(function() HideTooltip() end)

	local bg = Instance.new("Frame")
	bg.Name="CircleBackground"; bg.Size=UDim2.new(1,0,1,0); bg.Position=UDim2.new(0.5,0,0.5,0)
	bg.AnchorPoint=Vector2.new(0.5,0.5); bg.BackgroundColor3=theme.Dark; bg.BorderSizePixel=0; bg.ZIndex=11
	bg.Parent=container
	Instance.new("UICorner",bg).CornerRadius=UDim.new(1,0)

	local inner = Instance.new("Frame")
	inner.Name="InnerCircle"; inner.Size=UDim2.new(1,0,1,0); inner.Position=UDim2.new(0.5,0,0.5,0)
	inner.AnchorPoint=Vector2.new(0.5,0.5); inner.BackgroundColor3=theme.Dark; inner.BorderSizePixel=0
	inner.ZIndex=12; inner.ClipsDescendants=true; inner.Parent=bg
	Instance.new("UICorner",inner).CornerRadius=UDim.new(1,0)

	local icon = Instance.new("ImageLabel")
	icon.Name="LayerIcon"; icon.Size=UDim2.new(1,0,1,0); icon.Position=UDim2.new(0.5,0,0.5,0)
	icon.AnchorPoint=Vector2.new(0.5,0.5); icon.BackgroundTransparency=1; icon.ZIndex=13; icon.Parent=inner
	Instance.new("UICorner",icon).CornerRadius=UDim.new(1,0)

	local asset = LAYER_ICONS[idx]
	if asset and asset ~= "rbxassetid://0" and asset ~= "" then
		icon.Image = asset; icon.ScaleType = Enum.ScaleType.Stretch
	else
		icon.Visible = false
		local emoji = Instance.new("TextLabel")
		emoji.Name="EmojiIcon"; emoji.Size=UDim2.new(1,0,1,0); emoji.Position=UDim2.new(0.5,0,0.5,0)
		emoji.AnchorPoint=Vector2.new(0.5,0.5); emoji.BackgroundTransparency=1
		emoji.Text=LAYER_EMOJI[idx] or "?"; emoji.TextSize=UI_CONFIG.EmojiSize
		emoji.Font=Enum.Font.GothamBold; emoji.TextColor3=Color3.new(1,1,1); emoji.ZIndex=13
		emoji.TextScaled=true
		emoji.Parent=inner
	end

	local lock = Instance.new("ImageLabel")
	lock.Name="LockOverlay"; lock.Size=UDim2.new(0.7,0,0.7,0); lock.Position=UDim2.new(0.5,0,0.5,0)
	lock.AnchorPoint=Vector2.new(0.5,0.5); lock.BackgroundTransparency=1; lock.Image=LOCK_ICON_ASSET
	lock.ImageColor3=Color3.fromRGB(200,200,200); lock.ScaleType=Enum.ScaleType.Fit
	lock.Visible=false; lock.ZIndex=20; lock.Parent=container

	local border = Instance.new("Frame")
	border.Name="BorderFrame"; border.Size=UDim2.new(1,0,1,0); border.Position=UDim2.new(0.5,0,0.5,0)
	border.AnchorPoint=Vector2.new(0.5,0.5); border.BackgroundTransparency=1; border.ZIndex=14
	border.Parent=container
	Instance.new("UICorner",border).CornerRadius=UDim.new(1,0)

	local stroke = Instance.new("UIStroke")
	stroke.Name="CircleStroke"; stroke.Color=Color3.new(1,1,1); stroke.Thickness=UI_CONFIG.StrokeThickness
	stroke.Transparency=0; stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke.Parent=border

	local grad = Instance.new("UIGradient")
	grad.Name="StrokeGradient"; grad.Rotation=45
	grad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,theme.Primary),ColorSequenceKeypoint.new(0.5,theme.Glow),ColorSequenceKeypoint.new(1,theme.Primary)})
	grad.Parent=stroke

	local badge = Instance.new("Frame")
	badge.Name="LayerBadge"; badge.Size=UDim2.new(0,UI_CONFIG.BadgeSize,0,UI_CONFIG.BadgeSize)
	badge.Position=UDim2.new(1,-2,0,2); badge.AnchorPoint=Vector2.new(0.5,0.5)
	badge.BackgroundColor3=theme.Primary; badge.BorderSizePixel=0; badge.ZIndex=15; badge.Parent=container
	Instance.new("UICorner",badge).CornerRadius=UDim.new(1,0)
	local bs = Instance.new("UIStroke"); bs.Color=Color3.new(1,1,1); bs.Thickness=2; bs.Parent=badge
	local bt = Instance.new("TextLabel")
	bt.Name="BadgeNumber"; bt.Size=UDim2.new(1,0,1,0); bt.BackgroundTransparency=1
	bt.Text=tostring(idx); bt.TextColor3=Color3.new(1,1,1); bt.TextSize=UI_CONFIG.BadgeFontSize
	bt.Font=Enum.Font.GothamBlack; bt.ZIndex=16; bt.TextScaled=true; bt.Parent=badge

	LayerCircleImages[idx] = icon
	UpdateCircleLockState(idx, container)
	return container
end

--------------------------------------------------------------------------------
-- BUILD PAGE
--------------------------------------------------------------------------------

local function BuildPageContent(pageIdx)
	if not MainContainer then return end
	for _,c in pairs(MainContainer:GetChildren()) do
		if c.Name:find("LayerCircle") or c.Name:find("ProgressLineBack") or c.Name:find("AvatarContainer") then c:Destroy() end
	end
	LayerCircles = {}; LayerCircleImages = {}

	local sL, eL = GetLayersOnPage(pageIdx)
	local count = eL - sL + 1
	local cs = UI_CONFIG.CircleSize
	local sp = UI_CONFIG.CircleSpacing
	local pd = UI_CONFIG.ContainerPadding
	local headerOffset = UI_CONFIG.TitleHeight + UI_CONFIG.LayerNameHeight + 10
	local totalH = pd*2 + cs*LAYERS_PER_PAGE + sp*(LAYERS_PER_PAGE-1) + headerOffset + 10
	MainContainer.Size = UDim2.new(0, UI_CONFIG.ContainerWidth, 0, totalH)

	local lineStartY = pd + headerOffset
	local firstY = lineStartY + cs/2
	local lastY = firstY + (count-1)*(cs+sp)
	local lineH = lastY - firstY

	-- Progress line back
	local lineBack = Instance.new("Frame")
	lineBack.Name="ProgressLineBack"; lineBack.Size=UDim2.new(0,UI_CONFIG.LineWidth,0,lineH)
	lineBack.Position=UDim2.new(0.5,0,0,firstY); lineBack.AnchorPoint=Vector2.new(0.5,0)
	lineBack.BackgroundColor3=Color3.fromRGB(15,18,25); lineBack.BorderSizePixel=0; lineBack.ZIndex=3
	lineBack.Parent=MainContainer
	ProgressLineBack = lineBack
	Instance.new("UICorner",lineBack).CornerRadius=UDim.new(0.3,0)
	local lbs1=Instance.new("UIStroke"); lbs1.Color=Color3.fromRGB(255,255,255); lbs1.Transparency=0.7; lbs1.Thickness=2; lbs1.Parent=lineBack
	local lbs2=Instance.new("UIStroke"); lbs2.Color=Color3.fromRGB(0,0,0); lbs2.Transparency=0.4; lbs2.Thickness=4; lbs2.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; lbs2.Parent=lineBack
	local lg=Instance.new("UIGradient"); lg.Rotation=90
	lg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(10,12,18)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(25,30,45)),ColorSequenceKeypoint.new(1,Color3.fromRGB(10,12,18))})
	lg.Parent=lineBack

	-- Progress fill
	local lineFill = Instance.new("Frame")
	lineFill.Name="ProgressLineFill"; lineFill.Size=UDim2.new(1,-8,0,0)
	lineFill.Position=UDim2.new(0.5,0,0,0); lineFill.AnchorPoint=Vector2.new(0.5,0)
	lineFill.BackgroundColor3=Color3.fromRGB(255,255,255); lineFill.BorderSizePixel=0; lineFill.ZIndex=4
	lineFill.Parent=lineBack
	ProgressLineFill = lineFill
	Instance.new("UICorner",lineFill).CornerRadius=UDim.new(0.3,0)
	local fs=Instance.new("UIStroke"); fs.Name="FillStroke"; fs.Color=LAYER_THEMES[sL].Glow; fs.Thickness=2; fs.Transparency=0.2; fs.Parent=lineFill
	local fg=Instance.new("UIGradient"); fg.Name="FillGradient"; fg.Rotation=0
	local th=LAYER_THEMES[sL]
	fg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,th.Dark),ColorSequenceKeypoint.new(0.5,th.Primary),ColorSequenceKeypoint.new(1,th.Dark)})
	fg.Parent=lineFill

	-- Circles
	for i=sL,eL do
		local rel = GetRelativeIndex(i, pageIdx)
		local yp = firstY + (rel-1)*(cs+sp)
		local c = CreateLayerCircle(i, yp)
		c.Parent = MainContainer
		LayerCircles[i] = c
	end

	-- Avatar
	local avs = UI_CONFIG.AvatarSize
	local av = Instance.new("Frame")
	av.Name="AvatarContainer"; av.Size=UDim2.new(0,avs,0,avs); av.Position=UDim2.new(0.5,0,0,firstY)
	av.AnchorPoint=Vector2.new(0.5,0.5); av.BackgroundColor3=Color3.fromRGB(35,40,55); av.BorderSizePixel=0; av.ZIndex=25
	av.Parent=MainContainer
	AvatarFrame = av
	Instance.new("UICorner",av).CornerRadius=UDim.new(1,0)
	local avst=Instance.new("UIStroke"); avst.Name="AvatarStroke"; avst.Color=Color3.fromRGB(255,255,255); avst.Thickness=math.max(2, UI_CONFIG.StrokeThickness - 2); avst.Parent=av
	local avi=Instance.new("ImageLabel")
	avi.Name="AvatarImage"; avi.Size=UDim2.new(1,-6,1,-6); avi.Position=UDim2.new(0.5,0,0.5,0)
	avi.AnchorPoint=Vector2.new(0.5,0.5); avi.BackgroundTransparency=1; avi.Image=""; avi.ZIndex=26; avi.Parent=av
	AvatarImage = avi
	Instance.new("UICorner",avi).CornerRadius=UDim.new(1,0)

	-- Depth tag
	local dl=Instance.new("Frame"); dl.Name="DepthBranchLine"; dl.Size=UDim2.new(0,UI_CONFIG.DepthBranchWidth,0,UI_CONFIG.DepthBranchHeight)
	dl.Position=UDim2.new(0,5,0.5,0); dl.AnchorPoint=Vector2.new(1,0.5); dl.BackgroundColor3=Color3.fromRGB(255,50,50)
	dl.BorderSizePixel=0; dl.ZIndex=24; dl.Parent=av
	Instance.new("UICorner",dl).CornerRadius=UDim.new(1,0)
	local dlg=Instance.new("UIStroke"); dlg.Color=Color3.fromRGB(255,100,100); dlg.Thickness=2; dlg.Transparency=0.4; dlg.Parent=dl
	local dt=Instance.new("Frame"); dt.Name="DepthTag"; dt.Size=UDim2.new(0,UI_CONFIG.DepthTagWidth,0,UI_CONFIG.DepthTagHeight)
	dt.Position=UDim2.new(0,0,0.5,0); dt.AnchorPoint=Vector2.new(1,0.5); dt.BackgroundColor3=Color3.fromRGB(20,20,25)
	dt.BorderSizePixel=0; dt.ZIndex=24; dt.Parent=dl
	Instance.new("UICorner",dt).CornerRadius=UDim.new(1,0)
	local dts=Instance.new("UIStroke"); dts.Color=Color3.fromRGB(255,50,50); dts.Thickness=math.max(2, UI_CONFIG.StrokeThickness - 3); dts.Parent=dt
	local dtl=Instance.new("TextLabel"); dtl.Name="Value"; dtl.Size=UDim2.new(1,0,1,0); dtl.BackgroundTransparency=1
	dtl.Text="0m"; dtl.TextColor3=Color3.fromRGB(255,255,255); dtl.Font=Enum.Font.GothamBlack
	dtl.TextSize=UI_CONFIG.DepthFontSize; dtl.TextScaled=true; dtl.ZIndex=25; dtl.Parent=dt
	DepthLabel = dtl

	-- Tooltip (only on desktop/tablet)
	if CurrentDeviceType ~= "Mobile" then
		local tip=Instance.new("CanvasGroup"); tip.Name="Tooltip"; tip.Size=UDim2.new(0,UI_CONFIG.TooltipWidth,0,UI_CONFIG.TooltipHeight)
		tip.Position=UDim2.new(0,0,0,0); tip.AnchorPoint=Vector2.new(1,0.5)
		tip.BackgroundColor3=Color3.fromRGB(20,22,28); tip.BackgroundTransparency=0.1
		tip.BorderSizePixel=0; tip.Visible=false; tip.ZIndex=100; tip.Parent=MainContainer
		TooltipFrame = tip
		Instance.new("UICorner",tip).CornerRadius=UDim.new(0,8)
		local tips=Instance.new("UIStroke"); tips.Color=Color3.fromRGB(255,255,255); tips.Transparency=0.8; tips.Thickness=1; tips.Parent=tip
		local tipt=Instance.new("TextLabel"); tipt.Name="Title"; tipt.Size=UDim2.new(1,-20,0,20)
		tipt.Position=UDim2.new(0,10,0,8); tipt.BackgroundTransparency=1; tipt.Text="LAYER NAME"
		tipt.TextColor3=Color3.new(1,1,1); tipt.TextSize=UI_CONFIG.TooltipTitleSize; tipt.Font=Enum.Font.GothamBlack
		tipt.TextXAlignment=Enum.TextXAlignment.Left; tipt.Parent=tip
		TooltipTitle = tipt
		local tipb=Instance.new("TextLabel"); tipb.Name="Body"; tipb.Size=UDim2.new(1,-20,0,20)
		tipb.Position=UDim2.new(0,10,0,30); tipb.BackgroundTransparency=1; tipb.Text="Ores: ..."
		tipb.TextColor3=Color3.fromRGB(180,180,180); tipb.TextSize=UI_CONFIG.TooltipBodySize; tipb.Font=Enum.Font.GothamMedium
		tipb.TextXAlignment=Enum.TextXAlignment.Left; tipb.TextWrapped=true; tipb.Parent=tip
		TooltipBody = tipb
	end

	task.spawn(function()
		local ok, img = pcall(function() return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end)
		if ok and img and AvatarImage then AvatarImage.Image = img end
	end)
end

--------------------------------------------------------------------------------
-- CREATE UI
--------------------------------------------------------------------------------

local function CreateUI()
	TotalLayers = #GameConfig.Layers

	-- Update config for current device before creating UI
	UpdateDeviceConfig()

	local gui = Instance.new("ScreenGui")
	gui.Name="LayerProgressUI"; gui.ResetOnSpawn=false; gui.DisplayOrder=5
	gui.IgnoreGuiInset=true; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=PlayerGui
	ScreenGui = gui

	local main = Instance.new("Frame")
	main.Name="MainContainer"; main.Size=UDim2.new(0,UI_CONFIG.ContainerWidth,0,0)
	main.Position=UDim2.new(1,-UI_CONFIG.ScreenMarginRight,0.5,0)
	main.AnchorPoint=Vector2.new(1,0.5); main.BackgroundTransparency=1; main.Parent=gui
	MainContainer = main

	local scale = Instance.new("UIScale"); scale.Name="MainUIScale"; scale.Scale=CurrentScale; scale.Parent=main
	MainUIScale = scale

	local title = Instance.new("TextLabel")
	title.Name="Title"; title.Size=UDim2.new(1,-10,0,UI_CONFIG.TitleHeight)
	title.Position=UDim2.new(0.5,0,0,UI_CONFIG.ContainerPadding/2); title.AnchorPoint=Vector2.new(0.5,0)
	title.BackgroundTransparency=1; title.Text="LAYERS"; title.TextColor3=Color3.fromRGB(255,255,255)
	title.TextSize=UI_CONFIG.TitleSize; title.Font=Enum.Font.GothamBlack; title.ZIndex=20; title.TextScaled=true; title.Parent=main
	local tg=Instance.new("UIGradient"); tg.Rotation=45
	tg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,100,255)),ColorSequenceKeypoint.new(0.2,Color3.fromRGB(100,255,255)),ColorSequenceKeypoint.new(0.4,Color3.fromRGB(255,255,100)),ColorSequenceKeypoint.new(0.6,Color3.fromRGB(100,255,100)),ColorSequenceKeypoint.new(0.8,Color3.fromRGB(255,150,100)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,100,255))})
	tg.Parent=title
	task.spawn(function() while title.Parent do tg.Offset=Vector2.new((tick()*0.5)%2-1,0); task.wait() end end)

	local ln = Instance.new("TextLabel")
	ln.Name="LayerName"; ln.Size=UDim2.new(1,-10,0,UI_CONFIG.LayerNameHeight)
	ln.Position=UDim2.new(0.5,0,0,UI_CONFIG.ContainerPadding/2 + UI_CONFIG.TitleHeight + 2); ln.AnchorPoint=Vector2.new(0.5,0)
	ln.BackgroundTransparency=1; ln.Text="SURFACE"; ln.TextColor3=LAYER_THEMES[1].Glow
	ln.TextSize=UI_CONFIG.LayerNameSize; ln.Font=Enum.Font.GothamBold; ln.TextTransparency=0.3
	ln.ZIndex=20; ln.TextScaled=true; ln.Parent=main
	LayerNameLabel = ln

	BuildPageContent(CurrentPage)
	return gui
end

--------------------------------------------------------------------------------
-- ANIMATIONS
--------------------------------------------------------------------------------

local function StartCirclePulse(idx)
	if ActiveSpinConnection then ActiveSpinConnection:Disconnect(); ActiveSpinConnection=nil end
	local c = LayerCircles[idx]; if not c then return end
	local bf = c:FindFirstChild("BorderFrame")
	local st = bf and bf:FindFirstChild("CircleStroke")
	local gr = st and st:FindFirstChild("StrokeGradient")
	if not bf or not st or not gr then return end
	task.spawn(function()
		while c and c.Parent and CurrentLayerIndex==idx do
			TweenService:Create(st,TweenInfo.new(1,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Thickness=UI_CONFIG.StrokeThicknessPulse}):Play()
			task.wait(1); if CurrentLayerIndex~=idx then break end
			TweenService:Create(st,TweenInfo.new(1,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Thickness=UI_CONFIG.StrokeThicknessActive}):Play()
			task.wait(1)
		end
	end)
	ActiveSpinConnection = RunService.RenderStepped:Connect(function(dt)
		if not gr or not c.Parent then if ActiveSpinConnection then ActiveSpinConnection:Disconnect() end; return end
		gr.Rotation = (gr.Rotation + 90*dt) % 360
	end)
end

local function SetCircleActive(idx, active, animate)
	local c = LayerCircles[idx]; if not c then return end
	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
	local ns, as = UI_CONFIG.CircleSize, UI_CONFIG.CircleSizeActive
	local bf = c:FindFirstChild("BorderFrame")
	local st = bf and bf:FindFirstChild("CircleStroke")
	local gr = st and st:FindFirstChild("StrokeGradient")
	local ts = active and as or ns
	local tt = active and UI_CONFIG.StrokeThicknessActive or UI_CONFIG.StrokeThickness
	local tr = active and 0 or 0.3
	local ac = ColorSequence.new({ColorSequenceKeypoint.new(0,theme.Primary),ColorSequenceKeypoint.new(0.5,theme.Glow),ColorSequenceKeypoint.new(1,theme.Primary)})
	local ic = ColorSequence.new({ColorSequenceKeypoint.new(0,theme.Dark),ColorSequenceKeypoint.new(1,theme.Dark)})
	if animate~=false then
		TweenService:Create(c,TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,ts,0,ts)}):Play()
		if st then TweenService:Create(st,TweenInfo.new(0.3),{Thickness=tt,Transparency=tr}):Play() end
	else
		c.Size=UDim2.new(0,ts,0,ts); if st then st.Thickness=tt; st.Transparency=tr end
	end
	if active then if gr then gr.Color=ac end; StartCirclePulse(idx)
	else if gr then gr.Color=ic end end
end

local function PlayLayerEntryAnimation(idx)
	local c = LayerCircles[idx]; if not c then return end
	local as = UI_CONFIG.CircleSizeActive
	local ps = as * 1.35
	TweenService:Create(c,TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.new(0,ps,0,ps)}):Play()
	task.delay(0.12,function()
		TweenService:Create(c,TweenInfo.new(0.4,Enum.EasingStyle.Elastic,Enum.EasingDirection.Out),{Size=UDim2.new(0,as,0,as)}):Play()
	end)
end

local function SwitchPage(newPage)
	if not MainContainer or IsTransitioning then return end
	IsTransitioning = true
	if ActiveSpinConnection then ActiveSpinConnection:Disconnect(); ActiveSpinConnection=nil end
	local oldPage = CurrentPage; CurrentPage = newPage
	local dir = (newPage>oldPage) and 1 or -1
	local outY = dir==1 and -0.5 or 1.5
	local inY = dir==1 and 1.5 or -0.5
	TweenService:Create(MainContainer,TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Position=UDim2.new(1,-UI_CONFIG.ScreenMarginRight,outY,0)}):Play()
	task.wait(0.4)
	BuildPageContent(newPage)
	MainContainer.Position=UDim2.new(1,-UI_CONFIG.ScreenMarginRight,inY,0)
	TweenService:Create(MainContainer,TweenInfo.new(0.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(1,-UI_CONFIG.ScreenMarginRight,0.5,0)}):Play()
	task.wait(0.5)
	SetCircleActive(CurrentLayerIndex, true, true)
	IsTransitioning = false
	LayerProgressController.SetDepth(CurrentDepth)
end

--------------------------------------------------------------------------------
-- UI UPDATES
--------------------------------------------------------------------------------

local function UpdateAvatarPosition(idx, progress, animate)
	if not AvatarFrame or IsTransitioning then return end
	local sL, eL = GetLayersOnPage(CurrentPage)
	local rel = GetRelativeIndex(idx, CurrentPage)
	local count = eL - sL + 1
	if idx > eL then rel = count end
	if idx < sL then rel = 1 end

	local curY = GetCircleYPosition(rel)
	local nxtY = GetCircleYPosition(rel + 1)
	local targetY
	if rel >= count then targetY = curY
	else targetY = curY + (nxtY - curY) * progress end

	if ActiveAvatarTween then ActiveAvatarTween:Cancel(); ActiveAvatarTween = nil end
	local pos = UDim2.new(0.5, 0, 0, targetY)
	if animate ~= false then
		ActiveAvatarTween = TweenService:Create(AvatarFrame, TweenInfo.new(0.15, Enum.EasingStyle.Linear), {Position = pos})
		ActiveAvatarTween:Play()
	else AvatarFrame.Position = pos end

	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
	local st = AvatarFrame:FindFirstChild("AvatarStroke")
	if st then
		if animate ~= false then TweenService:Create(st, TweenInfo.new(0.3), {Color = theme.Primary}):Play()
		else st.Color = theme.Primary end
	end
end

local function UpdateProgressLine(idx, progress, animate)
	if not ProgressLineFill or not ProgressLineBack or IsTransitioning then return end
	local sL, eL = GetLayersOnPage(CurrentPage)
	local rel = GetRelativeIndex(idx, CurrentPage)
	local count = eL - sL + 1
	if idx < sL then rel = 1 end
	if idx > eL then rel = count end

	local curY = GetCircleYPosition(rel)
	local nxtY = GetCircleYPosition(rel + 1)
	local firstY = GetCircleYPosition(1)
	local avatarY
	if rel >= count then avatarY = curY
	else avatarY = curY + (nxtY - curY) * progress end

	local fillH = math.max(0, avatarY - firstY)
	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]

	if ActiveLineTween then ActiveLineTween:Cancel(); ActiveLineTween = nil end
	if animate ~= false then
		ActiveLineTween = TweenService:Create(ProgressLineFill, TweenInfo.new(0.15, Enum.EasingStyle.Linear), {Size = UDim2.new(1, -8, 0, fillH)})
		ActiveLineTween:Play()
	else ProgressLineFill.Size = UDim2.new(1, -8, 0, fillH) end

	local fg = ProgressLineFill:FindFirstChild("FillGradient")
	local fs = ProgressLineFill:FindFirstChild("FillStroke")
	if fg then fg.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,theme.Dark),ColorSequenceKeypoint.new(0.5,theme.Primary),ColorSequenceKeypoint.new(1,theme.Dark)}) end
	if fs then fs.Color = theme.Glow end
end

local function UpdateLayerName(idx)
	local ld = GameConfig.Layers[idx]
	if not ld or not LayerNameLabel then return end
	local theme = LAYER_THEMES[idx] or LAYER_THEMES[1]
	LayerNameLabel.Text = string.upper(ld.LayerName)
	LayerNameLabel.TextColor3 = theme.Glow
end

local function UpdateDepthLabel(d)
	if DepthLabel then DepthLabel.Text = d.."m" end
end

local function OnLayerChanged(newIdx)
	if newIdx == CurrentLayerIndex then return end
	local oldIdx = CurrentLayerIndex
	CurrentLayerIndex = newIdx
	if newIdx > MaxLayerReached then
		MaxLayerReached = newIdx
		task.delay(0.1, function() PlayUnlockAnimation(newIdx) end)
	end
	UpdateLayerName(newIdx)
	local newPage = GetPageForLayer(newIdx)
	if newPage ~= CurrentPage then task.spawn(function() SwitchPage(newPage) end); return end
	SetCircleActive(oldIdx, false, true)
	PlayLayerEntryAnimation(newIdx)
	SetCircleActive(newIdx, true, true)
end

local function OnDepthChanged(newD)
	CurrentDepth = newD
	UpdateDepthLabel(newD)
	local newIdx = GetLayerFromDepth(newD)
	if newIdx ~= CurrentLayerIndex then OnLayerChanged(newIdx) end
	if not IsTransitioning then
		local prog = CalculateLayerProgress(newD, CurrentLayerIndex)
		UpdateAvatarPosition(CurrentLayerIndex, prog, true)
		UpdateProgressLine(CurrentLayerIndex, prog, true)
	end
end

--------------------------------------------------------------------------------
-- DATA LISTENERS
--------------------------------------------------------------------------------

local function SetupDataListeners()
	local rf = ReplicatedStorage:WaitForChild("Remotes")
	DataLoadedRemote = rf:WaitForChild("DataLoaded")
	DataLoadedRemote.OnClientEvent:Connect(function(data)
		if data.MaxLayerReached and data.MaxLayerReached > MaxLayerReached then
			MaxLayerReached = data.MaxLayerReached
			RefreshAllCircleLockStates()
		end
	end)
	DataUpdatedRemote = rf:WaitForChild("DataUpdated")
	DataUpdatedRemote.OnClientEvent:Connect(function(data)
		if data.Field == "MaxLayerReached" and data.Value and data.Value > MaxLayerReached then
			MaxLayerReached = data.Value
			PlayUnlockAnimation(data.Value)
		end
	end)
end

local function SetupResponsiveListener()
	-- Listen for viewport changes (orientation, window resize)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local configChanged = UpdateDeviceConfig()
		if configChanged then
			-- Rebuild UI with new config
			print("[LayerProgressController] Device type changed to: " .. CurrentDeviceType .. ", rebuilding UI")
			BuildPageContent(CurrentPage)
			SetCircleActive(CurrentLayerIndex, true, false)
			local prog = CalculateLayerProgress(CurrentDepth, CurrentLayerIndex)
			UpdateAvatarPosition(CurrentLayerIndex, prog, false)
			UpdateProgressLine(CurrentLayerIndex, prog, false)
			RefreshAllCircleLockStates()
		else
			-- Just update scale
			if MainUIScale then
				MainUIScale.Scale = CurrentScale
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function LayerProgressController.Initialize()
	if IsInitialized then return end
	IsInitialized = true
	TotalLayers = #GameConfig.Layers
	local sm = LocalPlayer:GetAttribute("MaxLayerReached")
	if sm and sm > MaxLayerReached then MaxLayerReached = sm end
	CreateUI()
	SetupResponsiveListener()
	SetupDataListeners()
	CurrentLayerIndex = 1; CurrentPage = 1
	SetCircleActive(1, true, false)
	UpdateLayerName(1)
	UpdateAvatarPosition(1, 0, false)
	UpdateProgressLine(1, 0, false)
	UpdateDepthLabel(0)
	RefreshAllCircleLockStates()
	print("[LayerProgressController] Initialized - Device: " .. CurrentDeviceType .. " Scale: " .. string.format("%.2f", CurrentScale))
end

function LayerProgressController.SetDepth(d) OnDepthChanged(d) end
function LayerProgressController.GetCurrentLayer() return CurrentLayerIndex end
function LayerProgressController.GetLayerProgress() return CalculateLayerProgress(CurrentDepth, CurrentLayerIndex) end
function LayerProgressController.GetMaxLayerReached() return MaxLayerReached end
function LayerProgressController.SetMaxLayerReached(idx) if idx > MaxLayerReached then MaxLayerReached = idx; RefreshAllCircleLockStates() end end
function LayerProgressController.SetLayerIcon(idx, asset)
	if GetPageForLayer(idx)==CurrentPage then local i=LayerCircleImages[idx]; if i then i.Image=asset; i.Visible=true end end
end
function LayerProgressController.SetLayerTheme(idx, p, g, d)
	LAYER_THEMES[idx] = {Primary=p, Glow=g, Dark=d}
	if idx==CurrentLayerIndex then UpdateLayerName(idx); local prog=CalculateLayerProgress(CurrentDepth,CurrentLayerIndex); UpdateAvatarPosition(CurrentLayerIndex,prog,true); UpdateProgressLine(CurrentLayerIndex,prog,true) end
end
function LayerProgressController.SetVisible(v) if ScreenGui then ScreenGui.Enabled = v end end
function LayerProgressController.GetDeviceType() return CurrentDeviceType end
function LayerProgressController.GetCurrentScale() return CurrentScale end
function LayerProgressController.DebugState()
	print("[DEBUG] Device:"..CurrentDeviceType.." Scale:"..string.format("%.2f",CurrentScale).." Depth:"..CurrentDepth.."m Layer:"..CurrentLayerIndex.." Max:"..MaxLayerReached.." Page:"..CurrentPage.." Progress:"..string.format("%.1f",CalculateLayerProgress(CurrentDepth,CurrentLayerIndex)*100).."%")
end

return LayerProgressController
