--!strict
--[[
	InventoryFullNotification.lua
	Displays "Inventory Full" message when player tries to mine with full storage
	Location: StarterPlayerScripts/Controllers/InventoryFullNotification.lua
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local InventoryFullNotification = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local IsInitialized = false
local ScreenGui: ScreenGui? = nil
local NotificationLabel: TextLabel? = nil
local CurrentTween: Tween? = nil
local FadeOutTween: Tween? = nil
local IsShowing = false

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function CreateUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryFullUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui
	ScreenGui = gui

	local label = Instance.new("TextLabel")
	label.Name = "InventoryFullLabel"
	label.Size = UDim2.new(0, 400, 0, 60)
	label.Position = UDim2.new(0.5, 0, 0.4, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	label.BackgroundTransparency = 0.3
	label.BorderSizePixel = 0
	label.Text = "⚠️ INVENTORY FULL ⚠️"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 28
	label.Font = Enum.Font.GothamBlack
	label.TextTransparency = 1
	label.BackgroundTransparency = 1
	label.Visible = false
	label.ZIndex = 100
	label.Parent = gui
	NotificationLabel = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 100, 100)
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = label

	-- Add pulsing glow effect
	local uiGradient = Instance.new("UIGradient")
	uiGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 50, 50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 50)),
	})
	uiGradient.Rotation = 0
	uiGradient.Parent = label
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function InventoryFullNotification.Initialize()
	if IsInitialized then return end
	IsInitialized = true
	CreateUI()
	print("[InventoryFullNotification] Initialized")
end

function InventoryFullNotification.Show()
	if not NotificationLabel then return end

	-- Cancel any existing fade out
	if FadeOutTween then
		FadeOutTween:Cancel()
		FadeOutTween = nil
	end

	NotificationLabel.Visible = true
	IsShowing = true

	-- Fade in
	local stroke = NotificationLabel:FindFirstChildOfClass("UIStroke")

	local fadeIn = TweenService:Create(NotificationLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		BackgroundTransparency = 0.3
	})
	fadeIn:Play()

	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
	end

	-- Pulse animation
	if CurrentTween then
		CurrentTween:Cancel()
	end

	local pulseUp = TweenService:Create(NotificationLabel, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Size = UDim2.new(0, 420, 0, 65)
	})
	pulseUp:Play()

	pulseUp.Completed:Connect(function()
		if IsShowing then
			local pulseDown = TweenService:Create(NotificationLabel, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.new(0, 400, 0, 60)
			})
			pulseDown:Play()
			CurrentTween = pulseDown
		end
	end)
	CurrentTween = pulseUp
end

function InventoryFullNotification.Hide()
	if not NotificationLabel or not IsShowing then return end

	IsShowing = false

	if CurrentTween then
		CurrentTween:Cancel()
		CurrentTween = nil
	end

	local stroke = NotificationLabel:FindFirstChildOfClass("UIStroke")

	-- Fade out
	FadeOutTween = TweenService:Create(NotificationLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		BackgroundTransparency = 1
	})
	FadeOutTween:Play()

	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.5), {Transparency = 1}):Play()
	end

	FadeOutTween.Completed:Connect(function()
		if not IsShowing and NotificationLabel then
			NotificationLabel.Visible = false
			NotificationLabel.Size = UDim2.new(0, 400, 0, 60)
		end
	end)
end

function InventoryFullNotification.IsVisible(): boolean
	return IsShowing
end

return InventoryFullNotification
