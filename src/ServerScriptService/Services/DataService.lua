--!strict
--[[
    DataService.lua (V3.5 - Fixed Tutorial Persistence)
    Handles player data persistence using DataStoreService
    
    UPDATED: Added EnsureTutorialService() to auto-load TutorialService if not set via SetServiceReferences
    
    SAVES:
    - Cash
    - Storage (current inventory count)
    - InventoryValue (total value of items in inventory)
    - Ores (breakdown by ore type)
    - PickaxeLevel
    - BackpackLevel
    - EquippedPickaxe
    - EquippedBackpack
    - MaxLayerReached
    - Brainrots (lifetime counts)
    - DiscoveredOres
    - DiscoveredBrainrots
    - Statistics
    - Eggs
    - Units
    - IncubatorStates
    - PenStates
    - TutorialData
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local DataService = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local DATA_STORE_NAME = "BrainrotMiningV3_PlayerData"
local DATA_VERSION = 3
local AUTO_SAVE_INTERVAL = 60
local MAX_RETRIES = 3
local RETRY_DELAY = 1

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------

export type PlayerStatistics = {
	TotalBlocksMined: number,
	TotalCashEarned: number,
	TotalBrainrotsFound: number,
	DeepestDepthReached: number,
	PlayTime: number,
}

export type PlayerData = {
	Version: number,
	Cash: number,
	Storage: number,
	InventoryValue: number,
	Ores: {[string]: {Quantity: number, TotalValue: number, UnitValue: number, Icon: string?}}?,
	PickaxeLevel: number,
	BackpackLevel: number,
	EquippedPickaxe: number?,
	EquippedBackpack: number?,
	MaxLayerReached: number,
	Brainrots: {[string]: number},
	DiscoveredOres: {[string]: boolean},
	Statistics: PlayerStatistics,
	LastSaved: number,
	Eggs: {[string]: any}?,
	Units: {[string]: any}?,
	DiscoveredBrainrots: {[string]: boolean}?,
	IncubatorStates: {[string]: any}?,
	PenStates: {[string]: any}?,
	TutorialData: any?,
}

local DEFAULT_DATA: PlayerData = {
	Version = DATA_VERSION,
	Cash = 0,
	Storage = 0,
	InventoryValue = 0,
	Ores = {},
	PickaxeLevel = 1,
	BackpackLevel = 1,
	EquippedPickaxe = 1,
	EquippedBackpack = 1,
	MaxLayerReached = 1,
	Brainrots = {},
	DiscoveredOres = {},
	Statistics = {
		TotalBlocksMined = 0,
		TotalCashEarned = 0,
		TotalBrainrotsFound = 0,
		DeepestDepthReached = 0,
		PlayTime = 0,
	},
	LastSaved = 0,
	Eggs = {},
	Units = {},
	DiscoveredBrainrots = {},
	IncubatorStates = {},
	PenStates = {},
	TutorialData = nil,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local PlayerDataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)
local LoadedPlayerData: {[Player]: PlayerData} = {}
local PlayerSessionStart: {[Player]: number} = {}
local PlayerAlreadySaved: {[Player]: boolean} = {}  -- NEW: Track if we already saved on remove
local DataLoadedCallbacks: {(Player, PlayerData) -> ()} = {}
local IsStudio = RunService:IsStudio()

local Remotes: {[string]: RemoteEvent} = {}

-- Service references (set via SetServiceReferences)
local MiningService = nil
local StructureService = nil
local TutorialService = nil

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

local function DeepCopy<T>(original: T): T
	if type(original) ~= "table" then
		return original
	end

	local copy = {}
	for key, value in pairs(original :: any) do
		copy[key] = DeepCopy(value)
	end
	return copy :: T
end

local function MigrateData(savedData: any): PlayerData
	local data = DeepCopy(DEFAULT_DATA)

	if type(savedData) ~= "table" then
		return data
	end

	-- Migrate existing fields
	if savedData.Cash then data.Cash = savedData.Cash end
	if savedData.Storage then data.Storage = savedData.Storage end
	if savedData.InventoryValue then data.InventoryValue = savedData.InventoryValue end
	if savedData.Ores then data.Ores = savedData.Ores end
	if savedData.PickaxeLevel then data.PickaxeLevel = savedData.PickaxeLevel end
	if savedData.BackpackLevel then data.BackpackLevel = savedData.BackpackLevel end
	if savedData.MaxLayerReached then data.MaxLayerReached = savedData.MaxLayerReached end
	if savedData.Brainrots then data.Brainrots = savedData.Brainrots end
	if savedData.DiscoveredOres then data.DiscoveredOres = savedData.DiscoveredOres end

	-- Migrate equipped items (default to highest owned if not saved)
	data.EquippedPickaxe = savedData.EquippedPickaxe or data.PickaxeLevel
	data.EquippedBackpack = savedData.EquippedBackpack or data.BackpackLevel

	if savedData.Statistics then
		for key, value in pairs(savedData.Statistics) do
			if data.Statistics[key] ~= nil then
				data.Statistics[key] = value
			end
		end
	end

	-- Migrate NEW fields
	if savedData.Eggs then data.Eggs = savedData.Eggs end
	if savedData.Units then data.Units = savedData.Units end
	if savedData.DiscoveredBrainrots then data.DiscoveredBrainrots = savedData.DiscoveredBrainrots end
	if savedData.IncubatorStates then data.IncubatorStates = savedData.IncubatorStates end
	if savedData.PenStates then data.PenStates = savedData.PenStates end
	if savedData.TutorialData then data.TutorialData = savedData.TutorialData end

	data.Version = DATA_VERSION

	return data
end

local function GetPlayerKey(player: Player): string
	return `Player_{player.UserId}`
end

local function LoadDataWithRetry(player: Player): (boolean, PlayerData?)
	local key = GetPlayerKey(player)

	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			return PlayerDataStore:GetAsync(key)
		end)

		if success then
			if result then
				-- Debug: Log what TutorialData we got from DataStore
				if result.TutorialData then
					print(`[DataService] LOADED from DataStore - TutorialData found: Completed={result.TutorialData.TutorialCompleted}, Step={result.TutorialData.CurrentStepIndex}`)
				else
					warn(`[DataService] LOADED from DataStore - NO TutorialData field!`)
				end
				return true, MigrateData(result)
			else
				print(`[DataService] No saved data found for {player.Name} - using defaults`)
				return true, DeepCopy(DEFAULT_DATA)
			end
		else
			warn(`[DataService] Load attempt {attempt}/{MAX_RETRIES} failed for {player.Name}: {result}`)
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY)
			end
		end
	end

	return false, nil
