--[[
    ShopController.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    V8 - Fixed:
    - TutorialController integration moved to top and wrapped in pcall
    - Proper function ordering
    - Button click animations working
    - Respawn handling
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Load GameConfig for pickaxe data
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

-- TutorialController (optional - may not exist)
local TutorialController = nil
task.spawn(function()
	local success, result = pcall(function()
		local controllers = script.Parent
		local tutorialModule = controllers:FindFirstChild("TutorialController")
		if tutorialModule then
			return require(tutorialModule)
		end
		return nil
	end)
	if success and result then
		TutorialController = result
	end
end)

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	-- Proximity
	ProximityRange = 10,
	CloseRange = 15,

	-- NPC names to search for
	NPCNames = {"ShopKeeperNPC", "ShopNPC", "PickaxeShop", "Shop", "PickaxeShopNPC", "ShopKeeper", "Noob shop"},

	-- UI element names
	ScreenGuiName = "ShopUI",
	MainFrameName = "backround",
	ScrollFrameName = "ScrollingFrame",
	CashLabelName = "CashLabel",
	CloseButtonName = "CloseButton",
	BuyButtonName = "BuyButton",
	OwnedLabelName = "OwnedLabel",

	-- Pickaxe names mapped to levels
	PickaxeNames = {
		[2] = "Stone",
		[3] = "Iron",
		[4] = "Gold",
		[5] = "Diamond",
		[6] = "Emerald",
		[7] = "Obsidian",
		[8] = "Celestial",
	},

	-- Button states
	ButtonText = {
		Owned = "OWNED",
		Locked = "LOCKED",
		Buy = "BUY",
	},

	Colors = {
		Owned = Color3.fromRGB(100, 100, 100),
		Affordable = Color3.fromRGB(80, 200, 80),
		Locked = Color3.fromRGB(200, 80, 80),
		LockedLevel = Color3.fromRGB(150, 100, 50),
	},

	-- Animation Settings (matching SellUI)
	AnimTime = 0.4,
	StartScale = 0.8,
	StartOffsetY = 0.1,
	OverlayTransparency = 0.5,

	-- Button click animation
	ClickDuration = 0.15,
	ClickScale = 0.9,

	Debug = false,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local ShopUI = nil
local MainFrame = nil
local ScrollFrame = nil
local CashLabel = nil
local CloseButton = nil
local Overlay = nil

local BuyButtons = {}
local ItemFrames = {}
local OwnedLabels = {}
local ButtonConnections = {}

local IsShopOpen = false
local IsAnimating = false
local ShopNPC = nil

local OriginalSize = UDim2.new(0, 0, 0, 0)
local OriginalPosition = UDim2.new(0, 0, 0, 0)

local ProximityConnection = nil
local CashConnection = nil
local ScreenGuiAddedConnection = nil
local ScreenGuiRemovingConnection = nil

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function DebugPrint(...)
	if CONFIG.Debug then
		print("[ShopController]", ...)
	end
end

local function FormatCash(amount)
	amount = math.floor(amount or 0)
	local formatted = tostring(amount)
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return "$" .. formatted
end

local function GetPlayerCash()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	if leaderstats then
		local cash = leaderstats:FindFirstChild("Cash")
		if cash then
			return cash.Value
		end
	end
	return 0
end

local function GetPlayerPickaxeLevel()
	return LocalPlayer:GetAttribute("PickaxeLevel") or 1
end

local function GetPlayerPosition()
	local character = LocalPlayer.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			return hrp.Position
		end
	end
	return nil
end

local function CountTable(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- "ALREADY OWNED" NOTIFICATION POPUP
--------------------------------------------------------------------------------

local NotificationGui = nil

local function CreateNotificationGui()
	if NotificationGui then return end

	NotificationGui = Instance.new("ScreenGui")
	NotificationGui.Name = "ShopNotification"
	NotificationGui.ResetOnSpawn = false
	NotificationGui.DisplayOrder = 999
	NotificationGui.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "NotificationFrame"
	frame.Size = UDim2.new(0, 320, 0, 80)
	frame.Position = UDim2.new(0.5, -160, 0.3, 0)
	frame.BackgroundColor3 = Color3.fromRGB(75, 50, 35)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = NotificationGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(95, 65, 45)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(75, 50, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(55, 35, 25))
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Name = "OuterStroke"
	outerStroke.Color = Color3.fromRGB(60, 55, 50)
	outerStroke.Thickness = 4
	outerStroke.Parent = frame

	local innerFrame = Instance.new("Frame")
	innerFrame.Name = "InnerBorder"
	innerFrame.Size = UDim2.new(1, -8, 1, -8)
	innerFrame.Position = UDim2.new(0, 4, 0, 4)
	innerFrame.BackgroundTransparency = 1
	innerFrame.BorderSizePixel = 0
	innerFrame.Parent = frame

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 8)
	innerCorner.Parent = innerFrame

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Name = "InnerStroke"
	innerStroke.Color = Color3.fromRGB(120, 85, 60)
	innerStroke.Thickness = 2
	innerStroke.Transparency = 0.3
	innerStroke.Parent = innerFrame

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(1, -16, 0, 20)
	shine.Position = UDim2.new(0, 8, 0, 6)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.85
	shine.BorderSizePixel = 0
	shine.Parent = frame

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 6)
	shineCorner.Parent = shine

	local shineGradient = Instance.new("UIGradient")
	shineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	shineGradient.Rotation = 90
	shineGradient.Parent = shine

	local leftGem = Instance.new("TextLabel")
	leftGem.Name = "LeftGem"
	leftGem.Size = UDim2.new(0, 30, 0, 30)
	leftGem.Position = UDim2.new(0, 15, 0.5, -15)
	leftGem.BackgroundTransparency = 1
	leftGem.Text = "💎"
	leftGem.TextSize = 24
	leftGem.Parent = frame

	local rightGem = Instance.new("TextLabel")
	rightGem.Name = "RightGem"
	rightGem.Size = UDim2.new(0, 30, 0, 30)
	rightGem.Position = UDim2.new(1, -45, 0.5, -15)
	rightGem.BackgroundTransparency = 1
	rightGem.Text = "💎"
	rightGem.TextSize = 24
	rightGem.Parent = frame

	local textShadow = Instance.new("TextLabel")
	textShadow.Name = "TextShadow"
	textShadow.Size = UDim2.new(1, -80, 1, 0)
	textShadow.Position = UDim2.new(0, 42, 0, 3)
	textShadow.BackgroundTransparency = 1
	textShadow.Text = "Already Owned!"
	textShadow.TextColor3 = Color3.fromRGB(30, 20, 15)
	textShadow.TextSize = 26
	textShadow.Font = Enum.Font.GothamBlack
	textShadow.TextTransparency = 0.5
	textShadow.Parent = frame

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, -80, 1, 0)
	text.Position = UDim2.new(0, 40, 0, 0)
	text.BackgroundTransparency = 1
	text.Text = "Already Owned!"
	text.TextColor3 = Color3.fromRGB(255, 215, 100)
	text.TextSize = 26
	text.Font = Enum.Font.GothamBlack
	text.Parent = frame

	local textStroke = Instance.new("UIStroke")
	textStroke.Name = "TextStroke"
	textStroke.Color = Color3.fromRGB(80, 50, 30)
	textStroke.Thickness = 2
	textStroke.Parent = text
