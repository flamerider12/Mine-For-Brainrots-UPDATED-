--!strict
--[[
    PortalController.lua
    Client Script - Place in StarterPlayerScripts
    
    Handles the portal button to teleport player back to surface
    - Spins the portal swirl animation
    - Teleports player to surface when depth >= 1
    - Shows "ALREADY AT SURFACE" message if at surface
    - Handles character respawn
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlayerScripts = Player:WaitForChild("PlayerScripts")
local Controllers = PlayerScripts:WaitForChild("Controllers")

-- Use PlotController for teleport logic (same as /plot command)
local PlotController = require(Controllers:WaitForChild("PlotController"))

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	SpinDuration = 16,
	MessageDuration = 2,
	SurfaceY = 0,
	DepthThreshold = 8,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local Portal: ScreenGui? = nil
local Main: Frame? = nil
local Swirl: ImageLabel? = nil
local TeleportLabel: TextLabel? = nil
local ClickButton: TextButton? = nil

local SpinTween: Tween? = nil
local IsInitialized = false
local Connections: {RBXScriptConnection} = {}
local OriginalMainSize: UDim2? = nil

--------------------------------------------------------------------------------
-- UI REFERENCES
--------------------------------------------------------------------------------

local function FindUIElements(): boolean
	Portal = PlayerGui:FindFirstChild("Portal") :: ScreenGui?
	if not Portal then return false end

	Main = Portal:FindFirstChild("Main") :: Frame?
	if not Main then warn("[PortalController] Main frame not found!") return false end

	Swirl = Main:FindFirstChild("Swirl") :: ImageLabel?
	if not Swirl then warn("[PortalController] Swirl not found!") return false end

	-- TextLabel is optional - text might be baked into image
	TeleportLabel = Main:FindFirstChild("Teleport") :: TextLabel?
	if not TeleportLabel then 
		print("[PortalController] Teleport label not found (optional)")
	end

	ClickButton = Main:FindFirstChild("ClickButton") :: TextButton?
	if not ClickButton then warn("[PortalController] ClickButton not found!") return false end

	return true
end

--------------------------------------------------------------------------------
-- MESSAGE DISPLAY
--------------------------------------------------------------------------------

local function ShowMessage(text: string)
	-- Create temporary message in center of screen
	local messageGui = Instance.new("ScreenGui")
	messageGui.Name = "PortalMessage"
	messageGui.ResetOnSpawn = false
	messageGui.DisplayOrder = 100
	messageGui.Parent = PlayerGui

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.new(0.5, 0, 0.5, 0)
	message.Size = UDim2.new(0, 400, 0, 60)
	message.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	message.BackgroundTransparency = 0.3
	message.BorderSizePixel = 0
	message.Text = text
	message.TextColor3 = Color3.fromRGB(255, 200, 100)
	message.TextScaled = true
	message.Font = Enum.Font.GothamBold
	message.Parent = messageGui

	-- Add rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = message

	-- Add stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 140, 60)
	stroke.Thickness = 2
	stroke.Parent = message

	-- Animate in
	message.Size = UDim2.new(0, 0, 0, 0)
	message.TextTransparency = 1
	message.BackgroundTransparency = 1

	local showTween = TweenService:Create(message, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 400, 0, 60),
		TextTransparency = 0,
		BackgroundTransparency = 0.3
	})
	showTween:Play()

	-- Fade out and destroy after delay
	task.delay(CONFIG.MessageDuration, function()
		local hideTween = TweenService:Create(message, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
			TextTransparency = 1,
			BackgroundTransparency = 1
		})
		hideTween:Play()
		hideTween.Completed:Wait()
		messageGui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- DEPTH HELPERS
--------------------------------------------------------------------------------

local function GetPlayerDepth(): number
	local character = Player.Character
	if not character then return 0 end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end

	-- Depth is how far below surface (surface Y = 0)
	local depth = CONFIG.SurfaceY - hrp.Position.Y
	return depth
end

local function IsAtSurface(): boolean
	return GetPlayerDepth() < CONFIG.DepthThreshold
end

--------------------------------------------------------------------------------
-- TELEPORT
--------------------------------------------------------------------------------

local function TeleportToSurface()
	-- Use PlotController's teleport logic (same as /plot command)
	PlotController.TeleportToPlot()
	print("[PortalController] Teleported to plot surface!")
end

--------------------------------------------------------------------------------
-- CLICK HANDLER
--------------------------------------------------------------------------------

local function OnPortalClicked()
	if IsAtSurface() then
		ShowMessage("ALREADY AT SURFACE")
		return
	end

	TeleportToSurface()
end

--------------------------------------------------------------------------------
-- ANIMATION
--------------------------------------------------------------------------------

local function StartSpinAnimation()
	if not Swirl then return end

	-- Stop existing tween
	if SpinTween then
		SpinTween:Cancel()
	end

	-- Reset rotation
	Swirl.Rotation = 0

	-- Create continuous spin
	SpinTween = TweenService:Create(Swirl, TweenInfo.new(CONFIG.SpinDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
		Rotation = 360
	})
	SpinTween:Play()
end

local function StopSpinAnimation()
	if SpinTween then
		SpinTween:Cancel()
		SpinTween = nil
	end
end

--------------------------------------------------------------------------------
-- SETUP
--------------------------------------------------------------------------------

local function SetupConnections()
	-- Clear old connections
	for _, conn in ipairs(Connections) do
		conn:Disconnect()
	end
	Connections = {}

	if not ClickButton then return end

	-- Click handler
	table.insert(Connections, ClickButton.MouseButton1Click:Connect(OnPortalClicked))
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function Initialize()
	print("[PortalController] Initializing...")

	if not FindUIElements() then
		return false
	end

	-- Setup Swirl properties
	if Swirl then
		Swirl.AnchorPoint = Vector2.new(0.5, 0.5)
		Swirl.Position = UDim2.new(0.5, 0, 0.5, 0)
	end

	SetupConnections()
	StartSpinAnimation()

	print("[PortalController] ✓ Ready!")
	return true
end

local function Reinitialize()
	StopSpinAnimation()

	-- Clear connections
	for _, conn in ipairs(Connections) do
		conn:Disconnect()
	end
	Connections = {}

	-- Reset references
	Portal = nil
	Main = nil
	Swirl = nil
	TeleportLabel = nil
	ClickButton = nil
	OriginalMainSize = nil

	task.wait(0.2)
	Initialize()
end

--------------------------------------------------------------------------------
-- RESPAWN HANDLING
--------------------------------------------------------------------------------

Player.CharacterAdded:Connect(function(character)
	-- Wait for character to load
	character:WaitForChild("HumanoidRootPart")

	-- Re-check UI elements (they should persist with ResetOnSpawn = false)
	if not Portal or not Portal.Parent then
		task.wait(0.5)
		Reinitialize()
	end
end)

-- Watch for Portal GUI being added (in case it loads late)
PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "Portal" and child:IsA("ScreenGui") then
		task.wait(0.1)
		Reinitialize()
	end
end)

--------------------------------------------------------------------------------
-- START
--------------------------------------------------------------------------------

-- Initial attempt
task.defer(function()
	-- Wait for GUI to load
	local portal = PlayerGui:WaitForChild("Portal", 10)
	if portal then
		task.wait(0.1)
		Initialize()
	else
		warn("[PortalController] Portal ScreenGui not found!")
	end
end)

return {}
