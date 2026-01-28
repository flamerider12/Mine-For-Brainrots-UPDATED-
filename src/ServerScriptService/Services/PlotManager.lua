--[[
	PlotManager.lua
	Handles player plot assignment, cloning, and lifecycle management
	Location: ServerScriptService/Services/PlotManager.lua
	
	SETUP REQUIREMENTS:
	1. Place your base plot template in ServerStorage/Templates/BasePlot
	2. The template MUST contain a Part named "MineOrigin" - this is the reference point
	   for mine generation (top-center of wFhere blocks spawn beneath)
	3. Create a Folder in Workspace called "PlayerPlots"
	
	TEMPLATE STRUCTURE EXPECTED:
	BasePlot (Model)
	├── MineOrigin (Part) - Reference point for mine generation
	├── SpawnPoint (SpawnLocation) - Where player spawns on their plot
	├── Surface (Model/Folder) - Ground/buildings above the mine
	├── Pens (Folder) - Contains Pen1, Pen2, ... Pen10
	└── [Any other plot components]
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for GameConfig to be available
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local PlotManager = {}
PlotManager.__index = PlotManager

--------------------------------------------------------------------------------
-- PRIVATE STATE
--------------------------------------------------------------------------------

-- Active plot assignments: {[Player] = PlotData}
local ActivePlots: {[Player]: PlotData} = {}

-- Plot position tracking for grid layout
local NextPlotIndex: number = 0

-- Template reference (cached)
local PlotTemplate: Model? = nil

-- Plot container in workspace
local PlotContainer: Folder? = nil

--------------------------------------------------------------------------------
-- TYPE DEFINITIONS
--------------------------------------------------------------------------------

export type PlotData = {
	Player: Player,
	PlotModel: Model,
	MineOrigin: BasePart,
	SpawnPoint: SpawnLocation?,
	PlotIndex: number,
	GridPosition: Vector2,
	WorldPosition: Vector3,
	CreatedAt: number,
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Calculates world position for a plot based on grid index
	Uses a spiral or grid pattern to keep plots organized
]]
local function CalculatePlotPosition(plotIndex: number): (Vector3, Vector2)
	local config = GameConfig.Plot
	local columns = config.GridColumns
	local spacing = config.PlotSpacing

	-- Simple grid layout
	local gridX = plotIndex % columns
	local gridZ = math.floor(plotIndex / columns)

	local worldX = gridX * spacing
	local worldZ = gridZ * spacing

	return Vector3.new(worldX, 0, worldZ), Vector2.new(gridX, gridZ)
end

--[[
	Validates that the template has all required components
]]
local function ValidateTemplate(template: Model): (boolean, string?)
	if not template then
		return false, "Template is nil"
	end

	local mineOrigin = template:FindFirstChild("MineOrigin")
	if not mineOrigin or not mineOrigin:IsA("BasePart") then
		return false, "Template missing 'MineOrigin' Part - this is required for mine generation"
	end

	-- SpawnPoint is optional but recommended
	local spawnPoint = template:FindFirstChild("SpawnPoint")
	if not spawnPoint then
		warn("[PlotManager] Template missing 'SpawnPoint' - players will spawn at MineOrigin")
	end

	return true, nil
end

--[[
	Clones and positions a plot for a player
]]
local function CreatePlotForPlayer(player: Player): PlotData?
	if not PlotTemplate then
		warn("[PlotManager] Plot template not initialized!")
		return nil
	end

	-- Calculate position
	local plotIndex = NextPlotIndex
	NextPlotIndex += 1

	local worldPos, gridPos = CalculatePlotPosition(plotIndex)

	-- Clone template
	local plotModel = PlotTemplate:Clone()
	plotModel.Name = `Plot_{player.UserId}`

	-- Position the plot
	-- We need to offset based on the template's current position relative to origin
	local mineOrigin = plotModel:FindFirstChild("MineOrigin") :: BasePart
	local templateOffset = mineOrigin.Position

	-- Move entire plot so MineOrigin lands at the calculated world position
	local primaryPart = plotModel.PrimaryPart or mineOrigin
	plotModel.PrimaryPart = primaryPart

	local currentCFrame = plotModel:GetPivot()
	local offsetToOrigin = mineOrigin.Position - currentCFrame.Position
	local targetPosition = worldPos - offsetToOrigin

	plotModel:PivotTo(CFrame.new(targetPosition) * currentCFrame.Rotation)

	-- Update MineOrigin reference after move
	mineOrigin = plotModel:FindFirstChild("MineOrigin") :: BasePart

	-- Configure spawn point if it exists
	local spawnPoint = plotModel:FindFirstChild("SpawnPoint")
	if spawnPoint and spawnPoint:IsA("SpawnLocation") then
		spawnPoint.Neutral = false
		spawnPoint.TeamColor = BrickColor.new("White") -- Or use team system
		-- Make it player-specific by setting a tag or attribute
		spawnPoint:SetAttribute("OwnerUserId", player.UserId)
	end

	-- Parent to workspace
	plotModel.Parent = PlotContainer

	-- Create plot data
	local plotData: PlotData = {
		Player = player,
		PlotModel = plotModel,
		MineOrigin = mineOrigin,
		SpawnPoint = spawnPoint,
		PlotIndex = plotIndex,
		GridPosition = gridPos,
		WorldPosition = mineOrigin.Position,
		CreatedAt = os.time(),
	}

	-- Set attributes on model for external reference
	plotModel:SetAttribute("OwnerUserId", player.UserId)
	plotModel:SetAttribute("PlotIndex", plotIndex)

	print(`[PlotManager] Created plot for {player.Name} at grid position ({gridPos.X}, {gridPos.Y})`)

	return plotData
end

--[[
	Cleans up a player's plot when they leave
]]
local function DestroyPlot(plotData: PlotData)
	if plotData.PlotModel then
		-- Fire any cleanup events here if needed
		plotData.PlotModel:Destroy()
	end

	print(`[PlotManager] Destroyed plot for {plotData.Player.Name}`)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	Initializes the PlotManager
	Call this once from your main server script
]]
function PlotManager.Initialize()
	-- Get or create plot container
	PlotContainer = workspace:FindFirstChild("PlayerPlots")
	if not PlotContainer then
		PlotContainer = Instance.new("Folder")
		PlotContainer.Name = "PlayerPlots"
		PlotContainer.Parent = workspace
	end

	-- Load template
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then
		error("[PlotManager] ServerStorage/Templates folder not found!")
	end

	PlotTemplate = templates:FindFirstChild("BasePlot")
	if not PlotTemplate then
		error("[PlotManager] ServerStorage/Templates/BasePlot not found!")
	end

	-- Validate template
	local isValid, errorMsg = ValidateTemplate(PlotTemplate)
	if not isValid then
		error(`[PlotManager] Invalid template: {errorMsg}`)
	end

	-- Connect player events
	Players.PlayerAdded:Connect(function(player)
		PlotManager.AssignPlot(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlotManager.ReleasePlot(player)
	end)

	-- Handle players already in game (for Studio testing)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			PlotManager.AssignPlot(player)
		end)
	end

	print("[PlotManager] Initialized successfully")
