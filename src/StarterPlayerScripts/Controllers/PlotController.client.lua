--!strict
--[[
	PlotController.lua
	Client-side plot management and references
	Location: StarterPlayerScripts/Controllers/PlotController.lua
	
	Handles:
	- Receiving plot assignment from server
	- Storing local references to player's plot
	- Tracking current layer
	- Providing plot info to other client systems
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local PlotController = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local CurrentPlotData: PlotData? = nil
local CurrentLayerIndex: number = 1
local CurrentLayerData: GameConfig.LayerData? = nil
local IsPlotReady: boolean = false

-- Callbacks
local OnPlotReadyCallbacks: {() -> ()} = {}
local OnLayerChangedCallbacks: {(number, GameConfig.LayerData) -> ()} = {}

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------

export type PlotData = {
	PlotPosition: Vector3,
	MineOrigin: Vector3,
	GridSize: {X: number, Z: number},
	BlockSize: number,
	InitialLayer: GameConfig.LayerData,
}

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

local function NotifyPlotReady()
	IsPlotReady = true
	print("[PlotController] Notifying", #OnPlotReadyCallbacks, "ready callbacks")
	for _, callback in OnPlotReadyCallbacks do
		task.spawn(callback)
	end
	OnPlotReadyCallbacks = {}
end

local function NotifyLayerChanged(layerIndex: number, layerData: GameConfig.LayerData)
	for _, callback in OnLayerChangedCallbacks do
		task.spawn(callback, layerIndex, layerData)
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	Initializes the PlotController
]]
function PlotController.Initialize()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	-- Handle plot assignment
	local plotAssignedRemote = remotesFolder:WaitForChild("PlotAssigned") :: RemoteEvent
	plotAssignedRemote.OnClientEvent:Connect(function(plotData: PlotData)
		CurrentPlotData = plotData
		CurrentLayerIndex = 1
		CurrentLayerData = plotData.InitialLayer

		print("[PlotController] ========================================")
		print("[PlotController] Plot assigned!")
		print(`[PlotController]   Position: {plotData.PlotPosition}`)
		print(`[PlotController]   Mine Origin: {plotData.MineOrigin}`)
		print(`[PlotController]   Grid: {plotData.GridSize.X}x{plotData.GridSize.Z}`)
		print(`[PlotController]   Block Size: {plotData.BlockSize}`)
		print(`[PlotController]   Starting Layer: "{plotData.InitialLayer.LayerName}"`)
		print("[PlotController] ========================================")

		NotifyPlotReady()
	end)

	-- Handle layer changes
	local layerChangedRemote = remotesFolder:WaitForChild("LayerChanged") :: RemoteEvent
	layerChangedRemote.OnClientEvent:Connect(function(data)
		CurrentLayerIndex = data.LayerIndex
		CurrentLayerData = data.LayerData

		print(`[PlotController] Entered layer {data.LayerIndex}: "{data.LayerName}"`)

		NotifyLayerChanged(data.LayerIndex, data.LayerData)
	end)

	print("[PlotController] Initialized, waiting for plot assignment...")
end

--[[
	Returns the current plot data
]]
function PlotController.GetPlotData(): PlotData?
	return CurrentPlotData
end

--[[
	Returns the mine origin position
]]
function PlotController.GetMineOrigin(): Vector3?
	return CurrentPlotData and CurrentPlotData.MineOrigin
end

--[[
	Returns current layer index (1-7)
]]
function PlotController.GetCurrentLayerIndex(): number
	return CurrentLayerIndex
end

--[[
	Returns current layer data
]]
function PlotController.GetCurrentLayerData(): GameConfig.LayerData?
	return CurrentLayerData
end

--[[
	Checks if plot is ready
]]
function PlotController.IsReady(): boolean
	return IsPlotReady
end

--[[
	Waits until plot is ready (yields)
]]
function PlotController.WaitForReady()
	if IsPlotReady then
		return
	end

	local thread = coroutine.running()
	table.insert(OnPlotReadyCallbacks, function()
		coroutine.resume(thread)
	end)
	coroutine.yield()
end

--[[
	Registers a callback for when plot becomes ready
]]
function PlotController.OnReady(callback: () -> ())
	if IsPlotReady then
		task.spawn(callback)
	else
		table.insert(OnPlotReadyCallbacks, callback)
	end
end

--[[
	Registers a callback for layer changes
]]
function PlotController.OnLayerChanged(callback: (number, GameConfig.LayerData) -> ())
	table.insert(OnLayerChangedCallbacks, callback)
end

--[[
	Requests teleport back to plot
]]
function PlotController.TeleportToPlot()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		local remote = remotesFolder:FindFirstChild("RequestTeleportToPlot")
		if remote then
			(remote :: RemoteEvent):FireServer()
		end
	end
end

--[[
	Finds the player's plot model in workspace
]]
function PlotController.GetPlotModel(): Model?
	local plotsFolder = workspace:FindFirstChild("PlayerPlots")
	if not plotsFolder then
		return nil
	end
	return plotsFolder:FindFirstChild(`Plot_{LocalPlayer.UserId}`)
end

--[[
	Finds the Mine folder within the player's plot
]]
function PlotController.GetMineFolder(): Folder?
	local plotModel = PlotController.GetPlotModel()
	if plotModel then
		return plotModel:FindFirstChild("Mine") :: Folder?
	end
	return nil
end

--[[
	Calculates depth from Y position
]]
function PlotController.GetDepthFromY(yPosition: number): number
	if not CurrentPlotData then
		return 0
	end
	return math.max(0, CurrentPlotData.MineOrigin.Y - yPosition)
end

--[[
	Gets layer data for a specific depth
]]
function PlotController.GetLayerAtDepth(depth: number): GameConfig.LayerData
	return GameConfig.GetLayerByDepth(depth)
end

return PlotController
