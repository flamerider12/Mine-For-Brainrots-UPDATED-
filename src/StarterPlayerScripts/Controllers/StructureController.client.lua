--!strict
--[[
    StructureController.lua (V6.0 - Complete Rewrite)
    
    Client-side controller for Incubators and Pens.
    
    RESPONSIBILITIES:
    - ProximityPrompt management (E for primary action, F for secondary)
    - Selection UI for eggs/units (placeholder, customizable later)
    - Floating visual models (eggs in incubators, units in pens)
    - Timer displays for incubators
    - Income displays for pens
    - State synchronization with server
    
    INCUBATOR UI FLOW:
    1. Empty: Press E -> Opens Egg Selection Menu
    2. Incubating: Press E -> Speed Up, Press F -> Cancel (return egg)
    3. Ready: Press E -> Hatch (creates unit)
    
    PEN UI FLOW:
    1. Empty: Press E -> Opens Unit Selection Menu
    2. Occupied: Press E -> Collect Cash, Press F -> Remove Unit (collects + returns)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- MODULES
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

-- ASSETS
local ASSETS = ReplicatedStorage:WaitForChild("Assets")
local EggsFolder = ASSETS:FindFirstChild("Eggs")
local UnitsFolder = ASSETS:FindFirstChild("Brainrots") or ASSETS:FindFirstChild("Units")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local StructureController = {}

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------

type StructureCache = {
	Type: "Incubator" | "Pen",
	Object: Instance,
	Id: string,
	PrimaryPrompt: ProximityPrompt,
	SecondaryPrompt: ProximityPrompt?,
	PrimaryPromptUI: BillboardGui?,    -- Custom non-scaling UI
	SecondaryPromptUI: BillboardGui?,  -- Custom non-scaling UI
	InfoGui: BillboardGui?,
	Model: Instance?, -- Egg or Unit model
	Anchor: BasePart, -- Where to position things
	State: any?, -- Current server state
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local PROMPT_DISTANCE = 27
local MAX_RENDER_DISTANCE = 50
local MODEL_HOVER_HEIGHT = 3.5          -- How high the model floats above anchor
local MODEL_BOB_SPEED = 2
local MODEL_BOB_AMPLITUDE = 0.3
local MODEL_SPIN_SPEED = 1
local GUI_OFFSET_ABOVE_MODEL = 10        -- How far above the model the GUI floats

local RARITY_COLORS = {
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(50, 255, 50),
	Rare = Color3.fromRGB(50, 150, 255),
	Epic = Color3.fromRGB(200, 50, 255),
	Legendary = Color3.fromRGB(255, 150, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
	Godly = Color3.fromRGB(255, 255, 50),
}

local VARIANT_MATERIALS = {
	Normal = Enum.Material.SmoothPlastic,
	Gold = Enum.Material.Metal,
	Void = Enum.Material.Neon,
}

local VARIANT_COLORS = {
	Gold = Color3.fromRGB(255, 215, 0),
	Void = Color3.fromRGB(50, 0, 100),
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local Cache: { [string]: StructureCache } = {} -- [StructureId] = Cache
local Remotes: { [string]: RemoteEvent | RemoteFunction } = {}
local IsInitialized = false

-- UI References
local SelectionGui: ScreenGui? = nil
local SelectionFrame: Frame? = nil
local SelectionTitle: TextLabel? = nil
local SelectionScroll: ScrollingFrame? = nil
local SelectionClose: TextButton? = nil

local CurrentSelectionMode: "Egg" | "Unit" | nil = nil
local CurrentSelectionTarget: Instance? = nil


local PendingStates: { [string]: { State: any, Action: string } } = {}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

local function GetStructureId(object: Instance): string?
	if object:IsA("BasePart") then
		return object:GetAttribute("Id") or object.Name
	elseif object:IsA("Model") then
		return object:GetAttribute("Id") or object.Name
	end
	return nil
end

local function GetStructureType(object: Instance): "Incubator" | "Pen" | nil
	if CollectionService:HasTag(object, "Incubator") then
		return "Incubator"
	elseif CollectionService:HasTag(object, "Pen") then
		return "Pen"
	end
	return nil
end

local function GetAnchorPart(object: Instance): BasePart?
	if object:IsA("BasePart") then
		return object
	elseif object:IsA("Model") then
		return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function IsOwnStructure(object: Instance): boolean
	local current: Instance? = object
	while current and current ~= workspace do
		local ownerId = current:GetAttribute("OwnerUserId")
		if ownerId then
			return ownerId == LocalPlayer.UserId
		end
		current = current.Parent
	end
	return false
end

local function FormatTime(seconds: number): string
	if seconds <= 0 then return "READY!" end
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	if mins > 0 then
		return string.format("%d:%02d", mins, secs)
	else
		return string.format("%ds", secs)
	end
end

local function FormatCash(amount: number): string
	if amount >= 1000000 then
		return string.format("$%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return string.format("$%d", amount)
	end
end

--------------------------------------------------------------------------------
-- MODEL CREATION
--------------------------------------------------------------------------------

local function CreateEggModel(rarity: string, variant: string): Instance
	local eggName = `Egg_{rarity}`
	local template = EggsFolder and EggsFolder:FindFirstChild(eggName)
	local model: Instance

	if template then
		model = template:Clone()
	else
		-- Fallback procedural egg
		local part = Instance.new("Part")
		part.Name = "EggModel"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(2, 3, 2)
		part.Material = Enum.Material.SmoothPlastic
		part.Color = RARITY_COLORS[rarity] or RARITY_COLORS.Common
		part.Anchored = true
		part.CanCollide = false
		model = part
	end

	-- Apply variant visuals
	if variant ~= "Normal" then
		local variantColor = VARIANT_COLORS[variant]
		local variantMaterial = VARIANT_MATERIALS[variant]

		if model:IsA("BasePart") then
			if variantColor then model.Color = variantColor end
			if variantMaterial then model.Material = variantMaterial end
		end

		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				if variantColor then desc.Color = variantColor end
				if variantMaterial then desc.Material = variantMaterial end
			end
		end
	end

	-- Ensure anchored and non-collidable
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = false
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	return model
end

local function CreateUnitModel(unitId: string, variant: string): Instance
	local template = UnitsFolder and UnitsFolder:FindFirstChild(unitId)
	local model: Instance

	if template then
		model = template:Clone()
	else
		-- Fallback procedural unit
		local part = Instance.new("Part")
		part.Name = "UnitModel"
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(2, 2, 2)
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(255, 100, 100)
		part.Anchored = true
		part.CanCollide = false
		model = part
	end

	-- Apply variant visuals
	if variant ~= "Normal" then
		local variantColor = VARIANT_COLORS[variant]
		local variantMaterial = VARIANT_MATERIALS[variant]

		if model:IsA("BasePart") then
			if variantColor then model.Color = variantColor end
			if variantMaterial then model.Material = variantMaterial end
		end

		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				if variantColor then desc.Color = variantColor end
				if variantMaterial then desc.Material = variantMaterial end
			end
		end
	end

	-- Ensure anchored and non-collidable
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = false
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	return model
end

--------------------------------------------------------------------------------
-- BILLBOARD GUI CREATION
--------------------------------------------------------------------------------

local function CreateIncubatorGui(anchor: BasePart): BillboardGui
	local bbg = Instance.new("BillboardGui")
	bbg.Name = "IncubatorGui"
	bbg.Size = UDim2.fromOffset(180, 70)  -- Slightly smaller
	bbg.StudsOffset = Vector3.new(0, MODEL_HOVER_HEIGHT + GUI_OFFSET_ABOVE_MODEL, 0)
	bbg.AlwaysOnTop = true
	bbg.MaxDistance = MAX_RENDER_DISTANCE
	bbg.Enabled = false
	bbg.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = bbg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 150)
	stroke.Thickness = 2
	stroke.Parent = frame

	-- Timer label
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0.6, 0)
	timerLabel.Position = UDim2.new(0, 0, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.GothamBlack
	timerLabel.TextSize = 32
	timerLabel.TextColor3 = Color3.new(1, 1, 1)
	timerLabel.TextStrokeTransparency = 0.5
	timerLabel.Text = "0:00"
	timerLabel.Parent = frame

	-- Rarity label
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityLabel"
	rarityLabel.Size = UDim2.new(1, 0, 0.4, 0)
	rarityLabel.Position = UDim2.new(0, 0, 0.6, 0)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextSize = 16
	rarityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	rarityLabel.TextStrokeTransparency = 0.7
	rarityLabel.Text = "Common Egg"
	rarityLabel.Parent = frame

	return bbg
end

local function CreatePenGui(anchor: BasePart): BillboardGui
	local bbg = Instance.new("BillboardGui")
	bbg.Name = "PenGui"
	bbg.Size = UDim2.fromOffset(200, 90)  -- Slightly smaller
	bbg.StudsOffset = Vector3.new(0, MODEL_HOVER_HEIGHT + GUI_OFFSET_ABOVE_MODEL, 0)
	bbg.AlwaysOnTop = true
	bbg.MaxDistance = MAX_RENDER_DISTANCE
	bbg.Enabled = false
	bbg.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 30, 20)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = bbg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 150, 100)
	stroke.Thickness = 2
	stroke.Parent = frame

	-- Unit name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = "Unit Name"
	nameLabel.Parent = frame

	-- Cash accumulated label
	local cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Size = UDim2.new(1, 0, 0.4, 0)
	cashLabel.Position = UDim2.new(0, 0, 0.35, 0)
	cashLabel.BackgroundTransparency = 1
	cashLabel.Font = Enum.Font.GothamBlack
	cashLabel.TextSize = 28
	cashLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	cashLabel.TextStrokeTransparency = 0.3
	cashLabel.Text = "$0"
	cashLabel.Parent = frame

	-- Income rate label
	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "RateLabel"
	rateLabel.Size = UDim2.new(1, 0, 0.25, 0)
	rateLabel.Position = UDim2.new(0, 0, 0.75, 0)
	rateLabel.BackgroundTransparency = 1
	rateLabel.Font = Enum.Font.Gotham
	rateLabel.TextSize = 14
	rateLabel.TextColor3 = Color3.fromRGB(150, 200, 150)
	rateLabel.TextStrokeTransparency = 0.7
	rateLabel.Text = "+$0/s"
	rateLabel.Parent = frame

	return bbg
end

--------------------------------------------------------------------------------
-- SELECTION UI
--------------------------------------------------------------------------------

local function CreateSelectionUI()
	-- Main ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StructureSelectionUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 50
	screenGui.Enabled = false
	screenGui.Parent = PlayerGui

	-- Background blur/darken
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(400, 500)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(80, 90, 120)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -60, 0, 50)
	title.Position = UDim2.new(0, 15, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Select Item"
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(40, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 24
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "X"
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 8)
	closeBtnCorner.Parent = closeBtn

	-- Scrolling frame for items
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ItemScroll"
	scroll.Size = UDim2.new(1, -30, 1, -80)
	scroll.Position = UDim2.new(0, 15, 0, 70)
	scroll.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 110, 140)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 8)
	scrollCorner.Parent = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = scroll

	-- Store references
	SelectionGui = screenGui
	SelectionFrame = panel
	SelectionTitle = title
	SelectionScroll = scroll
	SelectionClose = closeBtn

	-- Close button handler
	closeBtn.MouseButton1Click:Connect(function()
		StructureController.CloseSelectionUI()
	end)

	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			StructureController.CloseSelectionUI()
		end
	end)
