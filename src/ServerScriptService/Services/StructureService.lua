--!strict
--[[
    StructureService.lua (V6.0 - Complete Rewrite)
    
    Server-side service for managing Incubators and Pens.
    
    ARCHITECTURE:
    - Clean separation between Incubator (Egg -> Unit) and Pen (Unit -> Cash) systems
    - Single source of truth for structure state
    - Event-driven client updates
    - Robust GUID handling
    
    INCUBATOR FLOW:
    1. Player interacts (E) -> Opens Egg Selection UI
    2. Player selects Egg -> Egg placed in Incubator, timer starts
    3. Player can Speed Up (E) or Cancel (F)
    4. Timer complete -> Egg hatches into Unit, goes to Unit Inventory
    
    PEN FLOW:
    1. Player interacts (E) -> Opens Unit Selection UI
    2. Player selects Unit -> Unit placed in Pen, income generation starts
    3. Player can Collect (E) or Remove (F)
    4. Collect -> Cash added, timer resets
    5. Remove -> Collects remaining cash, returns Unit to inventory
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")  -- ADD THIS LINE

-- MODULES
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

-- INJECTED SERVICES
local DataService = nil
local MiningService = nil
local TutorialService = nil

local StructureService = {}

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------

export type IncubatorState = {
	EggGUID: string,
	EggData: {
		Id: string,
		Rarity: string,
		Variant: string,
	},
	StartTime: number,
	HatchTime: number, -- Total seconds needed to hatch
}

export type PenState = {
	UnitGUID: string,
	UnitData: {
		Id: string,
		Name: string,
		Rarity: string,
		Variant: string,
		Level: number,
	},
	PlacedTime: number,
	LastCollectTime: number,
	AccumulatedCash: number, -- Cash earned but not yet collected
}

export type PlayerStructureData = {
	Incubators: { [string]: IncubatorState? }, -- [StructureId] = State
	Pens: { [string]: PenState? },              -- [StructureId] = State
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local PlayerStructures: { [Player]: PlayerStructureData } = {}
local Remotes: { [string]: RemoteEvent | RemoteFunction } = {}

-- Constants
local DEFAULT_UNIT_CAPACITY = 4
local INCOME_UPDATE_INTERVAL = 1 -- How often to calculate income (seconds)

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

local function GenerateGUID(): string
	return HttpService:GenerateGUID(false)
end

local function GetStructureId(object: Instance): string?
	if object:IsA("BasePart") then
		return object:GetAttribute("Id") or object.Name
	elseif object:IsA("Model") then
		return object:GetAttribute("Id") or object.Name
	end
	return nil
end

local function GetStructureOwner(object: Instance): Player?
	local current: Instance? = object
	while current and current ~= workspace do
		local ownerId = current:GetAttribute("OwnerUserId")
		if ownerId then
			return Players:GetPlayerByUserId(ownerId)
		end
		current = current.Parent
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

local function InitializePlayerData(player: Player)
	if PlayerStructures[player] then return end

	PlayerStructures[player] = {
		Incubators = {},
		Pens = {},
	}

	print(`[StructureService] Initialized data for {player.Name}`)
end

local function CleanupPlayerData(player: Player)
	PlayerStructures[player] = nil
	print(`[StructureService] Cleaned up data for {player.Name}`)
end

--------------------------------------------------------------------------------
-- INVENTORY HELPERS
--------------------------------------------------------------------------------

local function GetPlayerInventory(player: Player)
	if MiningService and MiningService.GetPlayerInventory then
		return MiningService.GetPlayerInventory(player)
	end
	return nil
end

local function GetPlayerEggs(player: Player): { [string]: any }
	local inv = GetPlayerInventory(player)
	return inv and inv.Eggs or {}
end

local function GetPlayerUnits(player: Player): { [string]: any }
	local inv = GetPlayerInventory(player)
	return inv and inv.Units or {}
end

local function GetUnitCapacity(player: Player): number
	-- TODO: Could be upgraded via backpack system
	return DEFAULT_UNIT_CAPACITY
end

local function GetUnitCount(player: Player): number
	local units = GetPlayerUnits(player)
	local count = 0
	for _ in pairs(units) do
		count += 1
	end
	return count
end

local function IsUnitInventoryFull(player: Player): boolean
	return GetUnitCount(player) >= GetUnitCapacity(player)
end

local function RemoveEggFromInventory(player: Player, eggGUID: string): boolean
	local inv = GetPlayerInventory(player)
	if not inv or not inv.Eggs then return false end

	-- Direct match
	if inv.Eggs[eggGUID] then
		inv.Eggs[eggGUID] = nil
		return true
	end

	-- Search by various keys (handle string/number mismatch)
	for key, data in pairs(inv.Eggs) do
		if tostring(key) == tostring(eggGUID) then
			inv.Eggs[key] = nil
			return true
		end
		if data.GUID and tostring(data.GUID) == tostring(eggGUID) then
			inv.Eggs[key] = nil
			return true
		end
		if data.Guid and tostring(data.Guid) == tostring(eggGUID) then
			inv.Eggs[key] = nil
			return true
		end
	end

	return false
end

local function AddEggToInventory(player: Player, eggGUID: string, eggData: any): boolean
	local inv = GetPlayerInventory(player)
	if not inv then return false end

	if not inv.Eggs then inv.Eggs = {} end
	inv.Eggs[eggGUID] = eggData
	return true
end

local function RemoveUnitFromInventory(player: Player, unitGUID: string): boolean
	local inv = GetPlayerInventory(player)
	if not inv or not inv.Units then return false end

	-- Direct match
	if inv.Units[unitGUID] then
		inv.Units[unitGUID] = nil
		return true
	end

	-- Search by various keys
	for key, data in pairs(inv.Units) do
		if tostring(key) == tostring(unitGUID) then
			inv.Units[key] = nil
			return true
		end
		if data.GUID and tostring(data.GUID) == tostring(unitGUID) then
			inv.Units[key] = nil
			return true
		end
	end

	return false
end

local function AddUnitToInventory(player: Player, unitGUID: string, unitData: any): boolean
	local inv = GetPlayerInventory(player)
	if not inv then 
		warn(`[StructureService] AddUnitToInventory: No inventory for {player.Name}`)
		return false 
	end

	if IsUnitInventoryFull(player) then
		warn(`[StructureService] Unit inventory full for {player.Name}`)
		return false
	end

	if not inv.Units then 
		print(`[StructureService] Creating Units table for {player.Name}`)
		inv.Units = {} 
	end

	inv.Units[unitGUID] = unitData
	print(`[StructureService] Added unit {unitGUID} ({unitData.Name or unitData.Id}) to {player.Name}'s inventory`)

	-- Verify it was added
	local count = 0
	for _ in pairs(inv.Units) do count += 1 end
	print(`[StructureService] {player.Name} now has {count} units in inventory`)

	return true
end

local function AddCashToPlayer(player: Player, amount: number): boolean
	local inv = GetPlayerInventory(player)
	if not inv then return false end

	inv.Cash = (inv.Cash or 0) + amount

	-- Update leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cashStat = leaderstats:FindFirstChild("Cash")
		if cashStat then
			cashStat.Value = inv.Cash
		end
	end

	-- Notify client
	if Remotes.CashChanged then
		Remotes.CashChanged:FireClient(player, {
			Cash = inv.Cash,
			Delta = amount,
			Reason = "PenCollect",
		})
	end

	return true
end

--------------------------------------------------------------------------------
-- INCUBATOR FUNCTIONS
--------------------------------------------------------------------------------

--[[
    Gets all eggs available for incubation
    Returns: Array of { GUID, Id, Rarity, Variant, DisplayName }
]]
local function GetAvailableEggs(player: Player): { any }
	local eggs = GetPlayerEggs(player)
	local result = {}

	for guid, data in pairs(eggs) do
		local eggConfig = GameConfig.Eggs and GameConfig.Eggs[data.Id or data.Rarity]
		local displayName = (eggConfig and eggConfig.DisplayName) or data.Rarity or "Unknown Egg"

		table.insert(result, {
			GUID = tostring(guid),
			Id = data.Id or `Egg_{data.Rarity or "Common"}`,
			Rarity = data.Rarity or GameConfig.RARITIES.Common,
			Variant = data.Variant or "Normal",
			DisplayName = displayName,
		})
	end

	return result
end

--[[
    Places an egg in an incubator
    Returns: success, errorMessage?
]]
local function PlaceEggInIncubator(player: Player, structureObject: Instance, eggGUID: string): (boolean, string?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure" end

	-- Validate ownership
	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your incubator" end

	-- Check if already occupied
	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized" end

	if playerData.Incubators[structureId] then
		return false, "Incubator already occupied"
	end

	-- Find the egg in inventory
	local eggs = GetPlayerEggs(player)
	local foundEgg = nil
	local foundKey = nil

	for key, data in pairs(eggs) do
		if tostring(key) == eggGUID or 
			(data.GUID and tostring(data.GUID) == eggGUID) or
			(data.Guid and tostring(data.Guid) == eggGUID) then
			foundEgg = data
			foundKey = key
			break
		end
	end

	if not foundEgg then
		return false, "Egg not found in inventory"
	end

	-- Get hatch time based on rarity
	local rarity = foundEgg.Rarity or GameConfig.RARITIES.Common
	local hatchTime = GameConfig.Eggs and GameConfig.Eggs.HatchTimes and GameConfig.Eggs.HatchTimes[rarity] or 30

	-- Create incubator state
	local state: IncubatorState = {
		EggGUID = eggGUID,
		EggData = {
			Id = foundEgg.Id or `Egg_{rarity}`,
			Rarity = rarity,
			Variant = foundEgg.Variant or "Normal",
		},
		StartTime = os.time(),
		HatchTime = hatchTime,
	}

	-- Remove egg from inventory
	if not RemoveEggFromInventory(player, tostring(foundKey)) then
		return false, "Failed to remove egg from inventory"
	end

	-- Store state
	playerData.Incubators[structureId] = state

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Incubator",
			StructureId = structureId,
			Action = "EggPlaced",
			State = state,
		})
	end

	print(`[StructureService] {player.Name} placed {rarity} egg in incubator {structureId}`)
	if TutorialService then
		TutorialService.OnEggPlaced(player)
	end
	return true
end

--[[
    Gets the current state of an incubator
    Returns: State with calculated remaining time, or nil if empty
]]
local function GetIncubatorState(player: Player, structureId: string): IncubatorState?
	local playerData = PlayerStructures[player]
	if not playerData then return nil end

	return playerData.Incubators[structureId]
end

--[[
    Calculates remaining time for an incubator
    Returns: seconds remaining, or 0 if ready
]]
local function GetIncubatorTimeRemaining(state: IncubatorState): number
	local elapsed = os.time() - state.StartTime
	return math.max(0, state.HatchTime - elapsed)
end

--[[
    Checks if an incubator is ready to hatch
]]
local function IsIncubatorReady(state: IncubatorState): boolean
	return GetIncubatorTimeRemaining(state) <= 0
end

--[[
    Speeds up incubation (for testing, makes it instant)
    In production, this would cost Robux
]]
local function SpeedUpIncubator(player: Player, structureObject: Instance): (boolean, string?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure" end

	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your incubator" end

	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized" end

	local state = playerData.Incubators[structureId]
	if not state then return false, "Incubator is empty" end

	-- For testing: Make it instant
	state.StartTime = os.time() - state.HatchTime - 1

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Incubator",
			StructureId = structureId,
			Action = "SpeedUp",
			State = state,
		})
	end

	print(`[StructureService] {player.Name} sped up incubator {structureId}`)
	return true
end

--[[
    Cancels incubation and returns egg to inventory
]]
local function CancelIncubation(player: Player, structureObject: Instance): (boolean, string?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure" end

	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your incubator" end

	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized" end

	local state = playerData.Incubators[structureId]
	if not state then return false, "Incubator is empty" end

	-- Return egg to inventory
	local eggData = {
		Id = state.EggData.Id,
		Rarity = state.EggData.Rarity,
		Variant = state.EggData.Variant,
		AcquiredAt = os.time(),
	}

	if not AddEggToInventory(player, state.EggGUID, eggData) then
		return false, "Failed to return egg to inventory"
	end

	-- Clear state
	playerData.Incubators[structureId] = nil

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Incubator",
			StructureId = structureId,
			Action = "Cancelled",
			State = nil,
		})
	end

	print(`[StructureService] {player.Name} cancelled incubation in {structureId}`)
	return true
