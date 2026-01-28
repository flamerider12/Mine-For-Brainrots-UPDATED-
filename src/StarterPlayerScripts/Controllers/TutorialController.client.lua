--[[
    TutorialController.lua (FIXED V2)
    Client-side tutorial UI and interaction handling
    Location: StarterPlayerScripts/Controllers/TutorialController.lua
    
    FIXES:
    - Uses CanvasGroup instead of Frame for GroupTransparency
    - Fixed final step closing properly
    - Improved state handling
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local TutorialController = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	Desktop = {
		PanelWidth = 420,
		PanelHeight = 180,
		TitleSize = 24,
		DescSize = 16,
		HintSize = 14,
		ButtonHeight = 40,
		Padding = 20,
		BottomOffset = 100,
	},
	Tablet = {
		PanelWidth = 380,
		PanelHeight = 160,
		TitleSize = 22,
		DescSize = 15,
		HintSize = 13,
		ButtonHeight = 38,
		Padding = 16,
		BottomOffset = 90,
	},
	Mobile = {
		PanelWidth = 320,
		PanelHeight = 150,
		TitleSize = 20,
		DescSize = 14,
		HintSize = 12,
		ButtonHeight = 36,
		Padding = 14,
		BottomOffset = 80,
	},

	Colors = {
		PanelBackground = Color3.fromRGB(25, 28, 38),
		PanelBorder = Color3.fromRGB(80, 90, 120),
		TitleText = Color3.fromRGB(255, 215, 100),
		DescText = Color3.fromRGB(240, 240, 240),
		HintText = Color3.fromRGB(150, 160, 180),
		ContinueButton = Color3.fromRGB(80, 180, 80),
		ContinueHover = Color3.fromRGB(100, 220, 100),
		SkipButton = Color3.fromRGB(100, 100, 120),
		SkipHover = Color3.fromRGB(120, 120, 140),
		ProgressBar = Color3.fromRGB(80, 180, 80),
		ProgressBg = Color3.fromRGB(40, 45, 55),
	},

	AnimDuration = 0.35,
	PopInScale = 0.8,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local TutorialGui: ScreenGui? = nil
local CanvasGroup: CanvasGroup? = nil
local MainPanel: Frame? = nil
local TitleLabel: TextLabel? = nil
local DescLabel: TextLabel? = nil
local HintLabel: TextLabel? = nil
local ContinueButton: TextButton? = nil
local SkipButton: TextButton? = nil
local ProgressFill: Frame? = nil
local StepCounter: TextLabel? = nil

local CurrentStep: any = nil
local CurrentStepIndex: number = 0
local TotalSteps: number = 15
local IsVisible: boolean = false
local IsAnimating: boolean = false
local IsTutorialComplete: boolean = false
local IsTutorialSkipped: boolean = false

local Remotes: {[string]: any} = {}
local DeviceType: string = "Desktop"
local CurrentConfig = CONFIG.Desktop

--------------------------------------------------------------------------------
-- DEVICE DETECTION
--------------------------------------------------------------------------------

local function DetectDeviceType(): string
	local viewportSize = workspace.CurrentCamera.ViewportSize
	if UserInputService.TouchEnabled then
		if viewportSize.X < 600 then
			return "Mobile"
		else
			return "Tablet"
		end
	end
	return "Desktop"
end

local function UpdateDeviceConfig()
	DeviceType = DetectDeviceType()
	CurrentConfig = CONFIG[DeviceType] or CONFIG.Desktop
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function CreateTutorialUI()
	TutorialGui = Instance.new("ScreenGui")
	TutorialGui.Name = "TutorialUI"
	TutorialGui.ResetOnSpawn = false
	TutorialGui.DisplayOrder = 150
	TutorialGui.Enabled = false
	TutorialGui.Parent = PlayerGui

	-- CanvasGroup for GroupTransparency animation
	CanvasGroup = Instance.new("CanvasGroup")
	CanvasGroup.Name = "TutorialCanvas"
	CanvasGroup.AnchorPoint = Vector2.new(0.5, 1)
	CanvasGroup.Position = UDim2.new(0.5, 0, 1, -CurrentConfig.BottomOffset)
	CanvasGroup.Size = UDim2.new(0, CurrentConfig.PanelWidth, 0, CurrentConfig.PanelHeight)
	CanvasGroup.BackgroundTransparency = 1
	CanvasGroup.Parent = TutorialGui

	MainPanel = Instance.new("Frame")
	MainPanel.Name = "TutorialPanel"
	MainPanel.Size = UDim2.new(1, 0, 1, 0)
	MainPanel.BackgroundColor3 = CONFIG.Colors.PanelBackground
	MainPanel.BackgroundTransparency = 0.05
	MainPanel.BorderSizePixel = 0
	MainPanel.Parent = CanvasGroup

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = MainPanel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CONFIG.Colors.PanelBorder
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = MainPanel

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -CurrentConfig.Padding * 2, 1, -CurrentConfig.Padding * 2)
	content.Position = UDim2.new(0, CurrentConfig.Padding, 0, CurrentConfig.Padding)
	content.BackgroundTransparency = 1
	content.Parent = MainPanel

	-- Progress bar
	local progressBar = Instance.new("Frame")
	progressBar.Name = "ProgressBar"
	progressBar.Size = UDim2.new(1, 0, 0, 4)
	progressBar.Position = UDim2.new(0, 0, 0, 0)
	progressBar.BackgroundColor3 = CONFIG.Colors.ProgressBg
	progressBar.BorderSizePixel = 0
	progressBar.Parent = content

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 2)
	progressCorner.Parent = progressBar

	ProgressFill = Instance.new("Frame")
	ProgressFill.Name = "Fill"
	ProgressFill.Size = UDim2.new(0, 0, 1, 0)
	ProgressFill.BackgroundColor3 = CONFIG.Colors.ProgressBar
	ProgressFill.BorderSizePixel = 0
	ProgressFill.Parent = progressBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 2)
	fillCorner.Parent = ProgressFill

	StepCounter = Instance.new("TextLabel")
	StepCounter.Name = "StepCounter"
	StepCounter.Size = UDim2.new(0, 60, 0, 20)
	StepCounter.Position = UDim2.new(1, 0, 0, 8)
	StepCounter.AnchorPoint = Vector2.new(1, 0)
	StepCounter.BackgroundTransparency = 1
	StepCounter.Font = Enum.Font.GothamMedium
	StepCounter.TextSize = 12
	StepCounter.TextColor3 = CONFIG.Colors.HintText
	StepCounter.TextXAlignment = Enum.TextXAlignment.Right
	StepCounter.Text = "1/15"
	StepCounter.Parent = content

	TitleLabel = Instance.new("TextLabel")
	TitleLabel.Name = "Title"
	TitleLabel.Size = UDim2.new(1, -70, 0, CurrentConfig.TitleSize + 8)
	TitleLabel.Position = UDim2.new(0, 0, 0, 12)
	TitleLabel.BackgroundTransparency = 1
	TitleLabel.Font = Enum.Font.GothamBlack
	TitleLabel.TextSize = CurrentConfig.TitleSize
	TitleLabel.TextColor3 = CONFIG.Colors.TitleText
	TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	TitleLabel.TextWrapped = true
	TitleLabel.Text = "Welcome!"
	TitleLabel.Parent = content

	DescLabel = Instance.new("TextLabel")
	DescLabel.Name = "Description"
	DescLabel.Size = UDim2.new(1, 0, 0, 50)
	DescLabel.Position = UDim2.new(0, 0, 0, 42)
	DescLabel.BackgroundTransparency = 1
	DescLabel.Font = Enum.Font.Gotham
	DescLabel.TextSize = CurrentConfig.DescSize
	DescLabel.TextColor3 = CONFIG.Colors.DescText
	DescLabel.TextXAlignment = Enum.TextXAlignment.Left
	DescLabel.TextYAlignment = Enum.TextYAlignment.Top
	DescLabel.TextWrapped = true
	DescLabel.Text = ""
	DescLabel.Parent = content

	HintLabel = Instance.new("TextLabel")
	HintLabel.Name = "Hint"
	HintLabel.Size = UDim2.new(1, 0, 0, 20)
	HintLabel.Position = UDim2.new(0, 0, 1, -(CurrentConfig.ButtonHeight + 28))
	HintLabel.BackgroundTransparency = 1
	HintLabel.Font = Enum.Font.GothamMedium
	HintLabel.TextSize = CurrentConfig.HintSize
	HintLabel.TextColor3 = CONFIG.Colors.HintText
	HintLabel.TextXAlignment = Enum.TextXAlignment.Left
	HintLabel.Text = ""
	HintLabel.Visible = false
	HintLabel.Parent = content

	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "Buttons"
	buttonContainer.Size = UDim2.new(1, 0, 0, CurrentConfig.ButtonHeight)
	buttonContainer.Position = UDim2.new(0, 0, 1, -CurrentConfig.ButtonHeight)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = content

	ContinueButton = Instance.new("TextButton")
	ContinueButton.Name = "Continue"
	ContinueButton.Size = UDim2.new(0.65, -5, 1, 0)
	ContinueButton.Position = UDim2.new(0, 0, 0, 0)
	ContinueButton.BackgroundColor3 = CONFIG.Colors.ContinueButton
	ContinueButton.BorderSizePixel = 0
	ContinueButton.Font = Enum.Font.GothamBold
	ContinueButton.TextSize = 16
	ContinueButton.TextColor3 = Color3.new(1, 1, 1)
	ContinueButton.Text = "CONTINUE"
	ContinueButton.AutoButtonColor = false
	ContinueButton.Parent = buttonContainer

	local continueCorner = Instance.new("UICorner")
	continueCorner.CornerRadius = UDim.new(0, 8)
	continueCorner.Parent = ContinueButton

	SkipButton = Instance.new("TextButton")
	SkipButton.Name = "Skip"
	SkipButton.Size = UDim2.new(0.35, -5, 1, 0)
	SkipButton.Position = UDim2.new(0.65, 5, 0, 0)
	SkipButton.BackgroundColor3 = CONFIG.Colors.SkipButton
	SkipButton.BorderSizePixel = 0
	SkipButton.Font = Enum.Font.GothamMedium
	SkipButton.TextSize = 14
	SkipButton.TextColor3 = Color3.new(1, 1, 1)
	SkipButton.Text = "SKIP"
	SkipButton.AutoButtonColor = false
	SkipButton.Parent = buttonContainer

	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = SkipButton

	-- Hover effects
	ContinueButton.MouseEnter:Connect(function()
		TweenService:Create(ContinueButton, TweenInfo.new(0.15), {BackgroundColor3 = CONFIG.Colors.ContinueHover}):Play()
	end)
	ContinueButton.MouseLeave:Connect(function()
		TweenService:Create(ContinueButton, TweenInfo.new(0.15), {BackgroundColor3 = CONFIG.Colors.ContinueButton}):Play()
	end)
	SkipButton.MouseEnter:Connect(function()
		TweenService:Create(SkipButton, TweenInfo.new(0.15), {BackgroundColor3 = CONFIG.Colors.SkipHover}):Play()
	end)
	SkipButton.MouseLeave:Connect(function()
		TweenService:Create(SkipButton, TweenInfo.new(0.15), {BackgroundColor3 = CONFIG.Colors.SkipButton}):Play()
	end)

	ContinueButton.MouseButton1Click:Connect(function()
		TutorialController.OnContinueClicked()
	end)
	SkipButton.MouseButton1Click:Connect(function()
		TutorialController.OnSkipClicked()
	end)

	print("[TutorialController] UI created")
