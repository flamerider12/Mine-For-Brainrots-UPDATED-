--!strict
-- SERVICE: MiningService
-- DESCRIPTION: Server-side mining logic. Handles Block Damage, Ore Collection, Egg Drops, and Economy.
-- CONTEXT: Brainrot Mining Simulator V5
-- 
-- FIXES APPLIED:
-- 1. Added cooldown validation to prevent mining exploit
-- 2. Added InventoryFull remote firing when inventory is full
-- 3. Added admin/debug remotes for testing
-- 4. Fixed leaderstats updates in AddOreToInventory
-- 5. Added TutorialService hooks for tutorial progression
-- 6. Fixed Ores persistence for Sell UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

-- MODULES
local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SharedFolder:WaitForChild("GameConfig"))

-- SERVICES (Dependency Injection)
local PlotManager
local MineGenerator
local DataService
local TutorialService = nil  -- Set in Initialize

local MiningService = {}

--------------------------------------------------------------------------------
-- CONSTANTS & CONFIG
--------------------------------------------------------------------------------

local COOLDOWN_BUFFER = 0.05 
local MIN_SAFE_COOLDOWN = 0.05 
local STARTING_CAPACITY = 50

local RARITY_ORDER = {
	GameConfig.RARITIES.Common,
	GameConfig.RARITIES.Uncommon,
	GameConfig.RARITIES.Rare,
	GameConfig.RARITIES.Epic,
	GameConfig.RARITIES.Legendary,
	GameConfig.RARITIES.Mythic,
	GameConfig.RARITIES.Godly
}

