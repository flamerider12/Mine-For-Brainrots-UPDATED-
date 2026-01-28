--[[
    CashDisplayUI.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    FIXED VERSION V2:
    - Handles ScreenGui being destroyed/recreated on respawn
    - Uses ChildAdded to detect when UI is available again
    - Properly re-establishes all connections after respawn
    
    IMPORTANT: This script assumes you have a ScreenGui named "CashDisplayUI" 
    in StarterGui with a TextLabel named "CashText" somewhere inside it.
    
    If your ScreenGui has ResetOnSpawn = true (default), the UI gets recreated
    on each respawn, so we need to re-find and re-connect everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

print("[CashDisplay] Initializing...")

--// CONFIG //--
local CONFIG = {
	CountDuration = 0.5,
	PulseOnChange = true,
	PulseScale = 1.15,
	PulseDuration = 0.15,
	UseCommas = true,
	Prefix = "$",
	Suffix = "",
	OutlineColor = Color3.fromRGB(212, 172, 10),
	OutlineThickness = 2.5,
	OutlineTransparency = 0.1,
	TextColor = Color3.fromRGB(242, 200, 81),
	GainColor = Color3.fromRGB(242, 200, 81),
	LossColor = Color3.fromRGB(255, 100, 100),
	ColorFlashDuration = 0.3,
}

--// STATE //--
local CurrentCash = 0
local DisplayedCash = 0
local CashTextLabel: TextLabel? = nil
local OriginalTextColor: Color3? = nil
local IsAnimating = false
local CountingConnection: RBXScriptConnection? = nil

-- Track connections so we can clean them up
local LeaderstatsConnection: RBXScriptConnection? = nil
local CashChangedConnection: RBXScriptConnection? = nil
local ScreenGuiAddedConnection: RBXScriptConnection? = nil

--// REMOTES //--
local Remotes: Folder? = nil

--// HELPERS //--

local function FormatNumber(n: number): string
	n = math.floor(n or 0)

	-- Suffixes for large numbers
	local suffixes = {
		{1e24, "Sep"},   -- Septillion
		{1e21, "Sex"},   -- Sextillion
		{1e18, "Quin"},  -- Quintillion
		{1e15, "Quad"},  -- Quadrillion
		{1e12, "T"},     -- Trillion
		{1e9, "B"},      -- Billion
		{1e6, "M"},      -- Million
	}

	for _, data in ipairs(suffixes) do
		local threshold = data[1]
		local suffix = data[2]
		if n >= threshold then
			return CONFIG.Prefix .. string.format("%.2f%s", n / threshold, suffix) .. CONFIG.Suffix
		end
	end

	-- Under 1 million: use commas
	if not CONFIG.UseCommas then
		return CONFIG.Prefix .. tostring(n) .. CONFIG.Suffix
	end
	local formatted = tostring(n)
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return CONFIG.Prefix .. formatted .. CONFIG.Suffix
end

local function AddTextOutline(textLabel: TextLabel)
	local existing = textLabel:FindFirstChildOfClass("UIStroke")
	if existing then return existing end

	local stroke = Instance.new("UIStroke")
	stroke.Name = "TextOutline"
	stroke.Color = CONFIG.OutlineColor
	stroke.Thickness = CONFIG.OutlineThickness
	stroke.Transparency = CONFIG.OutlineTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = textLabel
	return stroke
end

local function FindCashTextLabel(): TextLabel?
	local screenGui = PlayerGui:FindFirstChild("CashDisplayUI")
	if not screenGui then
		return nil
	end

	local function FindRecursive(parent: Instance): TextLabel?
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == "CashText" and child:IsA("TextLabel") then
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
	if not CashTextLabel or not CashTextLabel.Parent or not CONFIG.PulseOnChange then return end

	local parent = CashTextLabel.Parent
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

local function FlashColor(gained: boolean)
	if not CashTextLabel or not CashTextLabel.Parent or not OriginalTextColor then return end

	local flashColor = gained and CONFIG.GainColor or CONFIG.LossColor
	if not flashColor then return end

	CashTextLabel.TextColor3 = flashColor

	task.delay(CONFIG.ColorFlashDuration, function()
		if CashTextLabel and CashTextLabel.Parent and OriginalTextColor then
			TweenService:Create(CashTextLabel, TweenInfo.new(0.2), {
				TextColor3 = OriginalTextColor
			}):Play()
		end
	end)
end

local function AnimateCountTo(targetCash: number)
	if not CashTextLabel or not CashTextLabel.Parent then return end

	-- Cancel any existing counting animation
	if CountingConnection then
		CountingConnection:Disconnect()
		CountingConnection = nil
	end

	local startCash = DisplayedCash
	local difference = targetCash - startCash

	if difference == 0 then return end

	local gained = difference > 0

	PulseText()
	FlashColor(gained)

	IsAnimating = true
	local startTime = tick()

	CountingConnection = RunService.Heartbeat:Connect(function()
		-- Check if label still exists
		if not CashTextLabel or not CashTextLabel.Parent then
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

		DisplayedCash = math.floor(startCash + (difference * easedProgress))
		CashTextLabel.Text = FormatNumber(DisplayedCash)

		if progress >= 1 then
			if CountingConnection then
				CountingConnection:Disconnect()
				CountingConnection = nil
			end
			DisplayedCash = targetCash
			CashTextLabel.Text = FormatNumber(targetCash)
			IsAnimating = false
		end
	end)
end

--// UPDATE CASH //--

local function UpdateCashDisplay(newCash: number, animate: boolean?)
	CurrentCash = newCash

	-- Check if label exists and is valid
	if not CashTextLabel or not CashTextLabel.Parent then
		-- Try to find it again
		CashTextLabel = FindCashTextLabel()
		if CashTextLabel then
			AddTextOutline(CashTextLabel)
			OriginalTextColor = CashTextLabel.TextColor3
		end
	end

	if not CashTextLabel or not CashTextLabel.Parent then 
		-- Still can't find it, just store the value for later
		DisplayedCash = newCash
		return 
	end

	if animate ~= false and DisplayedCash ~= newCash then
		AnimateCountTo(newCash)
	else
		DisplayedCash = newCash
		CashTextLabel.Text = FormatNumber(newCash)
	end
end

--// SYNC FROM LEADERSTATS //--

local function GetCashFromLeaderstats(): number
	local leaderstats = Player:FindFirstChild("leaderstats")
	if leaderstats then
		local cashStat = leaderstats:FindFirstChild("Cash")
		if cashStat then
			return cashStat.Value
		end
	end
	return 0
end

local function SyncFromLeaderstats()
	local cash = GetCashFromLeaderstats()
	UpdateCashDisplay(cash, false)
end

--// SETUP UI AND CONNECTIONS //--

local function SetupLeaderstatsListener()
	-- Clean up old connection
	if LeaderstatsConnection then
		LeaderstatsConnection:Disconnect()
		LeaderstatsConnection = nil
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

	local cashStat = leaderstats:FindFirstChild("Cash")
	if not cashStat then
		-- Wait for Cash to appear
		local connection
		connection = leaderstats.ChildAdded:Connect(function(child)
			if child.Name == "Cash" then
				connection:Disconnect()
				SetupLeaderstatsListener()
			end
		end)
		return
	end

	-- Listen for changes
	LeaderstatsConnection = cashStat.Changed:Connect(function(newValue)
		UpdateCashDisplay(newValue, true)
	end)

	-- Initial sync
	UpdateCashDisplay(cashStat.Value, false)
	print("[CashDisplay] Connected to leaderstats.Cash")
end

local function SetupRemoteListeners()
	if not Remotes then return end

	-- Clean up old connection
	if CashChangedConnection then
		CashChangedConnection:Disconnect()
		CashChangedConnection = nil
	end

	local CashChanged = Remotes:FindFirstChild("CashChanged")
	if CashChanged and CashChanged:IsA("RemoteEvent") then
		CashChangedConnection = CashChanged.OnClientEvent:Connect(function(data)
			if data and data.Cash then
				UpdateCashDisplay(data.Cash, true)
			end
		end)
		print("[CashDisplay] Connected to CashChanged remote")
	end
end

local function SetupUI()
	-- Try to find the text label
	CashTextLabel = FindCashTextLabel()

	if CashTextLabel then
		AddTextOutline(CashTextLabel)
		OriginalTextColor = CashTextLabel.TextColor3
		-- Apply current value immediately
		CashTextLabel.Text = FormatNumber(CurrentCash)
		print("[CashDisplay] Found CashText label, applied value: " .. FormatNumber(CurrentCash))
	else
		print("[CashDisplay] CashText label not found yet, will retry when ScreenGui appears")
	end

	-- Sync from leaderstats
	SyncFromLeaderstats()
end

local function OnScreenGuiAdded(child: Instance)
	if child.Name == "CashDisplayUI" and child:IsA("ScreenGui") then
		print("[CashDisplay] CashDisplayUI ScreenGui detected, setting up...")
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

	-- Also watch for it being removed and re-added
	PlayerGui.ChildRemoved:Connect(function(child)
		if child.Name == "CashDisplayUI" then
			print("[CashDisplay] CashDisplayUI was removed (respawn?)")
			CashTextLabel = nil
		end
	end)

	print("[CashDisplay] Initialized - waiting for UI")
end

-- Initialize immediately
Initialize()

--// PUBLIC API //--
local CashDisplayAPI = {}

function CashDisplayAPI.SetCash(amount: number, animate: boolean?)
	UpdateCashDisplay(amount, animate)
end

function CashDisplayAPI.GetCash(): number
	return CurrentCash
end

function CashDisplayAPI.GetDisplayedCash(): number
	return DisplayedCash
end

function CashDisplayAPI.FormatNumber(n: number): string
	return FormatNumber(n)
end

function CashDisplayAPI.Refresh()
	SetupUI()
end

return CashDisplayAPI