end

local function SaveDataWithRetry(player: Player, data: PlayerData): boolean
	local key = GetPlayerKey(player)
	local saveId = math.random(1000, 9999)  -- Random ID to track this specific save
	data.LastSaved = os.time()

	-- Debug: Log what TutorialData we're saving
	if data.TutorialData then
		print(`[DataService] SAVE #{saveId} for {player.Name}: TutorialCompleted={data.TutorialData.TutorialCompleted}, Step={data.TutorialData.CurrentStepIndex}`)
	else
		warn(`[DataService] SAVE #{saveId} for {player.Name}: NO TutorialData!`)
	end

	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			PlayerDataStore:SetAsync(key, data)
		end)

		if success then
			print(`[DataService] SAVE #{saveId} for {player.Name}: SUCCESS`)
			return true
		else
			warn(`[DataService] SAVE #{saveId} attempt {attempt}/{MAX_RETRIES} failed for {player.Name}: {result}`)
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY)
			end
		end
	end

	return false
end

--[[
	NEW: Auto-load TutorialService if not set via SetServiceReferences
	This ensures tutorial persistence works even if ServerInit doesn't pass TutorialService
]]
local function EnsureTutorialService(): boolean
	if TutorialService then 
		return true 
	end

	-- Try to find and require TutorialService from Services folder
	local servicesFolder = ServerScriptService:FindFirstChild("Services")
	if servicesFolder then
		local tutorialModule = servicesFolder:FindFirstChild("TutorialService")
		if tutorialModule then
			local success, result = pcall(function()
				return require(tutorialModule)
			end)
			if success and result then
				TutorialService = result
				print("[DataService] ✓ Auto-loaded TutorialService from Services folder")
				return true
			else
				warn("[DataService] Failed to require TutorialService:", result)
			end
		else
			warn("[DataService] TutorialService module not found in Services folder")
		end
	else
		warn("[DataService] Services folder not found in ServerScriptService")
	end

	return false
