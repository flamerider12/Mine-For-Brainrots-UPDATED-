--!strict
--[[
	MegaBrainrotController.client.lua
	Client-side controller for the Mega Brainrot system

	FEATURES:
	- Timer UI (15-minute spawn countdown / 3-minute despawn countdown)
	- Rainbow highlight when within 20 blocks
	- Distance indicator above the block
	- Mining popup when block is mined

	UI NOTES:
	- All UI elements are created by code but can be replaced with designer-made UI
	- The script looks for existing UI elements first, falls back to code-created ones
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Configuration
local BLOCK_SIZE = 4 -- Default, will be updated from GameConfig
local DETECTION_RANGE_BLOCKS = 20

-- Rainbow colors for highlight cycling
local RAINBOW_COLORS = {
	Color3.fromRGB(255, 0, 0),    -- Red
	Color3.fromRGB(255, 127, 0),  -- Orange
	Color3.fromRGB(255, 255, 0),  -- Yellow
	Color3.fromRGB(0, 255, 0),    -- Green
	Color3.fromRGB(0, 0, 255),    -- Blue
	Color3.fromRGB(75, 0, 130),   -- Indigo
	Color3.fromRGB(148, 0, 211),  -- Violet
}
local COLOR_CYCLE_SPEED = 2 -- Seconds per full cycle

local MegaBrainrotController = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local IsInitialized = false
local CurrentState: "Waiting" | "Spawned" | "None" = "None"
local TimeRemaining: number = 0
local CurrentLayer: number = 0
local CurrentLayerName: string = ""

-- UI References
local TimerGui: ScreenGui? = nil
local TimerFrame: Frame? = nil
local TimerLabel: TextLabel? = nil
local TimerSubLabel: TextLabel? = nil

local MiningPopupGui: ScreenGui? = nil
local MiningPopupFrame: Frame? = nil
local MiningPopupLabel: TextLabel? = nil

-- Highlight
local MegaHighlight: Highlight? = nil
local DistanceBillboard: BillboardGui? = nil
local DistanceLabel: TextLabel? = nil

-- Tracked block
local TrackedBlock: BasePart? = nil

-- Update connections
local UpdateConnection: RBXScriptConnection? = nil
local HighlightConnection: RBXScriptConnection? = nil

-- Remotes
local Remotes: {[string]: RemoteEvent | RemoteFunction} = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", mins, secs)
end

local function LerpColor(colors: {Color3}, t: number): Color3
	local numColors = #colors
	local scaledT = (t % 1) * numColors
	local index = math.floor(scaledT) + 1
	local nextIndex = (index % numColors) + 1
	local lerpT = scaledT - math.floor(scaledT)

	local c1 = colors[index]
	local c2 = colors[nextIndex]

	return Color3.new(
		c1.R + (c2.R - c1.R) * lerpT,
		c1.G + (c2.G - c1.G) * lerpT,
		c1.B + (c2.B - c1.B) * lerpT
	)
end

local function GetDistanceToBlock(block: BasePart): number
	local character = LocalPlayer.Character
	if not character then return math.huge end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return math.huge end

	return (hrp.Position - block.Position).Magnitude
end

local function GetDistanceInBlocks(block: BasePart): number
	return math.floor(GetDistanceToBlock(block) / BLOCK_SIZE)
end

--------------------------------------------------------------------------------
-- TIMER UI
--------------------------------------------------------------------------------

local function CreateTimerUI()
	-- Check if designer-made UI exists
	local existingGui = PlayerGui:FindFirstChild("MegaBrainrotTimerGui")
	if existingGui then
		TimerGui = existingGui
		TimerFrame = existingGui:FindFirstChild("TimerFrame")
		TimerLabel = existingGui:FindFirstChild("TimerLabel", true)
		TimerSubLabel = existingGui:FindFirstChild("TimerSubLabel", true)
		return
	end

	-- Create UI programmatically
	local gui = Instance.new("ScreenGui")
	gui.Name = "MegaBrainrotTimerGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "TimerFrame"
	frame.Size = UDim2.new(0, 200, 0, 60)
	frame.Position = UDim2.new(0.5, -100, 0, 20)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 0, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Name = "TimerLabel"
	timerLbl.Size = UDim2.new(1, 0, 0.6, 0)
	timerLbl.Position = UDim2.new(0, 0, 0, 0)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Text = "15:00"
	timerLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerLbl.TextStrokeTransparency = 0
	timerLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.TextScaled = true
	timerLbl.Parent = frame

	local subLbl = Instance.new("TextLabel")
	subLbl.Name = "TimerSubLabel"
	subLbl.Size = UDim2.new(1, 0, 0.4, 0)
	subLbl.Position = UDim2.new(0, 0, 0.6, 0)
	subLbl.BackgroundTransparency = 1
	subLbl.Text = "MEGA BRAINROT SPAWNING..."
	subLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	subLbl.TextStrokeTransparency = 0.5
	subLbl.Font = Enum.Font.GothamBold
	subLbl.TextScaled = true
	subLbl.Parent = frame

	TimerGui = gui
	TimerFrame = frame
	TimerLabel = timerLbl
	TimerSubLabel = subLbl

	-- Start hidden
	gui.Enabled = false
end

local function UpdateTimerUI()
	if not TimerGui or not TimerLabel or not TimerSubLabel or not TimerFrame then return end

	TimerGui.Enabled = true
	TimerLabel.Text = FormatTime(TimeRemaining)

	local stroke = TimerFrame:FindFirstChildOfClass("UIStroke")

	if CurrentState == "Waiting" then
		TimerSubLabel.Text = "MEGA BRAINROT SPAWNING..."
		TimerSubLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		if stroke then stroke.Color = Color3.fromRGB(100, 100, 150) end

	elseif CurrentState == "Spawned" then
		TimerSubLabel.Text = `ACTIVE IN {CurrentLayerName}`
		TimerSubLabel.TextColor3 = Color3.fromRGB(255, 100, 255)
		if stroke then stroke.Color = Color3.fromRGB(255, 0, 255) end

		-- Pulse effect when spawned
		local pulse = (math.sin(tick() * 3) + 1) / 2
		TimerLabel.TextColor3 = Color3.fromRGB(
			255,
			math.floor(200 + pulse * 55),
			math.floor(200 + pulse * 55)
		)
	else
		TimerGui.Enabled = false
	end
end

local function AnimateTimerTransition(newState: string)
	if not TimerFrame then return end

	-- Quick scale animation
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local shrink = TweenService:Create(TimerFrame, TweenInfo.new(0.1), {
		Size = UDim2.new(0, 180, 0, 50)
	})
	local grow = TweenService:Create(TimerFrame, info, {
		Size = UDim2.new(0, 200, 0, 60)
	})

	shrink:Play()
	shrink.Completed:Connect(function()
		grow:Play()
	end)
end

--------------------------------------------------------------------------------
-- MINING POPUP UI
--------------------------------------------------------------------------------

local function CreateMiningPopupUI()
	-- Check if designer-made UI exists
	local existingGui = PlayerGui:FindFirstChild("MegaBrainrotPopupGui")
	if existingGui then
		MiningPopupGui = existingGui
		MiningPopupFrame = existingGui:FindFirstChild("PopupFrame")
		MiningPopupLabel = existingGui:FindFirstChild("PopupLabel", true)
		return
	end

	-- Create UI programmatically
	local gui = Instance.new("ScreenGui")
	gui.Name = "MegaBrainrotPopupGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "PopupFrame"
	frame.Size = UDim2.new(0, 400, 0, 150)
	frame.Position = UDim2.new(0.5, -200, 0.5, -75)
	frame.BackgroundColor3 = Color3.fromRGB(30, 10, 40)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 0, 255)
	stroke.Thickness = 4
	stroke.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255)),
	})
	gradient.Rotation = 0
	gradient.Parent = stroke

	local label = Instance.new("TextLabel")
	label.Name = "PopupLabel"
	label.Size = UDim2.new(1, -40, 1, -40)
	label.Position = UDim2.new(0, 20, 0, 20)
	label.BackgroundTransparency = 1
	label.Text = "MEGARARE BRAINROT ORE FOUND!"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(100, 0, 100)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = frame

	MiningPopupGui = gui
	MiningPopupFrame = frame
	MiningPopupLabel = label
