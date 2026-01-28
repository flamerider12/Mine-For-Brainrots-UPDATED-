--!strict
--[[
	MegaBrainrotService.lua
	Server-side service for the Mega Brainrot system

	FEATURES:
	- Global persistent 15-minute spawn timer (same for all servers)
	- Spawns in layers 4-7
	- 3-minute despawn timer after spawn
	- Guaranteed Godly+ egg with higher Gold/Void chances
	- Cross-server synchronization via MessagingService

	DEPENDENCIES:
	- GameConfig.MegaBrainrot (or MegaBrainrotConfig)
	- MineGenerator
	- MiningService
	- DataService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local MegaBrainrotService = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Try to load from GameConfig first, fallback to direct require
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

-- MegaBrainrot config (add to your GameConfig or use standalone)
local MegaConfig = GameConfig.MegaBrainrot or {
	SpawnInterval = 15 * 60,  -- 15 minutes
	DespawnTime = 3 * 60,     -- 3 minutes
	SpawnLayers = {4, 5, 6, 7},
	DataStoreKey = "MegaBrainrot_GlobalTimer_V1",
	Block = {
		Id = "MegaBrainrot",
		Name = "Mega Brainrot",
		Type = "Brainrot",
		Value = 0,
		Color = Color3.fromRGB(255, 0, 255),
		Material = Enum.Material.Neon,
	},
	MinimumRarity = "Godly",
	VariantChances = {
		Void = 10,
		Gold = 25,
		Normal = 65,
	},
	Highlight = {
		DetectionRange = 20,
	},
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local GlobalTimerDataStore = DataStoreService:GetDataStore("MegaBrainrotGlobalTimer")
local MESSAGING_TOPIC = "MegaBrainrot_Sync"

-- Service references (set during initialization)
local MineGenerator
local MiningService
local DataService

-- Current state
local CurrentState: "Waiting" | "Spawned" = "Waiting"
local GlobalSpawnTimestamp: number = 0  -- Unix timestamp when next spawn should occur
local DespawnTimestamp: number = 0      -- Unix timestamp when current block despawns
local CurrentSpawnLayer: number = 0     -- Which layer the current block is in
local SpawnedBlocks: {[Player]: BasePart} = {}  -- Per-player spawned blocks

-- Remotes
local Remotes: {[string]: RemoteEvent | RemoteFunction} = {}

-- Update loop connection
local UpdateConnection: RBXScriptConnection? = nil

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function GetCurrentUnixTime(): number
	return os.time()
end

local function FormatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

--[[
	Loads the global timer from DataStore
	Returns the Unix timestamp of when the next spawn should occur
]]
local function LoadGlobalTimer(): number
	local success, result = pcall(function()
		return GlobalTimerDataStore:GetAsync(MegaConfig.DataStoreKey)
	end)

	if success and result then
		return result
	end

	-- No saved timer, create new one
	local newSpawnTime = GetCurrentUnixTime() + MegaConfig.SpawnInterval
	SaveGlobalTimer(newSpawnTime)
	return newSpawnTime
end

--[[
	Saves the global timer to DataStore
]]
local function SaveGlobalTimer(timestamp: number)
	local success, err = pcall(function()
		GlobalTimerDataStore:SetAsync(MegaConfig.DataStoreKey, timestamp)
	end)

	if not success then
		warn("[MegaBrainrotService] Failed to save global timer:", err)
	end
end

--[[
	Broadcasts state to all servers via MessagingService
]]
local function BroadcastState(data: {[string]: any})
	local success, err = pcall(function()
		MessagingService:PublishAsync(MESSAGING_TOPIC, HttpService:JSONEncode(data))
	end)

	if not success then
		warn("[MegaBrainrotService] Failed to broadcast:", err)
	end
end

--[[
	Rolls a variant based on MegaBrainrot's higher chances
]]
local function RollMegaVariant(): string
	local roll = math.random() * 100
	local chances = MegaConfig.VariantChances

	if roll <= chances.Void then
		return "Void"
	elseif roll <= (chances.Void + chances.Gold) then
		return "Gold"
	end
	return "Normal"
end

--[[
	Gets a random spawn layer from config
]]
local function GetRandomSpawnLayer(): number
	local layers = MegaConfig.SpawnLayers
	return layers[math.random(1, #layers)]
end

--------------------------------------------------------------------------------
-- BLOCK SPAWNING
--------------------------------------------------------------------------------

--[[
	Gets all blocks in a specific layer for a player
]]
local function GetBlocksInLayer(player: Player, layerIndex: number): {BasePart}
	local mineData = MineGenerator.GetMineData(player)
	if not mineData then return {} end

	local blocksInLayer: {BasePart} = {}

	for _, block in mineData.Blocks do
		if block.Parent and block:GetAttribute("LayerIndex") == layerIndex then
			-- Don't replace brainrot blocks or mega brainrot
			local blockType = block:GetAttribute("BlockType")
			if blockType ~= "Brainrot" then
				table.insert(blocksInLayer, block)
			end
		end
	end

	return blocksInLayer
end

--[[
	Spawns the Mega Brainrot block for a player
]]
local function SpawnMegaBrainrotForPlayer(player: Player, layerIndex: number)
	-- Clean up any existing mega brainrot for this player
	if SpawnedBlocks[player] then
		SpawnedBlocks[player]:Destroy()
		SpawnedBlocks[player] = nil
	end

	local blocksInLayer = GetBlocksInLayer(player, layerIndex)
	if #blocksInLayer == 0 then
		warn(`[MegaBrainrotService] No blocks in layer {layerIndex} for {player.Name}`)
		return
	end

	-- Pick a random block to replace
	local targetBlock = blocksInLayer[math.random(1, #blocksInLayer)]
	local position = targetBlock.Position
	local gridX = targetBlock:GetAttribute("GridX")
	local gridY = targetBlock:GetAttribute("GridY")
	local gridZ = targetBlock:GetAttribute("GridZ")

	-- Destroy the original block
	targetBlock:Destroy()

	-- Create the Mega Brainrot block
	local blockSize = GameConfig.Mine.BlockSize
	local megaBlock = Instance.new("Part")
	megaBlock.Name = `MegaBrainrot_{player.UserId}`
	megaBlock.Size = Vector3.new(blockSize, blockSize, blockSize)
	megaBlock.Position = position
	megaBlock.Anchored = true
	megaBlock.CanCollide = true
	megaBlock.Color = MegaConfig.Block.Color
	megaBlock.Material = MegaConfig.Block.Material

	-- Set attributes
	megaBlock:SetAttribute("BlockId", MegaConfig.Block.Id)
	megaBlock:SetAttribute("BlockName", MegaConfig.Block.Name)
	megaBlock:SetAttribute("BlockType", "Brainrot")
	megaBlock:SetAttribute("IsMegaBrainrot", true)
	megaBlock:SetAttribute("Value", 0)
	megaBlock:SetAttribute("Health", 100)
	megaBlock:SetAttribute("MaxHealth", 100)
	megaBlock:SetAttribute("LayerIndex", layerIndex)
	megaBlock:SetAttribute("LayerName", GameConfig.Layers[layerIndex].LayerName)
	megaBlock:SetAttribute("GridX", gridX)
	megaBlock:SetAttribute("GridY", gridY)
	megaBlock:SetAttribute("GridZ", gridZ)

	-- Tags
	CollectionService:AddTag(megaBlock, "Mineable")
	CollectionService:AddTag(megaBlock, "BrainrotBlock")
	CollectionService:AddTag(megaBlock, "MegaBrainrot")

	-- Parent to player's mine
	local mineData = MineGenerator.GetMineData(player)
	if mineData and mineData.MineFolder then
		megaBlock.Parent = mineData.MineFolder
		SpawnedBlocks[player] = megaBlock
		print(`[MegaBrainrotService] Spawned Mega Brainrot for {player.Name} in layer {layerIndex}`)
	end
end

--[[
	Spawns Mega Brainrot for all players
]]
local function SpawnMegaBrainrotForAll(layerIndex: number)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			SpawnMegaBrainrotForPlayer(player, layerIndex)
		end)
	end
end

--[[
	Despawns all Mega Brainrot blocks
]]
local function DespawnAllMegaBrainrots()
	for player, block in SpawnedBlocks do
		if block and block.Parent then
			block:Destroy()
		end
	end
	SpawnedBlocks = {}
	print("[MegaBrainrotService] All Mega Brainrots despawned")
end

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------

--[[
	Transitions to "Waiting" state (15-minute countdown)
]]
local function EnterWaitingState()
	CurrentState = "Waiting"
	DespawnAllMegaBrainrots()

	-- Set next spawn time
	GlobalSpawnTimestamp = GetCurrentUnixTime() + MegaConfig.SpawnInterval
	SaveGlobalTimer(GlobalSpawnTimestamp)

	-- Notify all clients
	if Remotes.StateChanged then
		Remotes.StateChanged:FireAllClients({
			State = "Waiting",
			TimeRemaining = MegaConfig.SpawnInterval,
			SpawnTimestamp = GlobalSpawnTimestamp,
		})
	end

	-- Broadcast to other servers
	BroadcastState({
		Action = "EnterWaiting",
		SpawnTimestamp = GlobalSpawnTimestamp,
	})

	print(`[MegaBrainrotService] Waiting state - next spawn in {FormatTime(MegaConfig.SpawnInterval)}`)
end

--[[
	Transitions to "Spawned" state (3-minute countdown)
]]
local function EnterSpawnedState()
	CurrentState = "Spawned"
	CurrentSpawnLayer = GetRandomSpawnLayer()
	DespawnTimestamp = GetCurrentUnixTime() + MegaConfig.DespawnTime

	-- Spawn for all players
	SpawnMegaBrainrotForAll(CurrentSpawnLayer)

	-- Notify all clients
	if Remotes.StateChanged then
		Remotes.StateChanged:FireAllClients({
			State = "Spawned",
			TimeRemaining = MegaConfig.DespawnTime,
			DespawnTimestamp = DespawnTimestamp,
			Layer = CurrentSpawnLayer,
			LayerName = GameConfig.Layers[CurrentSpawnLayer].LayerName,
		})
	end

	-- Broadcast to other servers
	BroadcastState({
		Action = "EnterSpawned",
		DespawnTimestamp = DespawnTimestamp,
		Layer = CurrentSpawnLayer,
	})

	print(`[MegaBrainrotService] Spawned state - Mega Brainrot in Layer {CurrentSpawnLayer}, despawns in {FormatTime(MegaConfig.DespawnTime)}`)
end

--[[
	Called when a Mega Brainrot is mined
]]
function MegaBrainrotService.OnMegaBrainrotMined(player: Player, block: BasePart)
	if not block:GetAttribute("IsMegaBrainrot") then return end

	-- Remove from tracking
	if SpawnedBlocks[player] == block then
		SpawnedBlocks[player] = nil
	end

	-- Roll variant with higher chances
	local variant = RollMegaVariant()

	-- Guaranteed Godly rarity
	local rarity = MegaConfig.MinimumRarity

	-- Add egg to player inventory
	if MiningService and MiningService.GetPlayerInventory then
		local inv = MiningService.GetPlayerInventory(player)
		if inv then
			local uniqueId = HttpService:GenerateGUID(false)
			inv.Eggs[uniqueId] = {
				Id = uniqueId,
				Rarity = rarity,
				Variant = variant,
				AcquiredAt = os.time(),
				IsMega = true,
			}
			print(`[MegaBrainrotService] {player.Name} mined Mega Brainrot! Got {variant} {rarity} Egg`)
		end
	end

	-- Notify client of the drop
	if Remotes.MegaBrainrotMined then
		Remotes.MegaBrainrotMined:FireClient(player, {
			Rarity = rarity,
			Variant = variant,
			Position = block.Position,
		})
	end

	-- Fire standard brainrot dropped event too (for egg popout visual)
	local brainrotDroppedRemote = ReplicatedStorage:FindFirstChild("Remotes"):FindFirstChild("BrainrotDropped")
	if brainrotDroppedRemote then
		brainrotDroppedRemote:FireClient(player, {
			Position = block.Position,
			Rarity = rarity,
			Variant = variant,
		})
	end

	-- Increment stats
	if DataService and DataService.IncrementStat then
		DataService.IncrementStat(player, "MegaBrainrotsMined")
	end
end

--[[
	Gets the current Mega Brainrot block for a player (if any)
]]
function MegaBrainrotService.GetPlayerMegaBrainrot(player: Player): BasePart?
	return SpawnedBlocks[player]
end

--[[
	Checks if a block is a Mega Brainrot
]]
function MegaBrainrotService.IsMegaBrainrot(block: BasePart): boolean
	return block:GetAttribute("IsMegaBrainrot") == true
end

--------------------------------------------------------------------------------
-- UPDATE LOOP
--------------------------------------------------------------------------------

local function UpdateLoop()
	local now = GetCurrentUnixTime()

	if CurrentState == "Waiting" then
		local timeRemaining = GlobalSpawnTimestamp - now

		if timeRemaining <= 0 then
			-- Time to spawn!
			EnterSpawnedState()
		else
			-- Send periodic updates to clients (every 1 second via Heartbeat already)
			if Remotes.TimerUpdate then
				Remotes.TimerUpdate:FireAllClients({
					State = "Waiting",
					TimeRemaining = timeRemaining,
				})
			end
		end

	elseif CurrentState == "Spawned" then
		local timeRemaining = DespawnTimestamp - now

		if timeRemaining <= 0 then
			-- Time to despawn and restart waiting
			EnterWaitingState()
		else
			-- Send periodic updates
			if Remotes.TimerUpdate then
				Remotes.TimerUpdate:FireAllClients({
					State = "Spawned",
					TimeRemaining = timeRemaining,
					Layer = CurrentSpawnLayer,
				})
			end
		end
	end
end

--------------------------------------------------------------------------------
-- CROSS-SERVER SYNC
--------------------------------------------------------------------------------

local function OnMessageReceived(message: {[string]: any})
	local success, data = pcall(function()
		return HttpService:JSONDecode(message.Data)
	end)

	if not success then return end

	if data.Action == "EnterWaiting" then
		GlobalSpawnTimestamp = data.SpawnTimestamp
		CurrentState = "Waiting"
		DespawnAllMegaBrainrots()

	elseif data.Action == "EnterSpawned" then
		DespawnTimestamp = data.DespawnTimestamp
		CurrentSpawnLayer = data.Layer
		CurrentState = "Spawned"
		SpawnMegaBrainrotForAll(CurrentSpawnLayer)
	end
end

--------------------------------------------------------------------------------
-- PLAYER HANDLING
--------------------------------------------------------------------------------

local function OnPlayerAdded(player: Player)
	-- Wait for mine to be ready
	task.delay(3, function()
		-- If currently spawned, spawn for this player too
		if CurrentState == "Spawned" and CurrentSpawnLayer > 0 then
			SpawnMegaBrainrotForPlayer(player, CurrentSpawnLayer)
		end

		-- Send current state
		if Remotes.StateChanged then
			local now = GetCurrentUnixTime()

			if CurrentState == "Waiting" then
				Remotes.StateChanged:FireClient(player, {
					State = "Waiting",
					TimeRemaining = math.max(0, GlobalSpawnTimestamp - now),
					SpawnTimestamp = GlobalSpawnTimestamp,
				})
			else
				Remotes.StateChanged:FireClient(player, {
					State = "Spawned",
					TimeRemaining = math.max(0, DespawnTimestamp - now),
					DespawnTimestamp = DespawnTimestamp,
					Layer = CurrentSpawnLayer,
					LayerName = GameConfig.Layers[CurrentSpawnLayer] and GameConfig.Layers[CurrentSpawnLayer].LayerName or "Unknown",
				})
			end
		end
	end)
end

local function OnPlayerRemoving(player: Player)
	-- Clean up player's mega brainrot reference
	if SpawnedBlocks[player] then
		SpawnedBlocks[player] = nil
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function MegaBrainrotService.Initialize(mineGenerator, miningService, dataService)
	MineGenerator = mineGenerator
	MiningService = miningService
	DataService = dataService

	-- Create remotes
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	local function GetRemote(name: string, className: string): Instance
		local existing = remotesFolder:FindFirstChild(name)
		if existing then return existing end

		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = remotesFolder
		return remote
	end

	Remotes.StateChanged = GetRemote("MegaBrainrot_StateChanged", "RemoteEvent")
	Remotes.TimerUpdate = GetRemote("MegaBrainrot_TimerUpdate", "RemoteEvent")
	Remotes.MegaBrainrotMined = GetRemote("MegaBrainrot_Mined", "RemoteEvent")
	Remotes.GetMegaBrainrotPosition = GetRemote("MegaBrainrot_GetPosition", "RemoteFunction")

	-- Remote function to get position for client
	local getPositionFunc = Remotes.GetMegaBrainrotPosition :: RemoteFunction
	getPositionFunc.OnServerInvoke = function(player: Player)
		local block = SpawnedBlocks[player]
		if block and block.Parent then
			return {
				Position = block.Position,
				Layer = CurrentSpawnLayer,
			}
		end
		return nil
	end

	-- Subscribe to cross-server messages
	pcall(function()
		MessagingService:SubscribeAsync(MESSAGING_TOPIC, function(message)
			OnMessageReceived(message)
		end)
	end)

	-- Load global timer state
	GlobalSpawnTimestamp = LoadGlobalTimer()
	local now = GetCurrentUnixTime()

	if GlobalSpawnTimestamp <= now then
		-- Timer already expired, start fresh
		EnterWaitingState()
	else
		-- Resume waiting state with remaining time
		CurrentState = "Waiting"
		print(`[MegaBrainrotService] Resuming - next spawn in {FormatTime(GlobalSpawnTimestamp - now)}`)
	end

	-- Connect player events
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			OnPlayerAdded(player)
		end)
	end

	-- Start update loop
	UpdateConnection = RunService.Heartbeat:Connect(function()
		UpdateLoop()
	end)

	print("[MegaBrainrotService] Initialized")
	print(`[MegaBrainrotService] Spawn Interval: {FormatTime(MegaConfig.SpawnInterval)}`)
	print(`[MegaBrainrotService] Despawn Time: {FormatTime(MegaConfig.DespawnTime)}`)
	print(`[MegaBrainrotService] Spawn Layers: {table.concat(MegaConfig.SpawnLayers, ", ")}`)
end

return MegaBrainrotService
