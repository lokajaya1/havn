--!strict
-- DonationMessageClient.lua
-- Client handler untuk donation message prompt dengan Black & Gold theme

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ============================================
-- CONSTANTS
-- ============================================
local COLORS = {
	PrimaryBg = Color3.fromHex("#1a1b1f"),
	SecondaryBg = Color3.fromHex("#252630"),
	TertiaryBg = Color3.fromHex("#2a2b31"),
	Gold = Color3.fromRGB(255, 180, 106),
	TextPrimary = Color3.fromRGB(255, 255, 255),
	TextSecondary = Color3.fromRGB(184, 186, 193),
	TextTertiary = Color3.fromRGB(107, 108, 115),
	TextDark = Color3.fromRGB(26, 27, 31),
	Border = Color3.fromHex("#3a3b42"),
	Warning = Color3.fromRGB(255, 180, 100),
	Error = Color3.fromRGB(255, 100, 100),
}

local CONFIG = {
	MaxMessageLength = 100,
	AnimationDuration = 0.5,
	BackgroundTransparency = 0.2,
}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================
local function CreateCorner(radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function CreateStroke(color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

local function CreatePadding(left: number, right: number, top: number, bottom: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom)
	return padding
end

local function AnimatePosition(instance: GuiObject, targetPos: UDim2, callback: (() -> ())?)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(CONFIG.AnimationDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{Position = targetPos}
	)
	tween:Play()
	if callback then
		tween.Completed:Connect(callback)
	end
end

-- ============================================
-- UI CREATION
-- ============================================
local function CreateMessagePromptUI(productInfo: any)
	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "DonationMessagePrompt"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.DisplayOrder = 999
	ScreenGui.IgnoreGuiInset = true

	-- Compact container: 360x280 (dari 440x340)
	local Container = Instance.new("Frame")
	Container.Name = "Container"
	Container.AnchorPoint = Vector2.new(0.5, 0.5)
	Container.BackgroundColor3 = COLORS.PrimaryBg
	Container.BackgroundTransparency = CONFIG.BackgroundTransparency
	Container.BorderSizePixel = 0
	Container.Position = UDim2.fromScale(0.5, -0.5)
	Container.Size = UDim2.fromOffset(360, 280)
	Container.Parent = ScreenGui

	CreateCorner(12).Parent = Container
	CreateStroke(COLORS.Border, 2).Parent = Container
	CreatePadding(20, 20, 16, 16).Parent = Container

	-- Header dengan icon & title inline (compact!)
	local Header = Instance.new("Frame")
	Header.Name = "Header"
	Header.BackgroundTransparency = 1
	Header.Position = UDim2.fromOffset(0, 0)
	Header.Size = UDim2.new(1, 0, 0, 28)
	Header.Parent = Container

	local HeaderLayout = Instance.new("UIListLayout")
	HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
	HeaderLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	HeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	HeaderLayout.Padding = UDim.new(0, 8)
	HeaderLayout.Parent = Header

	local Icon = Instance.new("TextLabel")
	Icon.BackgroundTransparency = 1
	Icon.Size = UDim2.fromOffset(28, 28)
	Icon.Font = Enum.Font.GothamBold
	Icon.Text = "💬"
	Icon.TextColor3 = COLORS.Gold
	Icon.TextSize = 22
	Icon.Parent = Header

	local Title = Instance.new("TextLabel")
	Title.AutomaticSize = Enum.AutomaticSize.X
	Title.BackgroundTransparency = 1
	Title.Size = UDim2.fromOffset(0, 28)
	Title.Font = Enum.Font.GothamBold
	Title.Text = "Add a Message"
	Title.TextColor3 = COLORS.TextPrimary
	Title.TextSize = 20
	Title.TextXAlignment = Enum.TextXAlignment.Left
	Title.Parent = Header

	-- Divider
	local Divider = Instance.new("Frame")
	Divider.Name = "Divider"
	Divider.Position = UDim2.fromOffset(0, 40)
	Divider.BackgroundColor3 = COLORS.Border
	Divider.BorderSizePixel = 0
	Divider.Size = UDim2.new(1, 0, 0, 1)
	Divider.Parent = Container

	-- Description (compact)
	local Description = Instance.new("TextLabel")
	Description.Name = "Description"
	Description.BackgroundTransparency = 1
	Description.Position = UDim2.fromOffset(0, 50)
	Description.Size = UDim2.new(1, 0, 0, 32)
	Description.Font = Enum.Font.Gotham
	Description.Text = string.format(
		"Donating R$ %s • Add a message?",
		tostring(productInfo.PriceInRobux)
	)
	Description.TextColor3 = COLORS.TextSecondary
	Description.TextSize = 14
	Description.TextWrapped = true
	Description.TextXAlignment = Enum.TextXAlignment.Center
	Description.Parent = Container

	-- Message Box Container (lebih kecil: 70px dari 95px)
	local MessageBoxContainer = Instance.new("Frame")
	MessageBoxContainer.Name = "MessageBoxContainer"
	MessageBoxContainer.Position = UDim2.fromOffset(0, 90)
	MessageBoxContainer.Size = UDim2.new(1, 0, 0, 70)
	MessageBoxContainer.BackgroundColor3 = COLORS.SecondaryBg
	MessageBoxContainer.BackgroundTransparency = CONFIG.BackgroundTransparency
	MessageBoxContainer.BorderSizePixel = 0
	MessageBoxContainer.Parent = Container

	CreateCorner(8).Parent = MessageBoxContainer
	CreateStroke(COLORS.Border, 1).Parent = MessageBoxContainer

	-- TextBox dengan padding proper
	local TextBox = Instance.new("TextBox")
	TextBox.Name = "Input"
	TextBox.BackgroundTransparency = 1
	TextBox.Size = UDim2.new(1, -20, 1, -20)
	TextBox.Position = UDim2.fromOffset(10, 10)
	TextBox.Font = Enum.Font.Gotham
	TextBox.PlaceholderText = "Type your message... (optional)"
	TextBox.PlaceholderColor3 = COLORS.TextTertiary
	TextBox.Text = ""
	TextBox.TextColor3 = COLORS.TextPrimary
	TextBox.TextSize = 13
	TextBox.TextXAlignment = Enum.TextXAlignment.Left
	TextBox.TextYAlignment = Enum.TextYAlignment.Top
	TextBox.TextWrapped = true
	TextBox.MultiLine = true
	TextBox.ClearTextOnFocus = false
	TextBox.Parent = MessageBoxContainer

	-- Buttons Frame (smaller: 36px dari 44px, with margin)
	local ButtonsFrame = Instance.new("Frame")
	ButtonsFrame.Name = "Buttons"
	ButtonsFrame.BackgroundTransparency = 1
	ButtonsFrame.Position = UDim2.fromOffset(0, 192)
	ButtonsFrame.Size = UDim2.new(1, 0, 0, 36)
	ButtonsFrame.Parent = Container

	local ButtonLayout = Instance.new("UIListLayout")
	ButtonLayout.FillDirection = Enum.FillDirection.Horizontal
	ButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ButtonLayout.Padding = UDim.new(0, 10)
	ButtonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ButtonLayout.Parent = ButtonsFrame

	-- Skip Button (compact)
	local SkipButton = Instance.new("TextButton")
	SkipButton.Name = "Skip"
	SkipButton.BackgroundColor3 = COLORS.TertiaryBg
	SkipButton.BorderSizePixel = 0
	SkipButton.Size = UDim2.fromOffset(160, 36)
	SkipButton.Font = Enum.Font.GothamBold
	SkipButton.Text = "Skip"
	SkipButton.TextColor3 = COLORS.TextSecondary
	SkipButton.TextSize = 15
	SkipButton.LayoutOrder = 1
	SkipButton.Parent = ButtonsFrame

	CreateCorner(8).Parent = SkipButton
	CreateStroke(COLORS.Border, 1).Parent = SkipButton

	-- Submit Button (compact)
	local SubmitButton = Instance.new("TextButton")
	SubmitButton.Name = "Submit"
	SubmitButton.BackgroundColor3 = COLORS.Gold
	SubmitButton.BorderSizePixel = 0
	SubmitButton.Size = UDim2.fromOffset(160, 36)
	SubmitButton.Font = Enum.Font.GothamBold
	SubmitButton.Text = "Submit"
	SubmitButton.TextColor3 = COLORS.TextDark
	SubmitButton.TextSize = 15
	SubmitButton.LayoutOrder = 2
	SubmitButton.Parent = ButtonsFrame

	CreateCorner(8).Parent = SubmitButton

	return ScreenGui, TextBox, SkipButton, SubmitButton
end

-- ============================================
-- CHARACTER LIMITER (no display)
-- ============================================
local function SetupCharacterLimiter(textBox: TextBox)
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = textBox.Text
		if #text > CONFIG.MaxMessageLength then
			textBox.Text = text:sub(1, CONFIG.MaxMessageLength)
		end
	end)
end

-- ============================================
-- PROMPT HANDLER
-- ============================================
local currentPrompt = nil
local isShowing = false

local function HidePrompt()
	if not currentPrompt then return end

	AnimatePosition(currentPrompt.Container, UDim2.fromScale(0.5, -0.5), function()
		if currentPrompt then
			currentPrompt:Destroy()
			currentPrompt = nil
		end
		isShowing = false
	end)
end

local function ShowMessagePrompt(productId: number, robuxAmount: number, SubmitMessageEvent: RemoteEvent)
	if isShowing then return end
	isShowing = true

	local success, productInfo = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if not success then
		productInfo = {Name = "Product", PriceInRobux = robuxAmount}
	end

	local screenGui, textBox, skipButton, submitButton = CreateMessagePromptUI(productInfo)
	screenGui.Parent = player.PlayerGui
	currentPrompt = screenGui

	AnimatePosition(screenGui.Container, UDim2.fromScale(0.5, 0.5))
	SetupCharacterLimiter(textBox)

	-- Button hover effects
	skipButton.MouseEnter:Connect(function()
		skipButton.BackgroundColor3 = Color3.fromHex("#34353b")
	end)
	skipButton.MouseLeave:Connect(function()
		skipButton.BackgroundColor3 = COLORS.TertiaryBg
	end)

	submitButton.MouseEnter:Connect(function()
		submitButton.BackgroundTransparency = 0.2
	end)
	submitButton.MouseLeave:Connect(function()
		submitButton.BackgroundTransparency = 0
	end)

	skipButton.MouseButton1Click:Connect(function()
		HidePrompt()
		SubmitMessageEvent:FireServer(productId, nil)
	end)

	submitButton.MouseButton1Click:Connect(function()
		local message = textBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		HidePrompt()
		SubmitMessageEvent:FireServer(productId, message ~= "" and message or nil)
	end)
end

-- ============================================
-- SETUP
-- ============================================
local RemoteFolder = ReplicatedStorage:WaitForChild("DonationMessageSystem", 10)
if not RemoteFolder then
	warn("⚠️ DonationMessageSystem folder not found!")
	return
end

local PromptMessageEvent = RemoteFolder:WaitForChild("PromptMessage", 5) :: RemoteEvent
local SubmitMessageEvent = RemoteFolder:WaitForChild("SubmitMessage", 5) :: RemoteEvent

if not PromptMessageEvent or not SubmitMessageEvent then
	warn("⚠️ Remote events not found!")
	return
end

PromptMessageEvent.OnClientEvent:Connect(function(productId: number, robuxAmount: number)
	ShowMessagePrompt(productId, robuxAmount, SubmitMessageEvent)
end)