end

--------------------------------------------------------------------------------
-- ANIMATIONS
--------------------------------------------------------------------------------

local function AnimateShow()
	if IsAnimating or not TutorialGui or not CanvasGroup then return end
	IsAnimating = true

	TutorialGui.Enabled = true
	CanvasGroup.Size = UDim2.new(0, CurrentConfig.PanelWidth * CONFIG.PopInScale, 0, CurrentConfig.PanelHeight * CONFIG.PopInScale)
	CanvasGroup.Position = UDim2.new(0.5, 0, 1, -CurrentConfig.BottomOffset + 50)
	CanvasGroup.GroupTransparency = 1

	local showTween = TweenService:Create(CanvasGroup, TweenInfo.new(CONFIG.AnimDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, CurrentConfig.PanelWidth, 0, CurrentConfig.PanelHeight),
		Position = UDim2.new(0.5, 0, 1, -CurrentConfig.BottomOffset),
		GroupTransparency = 0
	})

	showTween:Play()
	showTween.Completed:Connect(function()
		IsAnimating = false
		IsVisible = true
	end)
end

local function AnimateHide(callback: (() -> ())?)
	if IsAnimating or not TutorialGui or not CanvasGroup then 
		if callback then callback() end
		return 
	end
	IsAnimating = true

	local hideTween = TweenService:Create(CanvasGroup, TweenInfo.new(CONFIG.AnimDuration * 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, CurrentConfig.PanelWidth * CONFIG.PopInScale, 0, CurrentConfig.PanelHeight * CONFIG.PopInScale),
		Position = UDim2.new(0.5, 0, 1, -CurrentConfig.BottomOffset + 50),
		GroupTransparency = 1
	})

	hideTween:Play()
	hideTween.Completed:Connect(function()
		if TutorialGui then TutorialGui.Enabled = false end
		IsAnimating = false
		IsVisible = false
		if callback then callback() end
	end)