end

local function ShowAlreadyOwnedNotification()
	if not NotificationGui then
		CreateNotificationGui()
	end

	local frame = NotificationGui:FindFirstChild("NotificationFrame")
	if not frame then return end

	frame.Visible = true
	frame.BackgroundTransparency = 0
	frame.Position = UDim2.new(0.5, -160, 0.35, 0)

	local text = frame:FindFirstChild("Text")
	local textShadow = frame:FindFirstChild("TextShadow")
	local outerStroke = frame:FindFirstChild("OuterStroke")
	local innerFrame = frame:FindFirstChild("InnerBorder")
	local shine = frame:FindFirstChild("Shine")
	local leftGem = frame:FindFirstChild("LeftGem")
	local rightGem = frame:FindFirstChild("RightGem")

	if text then text.TextTransparency = 0 end
	if textShadow then textShadow.TextTransparency = 0.5 end
	if outerStroke then outerStroke.Transparency = 0 end
	if innerFrame then
		local innerStroke = innerFrame:FindFirstChild("InnerStroke")
		if innerStroke then innerStroke.Transparency = 0.3 end
	end
	if shine then shine.BackgroundTransparency = 0.85 end
	if leftGem then leftGem.TextTransparency = 0 end
	if rightGem then rightGem.TextTransparency = 0 end

	local textStroke = text and text:FindFirstChild("TextStroke")
	if textStroke then textStroke.Transparency = 0 end

	TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -160, 0.25, 0)
	}):Play()

	if leftGem and rightGem then
		task.spawn(function()
			for i = 1, 3 do
				TweenService:Create(leftGem, TweenInfo.new(0.15), {Rotation = 10, TextSize = 28}):Play()
				TweenService:Create(rightGem, TweenInfo.new(0.15), {Rotation = -10, TextSize = 28}):Play()
				task.wait(0.15)
				TweenService:Create(leftGem, TweenInfo.new(0.15), {Rotation = -10, TextSize = 24}):Play()
				TweenService:Create(rightGem, TweenInfo.new(0.15), {Rotation = 10, TextSize = 24}):Play()
				task.wait(0.15)
			end
			TweenService:Create(leftGem, TweenInfo.new(0.1), {Rotation = 0, TextSize = 24}):Play()
			TweenService:Create(rightGem, TweenInfo.new(0.1), {Rotation = 0, TextSize = 24}):Play()
		end)
	end

	task.delay(1.8, function()
		local fadeOut = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		TweenService:Create(frame, fadeOut, {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, -160, 0.2, 0)
		}):Play()

		if text then TweenService:Create(text, fadeOut, {TextTransparency = 1}):Play() end
		if textShadow then TweenService:Create(textShadow, fadeOut, {TextTransparency = 1}):Play() end
		if outerStroke then TweenService:Create(outerStroke, fadeOut, {Transparency = 1}):Play() end
		if textStroke then TweenService:Create(textStroke, fadeOut, {Transparency = 1}):Play() end
		if innerFrame then
			local innerStroke = innerFrame:FindFirstChild("InnerStroke")
			if innerStroke then TweenService:Create(innerStroke, fadeOut, {Transparency = 1}):Play() end
		end
		if shine then TweenService:Create(shine, fadeOut, {BackgroundTransparency = 1}):Play() end
		if leftGem then TweenService:Create(leftGem, fadeOut, {TextTransparency = 1}):Play() end
		if rightGem then TweenService:Create(rightGem, fadeOut, {TextTransparency = 1}):Play() end

		task.delay(0.4, function()
			frame.Visible = false
		end)
	end)