end

local function CreateItemButton(data: any, itemType: "Egg" | "Unit"): Frame
	local frame = Instance.new("Frame")
	frame.Name = data.GUID
	frame.Size = UDim2.new(1, -16, 0, 70)
	frame.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- Rarity color indicator
	local rarityColor = RARITY_COLORS[data.Rarity] or RARITY_COLORS.Common

	local indicator = Instance.new("Frame")
	indicator.Name = "RarityIndicator"
	indicator.Size = UDim2.new(0, 6, 1, -10)
	indicator.Position = UDim2.new(0, 5, 0, 5)
	indicator.BackgroundColor3 = rarityColor
	indicator.BorderSizePixel = 0
	indicator.Parent = frame

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(0, 3)
	indicatorCorner.Parent = indicator

	-- Item name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(0.6, -20, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 20, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	-- Details label (rarity + variant)
	local detailsLabel = Instance.new("TextLabel")
	detailsLabel.Name = "DetailsLabel"
	detailsLabel.Size = UDim2.new(0.6, -20, 0.5, 0)
	detailsLabel.Position = UDim2.new(0, 20, 0.5, 0)
	detailsLabel.BackgroundTransparency = 1
	detailsLabel.Font = Enum.Font.Gotham
	detailsLabel.TextSize = 14
	detailsLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailsLabel.Parent = frame

	if itemType == "Egg" then
		nameLabel.Text = data.DisplayName or `{data.Rarity} Egg`
		local variantText = data.Variant ~= "Normal" and `{data.Variant} ` or ""
		detailsLabel.Text = `{variantText}{data.Rarity}`
	else
		nameLabel.Text = data.Name or data.Id
		local variantText = data.Variant ~= "Normal" and `{data.Variant} ` or ""
		detailsLabel.Text = `{variantText}{data.Rarity} • +${data.IncomePerSecond or 1}/s`
	end

	-- Select button
	local selectBtn = Instance.new("TextButton")
	selectBtn.Name = "SelectButton"
	selectBtn.Size = UDim2.new(0.35, -10, 0.7, 0)
	selectBtn.Position = UDim2.new(0.65, 0, 0.15, 0)
	selectBtn.BackgroundColor3 = Color3.fromRGB(60, 150, 60)
	selectBtn.Font = Enum.Font.GothamBold
	selectBtn.TextSize = 16
	selectBtn.TextColor3 = Color3.new(1, 1, 1)
	selectBtn.Text = "SELECT"
	selectBtn.Parent = frame

	local selectBtnCorner = Instance.new("UICorner")
	selectBtnCorner.CornerRadius = UDim.new(0, 6)
	selectBtnCorner.Parent = selectBtn

	-- Hover effects
	selectBtn.MouseEnter:Connect(function()
		TweenService:Create(selectBtn, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(80, 200, 80)
		}):Play()
	end)

	selectBtn.MouseLeave:Connect(function()
		TweenService:Create(selectBtn, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(60, 150, 60)
		}):Play()
	end)

	-- Click handler
	selectBtn.MouseButton1Click:Connect(function()
		StructureController.OnItemSelected(data.GUID, itemType)
	end)

	return frame
