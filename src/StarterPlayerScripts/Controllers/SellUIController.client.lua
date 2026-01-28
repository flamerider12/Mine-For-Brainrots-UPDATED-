--[[
    SellUIController.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    Template-Based Sell UI:
    - Uses YOUR custom UI designed in Studio
    - Clones ContainerTemplate for each ore type
    - Auto-opens when entering sell zone
    - Handles ALL 35 block types from GameConfig
    
    Required Hierarchy:
    SellUI (ScreenGui)
    ├── SellButton (ImageButton)
    ├── CancelButton (ImageButton)
    ├── SellStationSign (ImageLabel)
    ├── ConfirmPopup (ImageLabel) [Visible = false]
    │   ├── ConfirmText (TextLabel)
    │   ├── ConfirmButton (ImageButton)
    │   └── CancelPopupButton (ImageButton)
    ├── SoldPopup (ImageLabel) [Visible = false]
    └── Backround (Frame)
        ├── ContentArea (ScrollingFrame)
        │   └── ContainerTemplate (Frame) [Visible = false]
        │       ├── BlockImage (ImageLabel)
        │       ├── BlockName (TextLabel)
        │       ├── Quantity (TextLabel)
        │       └── AmountContainer (Frame)
        │           └── AmountNumber (TextLabel)
        ├── GoldenDivider
        └── TotalWorthDisplay (TextLabel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	GridPaddingY = 4,
	AnimTime = 0.35,

	BlockImages = {
		["Grass"] = "", ["Dirt"] = "", ["Coal Ore"] = "", ["Iron Ore"] = "", ["Common Box"] = "",
		["Stone"] = "", ["Gravel"] = "", ["Gold Ore"] = "", ["Diamond Ore"] = "", ["Uncommon Box"] = "",
		["Granite"] = "", ["Diorite"] = "", ["Emerald Ore"] = "", ["Ruby Ore"] = "", ["Rare Box"] = "",
		["Deep Slate"] = "", ["Tuff"] = "", ["Sapphire Ore"] = "", ["Amethyst Ore"] = "", ["Epic Box"] = "",
		["Cool Magma"] = "", ["Basalt"] = "", ["Onyx Ore"] = "", ["Painite Ore"] = "", ["Legendary Box"] = "",
		["Corrupted Data"] = "", ["Dead Pixel"] = "", ["Crypto Ore"] = "", ["Eth Ore"] = "", ["Mythic Box"] = "",
		["Ohio Turf"] = "", ["Ohio Mud"] = "", ["Unobtainium"] = "", ["Skibidinite"] = "", ["Godly Box"] = "",
	},

	BlockEmojis = {
		["Grass"] = "🌿", ["Dirt"] = "🟫", ["Coal Ore"] = "⬛", ["Iron Ore"] = "⚪", ["Common Box"] = "📦",
		["Stone"] = "🪨", ["Gravel"] = "�ite", ["Gold Ore"] = "🟡", ["Diamond Ore"] = "💎", ["Uncommon Box"] = "📦",
		["Granite"] = "🟤", ["Diorite"] = "⬜", ["Emerald Ore"] = "💚", ["Ruby Ore"] = "❤️", ["Rare Box"] = "📦",
		["Deep Slate"] = "🩶", ["Tuff"] = "🪨", ["Sapphire Ore"] = "💙", ["Amethyst Ore"] = "💜", ["Epic Box"] = "📦",
		["Cool Magma"] = "🔥", ["Basalt"] = "⬛", ["Onyx Ore"] = "🖤", ["Painite Ore"] = "💗", ["Legendary Box"] = "📦",
		["Corrupted Data"] = "👾", ["Dead Pixel"] = "🟪", ["Crypto Ore"] = "₿", ["Eth Ore"] = "Ξ", ["Mythic Box"] = "📦",
		["Ohio Turf"] = "🌾", ["Ohio Mud"] = "🟫", ["Unobtainium"] = "✨", ["Skibidinite"] = "🚽", ["Godly Box"] = "📦",
	},

	Debug = true,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local SellUI, Backround, ContentArea, ContainerTemplate, TotalWorthDisplay
local SellButton, CancelButton, SellStationSign
local ConfirmPopup, ConfirmText, ConfirmButton, CancelPopupButton
local SoldPopup

local IsOpen = false
local IsAnimating = false
local IsSelling = false
local ClonedItems = {}

local OriginalSize, OriginalPosition
local SellButtonOriginalSize, SellButtonOriginalPosition
local CancelButtonOriginalSize, CancelButtonOriginalPosition
local SignOriginalSize, SignOriginalPosition
local ConfirmPopupOriginalSize, ConfirmPopupOriginalPosition
local SoldPopupOriginalSize, SoldPopupOriginalPosition

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then warn("[SellUI] Remotes folder not found!") return end

local EnterSellZone = Remotes:WaitForChild("EnterSellZone", 10)
local LeaveSellZone = Remotes:WaitForChild("LeaveSellZone", 10)
local SellInventory = Remotes:WaitForChild("SellInventory", 10)
local GetInventoryForSell = Remotes:WaitForChild("GetInventoryForSell", 10)

if not EnterSellZone or not LeaveSellZone or not SellInventory or not GetInventoryForSell then
	warn("[SellUI] Missing required remotes!")
	return
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function DebugPrint(...)
	if CONFIG.Debug then print("[SellUI]", ...) end
end

local function FormatNumber(n)
	n = math.floor(n or 0)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000)
	elseif n >= 1000 then return string.format("%.1fK", n / 1000)
	else return tostring(n) end
end

local function GetBlockImage(blockName)
	local customImage = CONFIG.BlockImages[blockName]
	if customImage and customImage ~= "" then return customImage, false end
	return CONFIG.BlockEmojis[blockName] or "💎", true
end

--------------------------------------------------------------------------------
-- UI REFERENCES
--------------------------------------------------------------------------------

local function EnsureListLayout()
	if ContentArea:FindFirstChildOfClass("UIListLayout") then return end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, CONFIG.GridPaddingY)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = ContentArea
end

local function FindUIElements()
	SellUI = PlayerGui:WaitForChild("SellUI", 10)
	if not SellUI then warn("[SellUI] SellUI not found!") return false end

	SellButton = SellUI:FindFirstChild("SellButton")
	CancelButton = SellUI:FindFirstChild("CancelButton")
	SellStationSign = SellUI:FindFirstChild("SellStationSign")
	Backround = SellUI:FindFirstChild("Backround")

	if not Backround then warn("[SellUI] Backround not found!") return false end

	ContentArea = Backround:FindFirstChild("ContentArea")
	if not ContentArea then warn("[SellUI] ContentArea not found!") return false end

	ContainerTemplate = ContentArea:FindFirstChild("ContainerTemplate")
	if not ContainerTemplate then warn("[SellUI] ContainerTemplate not found!") return false end

	ContainerTemplate.Visible = false
	for _, child in ipairs(ContainerTemplate:GetDescendants()) do
		if child:IsA("GuiObject") then child.Visible = false end
	end

	EnsureListLayout()
	TotalWorthDisplay = Backround:FindFirstChild("TotalWorthDisplay")

	-- Find ConfirmPopup
	ConfirmPopup = SellUI:FindFirstChild("ConfirmPopup") or SellUI:FindFirstChild("ConfirmPopup", true)
	if ConfirmPopup then
		ConfirmText = ConfirmPopup:FindFirstChild("ConfirmText")
		ConfirmButton = ConfirmPopup:FindFirstChild("ConfirmButton")
		CancelPopupButton = ConfirmPopup:FindFirstChild("CancelPopupButton")
		ConfirmPopup.Visible = false
		DebugPrint("ConfirmPopup found! ConfirmButton:", ConfirmButton and "YES" or "NO")
	else
		warn("[SellUI] ConfirmPopup not found!")
	end

	-- Find SoldPopup
	SoldPopup = SellUI:FindFirstChild("SoldPopup") or SellUI:FindFirstChild("SoldPopup", true)
	if SoldPopup then
		SoldPopup.Visible = false
		DebugPrint("SoldPopup found!")
	else
		warn("[SellUI] SoldPopup not found!")
	end

	return true
end

--------------------------------------------------------------------------------
-- ITEM CREATION
--------------------------------------------------------------------------------

local function CreateItemFromTemplate(blockName, quantity, totalValue, index)
	local item = ContainerTemplate:Clone()
	item.Name = "Item_" .. blockName
	item.Visible = true
	item.LayoutOrder = index

	for _, child in ipairs(item:GetDescendants()) do
		if child:IsA("GuiObject") then child.Visible = true end
	end

	local blockImage = item:FindFirstChild("BlockImage")
	if blockImage then
		local imageOrEmoji, isEmoji = GetBlockImage(blockName)
		if isEmoji then
			blockImage.Image = ""
			local emojiLabel = blockImage:FindFirstChild("EmojiLabel") or Instance.new("TextLabel")
			emojiLabel.Name = "EmojiLabel"
			emojiLabel.Size = UDim2.new(1, 0, 1, 0)
			emojiLabel.BackgroundTransparency = 1
			emojiLabel.TextScaled = true
			emojiLabel.Font = Enum.Font.GothamBold
			emojiLabel.TextColor3 = Color3.new(1, 1, 1)
			emojiLabel.Text = imageOrEmoji
			emojiLabel.Visible = true
			emojiLabel.Parent = blockImage
		else
			blockImage.Image = imageOrEmoji
		end
	end

	local nameLabel = item:FindFirstChild("BlockName")
	if nameLabel then nameLabel.Text = blockName end

	local quantityLabel = item:FindFirstChild("Quantity")
	if quantityLabel then quantityLabel.Text = "x" .. tostring(quantity) end

	local amountContainer = item:FindFirstChild("AmountContainer")
	if amountContainer then
		local amountNumber = amountContainer:FindFirstChild("AmountNumber")
		if amountNumber then amountNumber.Text = "$" .. FormatNumber(totalValue) end
	end

	item.Parent = ContentArea
	return item
end

--------------------------------------------------------------------------------
-- CLEAR & POPULATE
--------------------------------------------------------------------------------

local function ClearItems()
	for _, item in pairs(ClonedItems) do
		if item and item.Parent then item:Destroy() end
	end
	ClonedItems = {}

	if ContentArea then
		for _, child in ipairs(ContentArea:GetChildren()) do
			if child.Name ~= "ContainerTemplate" and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end
end

local function UpdateDisplay()
	-- Safety check - re-find elements if they're invalid
	if not ContentArea or not ContentArea.Parent then
		DebugPrint("ContentArea invalid, re-finding...")
		if not FindUIElements() then
			DebugPrint("Failed to re-find UI elements")
			return
		end
	end

	if not ContainerTemplate or not ContainerTemplate.Parent then
		DebugPrint("ContainerTemplate invalid, re-finding...")
		ContainerTemplate = ContentArea:FindFirstChild("ContainerTemplate")
		if not ContainerTemplate then
			DebugPrint("ContainerTemplate still not found!")
			return
		end
	end

	ClearItems()

	local success, data = pcall(function() return GetInventoryForSell:InvokeServer() end)
	if not success or not data then
		DebugPrint("Failed to get inventory data")
		if TotalWorthDisplay then TotalWorthDisplay.Text = "$0" end
		return
	end

	DebugPrint("Got inventory:", data.TotalValue, "total,", data.Ores and #data.Ores or 0, "ore types")

	if TotalWorthDisplay then TotalWorthDisplay.Text = "$" .. FormatNumber(data.TotalValue or 0) end

	if data.Ores and #data.Ores > 0 then
		for i, ore in ipairs(data.Ores) do
			local item = CreateItemFromTemplate(ore.Name or "Unknown", ore.Quantity or 0, ore.TotalValue or 0, i)
			if item then
				table.insert(ClonedItems, item)
				DebugPrint("Created item for", ore.Name, "- Visible:", item.Visible)
			else
				DebugPrint("Failed to create item for", ore.Name)
			end
		end
		DebugPrint("Created", #ClonedItems, "item containers")
	else
		DebugPrint("No ores in inventory")
	end

	task.defer(function()
		local layout = ContentArea:FindFirstChildOfClass("UIListLayout")
		if layout then ContentArea.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20) end
	end)
end

--------------------------------------------------------------------------------
-- FORWARD DECLARATION
--------------------------------------------------------------------------------

local CloseUI

--------------------------------------------------------------------------------
-- SOLD POPUP
--------------------------------------------------------------------------------

local function ShowSoldPopup()
	DebugPrint("ShowSoldPopup called!")

	-- Hide confirm popup immediately
	if ConfirmPopup then
		ConfirmPopup.Visible = false
	end

	if not SoldPopup then
		warn("[SellUI] SoldPopup is nil!")
		task.delay(1.5, function()
			IsAnimating = false
			IsOpen = true
			CloseUI()
		end)
		return
	end

	-- Store original values
	if not SoldPopupOriginalSize then
		SoldPopupOriginalSize = SoldPopup.Size
		SoldPopupOriginalPosition = SoldPopup.Position
	end

	DebugPrint("Showing SoldPopup, size:", tostring(SoldPopupOriginalSize))

	-- Setup and show
	SoldPopup.Size = UDim2.new(0, 0, 0, 0)
	SoldPopup.Position = SoldPopupOriginalPosition
	SoldPopup.Rotation = -15
	SoldPopup.Visible = true

	-- Pop in animation
	TweenService:Create(SoldPopup, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = SoldPopupOriginalSize,
		Position = SoldPopupOriginalPosition,
		Rotation = 0
	}):Play()

	-- Bounce
	task.delay(0.4, function()
		if not SoldPopup or not SoldPopup.Visible then return end
		TweenService:Create(SoldPopup, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = SoldPopupOriginalPosition + UDim2.new(0, 0, 0, -10)
		}):Play()
		task.delay(0.15, function()
			if not SoldPopup or not SoldPopup.Visible then return end
			TweenService:Create(SoldPopup, TweenInfo.new(0.15, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
				Position = SoldPopupOriginalPosition
			}):Play()
		end)
	end)

	-- Auto close after 1.5s
	task.delay(1.5, function()
		if not SoldPopup then return end

		TweenService:Create(SoldPopup, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
			Rotation = 15
		}):Play()

		task.delay(0.25, function()
			if SoldPopup then
				SoldPopup.Visible = false
				SoldPopup.Size = SoldPopupOriginalSize
				SoldPopup.Position = SoldPopupOriginalPosition
				SoldPopup.Rotation = 0
			end
			IsAnimating = false
			IsOpen = true
			CloseUI()
		end)
	end)