end

--------------------------------------------------------------------------------
-- CREATE OVERLAY
--------------------------------------------------------------------------------

local function CreateOverlay()
	if Overlay then return end
	if not ShopUI then return end

	Overlay = Instance.new("Frame")
	Overlay.Name = "ShopOverlay"
	Overlay.Size = UDim2.new(1, 0, 1, 0)
	Overlay.Position = UDim2.new(0, 0, 0, 0)
	Overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	Overlay.BackgroundTransparency = 1
	Overlay.BorderSizePixel = 0
	Overlay.ZIndex = 1
	Overlay.Parent = ShopUI

	if MainFrame then
		MainFrame.ZIndex = 10
	end
end

--------------------------------------------------------------------------------
-- BUTTON CLICK ANIMATION
--------------------------------------------------------------------------------

local function AnimateButtonClick(button, callback)
	if not button then 
		if callback then callback() end
		return 
	end

	local originalSize = button.Size

	local shrinkTween = TweenService:Create(button, TweenInfo.new(
		CONFIG.ClickDuration / 2,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
		), {
			Size = UDim2.new(
				originalSize.X.Scale * CONFIG.ClickScale,
				originalSize.X.Offset * CONFIG.ClickScale,
				originalSize.Y.Scale * CONFIG.ClickScale,
				originalSize.Y.Offset * CONFIG.ClickScale
			)
		})

	local bounceTween = TweenService:Create(button, TweenInfo.new(
		CONFIG.ClickDuration / 2,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
		), {
			Size = originalSize
		})

	shrinkTween:Play()

	shrinkTween.Completed:Once(function()
		if callback then
			callback()
		end
		bounceTween:Play()
	end)
