--[[
    SpeedPassHandler.lua
    Handles 2x Speed Gamepass & Developer Perks
    Location: ServerScriptService
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

-- CONFIGURATION
local GAMEPASS_ID = 1672972637 -- 🔴 REPLACE WITH YOUR GAMEPASS ID
local DEFAULT_SPEED = 16
local BOOST_SPEED = 32 -- 2x Speed

-- LIST OF DEVELOPERS (UserIDs)
-- Add your UserID and your friends' UserIDs here
local DEVELOPERS = {
	[93774265] = true, -- Replace with your UserID
	[88257682] = true, -- Replace with friend's UserID
}

-- FUNCTION: Check logic and apply speed
local function applySpeed(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local hasPass = false

	-- 1. Check if Developer
	if DEVELOPERS[player.UserId] then
		hasPass = true
		print("⚡ Speed Boost applied for Developer: " .. player.Name)
	end

	-- 2. Check GamePass (if not dev)
	if not hasPass then
		local success, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)
		end)

		if success and result then
			hasPass = true
			print("⚡ Speed Boost applied for Owner: " .. player.Name)
		end
	end

	-- 3. Apply Speed
	if hasPass then
		humanoid.WalkSpeed = BOOST_SPEED
	else
		humanoid.WalkSpeed = DEFAULT_SPEED
	end
end

-- EVENT: Player Joins
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		-- Wait a tiny bit for Roblox to load the character fully
		task.wait(0.5) 
		applySpeed(player)
	end)
end)

-- EVENT: Player buys it while in-game (Instant Update)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased and passId == GAMEPASS_ID then
		applySpeed(player)

		-- Optional: Add a "ka-ching" sound or particle here
		print("💰 " .. player.Name .. " just bought 2x Speed!")
	end
end)