end

--[[
    Hatches the egg and creates a new unit
]]
local function HatchEgg(player: Player, structureObject: Instance): (boolean, string?, any?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure", nil end

	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your incubator", nil end

	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized", nil end

	local state = playerData.Incubators[structureId]
	if not state then return false, "Incubator is empty", nil end

	-- Check if ready
	if not IsIncubatorReady(state) then
		return false, "Egg not ready to hatch", nil
	end

	-- Check unit inventory capacity
	if IsUnitInventoryFull(player) then
		return false, "Unit inventory is full", nil
	end

	-- Roll for which unit to create based on rarity
	local rarity = state.EggData.Rarity
	local potentialUnits = {}

	-- Get units of this rarity from GameConfig
	if GameConfig.Brainrots then
		for id, config in pairs(GameConfig.Brainrots) do
			if config.Rarity == rarity then
				table.insert(potentialUnits, config)
			end
		end
	end

	-- Fallback if no units found
	if #potentialUnits == 0 then
		table.insert(potentialUnits, {
			Id = "Ohio_Rat",
			Name = "Ohio Rat",
			Rarity = rarity,
			IncomePerSecond = 1,
		})
	end

	-- Random selection
	local selectedUnit = potentialUnits[math.random(1, #potentialUnits)]

	-- Create new unit
	local newUnitGUID = GenerateGUID()
	local newUnit = {
		Id = selectedUnit.Id,
		Name = selectedUnit.Name or selectedUnit.Id,
		Rarity = rarity,
		Variant = state.EggData.Variant,
		Level = 1,
		GUID = newUnitGUID,
		HatchedAt = os.time(),
	}

	-- Add to inventory
	if not AddUnitToInventory(player, newUnitGUID, newUnit) then
		return false, "Failed to add unit to inventory", nil
	end

	-- Clear incubator state
	playerData.Incubators[structureId] = nil

	-- Track brainrot discovery and stats via DataService
	if DataService then
		-- This handles: DiscoveredBrainrots, Brainrots count, TotalBrainrotsFound stat
		if DataService.DiscoverBrainrot then
			local isNewDiscovery = DataService.DiscoverBrainrot(player, selectedUnit.Id)
			if isNewDiscovery then
				print(`[StructureService] {player.Name} discovered a NEW brainrot type: {selectedUnit.Id}!`)
			end
		end
	end

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Incubator",
			StructureId = structureId,
			Action = "Hatched",
			State = nil,
			HatchedUnit = newUnit,
		})
	end

	print(`[StructureService] {player.Name} hatched {newUnit.Name} ({rarity} {state.EggData.Variant})!`)
	
	if TutorialService then
		TutorialService.OnEggHatched(player)
	end
	
	return true, nil, newUnit
end

--------------------------------------------------------------------------------
-- PEN FUNCTIONS
--------------------------------------------------------------------------------

--[[
    Gets all units available for placing in pens
    Returns: Array of { GUID, Id, Name, Rarity, Variant, Level, IncomePerSecond }
]]
local function GetAvailableUnits(player: Player): { any }
	local inv = GetPlayerInventory(player)

	-- Debug logging
	print(`[StructureService] GetAvailableUnits called for {player.Name}`)
	print(`[StructureService]   Inventory exists: {inv ~= nil}`)

	if not inv then
		warn(`[StructureService] No inventory found for {player.Name}`)
		return {}
	end

	print(`[StructureService]   inv.Units exists: {inv.Units ~= nil}`)

	if not inv.Units then
		warn(`[StructureService] No Units table in inventory for {player.Name}`)
		return {}
	end

	-- Count units
	local unitCount = 0
	for _ in pairs(inv.Units) do
		unitCount += 1
	end
	print(`[StructureService]   Unit count: {unitCount}`)

	local units = inv.Units
	local result = {}

	for guid, data in pairs(units) do
		print(`[StructureService]   Found unit: {guid} -> {data.Id or data.Name or "unknown"}`)

		local unitConfig = GameConfig.Brainrots and GameConfig.Brainrots[data.Id]
		local baseIncome = (unitConfig and unitConfig.IncomePerSecond) or 1

		-- Apply variant multiplier
		local variantMult = 1
		if GameConfig.Eggs and GameConfig.Eggs.VariantMultipliers then
			variantMult = GameConfig.Eggs.VariantMultipliers[data.Variant] or 1
		end

		local incomePerSecond = baseIncome * variantMult * (data.Level or 1)

		table.insert(result, {
			GUID = tostring(guid),
			Id = data.Id,
			Name = data.Name or data.Id,
			Rarity = data.Rarity or "Common",
			Variant = data.Variant or "Normal",
			Level = data.Level or 1,
			IncomePerSecond = incomePerSecond,
		})
	end

	print(`[StructureService]   Returning {#result} units`)
	return result
end

--[[
    Places a unit in a pen
    Returns: success, errorMessage?
]]
local function PlaceUnitInPen(player: Player, structureObject: Instance, unitGUID: string): (boolean, string?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure" end

	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your pen" end

	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized" end

	if playerData.Pens[structureId] then
		return false, "Pen already occupied"
	end

	-- Find the unit in inventory
	local units = GetPlayerUnits(player)
	local foundUnit = nil
	local foundKey = nil

	for key, data in pairs(units) do
		if tostring(key) == unitGUID or 
			(data.GUID and tostring(data.GUID) == unitGUID) then
			foundUnit = data
			foundKey = key
			break
		end
	end

	if not foundUnit then
		return false, "Unit not found in inventory"
	end

	-- Create pen state
	local now = os.time()
	local state: PenState = {
		UnitGUID = unitGUID,
		UnitData = {
			Id = foundUnit.Id,
			Name = foundUnit.Name or foundUnit.Id,
			Rarity = foundUnit.Rarity or "Common",
			Variant = foundUnit.Variant or "Normal",
			Level = foundUnit.Level or 1,
		},
		PlacedTime = now,
		LastCollectTime = now,
		AccumulatedCash = 0,
	}

	-- Remove unit from inventory
	if not RemoveUnitFromInventory(player, tostring(foundKey)) then
		return false, "Failed to remove unit from inventory"
	end

	-- Store state
	playerData.Pens[structureId] = state

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Pen",
			StructureId = structureId,
			Action = "UnitPlaced",
			State = state,
		})
	end

	print(`[StructureService] {player.Name} placed {foundUnit.Name or foundUnit.Id} in pen {structureId}`)
	return true
