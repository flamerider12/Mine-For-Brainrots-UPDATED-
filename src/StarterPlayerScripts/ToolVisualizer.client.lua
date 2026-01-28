--[[
    ToolVisualizer.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    V7 - AGGRESSIVE SPEED SCALING
    
    Changes from V6:
    - Added detailed debug output to see what's happening
    - Uses BOTH AdjustSpeed AND timing-based replay
    - Prints animation length and actual speed being used
    - Forces replay based on cooldown timing, not just animation end
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Load GameConfig
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

-- Configuration
local CONFIG = {
	DefaultGripOffset = CFrame.new(0, -0.5, -0.5) * CFrame.Angles(math.rad(-90), 0, 0),

	-- Speed limits
	MinSwingSpeed = 1.0,
	MaxSwingSpeed = 15.0,

	-- Debug - SET TO TRUE TO SEE WHAT'S HAPPENING
	Debug = true,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local CurrentPickaxeModel: Model? = nil
local CurrentPickaxeLevel: number = 0
local CurrentPickaxeName: string = ""
local CurrentMotor6D: Motor6D? = nil
local CurrentIdleTrack: AnimationTrack? = nil
local CurrentSwingTrack: AnimationTrack? = nil
local CurrentAnimator: Animator? = nil

-- Timing
local CurrentCooldown: number = 0.5
local LastSwingTime: number = 0

-- Input state
local IsMouseHeld: boolean = false
local IsSwinging: boolean = false
local SwingLoopConnection: RBXScriptConnection? = nil

-- Connections
local InputBeganConnection: RBXScriptConnection? = nil
local InputEndedConnection: RBXScriptConnection? = nil
local AttributeConnection: RBXScriptConnection? = nil

local PickaxeFolder: Folder? = nil

--------------------------------------------------------------------------------
-- DEBUG
--------------------------------------------------------------------------------

local function DebugPrint(...)
	if CONFIG.Debug then
		print("[ToolVisualizer]", ...)
	end
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function GetPickaxeFolder(): Folder?
	if PickaxeFolder and PickaxeFolder.Parent then 
		return PickaxeFolder 
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end

	PickaxeFolder = assets:FindFirstChild("Pickaxes")
	return PickaxeFolder
end

local function GetCurrentPickaxeLevel(): number
	-- Use equipped pickaxe if set, otherwise use owned level
	local equipped = LocalPlayer:GetAttribute("EquippedPickaxe")
	if equipped then return equipped end
	return LocalPlayer:GetAttribute("PickaxeLevel") or 1
end

local function GetPickaxeConfig(level: number)
	if GameConfig.GetPickaxe then
		return GameConfig.GetPickaxe(level)
	end
	if GameConfig.Pickaxes and GameConfig.Pickaxes[level] then
		return GameConfig.Pickaxes[level]
	end
	return nil
end

local function GetPickaxeModel(pickaxeName: string): Model?
	local folder = GetPickaxeFolder()
	if not folder then return nil end

	-- Try exact match
	local model = folder:FindFirstChild(pickaxeName)
	if model and model:IsA("Model") then return model end

	-- Try no spaces
	model = folder:FindFirstChild(string.gsub(pickaxeName, " ", ""))
	if model and model:IsA("Model") then return model end

	-- Try underscores
	model = folder:FindFirstChild(string.gsub(pickaxeName, " ", "_"))
	if model and model:IsA("Model") then return model end

	-- Case insensitive
	local lower = string.lower(pickaxeName)
	for _, child in folder:GetChildren() do
		if string.lower(child.Name) == lower and child:IsA("Model") then
			return child
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- ANIMATIONS
--------------------------------------------------------------------------------

local function DestroyAnimations()
	if CurrentIdleTrack then
		CurrentIdleTrack:Stop(0)
		CurrentIdleTrack:Destroy()
		CurrentIdleTrack = nil
	end

	if CurrentSwingTrack then
		CurrentSwingTrack:Stop(0)
		CurrentSwingTrack:Destroy()
		CurrentSwingTrack = nil
	end
end

local function SetupAnimations(humanoid: Humanoid, level: number)
	CurrentAnimator = humanoid:FindFirstChildOfClass("Animator")
	if not CurrentAnimator then
		CurrentAnimator = Instance.new("Animator")
		CurrentAnimator.Parent = humanoid
	end

	local anims = GameConfig.GetPickaxeAnims(level)
	local swingAnimId = anims.Swing

	local pickaxeConfig = GetPickaxeConfig(level)
	CurrentCooldown = pickaxeConfig and pickaxeConfig.Cooldown or 0.5

	DebugPrint("=== ANIMATION SETUP ===")
	DebugPrint("Level:", level)
	DebugPrint("Cooldown:", CurrentCooldown, "seconds")
	DebugPrint("Swing Anim ID:", swingAnimId)

	-- Load Swing Animation
	if swingAnimId and swingAnimId ~= "" and swingAnimId ~= "rbxassetid://0" then
		local swingAnim = Instance.new("Animation")
		swingAnim.AnimationId = swingAnimId

		local success, track = pcall(function()
			return CurrentAnimator:LoadAnimation(swingAnim)
		end)

		if success and track then
			CurrentSwingTrack = track
			CurrentSwingTrack.Priority = Enum.AnimationPriority.Action
			CurrentSwingTrack.Looped = false

			-- Wait a frame for the animation to load its length
			task.wait()

			local animLength = CurrentSwingTrack.Length
			DebugPrint("Animation Length:", animLength, "seconds")

			-- Calculate speed: we want the animation to complete in (cooldown) seconds
			-- But we also want it to LOOK fast, so we'll make it even faster
			local targetDuration = CurrentCooldown * 0.8  -- Complete animation in 80% of cooldown
			local speed = animLength / targetDuration
			speed = math.clamp(speed, CONFIG.MinSwingSpeed, CONFIG.MaxSwingSpeed)

			DebugPrint("Target Duration:", targetDuration, "seconds")
			DebugPrint("Calculated Speed:", speed, "x")

			CurrentSwingTrack:AdjustSpeed(speed)

			DebugPrint("✓ Swing animation ready")
			DebugPrint("========================")
		else
			warn("[ToolVisualizer] Failed to load swing animation!")
		end

		swingAnim:Destroy()
	end
end

--------------------------------------------------------------------------------
-- TOOL MANAGEMENT
--------------------------------------------------------------------------------

local function CleanupCurrentTool()
	DestroyAnimations()

	if CurrentMotor6D then
		CurrentMotor6D:Destroy()
		CurrentMotor6D = nil
	end

	if CurrentPickaxeModel then
		CurrentPickaxeModel:Destroy()
		CurrentPickaxeModel = nil
	end

	CurrentPickaxeName = ""
	CurrentAnimator = nil
end

local function EquipPickaxe(level: number)
	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if not rightArm then return end

	local pickaxeConfig = GetPickaxeConfig(level)
	if not pickaxeConfig then return end

	local pickaxeName = pickaxeConfig.Name
	local gripOffset = pickaxeConfig.GripOffset or CONFIG.DefaultGripOffset

	if CurrentPickaxeName == pickaxeName and CurrentPickaxeModel and CurrentPickaxeModel.Parent then
		return
	end

	CleanupCurrentTool()

	local modelTemplate = GetPickaxeModel(pickaxeName)
	if not modelTemplate then
		warn("[ToolVisualizer] Model not found:", pickaxeName)
		return
	end

	local model = modelTemplate:Clone()
	model.Name = "EquippedPickaxe"

	local handle = model:FindFirstChild("Handle") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not handle then
		model:Destroy()
		return
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
			part.Anchored = false
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "PickaxeMotor"
	motor.Part0 = rightArm
	motor.Part1 = handle
	motor.C0 = gripOffset
	motor.Parent = rightArm

	model.Parent = character

	CurrentPickaxeModel = model
	CurrentMotor6D = motor
	CurrentPickaxeLevel = level
	CurrentPickaxeName = pickaxeName

	SetupAnimations(humanoid, level)

	print(string.format("[ToolVisualizer] Equipped: %s (Cooldown: %.2fs)", pickaxeName, CurrentCooldown))
end

--------------------------------------------------------------------------------
-- SWING LOOP - TIMING BASED
--------------------------------------------------------------------------------

local function PlaySwing()
	if not CurrentSwingTrack then 
		DebugPrint("No swing track!")
		return 
	end

	-- Only play if enough time has passed (based on cooldown)
	local now = tick()
	local timeSinceLastSwing = now - LastSwingTime

	if timeSinceLastSwing < CurrentCooldown * 0.9 then
		-- Too soon, skip
		return
	end

	LastSwingTime = now

	-- Stop current animation if playing and restart
	if CurrentSwingTrack.IsPlaying then
		CurrentSwingTrack:Stop(0)
	end

	CurrentSwingTrack:Play(0)  -- 0 = instant start, no fade

	DebugPrint("SWING! (cooldown:", CurrentCooldown, ")")
end

local function StartSwingLoop()
	if SwingLoopConnection then return end
	if not CurrentSwingTrack then return end

	IsSwinging = true
	LastSwingTime = 0  -- Reset so first swing plays immediately

	DebugPrint("Starting swing loop (cooldown:", CurrentCooldown, "s)")

	-- Play first swing immediately
	PlaySwing()

	-- Loop based on time, not animation completion
	SwingLoopConnection = RunService.Heartbeat:Connect(function()
		if not IsMouseHeld then
			if SwingLoopConnection then
				SwingLoopConnection:Disconnect()
				SwingLoopConnection = nil
			end
			IsSwinging = false
			return
		end

		-- Try to play swing (function checks timing internally)
		PlaySwing()
	end)
end

local function StopSwingLoop()
	IsSwinging = false
	if SwingLoopConnection then
		SwingLoopConnection:Disconnect()
		SwingLoopConnection = nil
	end
end

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------

local function OnInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or 
		input.UserInputType == Enum.UserInputType.Touch then
		IsMouseHeld = true
		StartSwingLoop()
	end
end

local function OnInputEnded(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or 
		input.UserInputType == Enum.UserInputType.Touch then
		IsMouseHeld = false
	end
end

local function StartInputTracking()
	if InputBeganConnection then InputBeganConnection:Disconnect() end
	if InputEndedConnection then InputEndedConnection:Disconnect() end

	InputBeganConnection = UserInputService.InputBegan:Connect(OnInputBegan)
	InputEndedConnection = UserInputService.InputEnded:Connect(OnInputEnded)
end

local function StopInputTracking()
	IsMouseHeld = false
	StopSwingLoop()

	if InputBeganConnection then InputBeganConnection:Disconnect(); InputBeganConnection = nil end
	if InputEndedConnection then InputEndedConnection:Disconnect(); InputEndedConnection = nil end
end

--------------------------------------------------------------------------------
-- CHARACTER & LEVEL CHANGES
--------------------------------------------------------------------------------

local function OnPickaxeLevelChanged()
	local newLevel = GetCurrentPickaxeLevel()
	if newLevel ~= CurrentPickaxeLevel then
		print("[ToolVisualizer] Level changed:", CurrentPickaxeLevel, "→", newLevel)
		EquipPickaxe(newLevel)
	end
end

local function OnCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	-- Wait for right arm (R6) or right hand (R15)
	local rightArm = character:WaitForChild("Right Arm", 3)
	if not rightArm then
		rightArm = character:WaitForChild("RightHand", 3)
	end
	task.wait(0.3)

	CurrentPickaxeLevel = 0
	CurrentPickaxeName = ""
	IsMouseHeld = false
	IsSwinging = false
	LastSwingTime = 0

	EquipPickaxe(GetCurrentPickaxeLevel())
	StartInputTracking()

	humanoid.Died:Once(function()
		StopInputTracking()
		CleanupCurrentTool()
	end)
end

local function OnCharacterRemoving()
	StopInputTracking()
	CleanupCurrentTool()
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

local function Initialize()
	print("[ToolVisualizer V7] Initializing...")
	print("  Debug mode:", CONFIG.Debug and "ON" or "OFF")
	print("  Cooldowns from GameConfig:")

	for i, pick in ipairs(GameConfig.Pickaxes) do
		print(string.format("    Level %d: %s - %.2fs cooldown", pick.Level, pick.Name, pick.Cooldown))
	end

	if AttributeConnection then AttributeConnection:Disconnect() end

	-- Listen for BOTH PickaxeLevel AND EquippedPickaxe changes
	AttributeConnection = LocalPlayer:GetAttributeChangedSignal("PickaxeLevel"):Connect(OnPickaxeLevelChanged)
	LocalPlayer:GetAttributeChangedSignal("EquippedPickaxe"):Connect(OnPickaxeLevelChanged)

	LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)
	LocalPlayer.CharacterRemoving:Connect(OnCharacterRemoving)

	if LocalPlayer.Character then
		task.spawn(function()
			OnCharacterAdded(LocalPlayer.Character)
		end)
	end

	print("[ToolVisualizer V7] Ready!")
end

Initialize()

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local API = {}
function API.Refresh() CurrentPickaxeLevel = 0; EquipPickaxe(GetCurrentPickaxeLevel()) end
function API.GetCurrentLevel() return CurrentPickaxeLevel end
function API.GetCurrentName() return CurrentPickaxeName end
function API.GetCurrentCooldown() return CurrentCooldown end
function API.PlaySwing() PlaySwing() end
function API.IsSwinging() return IsSwinging end
function API.IsHoldingMouse() return IsMouseHeld end
return API