end

local function ApplyDataToPlayer(player: Player, data: PlayerData)
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		warn(`[DataService] leaderstats not found for {player.Name}`)
		return
	end

	local cashStat = leaderstats:FindFirstChild("Cash")
	if cashStat then
		cashStat.Value = data.Cash
	end

	local storageStat = leaderstats:FindFirstChild("Storage")
	if storageStat then
		storageStat.Value = data.Storage
	end

	local inventoryValueStat = leaderstats:FindFirstChild("InventoryValue")
	if inventoryValueStat then
		inventoryValueStat.Value = data.InventoryValue
	end

	-- Set owned levels FIRST
	player:SetAttribute("PickaxeLevel", data.PickaxeLevel)
	player:SetAttribute("BackpackLevel", data.BackpackLevel)
	player:SetAttribute("MaxLayerReached", data.MaxLayerReached)

	-- Set EQUIPPED items
	local equippedPickaxe = data.EquippedPickaxe or data.PickaxeLevel
	local equippedBackpack = data.EquippedBackpack or data.BackpackLevel
	player:SetAttribute("EquippedPickaxe", equippedPickaxe)
	player:SetAttribute("EquippedBackpack", equippedBackpack)

	-- Use EQUIPPED backpack for capacity
	local capacityStat = leaderstats:FindFirstChild("Capacity")
	if capacityStat then
		local backpack = GameConfig.GetBackpack(equippedBackpack)
		local capacity = (equippedBackpack == 1) and 50 or (backpack and backpack.Capacity or 50)
		capacityStat.Value = capacity
		print(`[DataService] Set capacity to {capacity} (Equipped Backpack Level {equippedBackpack})`)
	end

	-- Apply Eggs/Units to MiningService
	if MiningService and MiningService.SetEggsAndUnits then
		MiningService.SetEggsAndUnits(player, data.Eggs or {}, data.Units or {})
	end

	-- Apply Structure States to StructureService
	if StructureService and StructureService.SetStructureStates then
		local penStatesWithResetTime = {}
		local now = os.time()
		for structureId, penState in pairs(data.PenStates or {}) do
			local resetState = DeepCopy(penState)
			resetState.LastCollectTime = now
			penStatesWithResetTime[structureId] = resetState
		end
		StructureService.SetStructureStates(player, data.IncubatorStates or {}, penStatesWithResetTime)
	end

	-- Apply Tutorial Data to TutorialService
	-- NEW: Try to auto-load TutorialService if not set
	EnsureTutorialService()

	if TutorialService and TutorialService.SetTutorialData then
		-- Log what we're loading for debugging
		if data.TutorialData then
			local completed = data.TutorialData.TutorialCompleted == true
			local skipped = data.TutorialData.TutorialSkipped == true
			local step = data.TutorialData.CurrentStepIndex or 1
			print(`[DataService] Loading tutorial for {player.Name}: Completed={completed}, Skipped={skipped}, Step={step}`)
		else
			print(`[DataService] No saved tutorial data for {player.Name} (new player)`)
		end
		TutorialService.SetTutorialData(player, data.TutorialData)
	else
		warn(`[DataService] ⚠️ TutorialService NOT available - tutorial progress will NOT be restored!`)
	end

	print(`[DataService] Applied data to {player.Name}:`)
	print(`[DataService]   Cash: {data.Cash}, Storage: {data.Storage}, InventoryValue: {data.InventoryValue}`)
	print(`[DataService]   Pickaxe Level: {data.PickaxeLevel}, Backpack Level: {data.BackpackLevel}`)
	print(`[DataService]   Equipped Pickaxe: {equippedPickaxe}, Equipped Backpack: {equippedBackpack}`)
	print(`[DataService]   Max Layer Reached: {data.MaxLayerReached}`)

	-- Count and log data
	local eggCount = 0
	for _ in pairs(data.Eggs or {}) do eggCount += 1 end
	local unitCount = 0
	for _ in pairs(data.Units or {}) do unitCount += 1 end
	local incubatorCount = 0
	for _ in pairs(data.IncubatorStates or {}) do incubatorCount += 1 end
	local penCount = 0
	for _ in pairs(data.PenStates or {}) do penCount += 1 end
	local oreCount = 0
	for _ in pairs(data.Ores or {}) do oreCount += 1 end

	if eggCount > 0 or unitCount > 0 or incubatorCount > 0 or penCount > 0 then
		print(`[DataService]   Eggs: {eggCount}, Units: {unitCount}, Incubators: {incubatorCount}, Pens: {penCount}`)
	end

	if oreCount > 0 then
		print(`[DataService]   Ores in inventory: {oreCount} types`)
	end

	-- Log tutorial status
	if data.TutorialData then
		local tutStatus = (data.TutorialData.TutorialCompleted == true) and "COMPLETED" or 
			((data.TutorialData.TutorialSkipped == true) and "SKIPPED" or `Step {data.TutorialData.CurrentStepIndex}`)
		print(`[DataService]   Tutorial: {tutStatus}`)
	else
		print(`[DataService]   Tutorial: NEW (no saved data)`)
	end