end

--------------------------------------------------------------------------------
-- SHOP OPEN/CLOSE ANIMATIONS
--------------------------------------------------------------------------------

local function AnimateShopOpen()
	if IsAnimating then return end
	if not ShopUI or not MainFrame then return end

	IsAnimating = true

	ShopUI.Enabled = true
	MainFrame.Visible = true

	local startSize = UDim2.new(
		OriginalSize.X.Scale * CONFIG.StartScale,
		OriginalSize.X.Offset * CONFIG.StartScale,
		OriginalSize.Y.Scale * CONFIG.StartScale,
		OriginalSize.Y.Offset * CONFIG.StartScale
	)

	local startPosition = UDim2.new(
		OriginalPosition.X.Scale,
		OriginalPosition.X.Offset,
		OriginalPosition.Y.Scale + CONFIG.StartOffsetY,
		OriginalPosition.Y.Offset
	)

	MainFrame.Size = startSize
	MainFrame.Position = startPosition

	if Overlay then
		Overlay.BackgroundTransparency = 1
		TweenService:Create(Overlay, TweenInfo.new(CONFIG.AnimTime), {
			BackgroundTransparency = CONFIG.OverlayTransparency
		}):Play()
	end

	TweenService:Create(MainFrame, TweenInfo.new(
		CONFIG.AnimTime,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
		), {
			Size = OriginalSize,
			Position = OriginalPosition
		}):Play()

	task.delay(CONFIG.AnimTime, function()
		IsAnimating = false
	end)

	-- Tutorial hook: Shop opened
	if TutorialController and TutorialController.ReportShopOpened then
		TutorialController.ReportShopOpened()
	end
end

local function AnimateShopClose(onComplete)
	if IsAnimating then return end
	if not ShopUI or not MainFrame then 
		if onComplete then onComplete() end
		return 
	end

	IsAnimating = true

	local endSize = UDim2.new(
		OriginalSize.X.Scale * CONFIG.StartScale,
		OriginalSize.X.Offset * CONFIG.StartScale,
		OriginalSize.Y.Scale * CONFIG.StartScale,
		OriginalSize.Y.Offset * CONFIG.StartScale
	)

	local endPosition = UDim2.new(
		OriginalPosition.X.Scale,
		OriginalPosition.X.Offset,
		OriginalPosition.Y.Scale + CONFIG.StartOffsetY,
		OriginalPosition.Y.Offset
	)

	if Overlay then
		TweenService:Create(Overlay, TweenInfo.new(CONFIG.AnimTime * 0.7), {
			BackgroundTransparency = 1
		}):Play()
	end

	local closeTween = TweenService:Create(MainFrame, TweenInfo.new(
		CONFIG.AnimTime * 0.7,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.In
		), {
			Size = endSize,
			Position = endPosition
		})

	closeTween:Play()

	closeTween.Completed:Once(function()
		if MainFrame then MainFrame.Visible = false end
		if ShopUI then ShopUI.Enabled = false end
		IsAnimating = false

		if onComplete then
			onComplete()
		end
	end)
end

--------------------------------------------------------------------------------
-- UPDATE UI
--------------------------------------------------------------------------------

