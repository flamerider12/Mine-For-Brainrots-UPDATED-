--[[
    StorageDisplayUI.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    FIXED VERSION V2:
    - Handles ScreenGui being destroyed/recreated on respawn
    - Uses ChildAdded to detect when UI is available again
    - Properly re-establishes all connections after respawn
    
    IMPORTANT: This script assumes you have a ScreenGui named "StorageDisplayUI" 
    in StarterGui with a TextLabel named "StorageText" somewhere inside it.
    
    If your ScreenGui has ResetOnSpawn = true (default), the UI gets recreated
    on each respawn, so we need to re-find and re-connect everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

print("[StorageDisplay] Initializing...")

--// CONFIG //--
local CONFIG = {
	CountDuration = 0.3,
	PulseOnChange = true,
	PulseScale = 1.1,
	PulseDuration = 0.1,
	Separator = "/",
	Prefix = "",
	Suffix = "",
	OutlineColor = Color3.fromRGB(0, 0, 0),
	OutlineThickness = 2.5,
	OutlineTransparency = 0.1,
	NormalColor = Color3.fromRGB(255, 255, 255),
	WarningColor = Color3.fromRGB(255, 200, 50),
	FullColor = Color3.fromRGB(255, 80, 80),
	WarningThreshold = 0.75,
	GainFlashEnabled = false,
	SellColor = Color3.fromRGB(100, 200, 255),
	ColorFlashDuration = 0.2,
}

--// STATE //--
local CurrentStorage = 0
local MaxStorage = 50
local DisplayedStorage = 0
local StorageTextLabel: TextLabel? = nil
local TextOutlineStroke: UIStroke? = nil
local IsAnimating = false
local CountingConnection: RBXScriptConnection? = nil

-- Track connections so we can clean them up
local StorageLeaderstatsConnection: RBXScriptConnection? = nil
local CapacityLeaderstatsConnection: RBXScriptConnection? = nil
local StorageChangedConnection: RBXScriptConnection? = nil
local ScreenGuiAddedConnection: RBXScriptConnection? = nil

--// REMOTES //--
local Remotes: Folder? = nil

--// HELPERS //--

local function FormatStorage(current: number, max: number): string
	current = math.floor(current or 0)
	max = math.floor(max or 50)
	return CONFIG.Prefix .. tostring(current) .. CONFIG.Separator .. tostring(max) .. CONFIG.Suffix
end

local function GetFillPercentage(): number
	if MaxStorage <= 0 then return 0 end
	return CurrentStorage / MaxStorage
end

local function GetColorForFillLevel(): Color3
	local fill = GetFillPercentage()

	if fill >= 1 then
		return CONFIG.FullColor
	elseif fill >= CONFIG.WarningThreshold then
		local t = (fill - CONFIG.WarningThreshold) / (1 - CONFIG.WarningThreshold)
		return CONFIG.WarningColor:Lerp(CONFIG.FullColor, t)
	else
		local t = fill / CONFIG.WarningThreshold
		return CONFIG.NormalColor:Lerp(CONFIG.WarningColor, t * 0.3)
	end
end

local function AddTextOutline(textLabel: TextLabel): UIStroke
	local existing = textLabel:FindFirstChildOfClass("UIStroke")
	if existing then 
		TextOutlineStroke = existing
		return existing 
	end

	local stroke = Instance.new("UIStroke")
	stroke.Name = "TextOutline"
	stroke.Color = CONFIG.OutlineColor
	stroke.Thickness = CONFIG.OutlineThickness
	stroke.Transparency = CONFIG.OutlineTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = textLabel

	TextOutlineStroke = stroke
	return stroke
end

local function FindStorageTextLabel(): TextLabel?
	local screenGui = PlayerGui:FindFirstChild("StorageDisplayUI")
	if not screenGui then
		return nil
	end

	local function FindRecursive(parent: Instance): TextLabel?
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == "StorageText" and child:IsA("TextLabel") then
				return child
			end
			local found = FindRecursive(child)
			if found then return found end
		end
		return nil
	end

	return FindRecursive(screenGui)
end

--// ANIMATIONS //--

local function PulseText()
	if not StorageTextLabel or not StorageTextLabel.Parent or not CONFIG.PulseOnChange then return end

	local parent = StorageTextLabel.Parent
	if not parent then return end

	local uiScale = parent:FindFirstChild("UIScale")

	if uiScale then
		TweenService:Create(uiScale, TweenInfo.new(CONFIG.PulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = CONFIG.PulseScale
		}):Play()

		task.delay(CONFIG.PulseDuration, function()
			if uiScale and uiScale.Parent then
				TweenService:Create(uiScale, TweenInfo.new(CONFIG.PulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Scale = 1
				}):Play()
			end
		end)
	end
end

local function UpdateTextColor()
	if not StorageTextLabel or not StorageTextLabel.Parent then return end

	local targetColor = GetColorForFillLevel()
	TweenService:Create(StorageTextLabel, TweenInfo.new(0.3), {
		TextColor3 = targetColor
	}):Play()
end

local function AnimateCountTo(targetStorage: number)
	if not StorageTextLabel or not StorageTextLabel.Parent then return end

	-- Cancel any existing counting animation
	if CountingConnection then
		CountingConnection:Disconnect()
		CountingConnection = nil
	end

	local startStorage = DisplayedStorage
	local difference = targetStorage - startStorage

	if difference == 0 then
		UpdateTextColor()
		return
	end

	PulseText()

	IsAnimating = true
	local startTime = tick()

	CountingConnection = RunService.Heartbeat:Connect(function()
		-- Check if label still exists
		if not StorageTextLabel or not StorageTextLabel.Parent then
			if CountingConnection then
				CountingConnection:Disconnect()
				CountingConnection = nil
			end
			IsAnimating = false
			return
		end

		local elapsed = tick() - startTime
		local progress = math.min(elapsed / CONFIG.CountDuration, 1)
		local easedProgress = 1 - math.pow(1 - progress, 3)

		DisplayedStorage = math.floor(startStorage + (difference * easedProgress))
		StorageTextLabel.Text = FormatStorage(DisplayedStorage, MaxStorage)

		if progress >= 1 then
			if CountingConnection then
				CountingConnection:Disconnect()
				CountingConnection = nil
			end
			DisplayedStorage = targetStorage
			StorageTextLabel.Text = FormatStorage(targetStorage, MaxStorage)
			IsAnimating = false
			UpdateTextColor()
		end
	end)
end

--// UPDATE STORAGE //--

local function UpdateStorageDisplay(newStorage: number, newMax: number?, animate: boolean?)
	local storageChanged = (newStorage ~= CurrentStorage)
	local maxChanged = (newMax ~= nil and newMax ~= MaxStorage)

	if newMax then
		MaxStorage = newMax
	end

	CurrentStorage = newStorage

	-- Check if label exists and is valid
	if not StorageTextLabel or not StorageTextLabel.Parent then
		-- Try to find it again
		StorageTextLabel = FindStorageTextLabel()
		if StorageTextLabel then
			AddTextOutline(StorageTextLabel)
		end
	end

	if not StorageTextLabel or not StorageTextLabel.Parent then 
		-- Still can't find it, just store the value for later
		DisplayedStorage = newStorage
		return 
	end

	if animate ~= false and storageChanged then
		AnimateCountTo(newStorage)
	else
		DisplayedStorage = newStorage
		StorageTextLabel.Text = FormatStorage(newStorage, MaxStorage)
		UpdateTextColor()
	end
end

--// SYNC FROM LEADERSTATS //--

local function GetStorageFromLeaderstats(): (number, number)
	local leaderstats = Player:FindFirstChild("leaderstats")
	if leaderstats then
		local storageStat = leaderstats:FindFirstChild("Storage")
		local capacityStat = leaderstats:FindFirstChild("Capacity")

		local storage = storageStat and storageStat.Value or 0
		local capacity = capacityStat and capacityStat.Value or 50

		return storage, capacity
	end
	return 0, 50
end

local function SyncFromLeaderstats()
	local storage, capacity = GetStorageFromLeaderstats()
	UpdateStorageDisplay(storage, capacity, false)
end

--// SETUP UI AND CONNECTIONS //--

local function SetupLeaderstatsListener()
	-- Clean up old connections
	if StorageLeaderstatsConnection then
		StorageLeaderstatsConnection:Disconnect()
		StorageLeaderstatsConnection = nil
	end
	if CapacityLeaderstatsConnection then
		CapacityLeaderstatsConnection:Disconnect()
		CapacityLeaderstatsConnection = nil
	end

	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then
		-- Wait for leaderstats to appear
		local connection
		connection = Player.ChildAdded:Connect(function(child)
			if child.Name == "leaderstats" then
				connection:Disconnect()
				SetupLeaderstatsListener()
			end
		end)
		return
	end

	-- Storage stat
	local storageStat = leaderstats:FindFirstChild("Storage")
	if storageStat then
		StorageLeaderstatsConnection = storageStat.Changed:Connect(function(newValue)
			UpdateStorageDisplay(newValue, nil, true)
		end)
		print("[StorageDisplay] Connected to leaderstats.Storage")
	else
		-- Wait for Storage to appear
		local connection
		connection = leaderstats.ChildAdded:Connect(function(child)
			if child.Name == "Storage" then
				connection:Disconnect()
				SetupLeaderstatsListener()
			end
		end)
	end

	-- Capacity stat
	local capacityStat = leaderstats:FindFirstChild("Capacity")
	if capacityStat then
		CapacityLeaderstatsConnection = capacityStat.Changed:Connect(function(newValue)
			UpdateStorageDisplay(CurrentStorage, newValue, true)
		end)
		print("[StorageDisplay] Connected to leaderstats.Capacity")
	else
		-- Wait for Capacity to appear
		local connection
		connection = leaderstats.ChildAdded:Connect(function(child)
			if child.Name == "Capacity" then
				connection:Disconnect()
				SetupLeaderstatsListener()
			end
		end)
	end

	-- Initial sync
	SyncFromLeaderstats()
end

local function SetupRemoteListeners()
	if not Remotes then return end

	-- Clean up old connection
	if StorageChangedConnection then
		StorageChangedConnection:Disconnect()
		StorageChangedConnection = nil
	end

	local StorageChanged = Remotes:FindFirstChild("StorageChanged")
	if StorageChanged and StorageChanged:IsA("RemoteEvent") then
		StorageChangedConnection = StorageChanged.OnClientEvent:Connect(function(data)
			if data then
				local storage = data.StorageUsed or CurrentStorage
				local maxStorage = data.Capacity or MaxStorage
				UpdateStorageDisplay(storage, maxStorage, true)
			end
		end)
		print("[StorageDisplay] Connected to StorageChanged remote")
	end
end

local function SetupUI()
	-- Try to find the text label
	StorageTextLabel = FindStorageTextLabel()

	if StorageTextLabel then
		AddTextOutline(StorageTextLabel)
		-- Apply current value immediately
		StorageTextLabel.Text = FormatStorage(CurrentStorage, MaxStorage)
		UpdateTextColor()
		print("[StorageDisplay] Found StorageText label, applied value: " .. FormatStorage(CurrentStorage, MaxStorage))
	else
		print("[StorageDisplay] StorageText label not found yet, will retry when ScreenGui appears")
	end

	-- Sync from leaderstats
	SyncFromLeaderstats()
end

local function OnScreenGuiAdded(child: Instance)
	if child.Name == "StorageDisplayUI" and child:IsA("ScreenGui") then
		print("[StorageDisplay] StorageDisplayUI ScreenGui detected, setting up...")
		-- Small delay to let children load
		task.wait(0.1)
		SetupUI()
	end
end

local function Initialize()
	-- Wait for Remotes folder
	Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

	-- Setup remote listeners (these persist across respawns)
	SetupRemoteListeners()

	-- Setup leaderstats listener
	SetupLeaderstatsListener()

	-- Initial UI setup
	SetupUI()

	-- Watch for ScreenGui being added (after respawn)
	if ScreenGuiAddedConnection then
		ScreenGuiAddedConnection:Disconnect()
	end
	ScreenGuiAddedConnection = PlayerGui.ChildAdded:Connect(OnScreenGuiAdded)

	-- Also watch for it being removed
	PlayerGui.ChildRemoved:Connect(function(child)
		if child.Name == "StorageDisplayUI" then
			print("[StorageDisplay] StorageDisplayUI was removed (respawn?)")
			StorageTextLabel = nil
			TextOutlineStroke = nil
		end
	end)

	print("[StorageDisplay] Initialized - waiting for UI")
end

-- Initialize immediately
Initialize()

--// PUBLIC API //--
local StorageDisplayAPI = {}

function StorageDisplayAPI.SetStorage(current: number, max: number?, animate: boolean?)
	UpdateStorageDisplay(current, max, animate)
end

function StorageDisplayAPI.GetStorage(): (number, number)
	return CurrentStorage, MaxStorage
end

function StorageDisplayAPI.GetFillPercentage(): number
	return GetFillPercentage()
end

function StorageDisplayAPI.IsFull(): boolean
	return CurrentStorage >= MaxStorage
end

function StorageDisplayAPI.FormatStorage(current: number, max: number): string
	return FormatStorage(current, max)
end

function StorageDisplayAPI.Refresh()
	SetupUI()
end

return StorageDisplayAPI