end

local function CollectPlayerData(player: Player): PlayerData?
	local data = LoadedPlayerData[player]
	if not data then
		return nil
	end

	-- Collect from leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cashStat = leaderstats:FindFirstChild("Cash")
		if cashStat then
			data.Cash = cashStat.Value
		end

		local storageStat = leaderstats:FindFirstChild("Storage")
		if storageStat then
			data.Storage = storageStat.Value
		end

		local inventoryValueStat = leaderstats:FindFirstChild("InventoryValue")
		if inventoryValueStat then
			data.InventoryValue = inventoryValueStat.Value
		end
	end

	-- Collect from player attributes
	data.PickaxeLevel = player:GetAttribute("PickaxeLevel") or data.PickaxeLevel
	data.BackpackLevel = player:GetAttribute("BackpackLevel") or data.BackpackLevel
	data.MaxLayerReached = player:GetAttribute("MaxLayerReached") or data.MaxLayerReached
	data.EquippedPickaxe = player:GetAttribute("EquippedPickaxe") or data.PickaxeLevel
	data.EquippedBackpack = player:GetAttribute("EquippedBackpack") or data.BackpackLevel

	-- Collect Eggs/Units AND Ores from MiningService
	if MiningService then
		if MiningService.GetEggsAndUnits then
			local eggs, units = MiningService.GetEggsAndUnits(player)
			data.Eggs = eggs or {}
			data.Units = units or {}
		end

		-- Collect Ores breakdown for Sell UI persistence
		if MiningService.GetPlayerInventory then
			local inventory = MiningService.GetPlayerInventory(player)
			if inventory and inventory.Ores then
				data.Ores = inventory.Ores
			end
		end
	end

	-- Collect Structure States from StructureService
	if StructureService and StructureService.GetStructureStates then
		local incubators, pens = StructureService.GetStructureStates(player)
		data.IncubatorStates = incubators or {}
		data.PenStates = pens or {}
	end

	-- Collect Tutorial Data from TutorialService
	-- NEW: Try to auto-load TutorialService if not set
	EnsureTutorialService()

	if TutorialService and TutorialService.GetTutorialData then
		local tutorialData = TutorialService.GetTutorialData(player)
		data.TutorialData = tutorialData
		if tutorialData then
			local completed = tutorialData.TutorialCompleted == true
			local step = tutorialData.CurrentStepIndex or 1
			print(`[DataService] Collecting tutorial for {player.Name}: Completed={completed}, Step={step}`)
		end
	else
		warn(`[DataService] ⚠️ Cannot collect tutorial data - TutorialService not available`)
	end

	-- Update play time
	local sessionStart = PlayerSessionStart[player]
	if sessionStart then
		local sessionTime = os.time() - sessionStart
		data.Statistics.PlayTime += sessionTime
		PlayerSessionStart[player] = os.time()
	end

	return data
end

local function NotifyDataLoaded(player: Player, data: PlayerData)
	for _, callback in ipairs(DataLoadedCallbacks) do
		task.spawn(callback, player, data)
	end

	if Remotes.DataLoaded then
		Remotes.DataLoaded:FireClient(player, {
			Cash = data.Cash,
			Storage = data.Storage,
			InventoryValue = data.InventoryValue,
			PickaxeLevel = data.PickaxeLevel,
			BackpackLevel = data.BackpackLevel,
			EquippedPickaxe = data.EquippedPickaxe,
			EquippedBackpack = data.EquippedBackpack,
			MaxLayerReached = data.MaxLayerReached,
			DiscoveredOres = data.DiscoveredOres,
			DiscoveredBrainrots = data.DiscoveredBrainrots or {},
			Statistics = data.Statistics,
		})
	end