end

function StructureController.OpenEggSelectionUI(targetStructure: Instance)
	if not SelectionGui then return end

	CurrentSelectionMode = "Egg"
	CurrentSelectionTarget = targetStructure

	-- Clear existing items
	for _, child in SelectionScroll:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	-- Update title
	SelectionTitle.Text = "Select Egg to Incubate"

	-- Show loading text
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Name = "LoadingMessage"
	loadingLabel.Size = UDim2.new(1, 0, 0, 50)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.Font = Enum.Font.Gotham
	loadingLabel.TextSize = 16
	loadingLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	loadingLabel.Text = "Loading..."
	loadingLabel.Parent = SelectionScroll

	SelectionGui.Enabled = true

	-- Fetch available eggs from server
	task.spawn(function()
		local eggs = Remotes.GetAvailableEggs:InvokeServer()

		-- Remove loading text
		if loadingLabel and loadingLabel.Parent then
			loadingLabel:Destroy()
		end

		-- Check if UI was closed while loading
		if not SelectionGui.Enabled or CurrentSelectionMode ~= "Egg" then
			return
		end

		if not eggs or #eggs == 0 then
			-- Show empty message
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Name = "EmptyMessage"
			emptyLabel.Size = UDim2.new(1, 0, 0, 100)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.TextSize = 18
			emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			emptyLabel.Text = "No eggs available.\nMine Brainrot blocks to find eggs!"
			emptyLabel.Parent = SelectionScroll
		else
			for _, eggData in ipairs(eggs) do
				local button = CreateItemButton(eggData, "Egg")
				button.Parent = SelectionScroll
			end
		end
	end)