end

--------------------------------------------------------------------------------
-- OPEN/CLOSE UI
--------------------------------------------------------------------------------

local function OpenUI()
	if IsOpen or IsAnimating then return end
	if not Backround then return end

	IsAnimating = true
	IsOpen = true

	if not OriginalSize then
		OriginalSize = Backround.Size
		OriginalPosition = Backround.Position
	end
	if SellButton and not SellButtonOriginalSize then
		SellButtonOriginalSize = SellButton.Size
		SellButtonOriginalPosition = SellButton.Position
	end
	if CancelButton and not CancelButtonOriginalSize then
		CancelButtonOriginalSize = CancelButton.Size
		CancelButtonOriginalPosition = CancelButton.Position
	end
	if SellStationSign and not SignOriginalSize then
		SignOriginalSize = SellStationSign.Size
		SignOriginalPosition = SellStationSign.Position
	end

	-- Update display BEFORE showing UI (so data is ready)
	UpdateDisplay()

	SellUI.Enabled = true
	Backround.Visible = true
	if SellButton then SellButton.Visible = true end
	if CancelButton then CancelButton.Visible = true end
	if SellStationSign then SellStationSign.Visible = true end

	-- Start small
	Backround.Size = UDim2.new(OriginalSize.X.Scale * 0.8, OriginalSize.X.Offset * 0.8, OriginalSize.Y.Scale * 0.8, OriginalSize.Y.Offset * 0.8)
	Backround.Position = UDim2.new(OriginalPosition.X.Scale, OriginalPosition.X.Offset, OriginalPosition.Y.Scale + 0.05, OriginalPosition.Y.Offset)

	if SellButton then
		SellButton.Size = UDim2.new(SellButtonOriginalSize.X.Scale * 0.8, SellButtonOriginalSize.X.Offset * 0.8, SellButtonOriginalSize.Y.Scale * 0.8, SellButtonOriginalSize.Y.Offset * 0.8)
		SellButton.Position = UDim2.new(SellButtonOriginalPosition.X.Scale, SellButtonOriginalPosition.X.Offset, SellButtonOriginalPosition.Y.Scale + 0.05, SellButtonOriginalPosition.Y.Offset)
	end
	if CancelButton then
		CancelButton.Size = UDim2.new(CancelButtonOriginalSize.X.Scale * 0.8, CancelButtonOriginalSize.X.Offset * 0.8, CancelButtonOriginalSize.Y.Scale * 0.8, CancelButtonOriginalSize.Y.Offset * 0.8)
		CancelButton.Position = UDim2.new(CancelButtonOriginalPosition.X.Scale, CancelButtonOriginalPosition.X.Offset, CancelButtonOriginalPosition.Y.Scale + 0.05, CancelButtonOriginalPosition.Y.Offset)
	end
	if SellStationSign then
		SellStationSign.Size = UDim2.new(SignOriginalSize.X.Scale * 0.8, SignOriginalSize.X.Offset * 0.8, SignOriginalSize.Y.Scale * 0.8, SignOriginalSize.Y.Offset * 0.8)
		SellStationSign.Position = UDim2.new(SignOriginalPosition.X.Scale, SignOriginalPosition.X.Offset, SignOriginalPosition.Y.Scale + 0.05, SignOriginalPosition.Y.Offset)
	end

	-- Animate in
	TweenService:Create(Backround, TweenInfo.new(CONFIG.AnimTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = OriginalSize, Position = OriginalPosition}):Play()
	if SellButton then TweenService:Create(SellButton, TweenInfo.new(CONFIG.AnimTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = SellButtonOriginalSize, Position = SellButtonOriginalPosition}):Play() end
	if CancelButton then TweenService:Create(CancelButton, TweenInfo.new(CONFIG.AnimTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = CancelButtonOriginalSize, Position = CancelButtonOriginalPosition}):Play() end
	if SellStationSign then TweenService:Create(SellStationSign, TweenInfo.new(CONFIG.AnimTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = SignOriginalSize, Position = SignOriginalPosition}):Play() end

	task.delay(CONFIG.AnimTime, function()
		IsAnimating = false
	end)