end

--[[
    Calculates current income for a pen
]]
local function CalculatePenIncome(state: PenState): number
	local unitConfig = GameConfig.Brainrots and GameConfig.Brainrots[state.UnitData.Id]
	local baseIncome = (unitConfig and unitConfig.IncomePerSecond) or 1

	-- Apply variant multiplier
	local variantMult = 1
	if GameConfig.Eggs and GameConfig.Eggs.VariantMultipliers then
		variantMult = GameConfig.Eggs.VariantMultipliers[state.UnitData.Variant] or 1
	end

	local incomePerSecond = baseIncome * variantMult * state.UnitData.Level
	local elapsed = os.time() - state.LastCollectTime

	return math.floor(incomePerSecond * elapsed)
end

--[[
    Gets the income rate for a pen (per second)
]]
local function GetPenIncomeRate(state: PenState): number
	local unitConfig = GameConfig.Brainrots and GameConfig.Brainrots[state.UnitData.Id]
	local baseIncome = (unitConfig and unitConfig.IncomePerSecond) or 1

	local variantMult = 1
	if GameConfig.Eggs and GameConfig.Eggs.VariantMultipliers then
		variantMult = GameConfig.Eggs.VariantMultipliers[state.UnitData.Variant] or 1
	end

	return baseIncome * variantMult * state.UnitData.Level