end

--------------------------------------------------------------------------------
-- AUTO-SAVE LOOP
--------------------------------------------------------------------------------

local function StartAutoSaveLoop()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)

		for player, _ in pairs(LoadedPlayerData) do
			if player.Parent then
				task.spawn(function()
					local data = CollectPlayerData(player)
					if data then
						local success = SaveDataWithRetry(player, data)
						if success then
							print(`[DataService] Auto-saved data for {player.Name}`)
						end
					end
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function DataService.Initialize(miningServiceRef: any?, structureServiceRef: any?)
	if miningServiceRef then
		MiningService = miningServiceRef
	end
	if structureServiceRef then
		StructureService = structureServiceRef
	end

	-- NEW: Try to auto-load TutorialService at initialization
	EnsureTutorialService()

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	Remotes.DataLoaded = remotesFolder:FindFirstChild("DataLoaded") :: RemoteEvent
	Remotes.DataUpdated = remotesFolder:FindFirstChild("DataUpdated") :: RemoteEvent
	Remotes.OreDiscovered = remotesFolder:FindFirstChild("OreDiscovered") :: RemoteEvent

	task.spawn(StartAutoSaveLoop)

	game:BindToClose(function()
		print("[DataService] Game closing, saving all player data...")

		local saveThreads = {}
		for player, data in pairs(LoadedPlayerData) do
			-- Skip if already saved during OnPlayerRemoving
			if PlayerAlreadySaved[player] then
				print(`[DataService] Player {player.Name} already saved, skipping emergency save`)
				continue
			end

			table.insert(saveThreads, task.spawn(function()
				local collectedData = CollectPlayerData(player)
				if collectedData then
					-- Make a deep copy
					local dataCopy = DeepCopy(collectedData)

					if dataCopy.TutorialData then
						print(`[DataService] Emergency save - Tutorial: Completed={dataCopy.TutorialData.TutorialCompleted}`)
					end

					SaveDataWithRetry(player, dataCopy)
					print(`[DataService] Emergency save completed for {player.Name}`)
				end
			end))
		end

		task.wait(5)
	end)

	print("[DataService] Initialized with Inventory, Structure & Tutorial Persistence")
	if IsStudio then
		print("[DataService] Running in Studio - data persistence enabled")
	end
end

function DataService.SetServiceReferences(miningServiceRef: any?, structureServiceRef: any?, tutorialServiceRef: any?)
	if miningServiceRef then
		MiningService = miningServiceRef
	end
	if structureServiceRef then
		StructureService = structureServiceRef
	end
	if tutorialServiceRef then
		TutorialService = tutorialServiceRef
		print("[DataService] TutorialService reference set via SetServiceReferences")
	end
end

function DataService.LoadPlayerData(player: Player): PlayerData?
	if LoadedPlayerData[player] then
		return LoadedPlayerData[player]
	end

	print(`[DataService] Loading data for {player.Name}...`)

	local success, data = LoadDataWithRetry(player)

	if success and data then
		LoadedPlayerData[player] = data
		PlayerSessionStart[player] = os.time()

		task.delay(0.5, function()
			if player.Parent then
				ApplyDataToPlayer(player, data)
				NotifyDataLoaded(player, data)
			end
		end)

		print(`[DataService] Successfully loaded data for {player.Name}`)
		return data
	else
		warn(`[DataService] Failed to load data for {player.Name}, using defaults`)
		local defaultData = DeepCopy(DEFAULT_DATA)
		LoadedPlayerData[player] = defaultData
		PlayerSessionStart[player] = os.time()
		return defaultData
	end
end

function DataService.SavePlayerData(player: Player): boolean
	local data = CollectPlayerData(player)
	if not data then
		warn(`[DataService] No data to save for {player.Name}`)
		return false
	end

	local success = SaveDataWithRetry(player, data)
	if success then
		print(`[DataService] Saved data for {player.Name}`)
	end
	return success
end

function DataService.OnPlayerRemoving(player: Player)
	-- Mark as being saved to prevent BindToClose from double-saving
	if PlayerAlreadySaved[player] then
		print(`[DataService] Player {player.Name} already saved, skipping duplicate save`)
		return
	end
	PlayerAlreadySaved[player] = true

	-- Collect data BEFORE clearing anything
	local data = CollectPlayerData(player)
	if data then
		-- Make a deep copy to ensure we have all the data
		local dataCopy = DeepCopy(data)

		-- Debug log
		if dataCopy.TutorialData then
			print(`[DataService] OnPlayerRemoving - Saving tutorial: Completed={dataCopy.TutorialData.TutorialCompleted}, Step={dataCopy.TutorialData.CurrentStepIndex}`)
		else
			warn(`[DataService] OnPlayerRemoving - NO TutorialData to save!`)
		end

		SaveDataWithRetry(player, dataCopy)
		print(`[DataService] Saved and cleaned up data for {player.Name}`)
	end

	-- Clean up AFTER saving
	LoadedPlayerData[player] = nil
	PlayerSessionStart[player] = nil

	if StructureService and StructureService.CleanupPlayerData then
		StructureService.CleanupPlayerData(player)
	end
end

function DataService.GetPlayerData(player: Player): PlayerData?
	return LoadedPlayerData[player]
end

function DataService.UpdatePlayerData(player: Player, field: string, value: any)
	local data = LoadedPlayerData[player]
	if not data then
		return
	end

	if data[field] ~= nil then
		data[field] = value
	end

	if field == "MaxLayerReached" then
		player:SetAttribute("MaxLayerReached", value)

		if Remotes.DataUpdated then
			Remotes.DataUpdated:FireClient(player, {
				Field = field,
				Value = value,
			})
		end
	end
end

function DataService.IncrementStat(player: Player, statName: string, amount: number?)
	local data = LoadedPlayerData[player]
	if not data then
		return
	end

	amount = amount or 1

	if data.Statistics[statName] ~= nil then
		data.Statistics[statName] += amount
	end
end

function DataService.UpdateMaxLayerReached(player: Player, layerIndex: number)
	local data = LoadedPlayerData[player]
	if not data then
		return
	end

	if layerIndex > data.MaxLayerReached then
		data.MaxLayerReached = layerIndex
		player:SetAttribute("MaxLayerReached", layerIndex)

		print(`[DataService] {player.Name} unlocked Layer {layerIndex}!`)

		if Remotes.DataUpdated then
			Remotes.DataUpdated:FireClient(player, {
				Field = "MaxLayerReached",
				Value = layerIndex,
			})
		end
	end
end

function DataService.UpdateDeepestDepth(player: Player, depth: number)
	local data = LoadedPlayerData[player]
	if not data then
		return
	end

	if depth > data.Statistics.DeepestDepthReached then
		data.Statistics.DeepestDepthReached = depth
	end
end

function DataService.AddBrainrot(player: Player, brainrotId: string)
	local data = LoadedPlayerData[player]
	if not data then
		return
	end

	data.Brainrots[brainrotId] = (data.Brainrots[brainrotId] or 0) + 1
	DataService.IncrementStat(player, "TotalBrainrotsFound")
end

--------------------------------------------------------------------------------
-- ORE DISCOVERY
--------------------------------------------------------------------------------

function DataService.DiscoverOre(player: Player, oreId: string): boolean
	local data = LoadedPlayerData[player]
	if not data then
		return false
	end

	if data.DiscoveredOres[oreId] then
		return false
	end

	data.DiscoveredOres[oreId] = true

	print(`[DataService] {player.Name} discovered new ore: {oreId}!`)

	-- NEW: Ensure TutorialService is loaded
	EnsureTutorialService()
	if TutorialService and TutorialService.OnOreDiscovered then
		TutorialService.OnOreDiscovered(player, oreId)
	end

	if Remotes.OreDiscovered then
		Remotes.OreDiscovered:FireClient(player, {
			OreId = oreId,
		})
	end

	return true
end

function DataService.HasDiscoveredOre(player: Player, oreId: string): boolean
	local data = LoadedPlayerData[player]
	if not data then
		return false
	end

	return data.DiscoveredOres[oreId] == true
end

function DataService.GetDiscoveredOres(player: Player): {[string]: boolean}
	local data = LoadedPlayerData[player]
	if not data then
		return {}
	end

	return data.DiscoveredOres
end

--------------------------------------------------------------------------------
-- BRAINROT DISCOVERY
--------------------------------------------------------------------------------

function DataService.DiscoverBrainrot(player: Player, brainrotId: string): boolean
	local data = LoadedPlayerData[player]
	if not data then
		return false
	end

	data.Brainrots[brainrotId] = (data.Brainrots[brainrotId] or 0) + 1
	data.Statistics.TotalBrainrotsFound = (data.Statistics.TotalBrainrotsFound or 0) + 1

	if not data.DiscoveredBrainrots then
		data.DiscoveredBrainrots = {}
	end

	local isNewDiscovery = not data.DiscoveredBrainrots[brainrotId]

	if isNewDiscovery then
		data.DiscoveredBrainrots[brainrotId] = true
		print(`[DataService] {player.Name} discovered NEW brainrot: {brainrotId}!`)
	end

	return isNewDiscovery
end

function DataService.HasDiscoveredBrainrot(player: Player, brainrotId: string): boolean
	local data = LoadedPlayerData[player]
	if not data or not data.DiscoveredBrainrots then
		return false
	end

	return data.DiscoveredBrainrots[brainrotId] == true
end

function DataService.GetDiscoveredBrainrots(player: Player): {[string]: boolean}
	local data = LoadedPlayerData[player]
	if not data then
		return {}
	end

	return data.DiscoveredBrainrots or {}
end

function DataService.GetBrainrotCounts(player: Player): {[string]: number}
	local data = LoadedPlayerData[player]
	if not data then
		return {}
	end

	return data.Brainrots or {}
end

--------------------------------------------------------------------------------
-- CALLBACKS
--------------------------------------------------------------------------------

function DataService.OnDataLoaded(callback: (Player, PlayerData) -> ())
	table.insert(DataLoadedCallbacks, callback)
end

function DataService.GetMaxLayerReached(player: Player): number
	local data = LoadedPlayerData[player]
	return data and data.MaxLayerReached or 1
end

--------------------------------------------------------------------------------
-- DEBUG SERVICE
--------------------------------------------------------------------------------

local DEBUG_ENABLED = true
local ADMIN_IDS = {88257682}

local function IsAdmin(player: Player): boolean
	return table.find(ADMIN_IDS, player.UserId) ~= nil
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		if not DEBUG_ENABLED then return end
		if not IsAdmin(player) then return end

		local lowerMessage = message:lower()

		if lowerMessage == "/resetme" then
			local key = GetPlayerKey(player)

			local success, err = pcall(function()
				PlayerDataStore:RemoveAsync(key)
			end)

			if success then
				warn(`[DataService] ⚠️ DATA WIPED for {player.Name} (Key: {key})`)
				player:Kick("🔄 Data reset! Rejoin to start fresh.")
			else
				warn(`[DataService] ❌ Failed to reset data: {err}`)
			end
			return
		end

		if lowerMessage:match("^/givecash%s+%d+$") then
			local amount = tonumber(lowerMessage:match("/givecash%s+(%d+)"))
			if amount then
				local leaderstats = player:FindFirstChild("leaderstats")
				if leaderstats and leaderstats:FindFirstChild("Cash") then
					leaderstats.Cash.Value += amount
					print(`[Debug] Gave {player.Name} ${amount}`)
				end
			end
			return
		end

		if lowerMessage:match("^/setpick%s+%d+$") then
			local level = tonumber(lowerMessage:match("/setpick%s+(%d+)"))
			if level and level >= 1 and level <= #GameConfig.Pickaxes then
				player:SetAttribute("PickaxeLevel", level)
				player:SetAttribute("EquippedPickaxe", level)
				print(`[Debug] Set {player.Name}'s pickaxe to level {level}`)
			end
			return
		end

		if lowerMessage:match("^/setbag%s+%d+$") then
			local level = tonumber(lowerMessage:match("/setbag%s+(%d+)"))
			if level and level >= 1 and level <= #GameConfig.Backpacks then
				player:SetAttribute("BackpackLevel", level)
				player:SetAttribute("EquippedBackpack", level)
				local backpack = GameConfig.GetBackpack(level)
				local leaderstats = player:FindFirstChild("leaderstats")
				if leaderstats and leaderstats:FindFirstChild("Capacity") then
					leaderstats.Capacity.Value = backpack.Capacity
				end
				print(`[Debug] Set {player.Name}'s backpack to level {level}`)
			end
			return
		end

		if lowerMessage == "/stats" then
			local data = LoadedPlayerData[player]
			if data then
				print("========== PLAYER STATS ==========")
				print(`Cash: {data.Cash}`)
				print(`Pickaxe Level: {data.PickaxeLevel} (Equipped: {data.EquippedPickaxe})`)
				print(`Backpack Level: {data.BackpackLevel} (Equipped: {data.EquippedBackpack})`)
				print(`Max Layer: {data.MaxLayerReached}`)
				print(`Eggs: {#(data.Eggs or {})}`)
				print(`Units: {#(data.Units or {})}`)
				local oreCount = 0
				for _ in pairs(data.Ores or {}) do oreCount += 1 end
				print(`Ores in inventory: {oreCount} types`)
				if data.TutorialData then
					local status = (data.TutorialData.TutorialCompleted == true) and "COMPLETED" or
						((data.TutorialData.TutorialSkipped == true) and "SKIPPED" or `Step {data.TutorialData.CurrentStepIndex}`)
					print(`Tutorial: {status}`)
				else
					print(`Tutorial: NEW (no saved data)`)
				end
				print("==================================")
			end
			return
		end

		if lowerMessage == "/resettutorial" then
			local data = LoadedPlayerData[player]
			if data then
				data.TutorialData = nil
				EnsureTutorialService()
				if TutorialService and TutorialService.SetTutorialData then
					TutorialService.SetTutorialData(player, nil)
				end
				print(`[Debug] Reset tutorial for {player.Name}`)
			end
			return
		end

		if lowerMessage == "/savetutorial" or lowerMessage == "/saveme" then
			-- Force collect and display tutorial data, then save
			EnsureTutorialService()
			if TutorialService and TutorialService.GetTutorialData then
				local tutData = TutorialService.GetTutorialData(player)
				if tutData then
					print("========== TUTORIAL DATA ==========")
					print(`CurrentStepIndex: {tutData.CurrentStepIndex}`)
					print(`TutorialCompleted: {tutData.TutorialCompleted}`)
					print(`TutorialSkipped: {tutData.TutorialSkipped}`)
					print(`CompletedSteps: {#tutData.CompletedSteps or 0} steps`)
					print("====================================")

					-- Update in LoadedPlayerData
					local data = LoadedPlayerData[player]
					if data then
						data.TutorialData = tutData
						print(`[Debug] Tutorial data updated in memory`)
					end
				else
					print(`[Debug] No tutorial data found in TutorialService`)
				end
			end

			-- Force save
			local success = DataService.SavePlayerData(player)
			if success then
				print(`[Debug] ✓ Data saved successfully for {player.Name}`)
			else
				print(`[Debug] ✗ Failed to save data for {player.Name}`)
			end
			return
		end

		if lowerMessage == "/completetutorial" then
			EnsureTutorialService()
			if TutorialService then
				-- Manually set tutorial as completed
				local tutData = {
					CurrentStepIndex = 16,
					CompletedSteps = {},
					TutorialCompleted = true,
					TutorialSkipped = false,
					StartedAt = os.time(),
					CompletedAt = os.time(),
				}
				TutorialService.SetTutorialData(player, tutData)

				local data = LoadedPlayerData[player]
				if data then
					data.TutorialData = tutData
				end

				print(`[Debug] Tutorial marked as COMPLETED for {player.Name}`)
			end
			return
		end

		if lowerMessage == "/help" or lowerMessage == "/debug" then
			print("========== DEBUG COMMANDS ==========")
			print("/resetme - Wipe all your data and rejoin fresh")
			print("/givecash [amount] - Add cash (e.g., /givecash 10000)")
			print("/setpick [level] - Set pickaxe level (1-8)")
			print("/setbag [level] - Set backpack level (1-7)")
			print("/stats - Print your current data")
			print("/resettutorial - Reset tutorial progress")
			print("/savetutorial - Force save and show tutorial data")
			print("/completetutorial - Mark tutorial as completed")
			print("====================================")
			return
		end
	end)
end)

return DataService