end

CloseUI = function()
	if not IsOpen or IsAnimating then return end
	if not Backround then return end

	IsAnimating = true
	IsOpen = false
	IsSelling = false

	if ConfirmPopup then ConfirmPopup.Visible = false end
	if SoldPopup then SoldPopup.Visible = false end

	local endSize = UDim2.new(OriginalSize.X.Scale * 0.8, OriginalSize.X.Offset * 0.8, OriginalSize.Y.Scale * 0.8, OriginalSize.Y.Offset * 0.8)
	local endPosition = UDim2.new(OriginalPosition.X.Scale, OriginalPosition.X.Offset, OriginalPosition.Y.Scale + 0.05, OriginalPosition.Y.Offset)

	TweenService:Create(Backround, TweenInfo.new(CONFIG.AnimTime * 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = endSize, Position = endPosition}):Play()

	if SellButton and SellButtonOriginalSize then
		TweenService:Create(SellButton, TweenInfo.new(CONFIG.AnimTime * 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(SellButtonOriginalSize.X.Scale * 0.8, SellButtonOriginalSize.X.Offset * 0.8, SellButtonOriginalSize.Y.Scale * 0.8, SellButtonOriginalSize.Y.Offset * 0.8),
			Position = UDim2.new(SellButtonOriginalPosition.X.Scale, SellButtonOriginalPosition.X.Offset, SellButtonOriginalPosition.Y.Scale + 0.05, SellButtonOriginalPosition.Y.Offset)
		}):Play()
	end
	if CancelButton and CancelButtonOriginalSize then
		TweenService:Create(CancelButton, TweenInfo.new(CONFIG.AnimTime * 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(CancelButtonOriginalSize.X.Scale * 0.8, CancelButtonOriginalSize.X.Offset * 0.8, CancelButtonOriginalSize.Y.Scale * 0.8, CancelButtonOriginalSize.Y.Offset * 0.8),
			Position = UDim2.new(CancelButtonOriginalPosition.X.Scale, CancelButtonOriginalPosition.X.Offset, CancelButtonOriginalPosition.Y.Scale + 0.05, CancelButtonOriginalPosition.Y.Offset)
		}):Play()
	end
	if SellStationSign and SignOriginalSize then
		TweenService:Create(SellStationSign, TweenInfo.new(CONFIG.AnimTime * 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(SignOriginalSize.X.Scale * 0.8, SignOriginalSize.X.Offset * 0.8, SignOriginalSize.Y.Scale * 0.8, SignOriginalSize.Y.Offset * 0.8),
			Position = UDim2.new(SignOriginalPosition.X.Scale, SignOriginalPosition.X.Offset, SignOriginalPosition.Y.Scale + 0.05, SignOriginalPosition.Y.Offset)
		}):Play()
	end

	task.delay(CONFIG.AnimTime * 0.7, function()
		Backround.Visible = false
		if SellButton then SellButton.Visible = false end
		if CancelButton then CancelButton.Visible = false end
		if SellStationSign then SellStationSign.Visible = false end
		SellUI.Enabled = false

		Backround.Size = OriginalSize
		Backround.Position = OriginalPosition
		if SellButton then SellButton.Size = SellButtonOriginalSize; SellButton.Position = SellButtonOriginalPosition end
		if CancelButton then CancelButton.Size = CancelButtonOriginalSize; CancelButton.Position = CancelButtonOriginalPosition end
		if SellStationSign then SellStationSign.Size = SignOriginalSize; SellStationSign.Position = SignOriginalPosition end

		IsAnimating = false
		ClearItems()
	end)