end

--[[
	Assigns a plot to a player
	Returns the PlotData if successful
]]
function PlotManager.AssignPlot(player: Player): PlotData?
	-- Check if player already has a plot
	if ActivePlots[player] then
		warn(`[PlotManager] {player.Name} already has a plot assigned`)
		return ActivePlots[player]
	end

	-- Check max plots
	if NextPlotIndex >= GameConfig.Plot.MaxPlots then
		warn(`[PlotManager] Maximum plot limit reached ({GameConfig.Plot.MaxPlots})`)
		return nil
	end

	-- Create the plot
	local plotData = CreatePlotForPlayer(player)
	if not plotData then
		return nil
	end

	-- Store assignment
	ActivePlots[player] = plotData

	-- Teleport player to their plot
	task.delay(0.5, function()
		if player.Character and plotData.SpawnPoint then
			local spawnCFrame = plotData.SpawnPoint.CFrame + Vector3.new(0, 3, 0)
			player.Character:PivotTo(spawnCFrame)
		elseif player.Character then
			-- Fallback to MineOrigin if no spawn point
			local spawnCFrame = plotData.MineOrigin.CFrame + Vector3.new(0, 5, 0)
			player.Character:PivotTo(spawnCFrame)
		end
	end)

	return plotData
end

--[[
	Releases a player's plot (called on leave)
]]
function PlotManager.ReleasePlot(player: Player)
	local plotData = ActivePlots[player]
	if not plotData then
		return
	end

	DestroyPlot(plotData)
	ActivePlots[player] = nil