end

function StructureController.OpenUnitSelectionUI(targetStructure: Instance)
	if not SelectionGui then return end

	CurrentSelectionMode = "Unit"
	CurrentSelectionTarget = targetStructure

	-- Clear existing items
	for _, child in SelectionScroll:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	-- Update title
	SelectionTitle.Text = "Select Brainrot for Pen"

	-- Show loading text
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Name = "LoadingMessage"
	loadingLabel.Size = UDim2.new(1, 0, 0, 50)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.Font = Enum.Font.Gotham
	loadingLabel.TextSize = 16
	loadingLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	loadingLabel.Text = "Loading..."
	loadingLabel.Parent = SelectionScroll

	SelectionGui.Enabled = true

	-- Fetch available units from server
	task.spawn(function()
		local units = Remotes.GetAvailableUnits:InvokeServer()

		-- Remove loading text
		if loadingLabel and loadingLabel.Parent then
			loadingLabel:Destroy()
		end

		-- Check if UI was closed while loading
		if not SelectionGui.Enabled or CurrentSelectionMode ~= "Unit" then
			return
		end

		if not units or #units == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Name = "EmptyMessage"
			emptyLabel.Size = UDim2.new(1, 0, 0, 100)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.TextSize = 18
			emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			emptyLabel.Text = "No Brainrots available.\nHatch eggs in incubators first!"
			emptyLabel.Parent = SelectionScroll
		else
			for _, unitData in ipairs(units) do
				local button = CreateItemButton(unitData, "Unit")
				button.Parent = SelectionScroll
			end
		end
	end)
end

function StructureController.CloseSelectionUI()
	if SelectionGui then
		SelectionGui.Enabled = false
	end
	CurrentSelectionMode = nil
	CurrentSelectionTarget = nil
end

function StructureController.OnItemSelected(itemGUID: string, itemType: "Egg" | "Unit")
	if not CurrentSelectionTarget then return end

	local target = CurrentSelectionTarget
	StructureController.CloseSelectionUI()

	task.spawn(function()
		local success, errorMsg

		if itemType == "Egg" then
			success, errorMsg = Remotes.PlaceEggInIncubator:InvokeServer(target, itemGUID)
		else
			success, errorMsg = Remotes.PlaceUnitInPen:InvokeServer(target, itemGUID)
		end

		if not success then
			warn(`[StructureController] Failed to place {itemType}: {errorMsg or "Unknown error"}`)
			-- TODO: Show error notification to user
		end
	end)
end

--------------------------------------------------------------------------------
-- NON-SCALING PROXIMITY PROMPT UI
--------------------------------------------------------------------------------

local function CreateNonScalingPromptUI(prompt: ProximityPrompt, anchor: BasePart, yOffset: number): BillboardGui
	-- Create a BillboardGui parented to the anchor (world space)
	local bbg = Instance.new("BillboardGui")
	bbg.Name = "PromptUI_" .. prompt.Name
	bbg.Size = UDim2.fromOffset(140, 36)  -- Fixed pixel size
	bbg.StudsOffset = Vector3.new(0, 2 + yOffset, 0)
	bbg.AlwaysOnTop = true
	bbg.MaxDistance = 100  -- Large distance so camera position doesn't hide it
	bbg.LightInfluence = 0
	bbg.ClipsDescendants = false
	bbg.Active = false
	bbg.Enabled = false
	bbg.Parent = anchor  -- Parent to anchor, not PlayerGui

	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = bbg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 90, 110)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame

	-- Key box (left side)
	local keyBox = Instance.new("Frame")
	keyBox.Name = "KeyBox"
	keyBox.Size = UDim2.new(0, 32, 0, 26)
	keyBox.Position = UDim2.new(0, 5, 0.5, 0)
	keyBox.AnchorPoint = Vector2.new(0, 0.5)
	keyBox.BackgroundColor3 = Color3.fromRGB(70, 80, 100)
	keyBox.BorderSizePixel = 0
	keyBox.Parent = frame

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 6)
	keyCorner.Parent = keyBox

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Size = UDim2.new(1, 0, 1, 0)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextSize = 16
	keyLabel.TextColor3 = Color3.new(1, 1, 1)
	keyLabel.Text = prompt.KeyboardKeyCode.Name
	keyLabel.Parent = keyBox

	-- Action text (right side)
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, -45, 1, 0)
	actionLabel.Position = UDim2.new(0, 42, 0, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamMedium
	actionLabel.TextSize = 14
	actionLabel.TextColor3 = Color3.new(1, 1, 1)
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Text = prompt.ActionText
	actionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	actionLabel.Parent = frame

	-- Update text when action changes
	prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		actionLabel.Text = prompt.ActionText
	end)

	-- Show/hide based on prompt enabled state and CHARACTER distance (not camera)
	local function UpdateVisibility()
		if not prompt.Enabled then
			bbg.Enabled = false
			return
		end

		local character = LocalPlayer.Character
		if not character then
			bbg.Enabled = false
			return
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			bbg.Enabled = false
			return
		end

		-- Use CHARACTER position for distance, not camera
		local distance = (anchor.Position - hrp.Position).Magnitude
		bbg.Enabled = distance <= prompt.MaxActivationDistance
	end

	-- Listen for prompt enabled changes
	prompt:GetPropertyChangedSignal("Enabled"):Connect(UpdateVisibility)

	-- Update visibility on heartbeat (for distance checking)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not prompt or not prompt.Parent then
			connection:Disconnect()
			return
		end
		UpdateVisibility()
	end)

	return bbg