end

--------------------------------------------------------------------------------
-- UI UPDATES
--------------------------------------------------------------------------------

local function UpdateProgressBar()
	if not ProgressFill then return end
	local progress = CurrentStepIndex / TotalSteps
	TweenService:Create(ProgressFill, TweenInfo.new(0.3), {Size = UDim2.new(progress, 0, 1, 0)}):Play()
	if StepCounter then StepCounter.Text = `{CurrentStepIndex}/{TotalSteps}` end
end

local function UpdateStepDisplay(step: any)
	if not step then return end

	if TitleLabel then TitleLabel.Text = step.Title or "Tutorial" end
	if DescLabel then DescLabel.Text = step.Description or "" end

	if HintLabel then
		if step.Hint and step.Hint ~= "" then
			HintLabel.Text = "💡 " .. step.Hint
			HintLabel.Visible = true
		else
			HintLabel.Visible = false
		end
	end

	if ContinueButton then
		if step.Id == "Complete" then
			ContinueButton.Text = "FINISH!"
			ContinueButton.BackgroundColor3 = CONFIG.Colors.ContinueButton
		elseif step.AutoComplete then
			ContinueButton.Text = "WAITING..."
			ContinueButton.BackgroundColor3 = CONFIG.Colors.SkipButton
		else
			ContinueButton.Text = "CONTINUE"
			ContinueButton.BackgroundColor3 = CONFIG.Colors.ContinueButton
		end
	end

	if SkipButton then
		SkipButton.Visible = step.CanSkip ~= false and step.Id ~= "Complete"
	end

	UpdateProgressBar()
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function TutorialController.Initialize()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

	Remotes.TutorialUpdate = remotesFolder:WaitForChild("TutorialUpdate", 10)
	Remotes.TutorialAction = remotesFolder:WaitForChild("TutorialAction", 10)
	Remotes.GetTutorialState = remotesFolder:WaitForChild("GetTutorialState", 10)

	if not Remotes.TutorialUpdate then
		warn("[TutorialController] TutorialUpdate remote not found")
		return
	end

	UpdateDeviceConfig()
	CreateTutorialUI()

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateDeviceConfig)

	local updateRemote = Remotes.TutorialUpdate :: RemoteEvent
	updateRemote.OnClientEvent:Connect(function(data)
		TutorialController.OnTutorialUpdate(data)
	end)

	task.spawn(function()
		-- Wait longer to ensure DataService has loaded
		task.wait(2)
		if not Remotes.GetTutorialState then return end

		-- Try to get state, retry if data not ready
		local maxRetries = 5
		local retryDelay = 0.5

		for attempt = 1, maxRetries do
			local success, state = pcall(function()
				return (Remotes.GetTutorialState :: RemoteFunction):InvokeServer()
			end)

			if success and state then
				-- Check if data is ready
				if state.DataNotReady then
					print(`[TutorialController] Data not ready, attempt {attempt}/{maxRetries}...`)
					task.wait(retryDelay)
					continue
				end

				IsTutorialComplete = state.TutorialCompleted == true
				IsTutorialSkipped = state.TutorialSkipped == true
				CurrentStepIndex = state.CurrentStepIndex or 1
				TotalSteps = state.TotalSteps or 15

				print(`[TutorialController] Got state - Completed: {IsTutorialComplete}, Skipped: {IsTutorialSkipped}`)

				if not IsTutorialComplete and not IsTutorialSkipped and state.CurrentStep then
					CurrentStep = state.CurrentStep
					UpdateStepDisplay(CurrentStep)
					AnimateShow()
				end
				return  -- Successfully got data
			else
				print(`[TutorialController] Failed to get state, attempt {attempt}/{maxRetries}`)
				task.wait(retryDelay)
			end
		end

		print("[TutorialController] Could not get tutorial state after max retries")
	end)

	print("[TutorialController] Initialized")