end

--------------------------------------------------------------------------------
-- CONFIRM POPUP
--------------------------------------------------------------------------------

local function ShowConfirmPopup()
	if not ConfirmPopup then return false end

	if not ConfirmPopupOriginalSize then
		ConfirmPopupOriginalSize = ConfirmPopup.Size
		ConfirmPopupOriginalPosition = ConfirmPopup.Position
	end

	if ConfirmText and TotalWorthDisplay then
		ConfirmText.Text = "CONFIRM SELL: " .. (TotalWorthDisplay.Text or "$0")
	end

	ConfirmPopup.Visible = true
	ConfirmPopup.Size = UDim2.new(ConfirmPopupOriginalSize.X.Scale * 0.8, ConfirmPopupOriginalSize.X.Offset * 0.8, ConfirmPopupOriginalSize.Y.Scale * 0.8, ConfirmPopupOriginalSize.Y.Offset * 0.8)
	ConfirmPopup.Position = UDim2.new(ConfirmPopupOriginalPosition.X.Scale, ConfirmPopupOriginalPosition.X.Offset, ConfirmPopupOriginalPosition.Y.Scale + 0.02, ConfirmPopupOriginalPosition.Y.Offset)

	TweenService:Create(ConfirmPopup, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = ConfirmPopupOriginalSize, Position = ConfirmPopupOriginalPosition}):Play()
	return true