end

--[[
    Collects accumulated cash from a pen
]]
local function CollectFromPen(player: Player, structureObject: Instance): (boolean, string?, number?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure", nil end

	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your pen", nil end

	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized", nil end

	local state = playerData.Pens[structureId]
	if not state then return false, "Pen is empty", nil end

	-- Calculate income
	local income = CalculatePenIncome(state)

	if income <= 0 then
		return false, "No cash to collect", 0
	end

	-- Add cash to player
	if not AddCashToPlayer(player, income) then
		return false, "Failed to add cash", nil
	end

	-- Reset timer
	state.LastCollectTime = os.time()
	state.AccumulatedCash = 0

	-- Update stats
	if DataService and DataService.IncrementStat then
		DataService.IncrementStat(player, "TotalCashEarned", income)
	end

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Pen",
			StructureId = structureId,
			Action = "Collected",
			State = state,
			AmountCollected = income,
		})
	end

	print(`[StructureService] {player.Name} collected ${income} from pen {structureId}`)
	return true, nil, income
end

--[[
    Removes unit from pen and returns to inventory (after collecting cash)
]]
local function RemoveUnitFromPen(player: Player, structureObject: Instance): (boolean, string?, number?)
	local structureId = GetStructureId(structureObject)
	if not structureId then return false, "Invalid structure", nil end

	local owner = GetStructureOwner(structureObject)
	if owner ~= player then return false, "Not your pen", nil end

	local playerData = PlayerStructures[player]
	if not playerData then return false, "Player data not initialized", nil end

	local state = playerData.Pens[structureId]
	if not state then return false, "Pen is empty", nil end

	-- Collect remaining cash first
	local income = CalculatePenIncome(state)
	if income > 0 then
		AddCashToPlayer(player, income)
	end

	-- Check unit inventory capacity
	if IsUnitInventoryFull(player) then
		return false, "Unit inventory is full", income
	end

	-- Return unit to inventory
	local unitData = {
		Id = state.UnitData.Id,
		Name = state.UnitData.Name,
		Rarity = state.UnitData.Rarity,
		Variant = state.UnitData.Variant,
		Level = state.UnitData.Level,
		GUID = state.UnitGUID,
	}

	if not AddUnitToInventory(player, state.UnitGUID, unitData) then
		return false, "Failed to return unit to inventory", income
	end

	-- Clear state
	playerData.Pens[structureId] = nil

	-- Notify client
	if Remotes.StructureStateChanged then
		Remotes.StructureStateChanged:FireClient(player, {
			StructureType = "Pen",
			StructureId = structureId,
			Action = "UnitRemoved",
			State = nil,
			AmountCollected = income,
		})
	end

	print(`[StructureService] {player.Name} removed unit from pen {structureId}, collected ${income}`)
	return true, nil, income