end

--[[
	Gets plot data for a specific player
]]
function PlotManager.GetPlotData(player: Player): PlotData?
	return ActivePlots[player]
end

--[[
	Gets the MineOrigin position for a player's plot
	This is the primary reference point for MineGenerator
]]
function PlotManager.GetMineOrigin(player: Player): Vector3?
	local plotData = ActivePlots[player]
	if plotData and plotData.MineOrigin then
		return plotData.MineOrigin.Position
	end
	return nil
end

--[[
	Gets the MineOrigin CFrame for a player's plot
	Useful if you need rotation information
]]
function PlotManager.GetMineOriginCFrame(player: Player): CFrame?
	local plotData = ActivePlots[player]
	if plotData and plotData.MineOrigin then
		return plotData.MineOrigin.CFrame
	end
	return nil
end

--[[
	Checks if a position is within a player's plot bounds
	Useful for validation
]]
function PlotManager.IsPositionInPlot(player: Player, position: Vector3): boolean
	local plotData = ActivePlots[player]
	if not plotData then
		return false
	end

	-- Calculate rough bounds based on mine size
	local config = GameConfig.Mine
	local halfWidth = (config.GridSizeX * config.BlockSize) / 2
	local halfDepth = (config.GridSizeZ * config.BlockSize) / 2
	local maxDepthY = config.MaxDepth * config.BlockSize

	local origin = plotData.MineOrigin.Position

	local relativePos = position - origin

	-- Check X/Z bounds (centered on origin)
	if math.abs(relativePos.X) > halfWidth + 50 then -- 50 stud buffer
		return false
	end
	if math.abs(relativePos.Z) > halfDepth + 50 then
		return false
	end

	-- Check Y bounds (above origin is surface, below is mine)
	if relativePos.Y > 100 or relativePos.Y < -maxDepthY then
		return false
	end

	return true
end

--[[
	Gets all active plots (for admin/debug purposes)
]]
function PlotManager.GetAllPlots(): {[Player]: PlotData}
	return ActivePlots
end

--[[
	Gets plot count
]]
function PlotManager.GetActivePlotCount(): number
	local count = 0
	for _ in ActivePlots do
		count += 1
	end
	return count
end

--[[
	Finds which player owns a plot model
]]
function PlotManager.GetPlotOwner(plotModel: Model): Player?
	local userId = plotModel:GetAttribute("OwnerUserId")
	if userId then
		return Players:GetPlayerByUserId(userId)
	end
	return nil
end

--[[
	Finds which player owns an ore/block based on its ancestry
]]
function PlotManager.GetBlockOwner(block: BasePart): Player?
	-- Walk up ancestry to find plot model
	local current: Instance? = block.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("OwnerUserId") then
			return Players:GetPlayerByUserId(current:GetAttribute("OwnerUserId"))
		end
		current = current.Parent
	end
	return nil
end

return PlotManager
