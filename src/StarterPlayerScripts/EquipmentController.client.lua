--[[
    EquipmentController.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    Template-Based Version:
    - Uses YOUR custom UI designed in Studio
    - Clones ItemCardTemplate for each owned item
    - Auto-creates UIGridLayout if missing
    - You have full visual control!
    
    Required Hierarchy:
    EquipmentUI (ScreenGui)
    ├── EquipmentButton
    └── MainFrame
        ├── ContentArea (ScrollingFrame or Frame)
        │   └── ItemCardTemplate (Visible = false)
        │       ├── Icon
        │       ├── NameLabel
        │       ├── StatsLabel
        │       └── EquipButton
        │           └── Text
        ├── TabContainer
        │   ├── PickaxeTab
        │   │   └── Text
        │   └── BackpackTab
        │       └── Text
        └── CloseButton (optional)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Load GameConfig
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	-- Tab images (swap these when switching tabs)
	TabImageSelected = "rbxassetid://111257830187958",
	TabImageNormal = "rbxassetid://139351924924301",

	-- Tab text
	PickaxeTabText = "PICKS",
	BackpackTabText = "BAGS",
	EquipText = "EQUIP",
	EquippedText = "EQUIPPED",

	-- Tab text colors
	TabTextColorNormal = Color3.fromRGB(255, 255, 255),
	TabTextColorSelected = Color3.fromRGB(255, 215, 100),

	-- Button colors (if not using images)
	EquipButtonColor = Color3.fromRGB(80, 180, 80),
	EquippedButtonColor = Color3.fromRGB(100, 100, 100),
	EquipButtonTextColor = Color3.fromRGB(255, 255, 255),
	EquippedButtonTextColor = Color3.fromRGB(200, 200, 200),

	-- Grid Layout (auto-created if missing)
	GridCellWidth = 145,
	GridCellHeight = 195,
	GridPaddingX = 12,
	GridPaddingY = 12,

	-- Pickaxe icons (optional - leave as rbxassetid://0 to keep template icon)
	PickaxeImages = {
		[1] = "rbxassetid://0",
		[2] = "rbxassetid://0",
		[3] = "rbxassetid://0",
		[4] = "rbxassetid://0",
		[5] = "rbxassetid://0",
		[6] = "rbxassetid://0",
		[7] = "rbxassetid://0",
		[8] = "rbxassetid://0",
	},

	-- Backpack icons (optional)
	BackpackImages = {
		[1] = "rbxassetid://0",
		[2] = "rbxassetid://0",
		[3] = "rbxassetid://0",
		[4] = "rbxassetid://0",
		[5] = "rbxassetid://0",
		[6] = "rbxassetid://0",
		[7] = "rbxassetid://0",
	},

	-- Shorten pickaxe names ("Stone Pickaxe" -> "Stone")
	ShortenPickaxeNames = true,

	Debug = true,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local EquipmentUI = nil
local EquipmentGui = nil
local MainFrame = nil
local EquipmentButton = nil
local ContentArea = nil
local ItemCardTemplate = nil
local PickaxeTab = nil
local BackpackTab = nil
local CloseButton = nil

local IsOpen = false
local IsAnimating = false
local CurrentTab = "Pickaxe"

local ClonedCards = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function DebugPrint(...)
	if CONFIG.Debug then
		print("[EquipmentController]", ...)
	end
end

local function GetPlayerPickaxeLevel()
	return LocalPlayer:GetAttribute("PickaxeLevel") or 1
end

local function GetPlayerBackpackLevel()
	return LocalPlayer:GetAttribute("BackpackLevel") or 1
end

local function GetEquippedPickaxe()
	local equipped = LocalPlayer:GetAttribute("EquippedPickaxe")
	if equipped then return equipped end
	return GetPlayerPickaxeLevel()
end

local function GetEquippedBackpack()
	local equipped = LocalPlayer:GetAttribute("EquippedBackpack")
	if equipped then return equipped end
	return GetPlayerBackpackLevel()
end

local function FormatNumber(n)
	n = math.floor(n or 0)
	local suffixes = {
		{1e18, "Quin"}, {1e15, "Quad"}, {1e12, "T"},
		{1e9, "B"}, {1e6, "M"},
	}
	for _, data in ipairs(suffixes) do
		if n >= data[1] then
			return string.format("%.2f%s", n / data[1], data[2])
		end
	end
	local formatted = tostring(n)
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return formatted
end

--------------------------------------------------------------------------------
-- UI REFERENCES
--------------------------------------------------------------------------------

local function EnsureGridLayout()
	-- Check if UIGridLayout already exists
	local existingGrid = ContentArea:FindFirstChildOfClass("UIGridLayout")
	if existingGrid then
		DebugPrint("UIGridLayout already exists")
		return
	end

	-- Create UIGridLayout
	local grid = Instance.new("UIGridLayout")
	grid.Name = "UIGridLayout"
	grid.CellSize = UDim2.new(0, CONFIG.GridCellWidth, 0, CONFIG.GridCellHeight)
	grid.CellPadding = UDim2.new(0, CONFIG.GridPaddingX, 0, CONFIG.GridPaddingY)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = ContentArea

	DebugPrint("Created UIGridLayout automatically")
end

local function FindUIElements()
	EquipmentUI = PlayerGui:WaitForChild("EquipmentUI", 10)
	EquipmentGui = EquipmentUI -- Keep both for compatibility
	if not EquipmentUI then
		warn("[EquipmentController] EquipmentUI not found!")
		return false
	end

	EquipmentButton = EquipmentUI:FindFirstChild("EquipmentButton")
	MainFrame = EquipmentUI:FindFirstChild("MainFrame")

	if not MainFrame then
		warn("[EquipmentController] MainFrame not found!")
		return false
	end

	ContentArea = MainFrame:FindFirstChild("ContentArea")
	if not ContentArea then
		warn("[EquipmentController] ContentArea not found!")
		return false
	end

	ItemCardTemplate = ContentArea:FindFirstChild("ItemCardTemplate")
	if not ItemCardTemplate then
		warn("[EquipmentController] ItemCardTemplate not found!")
		return false
	end

	-- Hide the template
	ItemCardTemplate.Visible = false

	-- Ensure grid layout exists
	EnsureGridLayout()

	-- Find tabs
	local tabContainer = MainFrame:FindFirstChild("TabContainer")
	if tabContainer then
		PickaxeTab = tabContainer:FindFirstChild("PickaxeTab")
		BackpackTab = tabContainer:FindFirstChild("BackpackTab")
	end

	-- Find close button
	CloseButton = MainFrame:FindFirstChild("CloseButton")

	DebugPrint("All UI elements found!")
	return true
end

--------------------------------------------------------------------------------
-- CARD CREATION (from template)
--------------------------------------------------------------------------------

local function CreateCardFromTemplate(itemType, level, data)
	local card = ItemCardTemplate:Clone()
	card.Name = itemType .. "_" .. level
	card.Visible = true
	card.LayoutOrder = level

	-- Update Icon
	local icon = card:FindFirstChild("Icon")
	if icon then
		local imageId
		if itemType == "Pickaxe" then
			imageId = CONFIG.PickaxeImages[level]
		else
			imageId = CONFIG.BackpackImages[level]
		end

		-- Only update if we have a custom image
		if imageId and imageId ~= "rbxassetid://0" then
			icon.Image = imageId
		end
	end

	-- Update Name
	local nameLabel = card:FindFirstChild("NameLabel")
	if nameLabel then
		local displayName = data.Name
		if itemType == "Pickaxe" and CONFIG.ShortenPickaxeNames then
			displayName = displayName:gsub(" Pickaxe", "")
		end
		nameLabel.Text = displayName
	end

	-- Update Stats
	local statsLabel = card:FindFirstChild("StatsLabel")
	if statsLabel then
		if itemType == "Pickaxe" then
			statsLabel.Text = "Power: " .. data.Power .. "\nSpeed: " .. data.Cooldown .. "s"
		else
			statsLabel.Text = "Capacity: " .. FormatNumber(data.Capacity)
		end
	end

	-- Setup Equip Button
	local equipBtn = card:FindFirstChild("EquipButton")
	if equipBtn then
		equipBtn.MouseButton1Click:Connect(function()
			OnEquipClicked(itemType, level, equipBtn)
		end)
	end

	card.Parent = ContentArea
	return card
end

local function UpdateCardEquipState(card, isEquipped)
	local equipBtn = card:FindFirstChild("EquipButton")
	if not equipBtn then return end

	local text = equipBtn:FindFirstChild("Text")

	if isEquipped then
		if equipBtn:IsA("TextButton") then
			equipBtn.BackgroundColor3 = CONFIG.EquippedButtonColor
		end
		if text then
			text.Text = CONFIG.EquippedText
			text.TextColor3 = CONFIG.EquippedButtonTextColor
		end
	else
		if equipBtn:IsA("TextButton") then
			equipBtn.BackgroundColor3 = CONFIG.EquipButtonColor
		end
		if text then
			text.Text = CONFIG.EquipText
			text.TextColor3 = CONFIG.EquipButtonTextColor
		end
	end
end

--------------------------------------------------------------------------------
-- POPULATE CONTENT
--------------------------------------------------------------------------------

local function ClearCards()
	for _, card in pairs(ClonedCards) do
		if card and card.Parent then
			card:Destroy()
		end
	end
	ClonedCards = {}
end

local function PopulateContent()
	-- Safety check - make sure UI elements exist
	if not ContentArea or not ContentArea.Parent then
		DebugPrint("PopulateContent aborted - ContentArea invalid")
		return
	end

	if not ItemCardTemplate then
		DebugPrint("PopulateContent aborted - ItemCardTemplate missing")
		return
	end

	ClearCards()

	if CurrentTab == "Pickaxe" then
		local ownedLevel = GetPlayerPickaxeLevel()
		local equippedLevel = GetEquippedPickaxe()

		for level = 1, ownedLevel do
			local data = GameConfig.GetPickaxe(level)
			if data then
				local card = CreateCardFromTemplate("Pickaxe", level, data)
				ClonedCards[level] = card
				UpdateCardEquipState(card, level == equippedLevel)
			end
		end

		DebugPrint("Populated", ownedLevel, "pickaxes")
	else
		local ownedLevel = GetPlayerBackpackLevel()
		local equippedLevel = GetEquippedBackpack()

		for level = 1, ownedLevel do
			local data = GameConfig.GetBackpack(level)
			if data then
				local card = CreateCardFromTemplate("Backpack", level, data)
				ClonedCards[level] = card
				UpdateCardEquipState(card, level == equippedLevel)
			end
		end

		DebugPrint("Populated", ownedLevel, "backpacks")
	end
end

--------------------------------------------------------------------------------
-- TAB SWITCHING
--------------------------------------------------------------------------------

local function SwitchTab(tab)
	if tab == CurrentTab then return end

	CurrentTab = tab
	DebugPrint("Switched to tab:", tab)

	-- Update tab visuals (image + text color)
	if PickaxeTab and BackpackTab then
		local pickText = PickaxeTab:FindFirstChild("Text")
		local backText = BackpackTab:FindFirstChild("Text")

		if tab == "Pickaxe" then
			-- Pickaxe tab selected
			PickaxeTab.Image = CONFIG.TabImageSelected
			BackpackTab.Image = CONFIG.TabImageNormal
			if pickText then pickText.TextColor3 = CONFIG.TabTextColorSelected end
			if backText then backText.TextColor3 = CONFIG.TabTextColorNormal end
		else
			-- Backpack tab selected
			PickaxeTab.Image = CONFIG.TabImageNormal
			BackpackTab.Image = CONFIG.TabImageSelected
			if pickText then pickText.TextColor3 = CONFIG.TabTextColorNormal end
			if backText then backText.TextColor3 = CONFIG.TabTextColorSelected end
		end
	end

	PopulateContent()
end

--------------------------------------------------------------------------------
-- EQUIP HANDLING
--------------------------------------------------------------------------------

function OnEquipClicked(itemType, level, button)
	DebugPrint("Equip clicked:", itemType, level)

	-- Check if already equipped
	if itemType == "Pickaxe" then
		if level == GetEquippedPickaxe() then
			DebugPrint("Already equipped!")
			return
		end
	else
		if level == GetEquippedBackpack() then
			DebugPrint("Already equipped!")
			return
		end
	end

	-- Button click animation
	local originalSize = button.Size
	TweenService:Create(button, TweenInfo.new(0.1), {
		Size = UDim2.new(
			originalSize.X.Scale * 0.9,
			originalSize.X.Offset * 0.9,
			originalSize.Y.Scale * 0.9,
			originalSize.Y.Offset * 0.9
		)
	}):Play()
	task.wait(0.1)
	TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
		Size = originalSize
	}):Play()

	-- Send equip request to server
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not Remotes then
		warn("[EquipmentController] Remotes folder not found!")
		return
	end

	local remoteName = itemType == "Pickaxe" and "EquipPickaxe" or "EquipBackpack"
	local remote = Remotes:FindFirstChild(remoteName)

	if not remote then
		warn("[EquipmentController]", remoteName, "remote not found!")
		return
	end

	DebugPrint("Calling", remoteName, "with level", level)

	local success, errorMsg = remote:InvokeServer(level)

	if success then
		DebugPrint("✓ Equipped", itemType, "level", level)
		task.delay(0.1, function()
			PopulateContent()
		end)
	else
		DebugPrint("✗ Failed to equip:", errorMsg or "Unknown error")

		-- Flash red on fail
		local equipText = button:FindFirstChild("Text")
		if equipText then
			local originalColor = equipText.TextColor3
			equipText.TextColor3 = Color3.fromRGB(255, 100, 100)
			task.delay(0.3, function()
				equipText.TextColor3 = originalColor
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- OPEN/CLOSE (Shop-style animations)
--------------------------------------------------------------------------------

local OriginalSize = nil
local OriginalPosition = nil

local function AnimateShopOpen()
	if IsAnimating then return end
	if not EquipmentUI or not MainFrame then return end

	IsAnimating = true

	-- Only show MainFrame, EquipmentUI stays enabled always
	MainFrame.Visible = true

	-- Start smaller and slightly below
	local startSize = UDim2.new(
		OriginalSize.X.Scale * 0.8,
		OriginalSize.X.Offset * 0.8,
		OriginalSize.Y.Scale * 0.8,
		OriginalSize.Y.Offset * 0.8
	)

	local startPosition = UDim2.new(
		OriginalPosition.X.Scale,
		OriginalPosition.X.Offset,
		OriginalPosition.Y.Scale + 0.05,
		OriginalPosition.Y.Offset
	)

	MainFrame.Size = startSize
	MainFrame.Position = startPosition

	-- Animate to full size and original position
	TweenService:Create(MainFrame, TweenInfo.new(
		0.35,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
		), {
			Size = OriginalSize,
			Position = OriginalPosition
		}):Play()

	task.delay(0.35, function()
		IsAnimating = false
	end)
end

local function AnimateShopClose(onComplete)
	if IsAnimating then return end
	if not EquipmentUI or not MainFrame then 
		if onComplete then onComplete() end
		return 
	end

	IsAnimating = true

	local endSize = UDim2.new(
		OriginalSize.X.Scale * 0.8,
		OriginalSize.X.Offset * 0.8,
		OriginalSize.Y.Scale * 0.8,
		OriginalSize.Y.Offset * 0.8
	)

	local endPosition = UDim2.new(
		OriginalPosition.X.Scale,
		OriginalPosition.X.Offset,
		OriginalPosition.Y.Scale + 0.05,
		OriginalPosition.Y.Offset
	)

	local closeTween = TweenService:Create(MainFrame, TweenInfo.new(
		0.25,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.In
		), {
			Size = endSize,
			Position = endPosition
		})

	closeTween:Play()

	closeTween.Completed:Once(function()
		MainFrame.Visible = false
		-- DON'T disable EquipmentUI - the button needs to stay visible!
		-- Reset to original for next open
		MainFrame.Size = OriginalSize
		MainFrame.Position = OriginalPosition
		IsAnimating = false
		if onComplete then onComplete() end
	end)
end

local function OpenUI()
	if IsOpen or IsAnimating then return end
	if not MainFrame then return end
	if not OriginalSize then
		DebugPrint("ERROR: OriginalSize not set!")
		return
	end

	IsOpen = true

	PopulateContent()
	AnimateShopOpen()

	DebugPrint("UI Opened")
end

local function CloseUI()
	if not IsOpen or IsAnimating then return end
	if not MainFrame then return end

	IsOpen = false

	AnimateShopClose()

	DebugPrint("UI Closed")
end

local function ToggleUI()
	if IsOpen then
		CloseUI()
	else
		OpenUI()
	end
end

--------------------------------------------------------------------------------
-- SETUP CONNECTIONS
--------------------------------------------------------------------------------

local function SetupConnections()
	-- Equipment button
	if EquipmentButton then
		EquipmentButton.MouseButton1Click:Connect(function()
			local originalSize = EquipmentButton.Size
			TweenService:Create(EquipmentButton, TweenInfo.new(0.1), {
				Size = UDim2.new(
					originalSize.X.Scale * 0.9,
					originalSize.X.Offset * 0.9,
					originalSize.Y.Scale * 0.9,
					originalSize.Y.Offset * 0.9
				)
			}):Play()
			task.wait(0.1)
			TweenService:Create(EquipmentButton, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
				Size = originalSize
			}):Play()

			ToggleUI()
		end)
		DebugPrint("EquipmentButton connected")
	end

	-- Tabs
	if PickaxeTab then
		PickaxeTab.MouseButton1Click:Connect(function()
			SwitchTab("Pickaxe")
		end)
	end

	if BackpackTab then
		BackpackTab.MouseButton1Click:Connect(function()
			SwitchTab("Backpack")
		end)
	end

	-- Close button
	if CloseButton then
		CloseButton.MouseButton1Click:Connect(function()
			CloseUI()
		end)
	end

	-- Attribute listeners
	LocalPlayer:GetAttributeChangedSignal("PickaxeLevel"):Connect(function()
		if IsOpen and CurrentTab == "Pickaxe" then
			PopulateContent()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("BackpackLevel"):Connect(function()
		if IsOpen and CurrentTab == "Backpack" then
			PopulateContent()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("EquippedPickaxe"):Connect(function()
		if IsOpen and CurrentTab == "Pickaxe" then
			PopulateContent()
		end
	end)

	LocalPlayer:GetAttributeChangedSignal("EquippedBackpack"):Connect(function()
		if IsOpen and CurrentTab == "Backpack" then
			PopulateContent()
		end
	end)

	DebugPrint("All connections set up")
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function Initialize()
	print("[EquipmentController] Initializing (Template Version)...")

	if FindUIElements() then
		SetupConnections()

		-- Store original size/position for animations
		OriginalSize = MainFrame.Size
		OriginalPosition = MainFrame.Position
		DebugPrint("Stored original size:", OriginalSize, "position:", OriginalPosition)

		-- Set initial tab state (Pickaxe selected by default)
		if PickaxeTab then
			PickaxeTab.Image = CONFIG.TabImageSelected
			local text = PickaxeTab:FindFirstChild("Text")
			if text then
				if CONFIG.PickaxeTabText then text.Text = CONFIG.PickaxeTabText end
				text.TextColor3 = CONFIG.TabTextColorSelected
			end
		end

		if BackpackTab then
			BackpackTab.Image = CONFIG.TabImageNormal
			local text = BackpackTab:FindFirstChild("Text")
			if text then
				if CONFIG.BackpackTabText then text.Text = CONFIG.BackpackTabText end
				text.TextColor3 = CONFIG.TabTextColorNormal
			end
		end

		-- Hide MainFrame initially
		MainFrame.Visible = false
		EquipmentUI.Enabled = true  -- Keep ScreenGui enabled so button works

		print("[EquipmentController] ✓ Ready!")
		return true
	else
		warn("[EquipmentController] Failed to initialize - check UI hierarchy")
		return false
	end
end

--------------------------------------------------------------------------------
-- RESPAWN HANDLING
--------------------------------------------------------------------------------

local function Reinitialize()
	DebugPrint("Reinitializing after respawn...")

	-- Reset state
	IsOpen = false
	IsAnimating = false
	OriginalSize = nil
	OriginalPosition = nil
	ClonedCards = {}
	CurrentTab = "Pickaxe"

	-- Wait a moment for UI to be ready
	task.wait(0.2)

	if Initialize() then
		DebugPrint("✓ Reinitialized successfully")
	else
		DebugPrint("✗ Reinitialize failed")
	end
end

-- Watch for EquipmentUI being added (after respawn)
local function SetupUIWatcher()
	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "EquipmentUI" and child:IsA("ScreenGui") then
			-- Only reinitialize if our current reference is invalid
			if not EquipmentUI or not EquipmentUI.Parent or EquipmentUI ~= child then
				DebugPrint("EquipmentUI detected after respawn (new instance)")
				task.wait(0.1)
				Reinitialize()
			else
				DebugPrint("EquipmentUI added but we already have valid reference, ignoring")
			end
		end
	end)
end

-- Initial setup
Initialize()
SetupUIWatcher()

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local EquipmentAPI = {}
function EquipmentAPI.Open() OpenUI() end
function EquipmentAPI.Close() CloseUI() end
function EquipmentAPI.Toggle() ToggleUI() end
function EquipmentAPI.Refresh() PopulateContent() end
return EquipmentAPI
