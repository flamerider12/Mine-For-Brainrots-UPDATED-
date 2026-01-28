--!strict
--[[
    ServerInit.lua (V5.0 - Full Persistence)
    Main server initialization script
    
    UPDATED: 
    - DataService now receives references to MiningService and StructureService
    - Proper initialization order for persistence to work
    - Eggs, Units, and Structure states now save/load correctly
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- SETUP: Create folder structure
--------------------------------------------------------------------------------

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
if not sharedFolder then
	sharedFolder = Instance.new("Folder")
	sharedFolder.Name = "Shared"
	sharedFolder.Parent = ReplicatedStorage
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

--------------------------------------------------------------------------------
-- LOAD CONFIG
--------------------------------------------------------------------------------

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

--------------------------------------------------------------------------------
-- CREATE REMOTE EVENTS / FUNCTIONS
--------------------------------------------------------------------------------

local function CreateRemote(name: string, className: string): Instance
	local existing = remotesFolder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

-- Standard Remotes
CreateRemote("PlotAssigned", "RemoteEvent")
CreateRemote("RequestTeleportToPlot", "RemoteEvent")
CreateRemote("LayerChanged", "RemoteEvent")
CreateRemote("DataLoaded", "RemoteEvent")
CreateRemote("DataUpdated", "RemoteEvent")
CreateRemote("OreDiscovered", "RemoteEvent")
CreateRemote("InventoryFull", "RemoteEvent")
CreateRemote("CashChanged", "RemoteEvent")
CreateRemote("StructureStateChanged", "RemoteEvent")

--------------------------------------------------------------------------------
-- LOAD SERVICES
--------------------------------------------------------------------------------

local Services = ServerScriptService:WaitForChild("Services")

local PlotManager = require(Services:WaitForChild("PlotManager"))
local MineGenerator = require(Services:WaitForChild("MineGenerator"))
local MiningService = require(Services:WaitForChild("MiningService"))
local DataService = require(Services:WaitForChild("DataService"))
local StructureService = require(Services:WaitForChild("StructureService"))

local TutorialService = require(Services:WaitForChild("TutorialService"))

--------------------------------------------------------------------------------
-- GAME LOOP LOGIC
--------------------------------------------------------------------------------

local PlotAssignedRemote = remotesFolder:WaitForChild("PlotAssigned") :: RemoteEvent
local LayerChangedRemote = remotesFolder:WaitForChild("LayerChanged") :: RemoteEvent
local PlayerLastLayer: {[Player]: number} = {}

local function MonitorPlayerDepth(player: Player)
	while player.Parent do
		local character = player.Character or player.CharacterAdded:Wait()
		local root = character:WaitForChild("HumanoidRootPart") :: BasePart

		while player.Parent and character.Parent and character.PrimaryPart do
			local yPos = root.Position.Y

			MineGenerator.CheckGenerationNeeded(player, yPos)

			local currentLayer = MineGenerator.GetCurrentLayer(player, yPos)
			if currentLayer then
				local depth = (MineGenerator.GetBlockLayerFromYPosition(player, yPos) or 0) * GameConfig.Mine.BlockSize
				local layerIndex = GameConfig.GetLayerIndexByDepth(depth)

				local lastLayer = PlayerLastLayer[player]
				if lastLayer and layerIndex ~= lastLayer then
					PlayerLastLayer[player] = layerIndex
					DataService.UpdateMaxLayerReached(player, layerIndex)

					LayerChangedRemote:FireClient(player, {
						LayerIndex = layerIndex,
						LayerName = currentLayer.LayerName,
						LayerData = currentLayer,
					})
				end
			end
			task.wait(0.5)
		end
		task.wait(1)
	end
end

local function InitializePlayerGame(player: Player)
	print(`[ServerInit] Waiting for plot assignment for {player.Name}...`)

	local plotData = nil
	local attempts = 0
	while not plotData and player.Parent and attempts < 20 do
		plotData = PlotManager.GetPlotData(player)
		if not plotData then 
			task.wait(0.5) 
			attempts += 1
		end
	end

	if not plotData then
		warn(`[ServerInit] Timed out waiting for PlotManager to assign plot to {player.Name}`)
		return
	end

	MineGenerator.InitializeMine(
		player,
		plotData.MineOrigin.Position,
		plotData.PlotModel
	)

	local maxLayerReached = DataService.GetMaxLayerReached(player) or 1
	PlayerLastLayer[player] = 1

	PlotAssignedRemote:FireClient(player, {
		PlotPosition = plotData.WorldPosition,
		MineOrigin = plotData.MineOrigin.Position,
		GridSize = {
			X = GameConfig.Mine.GridSizeX,
			Z = GameConfig.Mine.GridSizeZ,
		},
		BlockSize = GameConfig.Mine.BlockSize,
		InitialLayer = GameConfig.Layers[1],
		MaxLayerReached = maxLayerReached,
	})

	print(`[ServerInit] Plot and Mine ready for {player.Name}`)

	task.spawn(MonitorPlayerDepth, player)
end

--------------------------------------------------------------------------------
-- INITIALIZE SERVICES (IMPORTANT: Order matters!)
--------------------------------------------------------------------------------

print("[ServerInit] ========================================")
print("[ServerInit] BRAINROT MINING SIMULATOR V5")
print("[ServerInit] Full Persistence System")
print("[ServerInit] ========================================")
print("[ServerInit] Initializing services...")

--[[
    INITIALIZATION ORDER:
    1. PlotManager - No dependencies
    2. DataService - Initialize early (no service refs yet)
    3. MiningService - Needs PlotManager, MineGenerator, DataService
    4. StructureService - Needs DataService, MiningService
    5. Set service references on DataService for persistence
]]

-- Step 1: Initialize PlotManager (no dependencies)
PlotManager.Initialize()

-- Step 2: Initialize DataService first (will set service refs later)
DataService.Initialize()

-- Step 3: Initialize MiningService
MiningService.Initialize(PlotManager, MineGenerator, DataService)

-- Step 4: Initialize StructureService
StructureService.Initialize(DataService, MiningService)

-- Step 5: Now set the service references on DataService for persistence
DataService.SetServiceReferences(MiningService, StructureService, TutorialService)

TutorialService.Initialize(DataService, MiningService, StructureService)

print("[ServerInit] Services initialized, setting up data loading...")

--------------------------------------------------------------------------------
-- PLAYER DATA LOADING
-- DataService handles loading and calls MiningService/StructureService setters
--------------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	-- MiningService.Initialize already connects to PlayerAdded to create inventory
	-- DataService.LoadPlayerData will be called and apply saved data
	task.defer(function()
		DataService.LoadPlayerData(player)
		InitializePlayerGame(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	DataService.OnPlayerRemoving(player)
end)

-- Handle existing players (Studio)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		DataService.LoadPlayerData(player)
		InitializePlayerGame(player)
	end)
end

--------------------------------------------------------------------------------
-- REMOTE EVENT HANDLERS
--------------------------------------------------------------------------------

local RequestTeleportRemote = remotesFolder:WaitForChild("RequestTeleportToPlot") :: RemoteEvent

RequestTeleportRemote.OnServerEvent:Connect(function(player)
	local plotData = PlotManager.GetPlotData(player)
	if plotData and player.Character then
		local targetCFrame: CFrame
		if plotData.SpawnPoint then
			targetCFrame = plotData.SpawnPoint.CFrame + Vector3.new(0, 3, 0)
		else
			targetCFrame = plotData.MineOrigin.CFrame + Vector3.new(0, 5, 0)
		end
		player.Character:PivotTo(targetCFrame)
	end
end)

print("[ServerInit] ========================================")
print("[ServerInit] All systems online.")
print("[ServerInit] Persistence: Eggs, Units, Structures")
print("[ServerInit] ========================================")