-- Admin UserIds
local ADMIN_IDS = {
	[93774265] = true,
	[88257682] = true,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local PlayerCooldowns: {[Player]: number} = {}
local PlayerEquipment: {[Player]: {PickaxeLevel: number, BackpackLevel: number}} = {}

local PlayerInventory: {[Player]: {
	Cash: number,
	Storage: number,
	InventoryValue: number,
	Ores: {[string]: {Quantity: number, TotalValue: number, UnitValue: number, Icon: string?}},
	Eggs: {[string]: GameConfig.EggData}, 
	Units: {[string]: any} 
}} = {}

local DamagedBlocks: {[BasePart]: number} = {} 
local Remotes: {[string]: RemoteEvent | RemoteFunction} = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function IsAdmin(player: Player): boolean
	return true  -- ⚠️ CHANGE THIS FOR PRODUCTION
end

--------------------------------------------------------------------------------
-- RNG HELPERS
--------------------------------------------------------------------------------

local function RollRarity(layerIndex: number): string
	local layer = GameConfig.Layers[layerIndex]
	if not layer or not layer.BrainrotDropRates then return GameConfig.RARITIES.Common end

	local rates = layer.BrainrotDropRates
	local totalWeight = 0
	for _, weight in pairs(rates) do totalWeight += weight end

	local roll = math.random() * totalWeight
	local current = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		local weight = rates[rarity] or 0
		current += weight
		if roll <= current then return rarity end
	end
	return GameConfig.RARITIES.Common
end

local function RollVariant(): string
	local roll = math.random() * 100 
	if roll <= GameConfig.Eggs.VariantChances.Void then return GameConfig.VARIANTS.Void
	elseif roll <= (GameConfig.Eggs.VariantChances.Void + GameConfig.Eggs.VariantChances.Gold) then return GameConfig.VARIANTS.Gold
	else return GameConfig.VARIANTS.Normal end
end

--------------------------------------------------------------------------------
-- INVENTORY HELPERS
--------------------------------------------------------------------------------

local function GetPlayerCapacity(player: Player): number
	local eq = PlayerEquipment[player]
	if not eq then return STARTING_CAPACITY end

	local equippedLevel = player:GetAttribute("EquippedBackpack") or eq.BackpackLevel
	local backpack = GameConfig.GetBackpack(equippedLevel)
	return backpack and backpack.Capacity or STARTING_CAPACITY
end

local function GetPlayerStorage(player: Player): number
	local inv = PlayerInventory[player]
	return inv and inv.Storage or 0
end

local function IsInventoryFull(player: Player): boolean
	return GetPlayerStorage(player) >= GetPlayerCapacity(player)
end

local function SetBackpackLevel(player: Player, level: number)
	local eq = PlayerEquipment[player]
	if not eq then return end

	local maxLevel = #GameConfig.Backpacks
	level = math.clamp(level, 1, maxLevel)

	eq.BackpackLevel = level
	player:SetAttribute("BackpackLevel", level)

	local backpack = GameConfig.GetBackpack(level)
	local capacity = (level == 1) and STARTING_CAPACITY or backpack.Capacity

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local capacityStat = leaderstats:FindFirstChild("Capacity")
		if capacityStat then capacityStat.Value = capacity end
	end

	if Remotes.StorageChanged then
		local inv = PlayerInventory[player]
		Remotes.StorageChanged:FireClient(player, {
			StorageUsed = inv and inv.Storage or 0,
			Capacity = capacity,
			InventoryValue = inv and inv.InventoryValue or 0,
			Action = "CapacityChanged"
		})
	end
end

local function AddOreToInventory(player: Player, blockValue: number, oreName: string?, oreIcon: string?): boolean
	local inv = PlayerInventory[player]
	if not inv then return false end
	local capacity = GetPlayerCapacity(player)

	if inv.Storage >= capacity then return false end

	inv.Storage += 1
	inv.InventoryValue += blockValue
	local oreId = oreName or "Unknown Ore"

	if not inv.Ores[oreId] then
		inv.Ores[oreId] = { Quantity = 0, TotalValue = 0, UnitValue = blockValue, Icon = oreIcon }
	end
	inv.Ores[oreId].Quantity += 1
	inv.Ores[oreId].TotalValue += blockValue

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local storageStat = ls:FindFirstChild("Storage")
		if storageStat then storageStat.Value = inv.Storage end
		local invValueStat = ls:FindFirstChild("InventoryValue")
		if invValueStat then invValueStat.Value = inv.InventoryValue end
	end

	if Remotes.StorageChanged then
		Remotes.StorageChanged:FireClient(player, {
			StorageUsed = inv.Storage,
			Capacity = capacity,
			InventoryValue = inv.InventoryValue,
			Action = "Added",
			OreName = oreId,
			OreValue = blockValue
		})
	end
	return true
end

local function AddEggToInventory(player: Player, rarity: string, variant: string)
	local inv = PlayerInventory[player]
	if not inv then return end

	local uniqueId = HttpService:GenerateGUID(false)
	local newEgg: GameConfig.EggData = {
		Id = uniqueId,
		Rarity = rarity,
		Variant = variant,
		AcquiredAt = os.time()
	}

	inv.Eggs[uniqueId] = newEgg
	print(`[MiningService] Added {variant} {rarity} Egg to {player.Name} (ID: {uniqueId})`)
end

local function SellInventory(player: Player)
	local inv = PlayerInventory[player]
	if not inv or inv.Storage <= 0 then return false, 0, 0 end

	local amount = inv.InventoryValue
	local count = inv.Storage

	inv.Cash += amount
	inv.Storage = 0
	inv.InventoryValue = 0
	inv.Ores = {}

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		if ls:FindFirstChild("Cash") then ls.Cash.Value = inv.Cash end
		if ls:FindFirstChild("Storage") then ls.Storage.Value = 0 end
		if ls:FindFirstChild("InventoryValue") then ls.InventoryValue.Value = 0 end
	end

	if Remotes.CashChanged then Remotes.CashChanged:FireClient(player, { Cash = inv.Cash, Delta = amount, Reason = "Sell" }) end
	if Remotes.StorageChanged then Remotes.StorageChanged:FireClient(player, { StorageUsed = 0, Capacity = GetPlayerCapacity(player), InventoryValue = 0, Action = "Sold" }) end
	if DataService then DataService.IncrementStat(player, "TotalCashEarned", amount) end

	-- Tutorial hook: Inventory sold
	if TutorialService and TutorialService.OnInventorySold then
		TutorialService.OnInventorySold(player)
	end

	return true, amount, count
end

local function GetFullInventory(player: Player)
	local inv = PlayerInventory[player]
	if not inv then return { Eggs = {}, Units = {} } end

	local eggs = {}
	for guid, data in pairs(inv.Eggs) do
		table.insert(eggs, { Id = guid, Type = "Egg", Rarity = data.Rarity, Variant = data.Variant })
	end

	local units = {}
	for guid, data in pairs(inv.Units) do
		table.insert(units, { Id = guid, Type = "Unit", Name = data.Id, Variant = data.Variant, Level = data.Level })
	end

	return { Eggs = eggs, Units = units }
end

local function GetInventoryForSell(player: Player)
	local inv = PlayerInventory[player]
	if not inv then return { Ores = {}, TotalValue = 0, TotalCount = 0, Cash = 0 } end

	local oreList = {}
	for oreName, oreData in pairs(inv.Ores) do
		table.insert(oreList, {
			Name = oreName,
			Quantity = oreData.Quantity,
			TotalValue = oreData.TotalValue,
			UnitValue = oreData.UnitValue,
			Icon = oreData.Icon
		})
	end
	table.sort(oreList, function(a, b) return a.TotalValue > b.TotalValue end)

	return {
		Ores = oreList,
		TotalValue = inv.InventoryValue,
		TotalCount = inv.Storage,
		Cash = inv.Cash
	}
end

--------------------------------------------------------------------------------
-- UPGRADE FUNCTIONS
--------------------------------------------------------------------------------

local function UpgradePickaxe(player: Player): (boolean, string?)
	local eq = PlayerEquipment[player]
	local inv = PlayerInventory[player]
	if not eq or not inv then return false, "Not initialized" end

	local currentLevel = eq.PickaxeLevel
	local nextLevel = currentLevel + 1
	local nextPickaxe = GameConfig.GetPickaxe(nextLevel)

	if not nextPickaxe then
		return false, "Max level reached"
	end

	if inv.Cash < nextPickaxe.Cost then 
		return false, string.format("Not enough cash (need $%d, have $%d)", nextPickaxe.Cost, inv.Cash)
	end

	inv.Cash = inv.Cash - nextPickaxe.Cost
	eq.PickaxeLevel = nextLevel
	player:SetAttribute("PickaxeLevel", nextLevel)

	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Cash") then ls.Cash.Value = inv.Cash end

	if Remotes.CashChanged then
		Remotes.CashChanged:FireClient(player, { Cash = inv.Cash, Delta = -nextPickaxe.Cost, Reason = "Purchase" })
	end

	print(string.format("[MiningService] %s upgraded pickaxe to level %d (%s)", player.Name, nextLevel, nextPickaxe.Name))

	-- Tutorial hook: Pickaxe upgraded
	if TutorialService and TutorialService.OnPickaxeUpgraded then
		TutorialService.OnPickaxeUpgraded(player)
	end

	return true, nil
end

local function UpgradeBackpack(player: Player): (boolean, string?)
	local eq = PlayerEquipment[player]
	local inv = PlayerInventory[player]
	if not eq or not inv then return false, "Not initialized" end

	local currentLevel = eq.BackpackLevel
	local nextLevel = currentLevel + 1
	local nextBackpack = GameConfig.GetBackpack(nextLevel)

	if not nextBackpack then
		return false, "Max level reached"
	end

	if inv.Cash < nextBackpack.Cost then 
		return false, string.format("Not enough cash (need $%d, have $%d)", nextBackpack.Cost, inv.Cash)
	end

	inv.Cash = inv.Cash - nextBackpack.Cost

	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Cash") then ls.Cash.Value = inv.Cash end

	SetBackpackLevel(player, nextLevel)

	if Remotes.CashChanged then
		Remotes.CashChanged:FireClient(player, { Cash = inv.Cash, Delta = -nextBackpack.Cost, Reason = "Purchase" })
	end

	print(string.format("[MiningService] %s upgraded backpack to level %d (%s, capacity: %d)", player.Name, nextLevel, nextBackpack.Name, nextBackpack.Capacity))
	return true, nil
end

--------------------------------------------------------------------------------
-- PLAYER MANAGEMENT
--------------------------------------------------------------------------------

local function InitializePlayerData(player: Player)
	PlayerEquipment[player] = { PickaxeLevel = 1, BackpackLevel = 1 }
	PlayerInventory[player] = { Cash = 0, Storage = 0, InventoryValue = 0, Ores = {}, Eggs = {}, Units = {} }
	PlayerCooldowns[player] = 0

	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local c = Instance.new("IntValue"); c.Name = "Cash"; c.Value = 0; c.Parent = ls
	local s = Instance.new("IntValue"); s.Name = "Storage"; s.Value = 0; s.Parent = ls
	local cap = Instance.new("IntValue"); cap.Name = "Capacity"; cap.Value = STARTING_CAPACITY; cap.Parent = ls
	local iv = Instance.new("IntValue"); iv.Name = "InventoryValue"; iv.Value = 0; iv.Parent = ls

	player:SetAttribute("PickaxeLevel", 1)
	player:SetAttribute("BackpackLevel", 1)

	print(`[MiningService] {player.Name} Initialized`)
end

local function ApplyLoadedData(player: Player, data: any)
	local eq = PlayerEquipment[player]
	local inv = PlayerInventory[player]

	if not eq or not inv then return end

	eq.PickaxeLevel = data.PickaxeLevel or 1
	eq.BackpackLevel = data.BackpackLevel or 1

	inv.Cash = data.Cash or 0
	inv.Storage = data.Storage or 0
	inv.InventoryValue = data.InventoryValue or 0

	-- Load Ores breakdown if it exists, otherwise create placeholder if player has items
	if data.Ores and next(data.Ores) then
		inv.Ores = data.Ores
		print(`[MiningService] Loaded Ores breakdown for {player.Name}`)
	elseif inv.Storage > 0 and inv.InventoryValue > 0 then
		-- Player has saved items but no Ores breakdown - create a placeholder
		-- This allows the sell UI to show something until they mine more
		inv.Ores = {
			["Saved Items"] = {
				Quantity = inv.Storage,
				TotalValue = inv.InventoryValue,
				UnitValue = math.floor(inv.InventoryValue / inv.Storage),
				Icon = nil
			}
		}
		print(`[MiningService] Created placeholder Ores for {player.Name} ({inv.Storage} items, ${inv.InventoryValue})`)
	else
		inv.Ores = {}
	end

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		if ls:FindFirstChild("Cash") then ls.Cash.Value = inv.Cash end
		if ls:FindFirstChild("Storage") then ls.Storage.Value = inv.Storage end
		if ls:FindFirstChild("InventoryValue") then ls.InventoryValue.Value = inv.InventoryValue end
	end

	player:SetAttribute("PickaxeLevel", eq.PickaxeLevel)
	player:SetAttribute("BackpackLevel", eq.BackpackLevel)
end

local function CleanupPlayerData(player: Player)
	PlayerEquipment[player] = nil
	PlayerInventory[player] = nil
	PlayerCooldowns[player] = nil
end

local function GetPlayerPickaxe(player: Player)
	local eq = PlayerEquipment[player]
	local equippedLevel = player:GetAttribute("EquippedPickaxe") or (eq and eq.PickaxeLevel or 1)
	return GameConfig.GetPickaxe(equippedLevel)
end

function MiningService.GetPlayerInventory(player: Player) return PlayerInventory[player] end

function MiningService.SetEggsAndUnits(player: Player, eggs: {[string]: any}, units: {[string]: any})
	local inv = PlayerInventory[player]
	if not inv then 
		warn(`[MiningService] SetEggsAndUnits: No inventory for {player.Name}`)
		return 
	end

	inv.Eggs = eggs or {}
	inv.Units = units or {}

	local eggCount = 0
	for _ in pairs(inv.Eggs) do eggCount += 1 end
	local unitCount = 0
	for _ in pairs(inv.Units) do unitCount += 1 end

	print(`[MiningService] Loaded {eggCount} eggs and {unitCount} units for {player.Name}`)
end

function MiningService.GetEggsAndUnits(player: Player): ({[string]: any}, {[string]: any})
	local inv = PlayerInventory[player]
	if not inv then 
		return {}, {}
	end

	return inv.Eggs or {}, inv.Units or {}
end

--------------------------------------------------------------------------------
-- MINING LOGIC
--------------------------------------------------------------------------------

local function DamageBlock(player: Player, block: BasePart)
	local pickaxe = GetPlayerPickaxe(player)
	local cur = block:GetAttribute("Health") or 0
	local max = block:GetAttribute("MaxHealth") or 1
	local new = math.max(0, cur - pickaxe.Power)

	block:SetAttribute("Health", new)
	PlayerCooldowns[player] = tick()

	if new > 0 then DamagedBlocks[block] = tick()
	else DamagedBlocks[block] = nil end

	return (new <= 0), new, max
end

local function OnMiningRequest(player: Player, block: BasePart)
	if not player.Character or not block or not block.Parent then return end
	if not CollectionService:HasTag(block, "Mineable") then return end

	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if (hrp.Position - block.Position).Magnitude > (GameConfig.Mining.MaxDistance or 25) then return end

	local now = tick()
	local lastHit = PlayerCooldowns[player] or 0
	local pickaxe = GetPlayerPickaxe(player)
	local cooldown = (pickaxe and pickaxe.Cooldown or 0.5) - COOLDOWN_BUFFER

	if (now - lastHit) < math.max(cooldown, MIN_SAFE_COOLDOWN) then
		return
	end

	if IsInventoryFull(player) then
		if Remotes.InventoryFull then
			Remotes.InventoryFull:FireClient(player)
		end
		return
	end

	local destroyed, newHealth, maxHealth = DamageBlock(player, block)

	if destroyed then
		local blockPos = block.Position
		local blockData = MineGenerator.GetBlockData(block)

		if blockData then
			if blockData.BlockType == "Brainrot" then
				local layerIndex = blockData.LayerIndex or 1
				local rarity = RollRarity(layerIndex)
				local variant = RollVariant()

				AddEggToInventory(player, rarity, variant)

				if Remotes.BrainrotDropped then
					Remotes.BrainrotDropped:FireClient(player, {
						Position = blockPos,
						Rarity = rarity,
						Variant = variant
					})
				end

				-- Tutorial hook: Brainrot dropped
				if TutorialService and TutorialService.OnBrainrotDropped then
					TutorialService.OnBrainrotDropped(player)
				end
			else
				local oreName = blockData.BlockName or blockData.BlockId or "Unknown"
				local added = AddOreToInventory(player, blockData.Value, oreName, blockData.Icon)

				if not added then
					if Remotes.InventoryFull then
						Remotes.InventoryFull:FireClient(player)
					end
				end

				if DataService and blockData.BlockType ~= "Brainrot" then
					DataService.DiscoverOre(player, blockData.BlockId)
				end

				local inv = PlayerInventory[player]
				if Remotes.BlockDestroyed then
					Remotes.BlockDestroyed:FireClient(player, {
						Position = blockPos,
						BlockData = blockData,
						CashAwarded = blockData.Value,
						CurrentStorage = inv and inv.Storage or 0,
						MaxStorage = GetPlayerCapacity(player)
					})
				end

				-- Tutorial hook: Storage changed (after adding ore)
				if TutorialService and TutorialService.OnStorageChanged and inv then
					TutorialService.OnStorageChanged(player, inv.Storage, GetPlayerCapacity(player))
				end
			end

			if DataService then DataService.IncrementStat(player, "TotalBlocksMined") end

			-- Tutorial hook: Block destroyed (for all block types)
			if TutorialService and TutorialService.OnBlockDestroyed then
				TutorialService.OnBlockDestroyed(player, blockData)
			end
		end

		block:Destroy()
	else
		if Remotes.BlockDamaged then
			Remotes.BlockDamaged:FireClient(player, { Block = block, Health = newHealth, MaxHealth = maxHealth })
		end
	end
end

--------------------------------------------------------------------------------
-- BLOCK REGEN LOOP
--------------------------------------------------------------------------------

local function StartRegenLoop()
	while true do
		task.wait(1)
		local now = tick()
		for block, lastHit in pairs(DamagedBlocks) do
			if not block.Parent then DamagedBlocks[block] = nil; continue end
			if (now - lastHit) > 2 then
				local max = block:GetAttribute("MaxHealth") or 1
				block:SetAttribute("Health", max)
				DamagedBlocks[block] = nil
				if Remotes.BlockDamaged then Remotes.BlockDamaged:FireAllClients({Block=block, Health=max, MaxHealth=max}) end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function MiningService.Initialize(plotManager, mineGenerator, dataService)
	PlotManager = plotManager
	MineGenerator = mineGenerator
	DataService = dataService

	-- Get TutorialService reference (may not exist yet)
	local servicesFolder = ServerScriptService:FindFirstChild("Services")
	if servicesFolder then
		local tutorialModule = servicesFolder:FindFirstChild("TutorialService")
		if tutorialModule then
			local success, result = pcall(function()
				return require(tutorialModule)
			end)
			if success then
				TutorialService = result
				print("[MiningService] TutorialService connected")
			end
		end
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	local function GetRemote(name, class)
		local r = remotesFolder:FindFirstChild(name)
		if not r then 
			r = Instance.new(class)
			r.Name = name
			r.Parent = remotesFolder
		end
		return r
	end

	-- Standard Remotes
	Remotes.RequestMineHit = GetRemote("RequestMineHit", "RemoteEvent")
	Remotes.BlockDamaged = GetRemote("BlockDamaged", "RemoteEvent")
	Remotes.BlockDestroyed = GetRemote("BlockDestroyed", "RemoteEvent")
	Remotes.BrainrotDropped = GetRemote("BrainrotDropped", "RemoteEvent")
	Remotes.StorageChanged = GetRemote("StorageChanged", "RemoteEvent")
	Remotes.CashChanged = GetRemote("CashChanged", "RemoteEvent")
	Remotes.InventoryFull = GetRemote("InventoryFull", "RemoteEvent")

	-- Standard RemoteFunctions
	Remotes.SellInventory = GetRemote("SellInventory", "RemoteFunction")
	local sellFunc = Remotes.SellInventory :: RemoteFunction
	sellFunc.OnServerInvoke = function(p) return SellInventory(p) end

	Remotes.GetInventoryForSell = GetRemote("GetInventoryForSell", "RemoteFunction")
	local getInvSell = Remotes.GetInventoryForSell :: RemoteFunction
	getInvSell.OnServerInvoke = function(p) return GetInventoryForSell(p) end

	Remotes.UpgradePickaxe = GetRemote("UpgradePickaxe", "RemoteFunction")
	local upPick = Remotes.UpgradePickaxe :: RemoteFunction
	upPick.OnServerInvoke = function(p) return UpgradePickaxe(p) end

	Remotes.UpgradeBackpack = GetRemote("UpgradeBackpack", "RemoteFunction")
	local upPack = Remotes.UpgradeBackpack :: RemoteFunction
	upPack.OnServerInvoke = function(p) return UpgradeBackpack(p) end

	Remotes.GetFullInventory = GetRemote("GetFullInventory", "RemoteFunction")
	local getFullInv = Remotes.GetFullInventory :: RemoteFunction
	getFullInv.OnServerInvoke = function(p) return GetFullInventory(p) end

	-- Mining request handler
	Remotes.RequestMineHit.OnServerEvent:Connect(OnMiningRequest)

	----------------------------------------------------------------------------
	-- ADMIN/DEBUG REMOTES
	----------------------------------------------------------------------------

	Remotes.SetPickaxeLevel = GetRemote("SetPickaxeLevel", "RemoteFunction")
	local setPickFunc = Remotes.SetPickaxeLevel :: RemoteFunction
	setPickFunc.OnServerInvoke = function(player: Player, level: number)
		if not IsAdmin(player) then return false, "Not authorized" end

		local eq = PlayerEquipment[player]
		if not eq then return false, "Not initialized" end

		local maxLevel = #GameConfig.Pickaxes
		level = math.clamp(level, 1, maxLevel)

		eq.PickaxeLevel = level
		player:SetAttribute("PickaxeLevel", level)

		print(string.format("[MiningService] Admin set %s pickaxe to level %d", player.Name, level))
		return true
	end

	Remotes.SetBackpackLevel = GetRemote("SetBackpackLevel", "RemoteFunction")
	local setPackFunc = Remotes.SetBackpackLevel :: RemoteFunction
	setPackFunc.OnServerInvoke = function(player: Player, level: number)
		if not IsAdmin(player) then return false, "Not authorized" end

		local eq = PlayerEquipment[player]
		if not eq then return false, "Not initialized" end

		local maxLevel = #GameConfig.Backpacks
		level = math.clamp(level, 1, maxLevel)

		SetBackpackLevel(player, level)

		print(string.format("[MiningService] Admin set %s backpack to level %d", player.Name, level))
		return true
	end

	Remotes.SetCash = GetRemote("SetCash", "RemoteFunction")
	local setCashFunc = Remotes.SetCash :: RemoteFunction
	setCashFunc.OnServerInvoke = function(player: Player, amount: number)
		if not IsAdmin(player) then return false, "Not authorized" end

		local inv = PlayerInventory[player]
		if not inv then return false, "Not initialized" end

		amount = math.max(0, math.floor(amount))
		inv.Cash = amount

		local ls = player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Cash") then
			ls.Cash.Value = amount
		end

		if Remotes.CashChanged then
			Remotes.CashChanged:FireClient(player, { Cash = amount, Delta = 0, Reason = "Admin" })
		end

		print(string.format("[MiningService] Admin set %s cash to $%d", player.Name, amount))
		return true
	end

	Remotes.AddCash = GetRemote("AddCash", "RemoteFunction")
	local addCashFunc = Remotes.AddCash :: RemoteFunction
	addCashFunc.OnServerInvoke = function(player: Player, amount: number)
		if not IsAdmin(player) then return false, "Not authorized" end

		local inv = PlayerInventory[player]
		if not inv then return false, "Not initialized" end

		amount = math.floor(amount)
		local oldCash = inv.Cash
		inv.Cash = math.max(0, inv.Cash + amount)

		local ls = player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Cash") then
			ls.Cash.Value = inv.Cash
		end

		if Remotes.CashChanged then
			Remotes.CashChanged:FireClient(player, { Cash = inv.Cash, Delta = amount, Reason = "Admin" })
		end

		print(string.format("[MiningService] Admin added $%d to %s (was $%d, now $%d)", amount, player.Name, oldCash, inv.Cash))
		return true
	end

	Remotes.FillInventory = GetRemote("FillInventory", "RemoteFunction")
	local fillInvFunc = Remotes.FillInventory :: RemoteFunction
	fillInvFunc.OnServerInvoke = function(player: Player)
		if not IsAdmin(player) then return false, "Not authorized" end

		local inv = PlayerInventory[player]
		if not inv then return false, "Not initialized" end

		local capacity = GetPlayerCapacity(player)
		local toAdd = capacity - inv.Storage

		if toAdd <= 0 then return false, "Inventory already full" end

		local testOres = {"Diamond", "Gold", "Emerald", "Ruby", "Iron", "Coal"}
		local valuePerOre = 100

		for i = 1, toAdd do
			local oreName = testOres[(i % #testOres) + 1]
			inv.Storage += 1
			inv.InventoryValue += valuePerOre

			if not inv.Ores[oreName] then
				inv.Ores[oreName] = { Quantity = 0, TotalValue = 0, UnitValue = valuePerOre }
			end
			inv.Ores[oreName].Quantity += 1
			inv.Ores[oreName].TotalValue += valuePerOre
		end

		local ls = player:FindFirstChild("leaderstats")
		if ls then
			if ls:FindFirstChild("Storage") then ls.Storage.Value = inv.Storage end
			if ls:FindFirstChild("InventoryValue") then ls.InventoryValue.Value = inv.InventoryValue end
		end

		if Remotes.StorageChanged then
			Remotes.StorageChanged:FireClient(player, {
				StorageUsed = inv.Storage,
				Capacity = capacity,
				InventoryValue = inv.InventoryValue,
				Action = "AdminFill"
			})
		end

		print(string.format("[MiningService] Admin filled %s inventory with %d test ores ($%d value)", player.Name, toAdd, toAdd * valuePerOre))
		return true, toAdd
	end

	Remotes.ClearInventory = GetRemote("ClearInventory", "RemoteFunction")
	local clearInvFunc = Remotes.ClearInventory :: RemoteFunction
	clearInvFunc.OnServerInvoke = function(player: Player)
		if not IsAdmin(player) then return false, "Not authorized" end

		local inv = PlayerInventory[player]
		if not inv then return false, "Not initialized" end

		local oldStorage = inv.Storage
		inv.Storage = 0
		inv.InventoryValue = 0
		inv.Ores = {}

		local ls = player:FindFirstChild("leaderstats")
		if ls then
			if ls:FindFirstChild("Storage") then ls.Storage.Value = 0 end
			if ls:FindFirstChild("InventoryValue") then ls.InventoryValue.Value = 0 end
		end

		if Remotes.StorageChanged then
			Remotes.StorageChanged:FireClient(player, {
				StorageUsed = 0,
				Capacity = GetPlayerCapacity(player),
				InventoryValue = 0,
				Action = "AdminClear"
			})
		end

		print(string.format("[MiningService] Admin cleared %s inventory (%d items removed)", player.Name, oldStorage))
		return true
	end

	Remotes.GetPlayerStats = GetRemote("GetPlayerStats", "RemoteFunction")
	local getStatsFunc = Remotes.GetPlayerStats :: RemoteFunction
	getStatsFunc.OnServerInvoke = function(player: Player)
		local eq = PlayerEquipment[player]
		local inv = PlayerInventory[player]

		if not eq or not inv then return nil end

		local pickaxe = GameConfig.GetPickaxe(eq.PickaxeLevel)
		local backpack = GameConfig.GetBackpack(eq.BackpackLevel)
		local nextPickaxe = GameConfig.GetPickaxe(eq.PickaxeLevel + 1)
		local nextBackpack = GameConfig.GetBackpack(eq.BackpackLevel + 1)

		return {
			Cash = inv.Cash,
			Storage = inv.Storage,
			Capacity = GetPlayerCapacity(player),
			InventoryValue = inv.InventoryValue,
			PickaxeLevel = eq.PickaxeLevel,
			PickaxeName = pickaxe and pickaxe.Name or "Unknown",
			PickaxePower = pickaxe and pickaxe.Power or 1,
			NextPickaxeCost = nextPickaxe and nextPickaxe.Cost or nil,
			BackpackLevel = eq.BackpackLevel,
			BackpackName = backpack and backpack.Name or "Unknown",
			NextBackpackCost = nextBackpack and nextBackpack.Cost or nil,
			NextBackpackCapacity = nextBackpack and nextBackpack.Capacity or nil,
		}
	end

	print("[MiningService] Admin remotes initialized")

	----------------------------------------------------------------------------
	-- EQUIP REMOTES
	----------------------------------------------------------------------------

	Remotes.EquipPickaxe = GetRemote("EquipPickaxe", "RemoteFunction")
	local equipPickFunc = Remotes.EquipPickaxe :: RemoteFunction
	equipPickFunc.OnServerInvoke = function(player: Player, level: number): (boolean, string?)
		local eq = PlayerEquipment[player]
		local inv = PlayerInventory[player]

		if not eq or not inv then
			return false, "Player data not found"
		end

		if type(level) ~= "number" then
			return false, "Invalid level"
		end

		level = math.floor(level)

		if level < 1 or level > eq.PickaxeLevel then
			return false, "You don't own this pickaxe"
		end

		local pickaxe = GameConfig.GetPickaxe(level)
		if not pickaxe then
			return false, "Invalid pickaxe"
		end

		player:SetAttribute("EquippedPickaxe", level)

		print("[MiningService]", player.Name, "equipped", pickaxe.Name)

		return true, nil
	end

	Remotes.EquipBackpack = GetRemote("EquipBackpack", "RemoteFunction")
	local equipPackFunc = Remotes.EquipBackpack :: RemoteFunction
	equipPackFunc.OnServerInvoke = function(player: Player, level: number): (boolean, string?)
		local eq = PlayerEquipment[player]
		local inv = PlayerInventory[player]

		if not eq or not inv then
			return false, "Player data not found"
		end

		if type(level) ~= "number" then
			return false, "Invalid level"
		end

		level = math.floor(level)

		if level < 1 or level > eq.BackpackLevel then
			return false, "You don't own this backpack"
		end

		local backpack = GameConfig.GetBackpack(level)
		if not backpack then
			return false, "Invalid backpack"
		end

		player:SetAttribute("EquippedBackpack", level)

		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local capacity = leaderstats:FindFirstChild("Capacity")
			if capacity then
				capacity.Value = backpack.Capacity
			end
		end

		if Remotes.StorageChanged then
			Remotes.StorageChanged:FireClient(player, {
				StorageUsed = inv.Storage,
				Capacity = backpack.Capacity,
				InventoryValue = inv.InventoryValue,
				Action = "EquipBackpack"
			})
		end

		print("[MiningService]", player.Name, "equipped", backpack.Name, "- Capacity:", backpack.Capacity)

		return true, nil
	end

	print("[MiningService] Equip remotes initialized")

	----------------------------------------------------------------------------
	-- DATA SERVICE INTEGRATION
	----------------------------------------------------------------------------

	if DataService then
		DataService.OnDataLoaded(function(player, data)
			ApplyLoadedData(player, data)
		end)
	end

	----------------------------------------------------------------------------
	-- PLAYER CONNECTIONS
	----------------------------------------------------------------------------

	Players.PlayerAdded:Connect(function(p)
		InitializePlayerData(p)
		if DataService then DataService.LoadPlayerData(p) end
	end)

	Players.PlayerRemoving:Connect(function(p)
		if DataService then DataService.OnPlayerRemoving(p) end
		CleanupPlayerData(p)
	end)

	for _, p in Players:GetPlayers() do 
		InitializePlayerData(p) 
	end

	task.spawn(StartRegenLoop)

	print("[MiningService] Initialized (V5 - With Tutorial Hooks)")
end

return MiningService
