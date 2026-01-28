--!strict
--[[
    TutorialService.lua (FIXED V2)
    Server-side tutorial state management
    Location: ServerScriptService/Services/TutorialService.lua
    
    FIXES:
    - Proper persistence integration with DataService
    - Fixed "Complete" step handling
    - Better step advancement logic
    - Allow Continue to work on all steps
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialService = {}

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------

export type TutorialStep = {
	Id: string,
	Index: number,
	Title: string,
	Description: string,
	Hint: string?,
	AutoComplete: boolean,
	CanSkip: boolean,
}

export type PlayerTutorialData = {
	CurrentStepIndex: number,
	CompletedSteps: {[string]: boolean},
	TutorialCompleted: boolean,
	TutorialSkipped: boolean,
	StartedAt: number?,
	CompletedAt: number?,
}

--------------------------------------------------------------------------------
-- TUTORIAL STEPS
--------------------------------------------------------------------------------

local TUTORIAL_STEPS: {TutorialStep} = {
	{
		Id = "Welcome",
		Index = 1,
		Title = "Welcome to Brainrot Mining!",
		Description = "Dig deep, collect rare ores, find Brainrot eggs, and build your mining empire!",
		Hint = "Click Continue to start",
		AutoComplete = false,
		CanSkip = true,
	},
	{
		Id = "FirstMine",
		Index = 2,
		Title = "Start Mining",
		Description = "Hold LEFT CLICK on a block to mine it. Try mining the block in front of you!",
		Hint = "Hold click on a block to break it",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "CollectOre",
		Index = 3,
		Title = "Ore Collected!",
		Description = "Great! When you mine blocks, ores go into your backpack. Check your storage in the top-right!",
		Hint = "Your backpack fills as you mine",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "FillBackpack",
		Index = 4,
		Title = "Keep Mining",
		Description = "Fill your backpack to at least 50% capacity. The fuller it is, the more cash you'll earn!",
		Hint = "Mine more blocks to fill your backpack",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "FindSellStation",
		Index = 5,
		Title = "Time to Sell",
		Description = "Head to the SELL STATION on your plot surface. Look for the glowing platform!",
		Hint = "Go up and find the sell station",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "SellOres",
		Index = 6,
		Title = "Sell Your Ores",
		Description = "Step on the sell station and press the SELL button to convert your ores to cash!",
		Hint = "Press the sell button",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "OpenShop",
		Index = 7,
		Title = "Visit the Shop",
		Description = "Find the PICKAXE SHOP on your plot. Walk up to the shopkeeper to browse upgrades!",
		Hint = "The shop is near your spawn point",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "BuyPickaxe",
		Index = 8,
		Title = "Upgrade Your Pickaxe",
		Description = "Better pickaxes mine faster and deal more damage. Buy an upgrade when you can afford it!",
		Hint = "Purchase upgrades to mine faster",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "MineDeeper",
		Index = 9,
		Title = "Go Deeper!",
		Description = "Dig down to depth 10 or more. Deeper layers have rarer ores and better rewards!",
		Hint = "Keep mining downward",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "DiscoverNewOre",
		Index = 10,
		Title = "Discover New Ores",
		Description = "Different layers contain different ores. Find a new type of ore!",
		Hint = "Each layer has unique ores",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "FindBrainrot",
		Index = 11,
		Title = "Find a Brainrot Block",
		Description = "Rare BRAINROT blocks contain special eggs. They look different from normal ores!",
		Hint = "Keep an eye out for unusual blocks",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "CollectEgg",
		Index = 12,
		Title = "Collect an Egg",
		Description = "Mining a Brainrot block gives you an EGG! Eggs can be hatched into powerful Brainrots!",
		Hint = "Mine the brainrot block",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "UseIncubator",
		Index = 13,
		Title = "Use the Incubator",
		Description = "Find an INCUBATOR on your plot and place your egg inside to start hatching!",
		Hint = "Press E near an incubator",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "HatchEgg",
		Index = 14,
		Title = "Hatch Your Egg",
		Description = "Wait for the timer or speed it up! Once hatched, you'll have your first Brainrot!",
		Hint = "Eggs take time to hatch",
		AutoComplete = true,
		CanSkip = true,
	},
	{
		Id = "Complete",
		Index = 15,
		Title = "Tutorial Complete!",
		Description = "You've learned the basics! Now explore, dig deeper, collect rare Brainrots, and become the ultimate miner!",
		Hint = nil,
		AutoComplete = false,
		CanSkip = false,
	},
}

local STEP_BY_ID: {[string]: TutorialStep} = {}
for _, step in TUTORIAL_STEPS do
	STEP_BY_ID[step.Id] = step
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local PlayerTutorials: {[Player]: PlayerTutorialData} = {}
local Remotes: {[string]: RemoteEvent | RemoteFunction} = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function GetDefaultTutorialData(): PlayerTutorialData
	return {
		CurrentStepIndex = 1,
		CompletedSteps = {},
		TutorialCompleted = false,
		TutorialSkipped = false,
		StartedAt = os.time(),
		CompletedAt = nil,
	}
end

local function GetCurrentStep(player: Player): TutorialStep?
	local data = PlayerTutorials[player]
	if not data or data.TutorialCompleted or data.TutorialSkipped then
		return nil
	end
	return TUTORIAL_STEPS[data.CurrentStepIndex]
end

local function NotifyStepChange(player: Player, step: TutorialStep?, action: string)
	if not Remotes.TutorialUpdate then return end

	local data = PlayerTutorials[player]

	Remotes.TutorialUpdate:FireClient(player, {
		Action = action,
		CurrentStep = step,
		CurrentStepIndex = data and data.CurrentStepIndex or 0,
		TotalSteps = #TUTORIAL_STEPS,
		TutorialCompleted = data and data.TutorialCompleted or false,
		TutorialSkipped = data and data.TutorialSkipped or false,
		CompletedSteps = data and data.CompletedSteps or {},
	})
end

local function AdvanceToNextStep(player: Player)
	local data = PlayerTutorials[player]
	if not data or data.TutorialCompleted or data.TutorialSkipped then return end

	local currentStep = TUTORIAL_STEPS[data.CurrentStepIndex]
	if currentStep then
		data.CompletedSteps[currentStep.Id] = true
	end

	data.CurrentStepIndex += 1

	-- Check if tutorial is complete (past last step)
	if data.CurrentStepIndex > #TUTORIAL_STEPS then
		data.TutorialCompleted = true
		data.CompletedAt = os.time()
		print(`[TutorialService] {player.Name} completed the tutorial!`)
		NotifyStepChange(player, nil, "TutorialCompleted")
		return
	end

	local nextStep = TUTORIAL_STEPS[data.CurrentStepIndex]
	print(`[TutorialService] {player.Name} advanced to step: {nextStep.Id}`)
	NotifyStepChange(player, nextStep, "StepChanged")
end

local function CompleteTutorial(player: Player)
	local data = PlayerTutorials[player]
	if not data then return end

	data.TutorialCompleted = true
	data.CompletedAt = os.time()
	print(`[TutorialService] {player.Name} completed the tutorial!`)
	NotifyStepChange(player, nil, "TutorialCompleted")
end

--------------------------------------------------------------------------------
-- STEP COMPLETION TRIGGERS
--------------------------------------------------------------------------------

local function OnBlockDestroyed(player: Player)
	local step = GetCurrentStep(player)
	if not step then return end
	if step.Id == "FirstMine" then
		AdvanceToNextStep(player)
	end
end

local function OnStorageChanged(player: Player, storageUsed: number, capacity: number)
	local step = GetCurrentStep(player)
	if not step then return end

	if step.Id == "CollectOre" and storageUsed > 0 then
		AdvanceToNextStep(player)
	elseif step.Id == "FillBackpack" and capacity > 0 and (storageUsed / capacity) >= 0.5 then
		AdvanceToNextStep(player)
	end
end

local function OnEnterSellZone(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "FindSellStation" then
		AdvanceToNextStep(player)
	end
end

local function OnSellInventory(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "SellOres" then
		AdvanceToNextStep(player)
	end
end

local function OnShopOpened(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "OpenShop" then
		AdvanceToNextStep(player)
	end
end

local function OnPickaxeUpgraded(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "BuyPickaxe" then
		AdvanceToNextStep(player)
	end
end

local function OnDepthChanged(player: Player, depth: number)
	local step = GetCurrentStep(player)
	if step and step.Id == "MineDeeper" and depth >= 10 then
		AdvanceToNextStep(player)
	end
end

local function OnOreDiscovered(player: Player, oreId: string)
	local step = GetCurrentStep(player)
	if step and step.Id == "DiscoverNewOre" then
		AdvanceToNextStep(player)
	end
end

local function OnBrainrotFound(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "FindBrainrot" then
		AdvanceToNextStep(player)
	end
end

local function OnBrainrotDropped(player: Player)
	local step = GetCurrentStep(player)
	if not step then return end

	-- Can complete either FindBrainrot or CollectEgg
	if step.Id == "FindBrainrot" then
		AdvanceToNextStep(player)
		step = GetCurrentStep(player)
	end
	if step and step.Id == "CollectEgg" then
		AdvanceToNextStep(player)
	end
end

local function OnEggPlaced(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "UseIncubator" then
		AdvanceToNextStep(player)
	end
end

local function OnEggHatched(player: Player)
	local step = GetCurrentStep(player)
	if step and step.Id == "HatchEgg" then
		AdvanceToNextStep(player)
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function TutorialService.Initialize()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	local function GetOrCreateRemote(name: string, className: string): Instance
		local existing = remotesFolder:FindFirstChild(name)
		if existing then return existing end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = remotesFolder
		return remote
	end

	Remotes.TutorialUpdate = GetOrCreateRemote("TutorialUpdate", "RemoteEvent")
	Remotes.TutorialAction = GetOrCreateRemote("TutorialAction", "RemoteEvent")
	Remotes.GetTutorialState = GetOrCreateRemote("GetTutorialState", "RemoteFunction")

	-- Handle client actions
	local tutorialActionRemote = Remotes.TutorialAction :: RemoteEvent
	tutorialActionRemote.OnServerEvent:Connect(function(player, action, data)
		local tutorialData = PlayerTutorials[player]
		if not tutorialData then return end

		if action == "Continue" then
			local step = GetCurrentStep(player)
			if step then
				if step.Id == "Complete" then
					-- Final step - complete the tutorial
					CompleteTutorial(player)
				else
					-- Advance to next step (works for all steps now)
					AdvanceToNextStep(player)
				end
			end

		elseif action == "Skip" then
			local step = GetCurrentStep(player)
			if step and step.CanSkip then
				AdvanceToNextStep(player)
			end

		elseif action == "SkipAll" then
			if not tutorialData.TutorialCompleted then
				tutorialData.TutorialSkipped = true
				tutorialData.CompletedAt = os.time()
				print(`[TutorialService] {player.Name} skipped the tutorial`)
				NotifyStepChange(player, nil, "TutorialSkipped")
			end

		elseif action == "ShopOpened" then
			OnShopOpened(player)

		elseif action == "SellZoneEntered" then
			OnEnterSellZone(player)
		end
	end)

	-- Handle state requests
	local getStateFunc = Remotes.GetTutorialState :: RemoteFunction
	getStateFunc.OnServerInvoke = function(player)
		local data = PlayerTutorials[player]
		if not data then
			-- Data not loaded yet - tell client to wait
			return {
				CurrentStep = nil,
				TutorialCompleted = false,
				TutorialSkipped = false,
				DataNotReady = true,  -- Signal to client to wait
			}
		end

		-- Return actual state
		return {
			CurrentStep = GetCurrentStep(player),
			CurrentStepIndex = data.CurrentStepIndex,
			TotalSteps = #TUTORIAL_STEPS,
			TutorialCompleted = data.TutorialCompleted == true,  -- Explicit boolean
			TutorialSkipped = data.TutorialSkipped == true,      -- Explicit boolean
			CompletedSteps = data.CompletedSteps,
			DataNotReady = false,
		}
	end

	-- Player connections
	-- NOTE: Don't create default data here - let DataService.SetTutorialData handle it
	-- This prevents race conditions where default data overwrites loaded data
	Players.PlayerAdded:Connect(function(player)
		-- Data will be set by DataService.ApplyDataToPlayer -> TutorialService.SetTutorialData
		print(`[TutorialService] Player {player.Name} joined, waiting for DataService to load tutorial data...`)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerTutorials[player] = nil
	end)

	print("[TutorialService] Initialized with", #TUTORIAL_STEPS, "tutorial steps")
end

--[[
    Called by DataService when loading saved data
    This is the ONLY place where tutorial data should be initialized
]]
function TutorialService.SetTutorialData(player: Player, savedData: any?)
	if savedData and type(savedData) == "table" then
		-- Returning player with saved data
		PlayerTutorials[player] = {
			CurrentStepIndex = savedData.CurrentStepIndex or 1,
			CompletedSteps = savedData.CompletedSteps or {},
			TutorialCompleted = savedData.TutorialCompleted == true,  -- Explicit boolean check
			TutorialSkipped = savedData.TutorialSkipped == true,      -- Explicit boolean check
			StartedAt = savedData.StartedAt,
			CompletedAt = savedData.CompletedAt,
		}

		local status = "In Progress"
		if savedData.TutorialCompleted == true then
			status = "COMPLETED"
		elseif savedData.TutorialSkipped == true then
			status = "SKIPPED"
		end

		print(`[TutorialService] Loaded tutorial data for {player.Name} - Status: {status}, Step: {savedData.CurrentStepIndex or 1}`)
	else
		-- New player - create default data
		PlayerTutorials[player] = GetDefaultTutorialData()
		print(`[TutorialService] New player {player.Name} - starting tutorial from step 1`)
	end

	-- Notify client of current state
	task.defer(function()
		if not player.Parent then return end
		local data = PlayerTutorials[player]
		if not data then return end

		if data.TutorialCompleted then
			print(`[TutorialService] {player.Name} already completed tutorial - not showing UI`)
			NotifyStepChange(player, nil, "TutorialCompleted")
		elseif data.TutorialSkipped then
			print(`[TutorialService] {player.Name} already skipped tutorial - not showing UI`)
			NotifyStepChange(player, nil, "TutorialSkipped")
		else
			local step = GetCurrentStep(player)
			print(`[TutorialService] {player.Name} resuming tutorial at step: {step and step.Id or "unknown"}`)
			NotifyStepChange(player, step, "TutorialResumed")
		end
	end)
end

--[[
    Called by DataService when saving
]]
function TutorialService.GetTutorialData(player: Player): PlayerTutorialData?
	return PlayerTutorials[player]
end

function TutorialService.IsTutorialActive(player: Player): boolean
	local data = PlayerTutorials[player]
	if not data then return false end
	return not data.TutorialCompleted and not data.TutorialSkipped
end

function TutorialService.GetCurrentStep(player: Player): TutorialStep?
	return GetCurrentStep(player)
end

--------------------------------------------------------------------------------
-- EVENT HOOKS (Called by other services)
--------------------------------------------------------------------------------

TutorialService.OnBlockDestroyed = OnBlockDestroyed
TutorialService.OnStorageChanged = OnStorageChanged
TutorialService.OnInventorySold = OnSellInventory
TutorialService.OnPickaxeUpgraded = OnPickaxeUpgraded
TutorialService.OnBrainrotDropped = OnBrainrotDropped
TutorialService.OnOreDiscovered = OnOreDiscovered
TutorialService.OnDepthChanged = OnDepthChanged
TutorialService.OnEggPlaced = OnEggPlaced
TutorialService.OnEggHatched = OnEggHatched

return TutorialService