end

local function ShowMiningPopup(rarity: string, variant: string)
	if not MiningPopupGui or not MiningPopupFrame then return end

	-- Update text
	if MiningPopupLabel then
		local variantText = (variant ~= "Normal") and (variant .. " ") or ""
		MiningPopupLabel.Text = `MEGARARE BRAINROT ORE FOUND!\n{variantText}{rarity} Egg!`
	end

	-- Show with animation
	MiningPopupGui.Enabled = true
	MiningPopupFrame.Size = UDim2.new(0, 0, 0, 0)
	MiningPopupFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

	local showTween = TweenService:Create(MiningPopupFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 400, 0, 150),
		Position = UDim2.new(0.5, -200, 0.5, -75)
	})
	showTween:Play()

	-- Animate gradient
	local stroke = MiningPopupFrame:FindFirstChildOfClass("UIStroke")
	local gradient = stroke and stroke:FindFirstChildOfClass("UIGradient")

	if gradient then
		task.spawn(function()
			local startTime = tick()
			while MiningPopupGui.Enabled and (tick() - startTime) < 5 do
				gradient.Rotation = ((tick() - startTime) * 90) % 360
				RunService.RenderStepped:Wait()
			end
		end)
	end

	-- Hide after delay
	task.delay(5, function()
		if not MiningPopupGui then return end

		local hideTween = TweenService:Create(MiningPopupFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0)
		})
		hideTween:Play()
		hideTween.Completed:Connect(function()
			MiningPopupGui.Enabled = false
		end)
	end)
