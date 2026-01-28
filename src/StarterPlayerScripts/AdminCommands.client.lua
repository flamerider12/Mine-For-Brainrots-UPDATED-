--[[
    AdminCommands.lua
    LOCAL SCRIPT - Place in StarterPlayerScripts
    
    Debug/Admin commands for testing game functionality.
    
    COMMANDS:
    /upgradepick or /uppick     - Upgrade pickaxe to next level
    /upgradepack or /uppack     - Upgrade backpack to next level
    /setpick [level]            - Set pickaxe to specific level (1-8)
    /setpack [level]            - Set backpack to specific level (1-7)
    /setcash [amount]           - Set cash to specific amount
    /addcash [amount]           - Add cash
    /maxpick                    - Max out pickaxe level
    /maxpack                    - Max out backpack level
    /maxall                     - Max out everything
    /stats                      - Show current player stats (detailed)
    /sell                       - Sell all inventory
    /fill                       - Fill inventory with test ores
    /clear                      - Clear inventory
    /help                       - Show all commands
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
	warn("[AdminCommands] Remotes folder not found!")
	return
end

-- Cache remote references
local UpgradePickaxe: RemoteFunction? = Remotes:FindFirstChild("UpgradePickaxe")
local UpgradeBackpack: RemoteFunction? = Remotes:FindFirstChild("UpgradeBackpack")
local SellInventory: RemoteFunction? = Remotes:FindFirstChild("SellInventory")
local GetInventoryForSell: RemoteFunction? = Remotes:FindFirstChild("GetInventoryForSell")
local GetPlayerStats: RemoteFunction? = Remotes:FindFirstChild("GetPlayerStats")

-- Admin-only remotes
local SetPickaxeLevel: RemoteFunction? = Remotes:FindFirstChild("SetPickaxeLevel")
local SetBackpackLevel: RemoteFunction? = Remotes:FindFirstChild("SetBackpackLevel")
local SetCash: RemoteFunction? = Remotes:FindFirstChild("SetCash")
local AddCash: RemoteFunction? = Remotes:FindFirstChild("AddCash")
local FillInventory: RemoteFunction? = Remotes:FindFirstChild("FillInventory")
local ClearInventory: RemoteFunction? = Remotes:FindFirstChild("ClearInventory")

print("[AdminCommands] Initializing...")
print("[AdminCommands] Type /help for available commands")

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function FormatNumber(n: number): string
	if not n then return "N/A" end
	n = math.floor(n)
	local formatted = tostring(n)
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return formatted
end

local function GetLeaderstats()
	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then return nil end

	return {
		Cash = leaderstats:FindFirstChild("Cash") and leaderstats.Cash.Value or 0,
		Storage = leaderstats:FindFirstChild("Storage") and leaderstats.Storage.Value or 0,
		Capacity = leaderstats:FindFirstChild("Capacity") and leaderstats.Capacity.Value or 50,
		InventoryValue = leaderstats:FindFirstChild("InventoryValue") and leaderstats.InventoryValue.Value or 0,
	}
end

local function GetPlayerAttributes()
	return {
		PickaxeLevel = Player:GetAttribute("PickaxeLevel") or 1,
		BackpackLevel = Player:GetAttribute("BackpackLevel") or 1,
		MaxLayerReached = Player:GetAttribute("MaxLayerReached") or 1,
	}
end

local function PrintStats()
	-- Try to get detailed stats from server first
	if GetPlayerStats then
		local stats = GetPlayerStats:InvokeServer()
		if stats then
			print("")
			print("╔════════════════════════════════════════════════════════╗")
			print("║                    PLAYER STATS                        ║")
			print("╠════════════════════════════════════════════════════════╣")
			print(string.format("║  💰 Cash: $%s", FormatNumber(stats.Cash)))
			print(string.format("║  📦 Storage: %s / %s", FormatNumber(stats.Storage), FormatNumber(stats.Capacity)))
			print(string.format("║  💎 Inventory Value: $%s", FormatNumber(stats.InventoryValue)))
			print("╠════════════════════════════════════════════════════════╣")
			print(string.format("║  ⛏️  PICKAXE: %s (Level %d)", stats.PickaxeName or "Unknown", stats.PickaxeLevel or 1))
			print(string.format("║     Power: %d damage per hit", stats.PickaxePower or 1))
			if stats.NextPickaxeCost then
				print(string.format("║     Next Upgrade: $%s", FormatNumber(stats.NextPickaxeCost)))
			else
				print("║     ✓ MAX LEVEL REACHED")
			end
			print("╠════════════════════════════════════════════════════════╣")
			print(string.format("║  🎒 BACKPACK: %s (Level %d)", stats.BackpackName or "Unknown", stats.BackpackLevel or 1))
			print(string.format("║     Capacity: %s slots", FormatNumber(stats.Capacity)))
			if stats.NextBackpackCost then
				print(string.format("║     Next Upgrade: $%s (→ %s slots)", FormatNumber(stats.NextBackpackCost), FormatNumber(stats.NextBackpackCapacity)))
			else
				print("║     ✓ MAX LEVEL REACHED")
			end
			print("╚════════════════════════════════════════════════════════╝")
			print("")
			return
		end
	end

	-- Fallback to local data if server remote not available
	local stats = GetLeaderstats()
	local attrs = GetPlayerAttributes()

	print("")
	print("========== PLAYER STATS (Local) ==========")
	print(string.format("  Cash: $%s", stats and FormatNumber(stats.Cash) or "N/A"))
	print(string.format("  Storage: %s / %s", stats and FormatNumber(stats.Storage) or "N/A", stats and FormatNumber(stats.Capacity) or "N/A"))
	print(string.format("  Inventory Value: $%s", stats and FormatNumber(stats.InventoryValue) or "N/A"))
	print(string.format("  Pickaxe Level: %d", attrs.PickaxeLevel))
	print(string.format("  Backpack Level: %d", attrs.BackpackLevel))
	print(string.format("  Max Layer Reached: %d", attrs.MaxLayerReached))
	print("===========================================")
	print("")
end

local function PrintHelp()
	print("")
	print("╔════════════════════════════════════════════════════════╗")
	print("║                   ADMIN COMMANDS                       ║")
	print("╠════════════════════════════════════════════════════════╣")
	print("║  UPGRADES:                                             ║")
	print("║    /upgradepick, /uppick   - Upgrade pickaxe           ║")
	print("║    /upgradepack, /uppack   - Upgrade backpack          ║")
	print("║    /maxpick                - Max pickaxe               ║")
	print("║    /maxpack                - Max backpack              ║")
	print("║    /maxall                 - Max everything            ║")
	print("╠════════════════════════════════════════════════════════╣")
	print("║  ADMIN SET:                                            ║")
	print("║    /setpick [1-8]          - Set pickaxe level         ║")
	print("║    /setpack [1-7]          - Set backpack level        ║")
	print("║    /setcash [amount]       - Set cash amount           ║")
	print("║    /addcash [amount]       - Add cash                  ║")
	print("╠════════════════════════════════════════════════════════╣")
	print("║  INVENTORY:                                            ║")
	print("║    /fill                   - Fill inventory            ║")
	print("║    /clear                  - Clear inventory           ║")
	print("║    /sell                   - Sell all ores             ║")
	print("╠════════════════════════════════════════════════════════╣")
	print("║  INFO:                                                 ║")
	print("║    /stats                  - Show detailed stats       ║")
	print("║    /help                   - This help message         ║")
	print("╚════════════════════════════════════════════════════════╝")
	print("")
end

--------------------------------------------------------------------------------
-- COMMAND HANDLERS
--------------------------------------------------------------------------------

local function HandleUpgradePickaxe()
	if not UpgradePickaxe then
		warn("[AdminCommands] UpgradePickaxe remote not found!")
		return
	end

	local currentLevel = Player:GetAttribute("PickaxeLevel") or 1
	print(string.format("[AdminCommands] Attempting to upgrade pickaxe from level %d...", currentLevel))

	local success, errorMsg = UpgradePickaxe:InvokeServer()

	if success then
		local newLevel = Player:GetAttribute("PickaxeLevel") or 1
		print(string.format("[AdminCommands] ✓ Pickaxe upgraded! Level %d → %d", currentLevel, newLevel))
		-- Show new stats
		task.wait(0.2)
		PrintStats()
	else
		warn(string.format("[AdminCommands] ✗ Failed: %s", errorMsg or "Unknown error"))
	end
end

local function HandleUpgradeBackpack()
	if not UpgradeBackpack then
		warn("[AdminCommands] UpgradeBackpack remote not found!")
		return
	end

	local currentLevel = Player:GetAttribute("BackpackLevel") or 1
	print(string.format("[AdminCommands] Attempting to upgrade backpack from level %d...", currentLevel))

	local success, errorMsg = UpgradeBackpack:InvokeServer()

	if success then
		local newLevel = Player:GetAttribute("BackpackLevel") or 1
		local stats = GetLeaderstats()
		print(string.format("[AdminCommands] ✓ Backpack upgraded! Level %d → %d (Capacity: %s)", currentLevel, newLevel, FormatNumber(stats and stats.Capacity or 0)))
		-- Show new stats
		task.wait(0.2)
		PrintStats()
	else
		warn(string.format("[AdminCommands] ✗ Failed: %s", errorMsg or "Unknown error"))
	end
end

local function HandleSell()
	if not SellInventory then
		warn("[AdminCommands] SellInventory remote not found!")
		return
	end

	local statsBefore = GetLeaderstats()
	print("[AdminCommands] Selling inventory...")

	local success, amount, count = SellInventory:InvokeServer()

	if success then
		print(string.format("[AdminCommands] ✓ Sold %s items for $%s!", FormatNumber(count or 0), FormatNumber(amount or 0)))
		local statsAfter = GetLeaderstats()
		print(string.format("[AdminCommands] Cash: $%s → $%s", FormatNumber(statsBefore and statsBefore.Cash or 0), FormatNumber(statsAfter and statsAfter.Cash or 0)))
	else
		warn("[AdminCommands] ✗ Failed to sell inventory (empty?)")
	end
end

local function HandleSetPickaxe(level: number)
	if not SetPickaxeLevel then
		warn("[AdminCommands] SetPickaxeLevel remote not found!")
		return
	end

	level = math.clamp(level, 1, 8)
	print(string.format("[AdminCommands] Setting pickaxe to level %d...", level))

	local success = SetPickaxeLevel:InvokeServer(level)

	if success then
		print(string.format("[AdminCommands] ✓ Pickaxe set to level %d!", level))
		task.wait(0.2)
		PrintStats()
	else
		warn("[AdminCommands] ✗ Failed to set pickaxe level")
	end
end

local function HandleSetBackpack(level: number)
	if not SetBackpackLevel then
		warn("[AdminCommands] SetBackpackLevel remote not found!")
		return
	end

	level = math.clamp(level, 1, 7)
	print(string.format("[AdminCommands] Setting backpack to level %d...", level))

	local success = SetBackpackLevel:InvokeServer(level)

	if success then
		print(string.format("[AdminCommands] ✓ Backpack set to level %d!", level))
		task.wait(0.2)
		PrintStats()
	else
		warn("[AdminCommands] ✗ Failed to set backpack level")
	end
end

local function HandleSetCash(amount: number)
	if not SetCash then
		warn("[AdminCommands] SetCash remote not found!")
		return
	end

	print(string.format("[AdminCommands] Setting cash to $%s...", FormatNumber(amount)))

	local success = SetCash:InvokeServer(amount)

	if success then
		print(string.format("[AdminCommands] ✓ Cash set to $%s!", FormatNumber(amount)))
	else
		warn("[AdminCommands] ✗ Failed to set cash")
	end
end

local function HandleAddCash(amount: number)
	if not AddCash then
		warn("[AdminCommands] AddCash remote not found!")
		return
	end

	local statsBefore = GetLeaderstats()
	print(string.format("[AdminCommands] Adding $%s...", FormatNumber(amount)))

	local success = AddCash:InvokeServer(amount)

	if success then
		task.wait(0.1)
		local statsAfter = GetLeaderstats()
		print(string.format("[AdminCommands] ✓ Cash: $%s → $%s", FormatNumber(statsBefore and statsBefore.Cash or 0), FormatNumber(statsAfter and statsAfter.Cash or 0)))
	else
		warn("[AdminCommands] ✗ Failed to add cash")
	end
end

local function HandleFill()
	if not FillInventory then
		warn("[AdminCommands] FillInventory remote not found!")
		return
	end

	print("[AdminCommands] Filling inventory with test ores...")

	local success, count = FillInventory:InvokeServer()

	if success then
		print(string.format("[AdminCommands] ✓ Added %s test ores to inventory!", FormatNumber(count or 0)))
	else
		warn("[AdminCommands] ✗ Failed to fill inventory (already full?)")
	end
end

local function HandleClear()
	if not ClearInventory then
		warn("[AdminCommands] ClearInventory remote not found!")
		return
	end

	print("[AdminCommands] Clearing inventory...")

	local success = ClearInventory:InvokeServer()

	if success then
		print("[AdminCommands] ✓ Inventory cleared!")
	else
		warn("[AdminCommands] ✗ Failed to clear inventory")
	end
end

local function HandleMaxPickaxe()
	if not UpgradePickaxe then
		warn("[AdminCommands] UpgradePickaxe remote not found!")
		return
	end

	print("[AdminCommands] Maxing out pickaxe...")
	local startLevel = Player:GetAttribute("PickaxeLevel") or 1
	local upgrades = 0

	for i = 1, 10 do -- Safety limit
		local success, errorMsg = UpgradePickaxe:InvokeServer()
		if not success then
			if errorMsg and string.find(errorMsg, "Max level") then
				break
			elseif errorMsg and string.find(errorMsg, "Not enough cash") then
				warn("[AdminCommands] Not enough cash! Use /addcash first")
				break
			end
			break
		end
		upgrades += 1
		task.wait(0.1)
	end

	local endLevel = Player:GetAttribute("PickaxeLevel") or 1
	print(string.format("[AdminCommands] ✓ Pickaxe: Level %d → %d (%d upgrades)", startLevel, endLevel, upgrades))
	task.wait(0.2)
	PrintStats()
end

local function HandleMaxBackpack()
	if not UpgradeBackpack then
		warn("[AdminCommands] UpgradeBackpack remote not found!")
		return
	end

	print("[AdminCommands] Maxing out backpack...")
	local startLevel = Player:GetAttribute("BackpackLevel") or 1
	local upgrades = 0

	for i = 1, 10 do -- Safety limit
		local success, errorMsg = UpgradeBackpack:InvokeServer()
		if not success then
			if errorMsg and string.find(errorMsg, "Max level") then
				break
			elseif errorMsg and string.find(errorMsg, "Not enough cash") then
				warn("[AdminCommands] Not enough cash! Use /addcash first")
				break
			end
			break
		end
		upgrades += 1
		task.wait(0.1)
	end

	local endLevel = Player:GetAttribute("BackpackLevel") or 1
	local stats = GetLeaderstats()
	print(string.format("[AdminCommands] ✓ Backpack: Level %d → %d (%d upgrades, Capacity: %s)", startLevel, endLevel, upgrades, FormatNumber(stats and stats.Capacity or 0)))
	task.wait(0.2)
	PrintStats()
end

local function HandleMaxAll()
	print("[AdminCommands] Maxing out everything...")
	HandleMaxPickaxe()
	task.wait(0.5)
	HandleMaxBackpack()
end

--------------------------------------------------------------------------------
-- COMMAND PARSER
--------------------------------------------------------------------------------

local function ParseCommand(message: string)
	local args = string.split(string.lower(message), " ")
	local cmd = args[1]

	if cmd == "/upgradepick" or cmd == "/uppick" then
		HandleUpgradePickaxe()

	elseif cmd == "/upgradepack" or cmd == "/uppack" then
		HandleUpgradeBackpack()

	elseif cmd == "/setpick" then
		local level = tonumber(args[2])
		if level then
			HandleSetPickaxe(level)
		else
			warn("[AdminCommands] Usage: /setpick [1-8]")
		end

	elseif cmd == "/setpack" then
		local level = tonumber(args[2])
		if level then
			HandleSetBackpack(level)
		else
			warn("[AdminCommands] Usage: /setpack [1-7]")
		end

	elseif cmd == "/setcash" then
		local amount = tonumber(args[2])
		if amount then
			HandleSetCash(amount)
		else
			warn("[AdminCommands] Usage: /setcash [amount]")
		end

	elseif cmd == "/addcash" then
		local amount = tonumber(args[2])
		if amount then
			HandleAddCash(amount)
		else
			warn("[AdminCommands] Usage: /addcash [amount]")
		end

	elseif cmd == "/maxpick" then
		HandleMaxPickaxe()

	elseif cmd == "/maxpack" then
		HandleMaxBackpack()

	elseif cmd == "/maxall" then
		HandleMaxAll()

	elseif cmd == "/stats" or cmd == "/info" then
		PrintStats()

	elseif cmd == "/sell" then
		HandleSell()

	elseif cmd == "/fill" then
		HandleFill()

	elseif cmd == "/clear" then
		HandleClear()

	elseif cmd == "/help" or cmd == "/?" or cmd == "/commands" then
		PrintHelp()

	end
end

--------------------------------------------------------------------------------
-- CONNECT TO CHAT
--------------------------------------------------------------------------------

Player.Chatted:Connect(function(message)
	if string.sub(message, 1, 1) == "/" then
		ParseCommand(message)
	end
end)

print("[AdminCommands] Ready! Type /help for commands or /stats to see your equipment.")