end

function TutorialController.OnTutorialUpdate(data: any)
	local action = data.Action
	CurrentStepIndex = data.CurrentStepIndex or CurrentStepIndex
	TotalSteps = data.TotalSteps or TotalSteps
	IsTutorialComplete = data.TutorialCompleted == true  -- Explicit boolean check
	IsTutorialSkipped = data.TutorialSkipped == true     -- Explicit boolean check

	print(`[TutorialController] Update - Action: {action}, Complete: {IsTutorialComplete}, Skipped: {IsTutorialSkipped}`)

	if action == "TutorialStarted" or action == "TutorialResumed" then
		CurrentStep = data.CurrentStep
		if CurrentStep and not IsTutorialComplete and not IsTutorialSkipped then
			UpdateStepDisplay(CurrentStep)
			AnimateShow()
		end
	elseif action == "StepChanged" then
		CurrentStep = data.CurrentStep
		if CurrentStep then
			UpdateStepDisplay(CurrentStep)
			if not IsVisible then AnimateShow() end
		end
	elseif action == "TutorialCompleted" or action == "TutorialSkipped" then
		IsTutorialComplete = true  -- Ensure it's set
		AnimateHide()
	end
end

function TutorialController.OnContinueClicked()
	if not CurrentStep or not Remotes.TutorialAction then return end
	(Remotes.TutorialAction :: RemoteEvent):FireServer("Continue")
end

function TutorialController.OnSkipClicked()
	if not CurrentStep or not Remotes.TutorialAction then return end
	(Remotes.TutorialAction :: RemoteEvent):FireServer("Skip")
end

function TutorialController.SkipEntireTutorial()
	if Remotes.TutorialAction then
		(Remotes.TutorialAction :: RemoteEvent):FireServer("SkipAll")
	end
end

function TutorialController.ReportShopOpened()
	if Remotes.TutorialAction then
		(Remotes.TutorialAction :: RemoteEvent):FireServer("ShopOpened")
	end
end

function TutorialController.ReportSellZoneEntered()
	if Remotes.TutorialAction then
		(Remotes.TutorialAction :: RemoteEvent):FireServer("SellZoneEntered")
	end
end

function TutorialController.IsTutorialActive(): boolean
	return not IsTutorialComplete and not IsTutorialSkipped
end

return TutorialController