end

--[[
    Gets the current state of a pen
]]
local function GetPenState(player: Player, structureId: string): PenState?
	local playerData = PlayerStructures[player]
	if not playerData then return nil end

	return playerData.Pens[structureId]
end

--------------------------------------------------------------------------------
-- GENERAL QUERY FUNCTIONS
--------------------------------------------------------------------------------

--[[
    Gets the state of any structure for initial sync
]]
local function GetStructureState(player: Player, structureObject: Instance): any
	local structureId = GetStructureId(structureObject)
	local structureType = GetStructureType(structureObject)

	if not structureId or not structureType then return nil end

	local playerData = PlayerStructures[player]
	if not playerData then return nil end

	if structureType == "Incubator" then
		return {
			Type = "Incubator",
			State = playerData.Incubators[structureId],
		}
	elseif structureType == "Pen" then
		local penState = playerData.Pens[structureId]
		if penState then
			-- Include calculated income
			return {
				Type = "Pen",
				State = penState,
				CurrentIncome = CalculatePenIncome(penState),
				IncomeRate = GetPenIncomeRate(penState),
			}
		end
		return { Type = "Pen", State = nil }
	end

	return nil
end

--[[
    Gets all structure states for a player (for reconnection sync)
]]
local function GetAllStructureStates(player: Player): { Incubators: any, Pens: any }
	local playerData = PlayerStructures[player]
	if not playerData then
		return { Incubators = {}, Pens = {} }
	end

	local result = {
		Incubators = {},
		Pens = {},
	}

	for structureId, state in pairs(playerData.Incubators) do
		result.Incubators[structureId] = {
			State = state,
			TimeRemaining = GetIncubatorTimeRemaining(state),
			IsReady = IsIncubatorReady(state),
		}
	end

	for structureId, state in pairs(playerData.Pens) do
		result.Pens[structureId] = {
			State = state,
			CurrentIncome = CalculatePenIncome(state),
			IncomeRate = GetPenIncomeRate(state),
		}
	end

	return result