local function UpdateCashDisplay()
	if not CashLabel then return end

	local cash = GetPlayerCash()
	CashLabel.Text = FormatCash(cash)
end

local function UpdateBuyButtons()
	local playerLevel = GetPlayerPickaxeLevel()
	local playerCash = GetPlayerCash()

	DebugPrint("Updating buttons - Player Level:", playerLevel, "Cash:", playerCash)

	for level, button in pairs(BuyButtons) do
		local pickaxe = GameConfig.GetPickaxe(level)
		if not pickaxe then continue end

		local cost = pickaxe.Cost
		local ownedLabel = OwnedLabels[level]

		if level <= playerLevel then
			button.Visible = false
			if ownedLabel then
				ownedLabel.Visible = true
			end

		elseif level == playerLevel + 1 then
			button.Visible = true
			if ownedLabel then
				ownedLabel.Visible = false
			end

			if playerCash >= cost then
				if button:IsA("TextButton") then
					button.Text = CONFIG.ButtonText.Buy
				end
				button.BackgroundColor3 = CONFIG.Colors.Affordable
				button.AutoButtonColor = true
			else
				if button:IsA("TextButton") then
					button.Text = FormatCash(cost)
				end
				button.BackgroundColor3 = CONFIG.Colors.Locked
				button.AutoButtonColor = false
			end

		else
			button.Visible = true
			if ownedLabel then
				ownedLabel.Visible = false
			end

			if button:IsA("TextButton") then
				button.Text = CONFIG.ButtonText.Locked
			end
			button.BackgroundColor3 = CONFIG.Colors.LockedLevel
			button.AutoButtonColor = false
		end
	end
end

--------------------------------------------------------------------------------
-- SHOP OPEN/CLOSE
--------------------------------------------------------------------------------

local function OpenShop()
	if IsShopOpen or IsAnimating then return end
	if not ShopUI or not MainFrame then 
		DebugPrint("Cannot open shop - UI not ready")
		return 
	end

	IsShopOpen = true

	UpdateCashDisplay()
	UpdateBuyButtons()

	AnimateShopOpen()

	DebugPrint("Shop OPENED")
end

local function CloseShop()
	if not IsShopOpen or IsAnimating then return end
	if not ShopUI or not MainFrame then 
		IsShopOpen = false
		return 
	end

	IsShopOpen = false

	AnimateShopClose()

	DebugPrint("Shop CLOSED")
end

--------------------------------------------------------------------------------
-- PURCHASE HANDLING
--------------------------------------------------------------------------------