end

local function HideConfirmPopup()
	if not ConfirmPopup or not ConfirmPopup.Visible then return end

	TweenService:Create(ConfirmPopup, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(ConfirmPopupOriginalSize.X.Scale * 0.8, ConfirmPopupOriginalSize.X.Offset * 0.8, ConfirmPopupOriginalSize.Y.Scale * 0.8, ConfirmPopupOriginalSize.Y.Offset * 0.8),
		Position = UDim2.new(ConfirmPopupOriginalPosition.X.Scale, ConfirmPopupOriginalPosition.X.Offset, ConfirmPopupOriginalPosition.Y.Scale + 0.02, ConfirmPopupOriginalPosition.Y.Offset)
	}):Play()

	task.delay(0.2, function()
		if ConfirmPopup then
			ConfirmPopup.Visible = false
			ConfirmPopup.Size = ConfirmPopupOriginalSize
			ConfirmPopup.Position = ConfirmPopupOriginalPosition
		end
	end)
end

--------------------------------------------------------------------------------
-- SELL HANDLING
--------------------------------------------------------------------------------

local function ConfirmSell()
	DebugPrint("ConfirmSell called!")

	if not IsOpen then
		DebugPrint("Not open, aborting")
		return
	end

	if IsSelling then
		DebugPrint("Already selling, aborting")
		return
	end

	IsSelling = true

	local success, cashEarned, itemsSold = pcall(function()
		return SellInventory:InvokeServer()
	end)

	DebugPrint("Sell result:", success, cashEarned, itemsSold)

	if success and itemsSold and itemsSold > 0 then
		ClearItems()
		if TotalWorthDisplay then TotalWorthDisplay.Text = "$0" end
		if ContentArea then ContentArea.CanvasSize = UDim2.new(0, 0, 0, 0) end

		DebugPrint("Calling ShowSoldPopup...")
		ShowSoldPopup()
		-- IsSelling will be reset when UI closes
	else
		DebugPrint("Nothing to sell")
		IsSelling = false
		if ConfirmPopup then ConfirmPopup.Visible = false end

		-- Shake
		local origPos = Backround.Position
		for i = 1, 3 do
			TweenService:Create(Backround, TweenInfo.new(0.04), {Position = origPos + UDim2.new(0, 8, 0, 0)}):Play()
			task.wait(0.04)
			TweenService:Create(Backround, TweenInfo.new(0.04), {Position = origPos + UDim2.new(0, -8, 0, 0)}):Play()
			task.wait(0.04)
		end
		TweenService:Create(Backround, TweenInfo.new(0.04), {Position = origPos}):Play()
	end