end

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

local function SetupRemotes()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	local function GetOrCreateRemote(name: string, className: string): Instance
		local existing = remotesFolder:FindFirstChild(name)
		if existing then return existing end

		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = remotesFolder
		return remote
	end

	-- Events (Server -> Client)
	Remotes.StructureStateChanged = GetOrCreateRemote("StructureStateChanged", "RemoteEvent")
	Remotes.CashChanged = GetOrCreateRemote("CashChanged", "RemoteEvent")

	-- Functions (Client -> Server)
	local getAvailableEggsFunc = GetOrCreateRemote("GetAvailableEggs", "RemoteFunction") :: RemoteFunction
	getAvailableEggsFunc.OnServerInvoke = function(player)
		return GetAvailableEggs(player)
	end

	local getAvailableUnitsFunc = GetOrCreateRemote("GetAvailableUnits", "RemoteFunction") :: RemoteFunction
	getAvailableUnitsFunc.OnServerInvoke = function(player)
		return GetAvailableUnits(player)
	end

	local placeEggFunc = GetOrCreateRemote("PlaceEggInIncubator", "RemoteFunction") :: RemoteFunction
	placeEggFunc.OnServerInvoke = function(player, structureObject, eggGUID)
		return PlaceEggInIncubator(player, structureObject, eggGUID)
	end

	local speedUpFunc = GetOrCreateRemote("SpeedUpIncubator", "RemoteFunction") :: RemoteFunction
	speedUpFunc.OnServerInvoke = function(player, structureObject)
		return SpeedUpIncubator(player, structureObject)
	end

	local cancelIncubationFunc = GetOrCreateRemote("CancelIncubation", "RemoteFunction") :: RemoteFunction
	cancelIncubationFunc.OnServerInvoke = function(player, structureObject)
		return CancelIncubation(player, structureObject)
	end

	local hatchEggFunc = GetOrCreateRemote("HatchEgg", "RemoteFunction") :: RemoteFunction
	hatchEggFunc.OnServerInvoke = function(player, structureObject)
		return HatchEgg(player, structureObject)
	end

	local placeUnitFunc = GetOrCreateRemote("PlaceUnitInPen", "RemoteFunction") :: RemoteFunction
	placeUnitFunc.OnServerInvoke = function(player, structureObject, unitGUID)
		return PlaceUnitInPen(player, structureObject, unitGUID)
	end

	local collectPenFunc = GetOrCreateRemote("CollectFromPen", "RemoteFunction") :: RemoteFunction
	collectPenFunc.OnServerInvoke = function(player, structureObject)
		return CollectFromPen(player, structureObject)
	end

	local removeUnitFunc = GetOrCreateRemote("RemoveUnitFromPen", "RemoteFunction") :: RemoteFunction
	removeUnitFunc.OnServerInvoke = function(player, structureObject)
		return RemoveUnitFromPen(player, structureObject)
	end

	local getStructureStateFunc = GetOrCreateRemote("GetStructureState", "RemoteFunction") :: RemoteFunction
	getStructureStateFunc.OnServerInvoke = function(player, structureObject)
		return GetStructureState(player, structureObject)
	end

	local getAllStatesFunc = GetOrCreateRemote("GetAllStructureStates", "RemoteFunction") :: RemoteFunction
	getAllStatesFunc.OnServerInvoke = function(player)
		return GetAllStructureStates(player)
	end

	local getUnitCapacityFunc = GetOrCreateRemote("GetUnitCapacity", "RemoteFunction") :: RemoteFunction
	getUnitCapacityFunc.OnServerInvoke = function(player)
		return GetUnitCapacity(player), GetUnitCount(player)
	end

	print("[StructureService] Remotes initialized")
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function StructureService.Initialize(dataService, miningService)
	DataService = dataService
	MiningService = miningService

	-- Safely try to load TutorialService
	local tutorialModule = ServerScriptService:FindFirstChild("Services") and 
		ServerScriptService.Services:FindFirstChild("TutorialService")
	if tutorialModule then
		local success, result = pcall(function()
			return require(tutorialModule)
		end)
		if success then
			TutorialService = result
		end
	end

	SetupRemotes()

	-- Player connections
	-- Player connections
	Players.PlayerAdded:Connect(InitializePlayerData)
	-- NOTE: Don't cleanup on PlayerRemoving - DataService handles save order
	-- CleanupPlayerData is called by DataService AFTER saving

	-- Initialize existing players
	for _, player in Players:GetPlayers() do
		InitializePlayerData(player)
	end

	print("[StructureService] V6.0 Initialized - Complete Rewrite")