local function OnBuyButtonClicked(level, button)
	DebugPrint("Button clicked for level", level)

	local playerLevel = GetPlayerPickaxeLevel()
	local playerCash = GetPlayerCash()
	local pickaxe = GameConfig.GetPickaxe(level)

	if not pickaxe then 
		DebugPrint("No pickaxe data for level", level)
		return 
	end

	if level <= playerLevel then
		AnimateButtonClick(button, nil)
		return
	end

	if level > playerLevel + 1 then
		AnimateButtonClick(button, nil)
		return
	end

	if playerCash < pickaxe.Cost then
		AnimateButtonClick(button, function()
			local originalPos = button.Position
			for i = 1, 3 do
				TweenService:Create(button, TweenInfo.new(0.04), {
					Position = originalPos + UDim2.new(0, 5, 0, 0)
				}):Play()
				task.wait(0.04)
				TweenService:Create(button, TweenInfo.new(0.04), {
					Position = originalPos + UDim2.new(0, -5, 0, 0)
				}):Play()
				task.wait(0.04)
			end
			TweenService:Create(button, TweenInfo.new(0.04), {
				Position = originalPos
			}):Play()
		end)
		return
	end

	AnimateButtonClick(button, function()
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not Remotes then
			warn("[ShopController] Remotes folder not found!")
			return
		end

		local UpgradePickaxe = Remotes:FindFirstChild("UpgradePickaxe")
		if not UpgradePickaxe then
			warn("[ShopController] UpgradePickaxe remote not found!")
			return
		end

		local success, errorMsg = UpgradePickaxe:InvokeServer()

		if success then
			button.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
			task.delay(0.3, function()
				UpdateCashDisplay()
				UpdateBuyButtons()
			end)
		else
			button.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
			task.delay(0.3, function()
				UpdateBuyButtons()
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- CONNECT BUTTONS
--------------------------------------------------------------------------------

local function ConnectBuyButtons()
	for _, conn in ipairs(ButtonConnections) do
		if conn then conn:Disconnect() end
	end
	ButtonConnections = {}

	for level, button in pairs(BuyButtons) do
		local conn = button.MouseButton1Click:Connect(function()
			OnBuyButtonClicked(level, button)
		end)
		table.insert(ButtonConnections, conn)
	end

	for level, ownedLabel in pairs(OwnedLabels) do
		local conn = ownedLabel.MouseButton1Click:Connect(function()
			AnimateButtonClick(ownedLabel, function()
				ShowAlreadyOwnedNotification()
			end)
		end)
		table.insert(ButtonConnections, conn)
	end

	if CloseButton then
		local conn = CloseButton.MouseButton1Click:Connect(function()
			AnimateButtonClick(CloseButton, function()
				CloseShop()
			end)
		end)
		table.insert(ButtonConnections, conn)
	end
end

--------------------------------------------------------------------------------
-- FIND SHOP NPC
--------------------------------------------------------------------------------

local function GetNPCPosition(npc)
	if not npc then return nil end

	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end

	local torso = npc:FindFirstChild("Torso") or npc:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		return torso.Position
	end

	if npc.PrimaryPart then
		return npc.PrimaryPart.Position
	end

	local part = npc:FindFirstChildOfClass("Part") or npc:FindFirstChildOfClass("MeshPart")
	if part then
		return part.Position
	end

	return nil
end

local function FindShopNPC()
	for _, npcName in ipairs(CONFIG.NPCNames) do
		local npc = workspace:FindFirstChild(npcName, true)
		if npc and npc:IsA("Model") then
			return npc
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- FIND UI ELEMENTS
--------------------------------------------------------------------------------

local function ClearUIReferences()
	ShopUI = nil
	MainFrame = nil
	ScrollFrame = nil
	CashLabel = nil
	CloseButton = nil
	Overlay = nil
	BuyButtons = {}
	OwnedLabels = {}
	ItemFrames = {}
	IsShopOpen = false
	IsAnimating = false
end

local function FindShopUI()
	ShopUI = PlayerGui:FindFirstChild(CONFIG.ScreenGuiName)
	if not ShopUI then
		return false
	end

	MainFrame = ShopUI:FindFirstChild(CONFIG.MainFrameName)
	if not MainFrame then
		return false
	end

	OriginalSize = MainFrame.Size
	OriginalPosition = MainFrame.Position

	CreateOverlay()

	ScrollFrame = MainFrame:FindFirstChild(CONFIG.ScrollFrameName)
	CashLabel = MainFrame:FindFirstChild(CONFIG.CashLabelName)
	CloseButton = MainFrame:FindFirstChild(CONFIG.CloseButtonName)

	BuyButtons = {}
	OwnedLabels = {}
	ItemFrames = {}

	local searchParent = ScrollFrame or MainFrame

	for level, pickaxeName in pairs(CONFIG.PickaxeNames) do
		local itemFrame = searchParent:FindFirstChild(pickaxeName)

		if itemFrame then
			ItemFrames[level] = itemFrame

			local buyButton = itemFrame:FindFirstChild(CONFIG.BuyButtonName)
			if buyButton and (buyButton:IsA("TextButton") or buyButton:IsA("ImageButton")) then
				BuyButtons[level] = buyButton
			end

			local ownedLabel = itemFrame:FindFirstChild(CONFIG.OwnedLabelName)
			if ownedLabel and (ownedLabel:IsA("TextLabel") or ownedLabel:IsA("ImageLabel") or ownedLabel:IsA("TextButton") or ownedLabel:IsA("ImageButton")) then
				OwnedLabels[level] = ownedLabel
				ownedLabel.Visible = false
			end
		end
	end

	return true
end

--------------------------------------------------------------------------------
-- LISTENERS
--------------------------------------------------------------------------------

local function SetupCashListener()
	local leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
	if not leaderstats then return end

	local cash = leaderstats:WaitForChild("Cash", 5)
	if not cash then return end

	if CashConnection then
		CashConnection:Disconnect()
	end

	CashConnection = cash.Changed:Connect(function()
		if IsShopOpen then
			UpdateCashDisplay()
			UpdateBuyButtons()
		end
	end)
end

local function SetupLevelListener()
	LocalPlayer:GetAttributeChangedSignal("PickaxeLevel"):Connect(function()
		if IsShopOpen then
			UpdateBuyButtons()
		end
	end)
end

--------------------------------------------------------------------------------
-- PROXIMITY DETECTION
--------------------------------------------------------------------------------

local function StartProximityDetection()
	if ProximityConnection then
		ProximityConnection:Disconnect()
	end

	ProximityConnection = RunService.Heartbeat:Connect(function()
		if IsAnimating then return end

		if not ShopNPC or not ShopNPC.Parent then
			ShopNPC = FindShopNPC()
		end

		if not ShopNPC then return end

		local npcPos = GetNPCPosition(ShopNPC)
		if not npcPos then return end

		local playerPos = GetPlayerPosition()
		if not playerPos then return end

		local distance = (playerPos - npcPos).Magnitude

		if not IsShopOpen and distance <= CONFIG.ProximityRange then
			OpenShop()
		elseif IsShopOpen and distance > CONFIG.CloseRange then
			CloseShop()
		end
	end)
end

--------------------------------------------------------------------------------
-- UI WATCHER (for respawns)
--------------------------------------------------------------------------------

local function SetupUIWatcher()
	if ScreenGuiAddedConnection then
		ScreenGuiAddedConnection:Disconnect()
		ScreenGuiAddedConnection = nil
	end
	if ScreenGuiRemovingConnection then
		ScreenGuiRemovingConnection:Disconnect()
		ScreenGuiRemovingConnection = nil
	end

	ScreenGuiAddedConnection = PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == CONFIG.ScreenGuiName and child:IsA("ScreenGui") then
			task.wait(0.1)
			if FindShopUI() then
				ShopUI.Enabled = false
				MainFrame.Visible = false
				ConnectBuyButtons()
			end
		end
	end)

	ScreenGuiRemovingConnection = PlayerGui.ChildRemoved:Connect(function(child)
		if child.Name == CONFIG.ScreenGuiName then
			ClearUIReferences()
		end
	end)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function Initialize()
	print("[ShopController] Initializing V8...")

	SetupUIWatcher()
	CreateNotificationGui()

	task.wait(0.5)

	if FindShopUI() then
		ShopUI.Enabled = false
		MainFrame.Visible = false
		ConnectBuyButtons()
		print("[ShopController] UI found and initialized")
	else
		print("[ShopController] UI not found yet, will initialize when it appears")
	end

	ShopNPC = FindShopNPC()

	SetupCashListener()
	SetupLevelListener()
	StartProximityDetection()

	print("[ShopController] ✓ Ready!")
	print("  - Buy buttons:", CountTable(BuyButtons))
	print("  - Owned labels:", CountTable(OwnedLabels))
	print("  - NPC:", ShopNPC and ShopNPC.Name or "Not found")
end

Initialize()

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

local ShopAPI = {}

function ShopAPI.Open()
	OpenShop()
end

function ShopAPI.Close()
	CloseShop()
end

function ShopAPI.Toggle()
	if IsShopOpen then
		CloseShop()
	else
		OpenShop()
	end
end

function ShopAPI.Refresh()
	UpdateCashDisplay()
	UpdateBuyButtons()
end

return ShopAPI