end

--------------------------------------------------------------------------------
-- CONNECTIONS
--------------------------------------------------------------------------------

local function SetupConnections()
	if SellButton then
		SellButton.MouseButton1Click:Connect(function()
			local orig = SellButton.Size
			TweenService:Create(SellButton, TweenInfo.new(0.1), {Size = UDim2.new(orig.X.Scale*0.9, orig.X.Offset*0.9, orig.Y.Scale*0.9, orig.Y.Offset*0.9)}):Play()
			task.wait(0.1)
			TweenService:Create(SellButton, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = orig}):Play()
			if not ShowConfirmPopup() then ConfirmSell() end
		end)
	end

	if CancelButton then
		CancelButton.MouseButton1Click:Connect(function()
			local orig = CancelButton.Size
			TweenService:Create(CancelButton, TweenInfo.new(0.1), {Size = UDim2.new(orig.X.Scale*0.9, orig.X.Offset*0.9, orig.Y.Scale*0.9, orig.Y.Offset*0.9)}):Play()
			task.wait(0.1)
			TweenService:Create(CancelButton, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = orig}):Play()
			HideConfirmPopup()
			CloseUI()
		end)
	end

	if ConfirmButton then
		ConfirmButton.MouseButton1Click:Connect(function()
			DebugPrint("ConfirmButton clicked!")
			local orig = ConfirmButton.Size
			TweenService:Create(ConfirmButton, TweenInfo.new(0.1), {Size = UDim2.new(orig.X.Scale*0.9, orig.X.Offset*0.9, orig.Y.Scale*0.9, orig.Y.Offset*0.9)}):Play()
			task.wait(0.1)
			TweenService:Create(ConfirmButton, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = orig}):Play()
			ConfirmSell()
		end)
	end

	if CancelPopupButton then
		CancelPopupButton.MouseButton1Click:Connect(function()
			local orig = CancelPopupButton.Size
			TweenService:Create(CancelPopupButton, TweenInfo.new(0.1), {Size = UDim2.new(orig.X.Scale*0.9, orig.X.Offset*0.9, orig.Y.Scale*0.9, orig.Y.Offset*0.9)}):Play()
			task.wait(0.1)
			TweenService:Create(CancelPopupButton, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = orig}):Play()
			HideConfirmPopup()
		end)
	end
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