end

--------------------------------------------------------------------------------
-- PUBLIC API (For other server scripts)
--------------------------------------------------------------------------------

StructureService.GetIncubatorState = GetIncubatorState
StructureService.GetPenState = GetPenState
StructureService.GetAllStructureStates = GetAllStructureStates
StructureService.GetAvailableEggs = GetAvailableEggs
StructureService.GetAvailableUnits = GetAvailableUnits

--------------------------------------------------------------------------------
-- PERSISTENCE API (Called by DataService)
--------------------------------------------------------------------------------

--[[
    Sets structure states from saved data (called by DataService on load)
    Note: PenStates should have LastCollectTime already reset by DataService
]]
function StructureService.SetStructureStates(player: Player, incubatorStates: {[string]: any}, penStates: {[string]: any})
	local playerData = PlayerStructures[player]
	if not playerData then
		-- Initialize if not exists
		InitializePlayerData(player)
		playerData = PlayerStructures[player]
	end

	if not playerData then
		warn(`[StructureService] SetStructureStates: Failed to get player data for {player.Name}`)
		return
	end

	-- Load incubator states (timers continue from where they left off)
	playerData.Incubators = incubatorStates or {}

	-- Load pen states (LastCollectTime should already be reset by DataService)
	playerData.Pens = penStates or {}

	local incubatorCount = 0
	for _ in pairs(playerData.Incubators) do incubatorCount += 1 end
	local penCount = 0
	for _ in pairs(playerData.Pens) do penCount += 1 end

	print(`[StructureService] Loaded {incubatorCount} incubator states and {penCount} pen states for {player.Name}`)

	-- Notify client of all states so they can update visuals
	task.defer(function()
		if not player.Parent then return end

		for structureId, state in pairs(playerData.Incubators) do
			if Remotes.StructureStateChanged then
				Remotes.StructureStateChanged:FireClient(player, {
					StructureType = "Incubator",
					StructureId = structureId,
					Action = "Loaded",
					State = state,
				})
			end
		end

		for structureId, state in pairs(playerData.Pens) do
			if Remotes.StructureStateChanged then
				Remotes.StructureStateChanged:FireClient(player, {
					StructureType = "Pen",
					StructureId = structureId,
					Action = "Loaded",
					State = state,
				})
			end
		end
	end)
end

--[[
    Gets structure states for saving (called by DataService on save)
    Returns: (incubatorStates, penStates)
]]
function StructureService.GetStructureStates(player: Player): ({[string]: any}, {[string]: any})
	local playerData = PlayerStructures[player]
	if not playerData then
		return {}, {}
	end

	return playerData.Incubators or {}, playerData.Pens or {}
end

--[[
    Cleanup function called by DataService AFTER saving
]]
function StructureService.CleanupPlayerData(player: Player)
	PlayerStructures[player] = nil
	print(`[StructureService] Cleaned up data for {player.Name}`)
end

return StructureService
