--!strict
--[[
    CashController.lua
    Client-side cash and inventory management
    
    UPDATED: Full inventory system support
    - Tracks cash, storage, and inventory value
    - Handles sell requests
    - Handles upgrade purchases
    - Events for any UI to subscribe to
    
    USAGE:
    
    -- Get current values
    local cash = CashController.GetCash()
    local storage, capacity = CashController.GetStorage()
    local inventoryValue = CashController.GetInventoryValue()
    
    -- Subscribe to changes
    CashController.OnCashChanged(function(newCash, delta, reason)
        -- Update your UI here
    end)
    
    CashController.OnStorageChanged(function(storage, capacity, inventoryValue, action)
        -- Update inventory UI here
    end)
    
    -- Actions
    local success, earned, count = CashController.SellInventory()
    local success, err = CashController.UpgradePickaxe()
    local success, err = CashController.UpgradeBackpack()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local CashController = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local IsInitialized = false
local CurrentCash: number = 0
local CurrentStorage: number = 0
local CurrentCapacity: number = 50
local CurrentInventoryValue: number = 0

-- Event listeners
local CashChangedListeners: {(number, number, string) -> ()} = {}
local StorageChangedListeners: {(number, number, number, string) -> ()} = {}

-- Remotes
local Remotes: {
	CashChanged: RemoteEvent?,
	StorageChanged: RemoteEvent?,
	SellInventory: RemoteFunction?,
	UpgradePickaxe: RemoteFunction?,
	UpgradeBackpack: RemoteFunction?,
} = {}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

local function NotifyCashListeners(newCash: number, delta: number, reason: string)
	for _, callback in ipairs(CashChangedListeners) do
		task.spawn(callback, newCash, delta, reason)
	end
end

local function NotifyStorageListeners(storage: number, capacity: number, inventoryValue: number, action: string)
	for _, callback in ipairs(StorageChangedListeners) do
		task.spawn(callback, storage, capacity, inventoryValue, action)
	end
end

local function OnCashChangedFromServer(data: {Cash: number, Delta: number, Reason: string})
	local oldCash = CurrentCash
	CurrentCash = data.Cash

	print(`[CashController] Cash: ${oldCash} -> ${CurrentCash} ({data.Delta >= 0 and "+" or ""}{data.Delta}) - {data.Reason}`)

	NotifyCashListeners(CurrentCash, data.Delta, data.Reason)
end

local function OnStorageChangedFromServer(data: {StorageUsed: number, Capacity: number, InventoryValue: number, Action: string})
	CurrentStorage = data.StorageUsed
	CurrentCapacity = data.Capacity
	CurrentInventoryValue = data.InventoryValue

	print(`[CashController] Storage: {CurrentStorage}/{CurrentCapacity} (${CurrentInventoryValue}) - {data.Action}`)

	NotifyStorageListeners(CurrentStorage, CurrentCapacity, CurrentInventoryValue, data.Action)
end

local function SyncFromLeaderstats()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	if leaderstats then
		local cashStat = leaderstats:FindFirstChild("Cash")
		if cashStat then
			CurrentCash = cashStat.Value
		end

		local storageStat = leaderstats:FindFirstChild("Storage")
		if storageStat then
			CurrentStorage = storageStat.Value
		end

		local capacityStat = leaderstats:FindFirstChild("Capacity")
		if capacityStat then
			CurrentCapacity = capacityStat.Value
		end

		local inventoryValueStat = leaderstats:FindFirstChild("InventoryValue")
		if inventoryValueStat then
			CurrentInventoryValue = inventoryValueStat.Value
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function CashController.Initialize()
	if IsInitialized then return end
	IsInitialized = true

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	-- Wait for remotes
	local cashChangedRemote = remotesFolder:WaitForChild("CashChanged", 5)
	local storageChangedRemote = remotesFolder:WaitForChild("StorageChanged", 5)
	local sellRemote = remotesFolder:WaitForChild("SellInventory", 5)
	local upgradePickaxeRemote = remotesFolder:WaitForChild("UpgradePickaxe", 5)
	local upgradeBackpackRemote = remotesFolder:WaitForChild("UpgradeBackpack", 5)

	if cashChangedRemote then
		Remotes.CashChanged = cashChangedRemote :: RemoteEvent
		Remotes.CashChanged.OnClientEvent:Connect(OnCashChangedFromServer)
	end

	if storageChangedRemote then
		Remotes.StorageChanged = storageChangedRemote :: RemoteEvent
		Remotes.StorageChanged.OnClientEvent:Connect(OnStorageChangedFromServer)
	end

	if sellRemote then
		Remotes.SellInventory = sellRemote :: RemoteFunction
	end

	if upgradePickaxeRemote then
		Remotes.UpgradePickaxe = upgradePickaxeRemote :: RemoteFunction
	end

	if upgradeBackpackRemote then
		Remotes.UpgradeBackpack = upgradeBackpackRemote :: RemoteFunction
	end

	-- Initial sync from leaderstats
	SyncFromLeaderstats()

	-- Listen for leaderstats changes as backup
	local leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
	if leaderstats then
		local cashStat = leaderstats:WaitForChild("Cash", 5)
		if cashStat then
			cashStat.Changed:Connect(function(newValue)
				if newValue ~= CurrentCash then
					local delta = newValue - CurrentCash
					CurrentCash = newValue
					NotifyCashListeners(CurrentCash, delta, "Sync")
				end
			end)
		end

		local storageStat = leaderstats:WaitForChild("Storage", 5)
		if storageStat then
			storageStat.Changed:Connect(function(newValue)
				if newValue ~= CurrentStorage then
					CurrentStorage = newValue
					NotifyStorageListeners(CurrentStorage, CurrentCapacity, CurrentInventoryValue, "Sync")
				end
			end)
		end

		local capacityStat = leaderstats:WaitForChild("Capacity", 5)
		if capacityStat then
			capacityStat.Changed:Connect(function(newValue)
				if newValue ~= CurrentCapacity then
					CurrentCapacity = newValue
					NotifyStorageListeners(CurrentStorage, CurrentCapacity, CurrentInventoryValue, "CapacityChanged")
				end
			end)
		end

		local inventoryValueStat = leaderstats:WaitForChild("InventoryValue", 5)
		if inventoryValueStat then
			inventoryValueStat.Changed:Connect(function(newValue)
				if newValue ~= CurrentInventoryValue then
					CurrentInventoryValue = newValue
					NotifyStorageListeners(CurrentStorage, CurrentCapacity, CurrentInventoryValue, "Sync")
				end
			end)
		end
	end

	print("[CashController] Initialized with Inventory System")
	print("[CashController] Ready for UI integration")
end

--[[
    Get current cash amount
]]
function CashController.GetCash(): number
	return CurrentCash
end

--[[
    Get storage info
    @return (storageUsed, capacity)
]]
function CashController.GetStorage(): (number, number)
	return CurrentStorage, CurrentCapacity
end

--[[
    Get inventory value (potential cash from selling)
]]
function CashController.GetInventoryValue(): number
	return CurrentInventoryValue
end

--[[
    Check if inventory is full
]]
function CashController.IsInventoryFull(): boolean
	return CurrentStorage >= CurrentCapacity
end

--[[
    Subscribe to cash changes
    @param callback (newCash: number, delta: number, reason: string) -> ()
    Reasons: "Sell", "Purchase", "Reward", "Debug", "Sync"
]]
function CashController.OnCashChanged(callback: (number, number, string) -> ()): () -> ()
	table.insert(CashChangedListeners, callback)

	return function()
		local index = table.find(CashChangedListeners, callback)
		if index then
			table.remove(CashChangedListeners, index)
		end
	end
end

--[[
    Subscribe to storage changes
    @param callback (storage, capacity, inventoryValue, action) -> ()
    Actions: "Added", "Sold", "Cleared", "CapacityChanged", "Sync"
]]
function CashController.OnStorageChanged(callback: (number, number, number, string) -> ()): () -> ()
	table.insert(StorageChangedListeners, callback)

	return function()
		local index = table.find(StorageChangedListeners, callback)
		if index then
			table.remove(StorageChangedListeners, index)
		end
	end
end

--[[
    Sell all items in inventory
    @return (success, cashEarned, itemsSold)
]]
function CashController.SellInventory(): (boolean, number, number)
	if not Remotes.SellInventory then
		warn("[CashController] SellInventory remote not available")
		return false, 0, 0
	end

	if CurrentStorage <= 0 then
		print("[CashController] Nothing to sell")
		return false, 0, 0
	end

	local success, cashEarned, itemsSold = Remotes.SellInventory:InvokeServer()

	if success then
		print(`[CashController] SOLD {itemsSold} items for ${cashEarned}!`)
	else
		print("[CashController] Sell failed")
	end

	return success, cashEarned, itemsSold
end

--[[
    Upgrade pickaxe
    @return (success, errorMessage?)
]]
function CashController.UpgradePickaxe(): (boolean, string?)
	if not Remotes.UpgradePickaxe then
		warn("[CashController] UpgradePickaxe remote not available")
		return false, "Remote not available"
	end

	local success, err = Remotes.UpgradePickaxe:InvokeServer()

	if success then
		print("[CashController] Pickaxe upgraded!")
	else
		print(`[CashController] Pickaxe upgrade failed: {err}`)
	end

	return success, err
end

--[[
    Upgrade backpack
    @return (success, errorMessage?)
]]
function CashController.UpgradeBackpack(): (boolean, string?)
	if not Remotes.UpgradeBackpack then
		warn("[CashController] UpgradeBackpack remote not available")
		return false, "Remote not available"
	end

	local success, err = Remotes.UpgradeBackpack:InvokeServer()

	if success then
		print("[CashController] Backpack upgraded!")
	else
		print(`[CashController] Backpack upgrade failed: {err}`)
	end

	return success, err
end

--[[
    Get current pickaxe level
]]
function CashController.GetPickaxeLevel(): number
	return LocalPlayer:GetAttribute("PickaxeLevel") or 1
end

--[[
    Get current backpack level
]]
function CashController.GetBackpackLevel(): number
	return LocalPlayer:GetAttribute("BackpackLevel") or 1
end

--[[
    Format cash for display (short form)
    @param amount number
    @return string (e.g., "$1.2K", "$3.4M")
]]
function CashController.FormatCash(amount: number): string
	if amount >= 1000000000 then
		return string.format("$%.1fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("$%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return string.format("$%d", amount)
	end
end

--[[
    Format cash with commas for detailed display
    @param amount number
    @return string (e.g., "$1,234,567")
]]
function CashController.FormatCashDetailed(amount: number): string
	local formatted = tostring(math.floor(amount))
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return "$" .. formatted
end

--[[
    Format storage display
    @return string (e.g., "45/100 ($1,234)")
]]
function CashController.FormatStorage(): string
	return `{CurrentStorage}/{CurrentCapacity} ({CashController.FormatCash(CurrentInventoryValue)})`
end

return CashController