local function Initialize()
	print("[SellUI] Initializing...")
	if FindUIElements() then
		OriginalSize = Backround.Size
		OriginalPosition = Backround.Position
		if SellButton then SellButtonOriginalSize = SellButton.Size; SellButtonOriginalPosition = SellButton.Position end
		if CancelButton then CancelButtonOriginalSize = CancelButton.Size; CancelButtonOriginalPosition = CancelButton.Position end
		if SellStationSign then SignOriginalSize = SellStationSign.Size; SignOriginalPosition = SellStationSign.Position end

		SetupConnections()

		SellUI.Enabled = false
		Backround.Visible = false
		if SellButton then SellButton.Visible = false end
		if CancelButton then CancelButton.Visible = false end
		if SellStationSign then SellStationSign.Visible = false end

		print("[SellUI] ✓ Ready!")
		return true
	end
	return false
end

local function Reinitialize()
	IsOpen = false
	IsAnimating = false
	IsSelling = false
	OriginalSize = nil
	OriginalPosition = nil
	SellButtonOriginalSize = nil
	CancelButtonOriginalSize = nil
	SignOriginalSize = nil
	ConfirmPopupOriginalSize = nil
	SoldPopupOriginalSize = nil
	ClonedItems = {}
	task.wait(0.2)
	Initialize()
end

PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "SellUI" and child:IsA("ScreenGui") then
		if not SellUI or SellUI ~= child then
			task.wait(0.1)
			Reinitialize()
		end
	end
end)

EnterSellZone.OnClientEvent:Connect(function() OpenUI() end)
LeaveSellZone.OnClientEvent:Connect(function()
	if SoldPopup and SoldPopup.Visible then return end
	CloseUI()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and IsOpen then
		if SoldPopup and SoldPopup.Visible then return end
		HideConfirmPopup()
		CloseUI()
	end
end)

Initialize()
print("[SellUI] 🎮 Ready!")

return {Open = OpenUI, Close = CloseUI, Refresh = UpdateDisplay}