end

--------------------------------------------------------------------------------
-- STRUCTURE REGISTRATION
--------------------------------------------------------------------------------

local function CreateProximityPrompts(cache: StructureCache)
	local anchor = cache.Anchor

	-- Create attachment for prompts if needed
	local attachment = anchor:FindFirstChild("PromptAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "PromptAttachment"
		attachment.Position = Vector3.new(0, 2, 0)
		attachment.Parent = anchor
	end

	-- Primary prompt (E key)
	local primaryPrompt = Instance.new("ProximityPrompt")
	primaryPrompt.Name = "PrimaryPrompt"
	primaryPrompt.ObjectText = cache.Type
	primaryPrompt.RequiresLineOfSight = false
	primaryPrompt.MaxActivationDistance = PROMPT_DISTANCE
	primaryPrompt.HoldDuration = 0
	primaryPrompt.KeyboardKeyCode = Enum.KeyCode.E
	primaryPrompt.UIOffset = Vector2.new(0, 0)
	primaryPrompt.Style = Enum.ProximityPromptStyle.Custom  -- Hide default UI
	primaryPrompt.Parent = attachment

	-- Secondary prompt (F key)
	local secondaryPrompt = Instance.new("ProximityPrompt")
	secondaryPrompt.Name = "SecondaryPrompt"
	secondaryPrompt.ObjectText = cache.Type
	secondaryPrompt.RequiresLineOfSight = false
	secondaryPrompt.MaxActivationDistance = PROMPT_DISTANCE
	secondaryPrompt.HoldDuration = 0
	secondaryPrompt.KeyboardKeyCode = Enum.KeyCode.F
	secondaryPrompt.UIOffset = Vector2.new(0, 50)
	secondaryPrompt.Style = Enum.ProximityPromptStyle.Custom  -- Hide default UI
	secondaryPrompt.Enabled = false
	secondaryPrompt.Parent = attachment

	cache.PrimaryPrompt = primaryPrompt
	cache.SecondaryPrompt = secondaryPrompt

	-- Set initial text based on type
	if cache.Type == "Incubator" then
		primaryPrompt.ActionText = "Place Egg"
	else
		primaryPrompt.ActionText = "Place Brainrot"
	end

	-- Connect handlers
	primaryPrompt.Triggered:Connect(function()
		StructureController.OnPrimaryInteraction(cache)
	end)

	secondaryPrompt.Triggered:Connect(function()
		StructureController.OnSecondaryInteraction(cache)
	end)

	-- Create custom non-scaling UI for each prompt
	cache.PrimaryPromptUI = CreateNonScalingPromptUI(primaryPrompt, anchor, .6)
	cache.SecondaryPromptUI = CreateNonScalingPromptUI(secondaryPrompt, anchor, -1.3)
end

local function RegisterStructure(object: Instance)
	local structureId = GetStructureId(object)
	local structureType = GetStructureType(object)

	if not structureId or not structureType then return end
	if Cache[structureId] then return end
	if not IsOwnStructure(object) then return end

	local anchor = GetAnchorPart(object)
	if not anchor then return end

	local cache: StructureCache = {
		Type = structureType,
		Object = object,
		Id = structureId,
		PrimaryPrompt = nil :: any,
		SecondaryPrompt = nil,
		InfoGui = nil,
		Model = nil,
		Anchor = anchor,
		State = nil,
	}
	
	Cache[structureId] = cache

	-- Check for pending state that arrived before registration
	if PendingStates[structureId] then
		local pending = PendingStates[structureId]
		print(`[StructureController] Applying pending state for {structureId}`)
		-- Make sure cache has prompts before updating state
		if cache.PrimaryPrompt then
			StructureController.UpdateStructureState(structureId, pending.State, pending.Action)
		else
			warn(`[StructureController] Cache for {structureId} missing prompts, skipping state apply`)
		end
		PendingStates[structureId] = nil
	else
		-- Fetch initial state from server (fallback)
		task.spawn(function()
			local result = Remotes.GetStructureState:InvokeServer(object)
			if result and result.State then
				StructureController.UpdateStructureState(structureId, result.State, "Initial")
			end
		end)
	end

	print(`[StructureController] Registered {structureType}: {structureId}`)

	-- Create prompts
	CreateProximityPrompts(cache)

	-- Create appropriate GUI
	if structureType == "Incubator" then
		cache.InfoGui = CreateIncubatorGui(anchor)
	else
		cache.InfoGui = CreatePenGui(anchor)
	end

	Cache[structureId] = cache

	-- Fetch initial state from server
	task.spawn(function()
		local result = Remotes.GetStructureState:InvokeServer(object)
		if result and result.State then
			StructureController.UpdateStructureState(structureId, result.State, "Initial")
		end
	end)

	print(`[StructureController] Registered {structureType}: {structureId}`)
end

local function UnregisterStructure(object: Instance)
	local structureId = GetStructureId(object)
	if not structureId then return end

	local cache = Cache[structureId]
	if not cache then return end

	-- Cleanup
	if cache.Model then
		cache.Model:Destroy()
	end
	if cache.InfoGui then
		cache.InfoGui:Destroy()
	end
	if cache.PrimaryPrompt then
		cache.PrimaryPrompt:Destroy()
	end
	if cache.SecondaryPrompt then
		cache.SecondaryPrompt:Destroy()
	end
	if cache.PrimaryPromptUI then
		cache.PrimaryPromptUI:Destroy()
	end
	if cache.SecondaryPromptUI then
		cache.SecondaryPromptUI:Destroy()
	end

	Cache[structureId] = nil
	print(`[StructureController] Unregistered: {structureId}`)
end

--------------------------------------------------------------------------------
-- INTERACTION HANDLERS
--------------------------------------------------------------------------------

function StructureController.OnPrimaryInteraction(cache: StructureCache)
	if cache.Type == "Incubator" then
		if not cache.State then
			-- Empty: Open egg selection
			StructureController.OpenEggSelectionUI(cache.Object)
		else
			-- Check if ready
			local elapsed = os.time() - cache.State.StartTime
			local hatchTime = cache.State.HatchTime or 30

			if elapsed >= hatchTime then
				-- Ready: Hatch
				task.spawn(function()
					local success, errorMsg, unit = Remotes.HatchEgg:InvokeServer(cache.Object)
					if success then
						print(`[StructureController] Hatched: {unit and unit.Name or "Unknown"}`)
					else
						warn(`[StructureController] Hatch failed: {errorMsg or "Unknown error"}`)
					end
				end)
			else
				-- Incubating: Speed up
				task.spawn(function()
					local success = Remotes.SpeedUpIncubator:InvokeServer(cache.Object)
					if success then
						print("[StructureController] Sped up incubation!")
					end
				end)
			end
		end
	elseif cache.Type == "Pen" then
		if not cache.State then
			-- Empty: Open unit selection
			StructureController.OpenUnitSelectionUI(cache.Object)
		else
			-- Occupied: Collect
			task.spawn(function()
				local success, errorMsg, amount = Remotes.CollectFromPen:InvokeServer(cache.Object)
				if success then
					print(`[StructureController] Collected: ${amount or 0}`)
				else
					warn(`[StructureController] Collect failed: {errorMsg or "Unknown error"}`)
				end
			end)
		end
	end
end

function StructureController.OnSecondaryInteraction(cache: StructureCache)
	if cache.Type == "Incubator" then
		if cache.State then
			-- Cancel incubation
			task.spawn(function()
				local success = Remotes.CancelIncubation:InvokeServer(cache.Object)
				if success then
					print("[StructureController] Cancelled incubation, egg returned")
				end
			end)
		end
	elseif cache.Type == "Pen" then
		if cache.State then
			-- Remove unit (collects + returns)
			task.spawn(function()
				local success, errorMsg, amount = Remotes.RemoveUnitFromPen:InvokeServer(cache.Object)
				if success then
					print(`[StructureController] Removed unit, collected ${amount or 0}`)
				else
					warn(`[StructureController] Remove failed: {errorMsg or "Unknown error"}`)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- STATE UPDATE
--------------------------------------------------------------------------------

function StructureController.UpdateStructureState(structureId: string, state: any?, action: string)
	local cache = Cache[structureId]
	if not cache then return end

	cache.State = state

	-- Cleanup old model
	if cache.Model then
		cache.Model:Destroy()
		cache.Model = nil
	end

	if cache.Type == "Incubator" then
		StructureController.UpdateIncubatorVisuals(cache, state, action)
	elseif cache.Type == "Pen" then
		StructureController.UpdatePenVisuals(cache, state, action)
	end
end

function StructureController.UpdateIncubatorVisuals(cache: StructureCache, state: any?, action: string)
	if not state then
		-- Empty state
		cache.PrimaryPrompt.ActionText = "Place Egg"
		if cache.SecondaryPrompt then
			cache.SecondaryPrompt.Enabled = false
		end
		if cache.InfoGui then
			cache.InfoGui.Enabled = false
		end
		return
	end

	-- Create egg model
	local eggModel = CreateEggModel(state.EggData.Rarity, state.EggData.Variant)
	eggModel.Parent = cache.Anchor
	cache.Model = eggModel

	-- Position model
	local offset = CFrame.new(0, MODEL_HOVER_HEIGHT, 0)
	if eggModel:IsA("Model") then
		eggModel:PivotTo(cache.Anchor.CFrame * offset)
	elseif eggModel:IsA("BasePart") then
		eggModel.CFrame = cache.Anchor.CFrame * offset
	end

	-- Update prompts
	local elapsed = os.time() - state.StartTime
	local hatchTime = state.HatchTime or 30

	if elapsed >= hatchTime then
		cache.PrimaryPrompt.ActionText = "Hatch"
	else
		cache.PrimaryPrompt.ActionText = "Speed Up"
	end

	if cache.SecondaryPrompt then
		cache.SecondaryPrompt.ActionText = "Cancel"
		cache.SecondaryPrompt.Enabled = true
	end

	-- Update GUI
	if cache.InfoGui then
		cache.InfoGui.Enabled = true

		local container = cache.InfoGui:FindFirstChild("Container")
		if container then
			local rarityLabel = container:FindFirstChild("RarityLabel")
			if rarityLabel then
				local variantText = state.EggData.Variant ~= "Normal" and `{state.EggData.Variant} ` or ""
				rarityLabel.Text = `{variantText}{state.EggData.Rarity} Egg`
				rarityLabel.TextColor3 = RARITY_COLORS[state.EggData.Rarity] or Color3.new(1, 1, 1)
			end
		end
	end
end

function StructureController.UpdatePenVisuals(cache: StructureCache, state: any?, action: string)
	if not state then
		-- Empty state
		cache.PrimaryPrompt.ActionText = "Place Brainrot"
		if cache.SecondaryPrompt then
			cache.SecondaryPrompt.Enabled = false
		end
		if cache.InfoGui then
			cache.InfoGui.Enabled = false
		end
		return
	end

	-- Create unit model
	local unitModel = CreateUnitModel(state.UnitData.Id, state.UnitData.Variant)
	unitModel.Parent = cache.Anchor
	cache.Model = unitModel

	-- Position model
	local offset = CFrame.new(0, MODEL_HOVER_HEIGHT, 0)
	if unitModel:IsA("Model") then
		unitModel:PivotTo(cache.Anchor.CFrame * offset)
	elseif unitModel:IsA("BasePart") then
		unitModel.CFrame = cache.Anchor.CFrame * offset
	end

	-- Update prompts
	cache.PrimaryPrompt.ActionText = "Collect"

	if cache.SecondaryPrompt then
		cache.SecondaryPrompt.ActionText = "Remove"
		cache.SecondaryPrompt.Enabled = true
	end

	-- Update GUI
	if cache.InfoGui then
		cache.InfoGui.Enabled = true

		local container = cache.InfoGui:FindFirstChild("Container")
		if container then
			local nameLabel = container:FindFirstChild("NameLabel")
			if nameLabel then
				local variantText = state.UnitData.Variant ~= "Normal" and `{state.UnitData.Variant} ` or ""
				nameLabel.Text = `{variantText}{state.UnitData.Name or state.UnitData.Id}`
				nameLabel.TextColor3 = RARITY_COLORS[state.UnitData.Rarity] or Color3.new(1, 1, 1)
			end

			-- Calculate income rate
			local unitConfig = GameConfig.Brainrots and GameConfig.Brainrots[state.UnitData.Id]
			local baseIncome = (unitConfig and unitConfig.IncomePerSecond) or 1
			local variantMult = 1
			if GameConfig.Eggs and GameConfig.Eggs.VariantMultipliers then
				variantMult = GameConfig.Eggs.VariantMultipliers[state.UnitData.Variant] or 1
			end
			local incomeRate = baseIncome * variantMult * (state.UnitData.Level or 1)

			local rateLabel = container:FindFirstChild("RateLabel")
			if rateLabel then
				rateLabel.Text = `+${incomeRate}/s`
			end
		end
	end
end

--------------------------------------------------------------------------------
-- RENDER LOOP
--------------------------------------------------------------------------------

local function StartRenderLoop()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local osTime = os.time()

		local character = LocalPlayer.Character
		local playerPosition = Vector3.new(0, 0, 0)
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				playerPosition = hrp.Position
			end
		end

		for structureId, cache in pairs(Cache) do
			if not cache or not cache.Anchor or not cache.Anchor.Parent then
				continue
			end

			-- Distance culling
			local distance = (cache.Anchor.Position - playerPosition).Magnitude
			local shouldRender = distance <= MAX_RENDER_DISTANCE

			if cache.InfoGui then
				local hasState = cache.State ~= nil
				cache.InfoGui.Enabled = shouldRender and hasState
			end

			if not shouldRender then
				continue
			end

			-- Animate model (bob + spin)
			if cache.Model then
				local bobOffset = math.sin(now * MODEL_BOB_SPEED) * MODEL_BOB_AMPLITUDE
				local spinAngle = now * MODEL_SPIN_SPEED
				local targetCFrame = cache.Anchor.CFrame 
					* CFrame.new(0, MODEL_HOVER_HEIGHT + bobOffset, 0)
					* CFrame.Angles(0, spinAngle, 0)

				if cache.Model:IsA("Model") then
					cache.Model:PivotTo(targetCFrame)
				elseif cache.Model:IsA("BasePart") then
					cache.Model.CFrame = targetCFrame
				end

				-- Update GUI offset to follow model
				if cache.InfoGui then
					cache.InfoGui.StudsOffset = Vector3.new(0, MODEL_HOVER_HEIGHT + bobOffset + GUI_OFFSET_ABOVE_MODEL, 0)
				end
			end

			-- Update GUI content
			if cache.State and cache.InfoGui then
				local container = cache.InfoGui:FindFirstChild("Container")
				if not container then continue end

				if cache.Type == "Incubator" then
					-- Update timer
					local elapsed = osTime - cache.State.StartTime
					local hatchTime = cache.State.HatchTime or 30
					local remaining = math.max(0, hatchTime - elapsed)

					local timerLabel = container:FindFirstChild("TimerLabel")
					if timerLabel then
						timerLabel.Text = FormatTime(remaining)

						if remaining <= 0 then
							timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
							-- Update prompt if not already updated
							if cache.PrimaryPrompt.ActionText ~= "Hatch" then
								cache.PrimaryPrompt.ActionText = "Hatch"
							end
						else
							timerLabel.TextColor3 = Color3.new(1, 1, 1)
						end
					end

				elseif cache.Type == "Pen" then
					-- Update accumulated cash display
					local unitConfig = GameConfig.Brainrots and GameConfig.Brainrots[cache.State.UnitData.Id]
					local baseIncome = (unitConfig and unitConfig.IncomePerSecond) or 1
					local variantMult = 1
					if GameConfig.Eggs and GameConfig.Eggs.VariantMultipliers then
						variantMult = GameConfig.Eggs.VariantMultipliers[cache.State.UnitData.Variant] or 1
					end
					local incomeRate = baseIncome * variantMult * (cache.State.UnitData.Level or 1)

					local elapsed = osTime - cache.State.LastCollectTime
					local accumulated = math.floor(incomeRate * elapsed)

					local cashLabel = container:FindFirstChild("CashLabel")
					if cashLabel then
						cashLabel.Text = FormatCash(accumulated)
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- SERVER EVENT HANDLERS
--------------------------------------------------------------------------------

local function OnStructureStateChanged(data: any)
	if not data then return end

	local structureId = data.StructureId
	local structureType = data.StructureType
	local action = data.Action
	local state = data.State

	print(`[StructureController] State changed: {structureType} {structureId} - {action}`)

	-- Check if structure is registered yet
	if not Cache[structureId] then
		-- Store for later when structure registers
		print(`[StructureController] Structure {structureId} not registered yet, queuing state`)
		PendingStates[structureId] = { State = state, Action = action, Data = data }
		return
	end

	StructureController.UpdateStructureState(structureId, state, action)

	-- Handle special actions (same as before)
	if action == "Hatched" and data.HatchedUnit then
		print(`[StructureController] NEW UNIT: {data.HatchedUnit.Name}`)
	end

	if action == "Collected" and data.AmountCollected then
		print(`[StructureController] Collected ${data.AmountCollected}`)
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function StructureController.Initialize()
	if IsInitialized then return end
	IsInitialized = true

	-- Wait for remotes
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	Remotes.StructureStateChanged = remotesFolder:WaitForChild("StructureStateChanged")
	Remotes.GetAvailableEggs = remotesFolder:WaitForChild("GetAvailableEggs")
	Remotes.GetAvailableUnits = remotesFolder:WaitForChild("GetAvailableUnits")
	Remotes.PlaceEggInIncubator = remotesFolder:WaitForChild("PlaceEggInIncubator")
	Remotes.SpeedUpIncubator = remotesFolder:WaitForChild("SpeedUpIncubator")
	Remotes.CancelIncubation = remotesFolder:WaitForChild("CancelIncubation")
	Remotes.HatchEgg = remotesFolder:WaitForChild("HatchEgg")
	Remotes.PlaceUnitInPen = remotesFolder:WaitForChild("PlaceUnitInPen")
	Remotes.CollectFromPen = remotesFolder:WaitForChild("CollectFromPen")
	Remotes.RemoveUnitFromPen = remotesFolder:WaitForChild("RemoveUnitFromPen")
	Remotes.GetStructureState = remotesFolder:WaitForChild("GetStructureState")
	Remotes.GetAllStructureStates = remotesFolder:WaitForChild("GetAllStructureStates")

	-- Create UI
	CreateSelectionUI()

	-- Connect server events
	Remotes.StructureStateChanged.OnClientEvent:Connect(OnStructureStateChanged)

	-- Register existing structures
	for _, obj in CollectionService:GetTagged("Incubator") do
		RegisterStructure(obj)
	end
	for _, obj in CollectionService:GetTagged("Pen") do
		RegisterStructure(obj)
	end

	-- Listen for new structures
	CollectionService:GetInstanceAddedSignal("Incubator"):Connect(RegisterStructure)
	CollectionService:GetInstanceAddedSignal("Pen"):Connect(RegisterStructure)
	CollectionService:GetInstanceRemovedSignal("Incubator"):Connect(UnregisterStructure)
	CollectionService:GetInstanceRemovedSignal("Pen"):Connect(UnregisterStructure)

	-- Start render loop
	StartRenderLoop()

	print("[StructureController] V6.0 Initialized - Complete Rewrite")
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function StructureController.GetStructureState(structureId: string): any?
	local cache = Cache[structureId]
	return cache and cache.State
end

function StructureController.IsStructureOccupied(structureId: string): boolean
	local cache = Cache[structureId]
	return cache and cache.State ~= nil
end

return StructureController