end

--------------------------------------------------------------------------------
-- RAINBOW HIGHLIGHT
--------------------------------------------------------------------------------

local function CreateHighlight()
	if MegaHighlight then
		MegaHighlight:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "MegaBrainrotHighlight"
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = Color3.fromRGB(255, 0, 255)
	highlight.FillColor = Color3.fromRGB(255, 0, 255)
	highlight.Enabled = false
	highlight.Parent = PlayerGui

	MegaHighlight = highlight
end

local function CreateDistanceBillboard()
	if DistanceBillboard then
		DistanceBillboard:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MegaBrainrotDistance"
	billboard.Size = UDim2.new(0, 100, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = PlayerGui

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bg

	local label = Instance.new("TextLabel")
	label.Name = "DistanceLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "0m"
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = bg

	DistanceBillboard = billboard
	DistanceLabel = label
end

local function UpdateHighlight()
	if not TrackedBlock or not TrackedBlock.Parent then
		if MegaHighlight then MegaHighlight.Enabled = false end
		if DistanceBillboard then DistanceBillboard.Enabled = false end
		return
	end

	local distanceBlocks = GetDistanceInBlocks(TrackedBlock)
	local distanceMeters = GetDistanceToBlock(TrackedBlock)

	if distanceBlocks <= DETECTION_RANGE_BLOCKS then
		-- Within range - show highlight
		if MegaHighlight then
			MegaHighlight.Adornee = TrackedBlock
			MegaHighlight.Enabled = true

			-- Rainbow color cycling
			local t = (tick() / COLOR_CYCLE_SPEED) % 1
			local color = LerpColor(RAINBOW_COLORS, t)
			MegaHighlight.OutlineColor = color
			MegaHighlight.FillColor = color
		end

		-- Update distance billboard
		if DistanceBillboard and DistanceLabel then
			DistanceBillboard.Adornee = TrackedBlock
			DistanceBillboard.Enabled = true
			DistanceLabel.Text = `{math.floor(distanceMeters)}m`
		end
	else
		-- Out of range - hide
		if MegaHighlight then MegaHighlight.Enabled = false end
		if DistanceBillboard then DistanceBillboard.Enabled = false end
	end
end

--------------------------------------------------------------------------------
-- BLOCK TRACKING
--------------------------------------------------------------------------------

local function FindMegaBrainrotBlock(): BasePart?
	-- First try to get from server
	if Remotes.GetMegaBrainrotPosition then
		local func = Remotes.GetMegaBrainrotPosition :: RemoteFunction
		local result = func:InvokeServer()

		if result and result.Position then
			-- Find the actual block at that position
			for _, block in CollectionService:GetTagged("MegaBrainrot") do
				if block:IsA("BasePart") and block.Parent then
					return block
				end
			end
		end
	end

	-- Fallback: search tagged blocks
	for _, block in CollectionService:GetTagged("MegaBrainrot") do
		if block:IsA("BasePart") and block.Parent then
			return block
		end
	end

	return nil
end

local function OnBlockAdded(block: Instance)
	if block:IsA("BasePart") and CollectionService:HasTag(block, "MegaBrainrot") then
		TrackedBlock = block
		print("[MegaBrainrotController] Tracking new Mega Brainrot block")
	end
end

local function OnBlockRemoved(block: Instance)
	if TrackedBlock == block then
		TrackedBlock = nil
		if MegaHighlight then MegaHighlight.Enabled = false end
		if DistanceBillboard then DistanceBillboard.Enabled = false end
	end
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

local function OnStateChanged(data: {[string]: any})
	local newState = data.State
	AnimateTimerTransition(newState)

	CurrentState = newState
	TimeRemaining = data.TimeRemaining or 0

	if newState == "Spawned" then
		CurrentLayer = data.Layer or 0
		CurrentLayerName = data.LayerName or "Unknown"

		-- Find the spawned block
		task.delay(0.5, function()
			TrackedBlock = FindMegaBrainrotBlock()
		end)
	else
		CurrentLayer = 0
		CurrentLayerName = ""
		TrackedBlock = nil
	end

	UpdateTimerUI()
end

local function OnTimerUpdate(data: {[string]: any})
	TimeRemaining = data.TimeRemaining or 0

	if data.State then
		CurrentState = data.State
	end

	if data.Layer then
		CurrentLayer = data.Layer
	end

	UpdateTimerUI()
end

local function OnMegaBrainrotMined(data: {[string]: any})
	ShowMiningPopup(data.Rarity or "Godly", data.Variant or "Normal")

	-- Clear tracked block
	TrackedBlock = nil
	if MegaHighlight then MegaHighlight.Enabled = false end
	if DistanceBillboard then DistanceBillboard.Enabled = false end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function MegaBrainrotController.Initialize()
	if IsInitialized then return end
	IsInitialized = true

	-- Try to get block size from GameConfig
	local SharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if SharedFolder then
		local GameConfig = SharedFolder:FindFirstChild("GameConfig")
		if GameConfig then
			local config = require(GameConfig)
			if config.Mine and config.Mine.BlockSize then
				BLOCK_SIZE = config.Mine.BlockSize
			end
		end
	end

	-- Create UI
	CreateTimerUI()
	CreateMiningPopupUI()
	CreateHighlight()
	CreateDistanceBillboard()

	-- Get remotes
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	Remotes.StateChanged = remotesFolder:WaitForChild("MegaBrainrot_StateChanged", 10)
	Remotes.TimerUpdate = remotesFolder:WaitForChild("MegaBrainrot_TimerUpdate", 10)
	Remotes.MegaBrainrotMined = remotesFolder:WaitForChild("MegaBrainrot_Mined", 10)
	Remotes.GetMegaBrainrotPosition = remotesFolder:WaitForChild("MegaBrainrot_GetPosition", 10)

	-- Connect events
	if Remotes.StateChanged then
		(Remotes.StateChanged :: RemoteEvent).OnClientEvent:Connect(OnStateChanged)
	end

	if Remotes.TimerUpdate then
		(Remotes.TimerUpdate :: RemoteEvent).OnClientEvent:Connect(OnTimerUpdate)
	end

	if Remotes.MegaBrainrotMined then
		(Remotes.MegaBrainrotMined :: RemoteEvent).OnClientEvent:Connect(OnMegaBrainrotMined)
	end

	-- Track block additions/removals
	CollectionService:GetInstanceAddedSignal("MegaBrainrot"):Connect(OnBlockAdded)
	CollectionService:GetInstanceRemovedSignal("MegaBrainrot"):Connect(OnBlockRemoved)

	-- Check for existing mega brainrot blocks
	for _, block in CollectionService:GetTagged("MegaBrainrot") do
		OnBlockAdded(block)
	end

	-- Start highlight update loop
	HighlightConnection = RunService.RenderStepped:Connect(function()
		UpdateHighlight()
	end)

	print("[MegaBrainrotController] Initialized")
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function MegaBrainrotController.GetCurrentState(): string
	return CurrentState
end

function MegaBrainrotController.GetTimeRemaining(): number
	return TimeRemaining
end

function MegaBrainrotController.GetCurrentLayer(): number
	return CurrentLayer
end

function MegaBrainrotController.GetTrackedBlock(): BasePart?
	return TrackedBlock
end

function MegaBrainrotController.IsBlockInRange(): boolean
	if not TrackedBlock then return false end
	return GetDistanceInBlocks(TrackedBlock) <= DETECTION_RANGE_BLOCKS
end

return MegaBrainrotController
