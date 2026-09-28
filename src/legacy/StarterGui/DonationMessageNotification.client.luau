--!strict
-- DonationMessageNotification.lua
-- Notification system untuk donation messages dengan Black & Gold theme

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ============================================
-- CONSTANTS
-- ============================================
local COLORS = {
	PrimaryBg   = Color3.fromHex("#1a1b1f"),
	SecondaryBg = Color3.fromHex("#252630"),
	Gold        = Color3.fromRGB(255, 180, 106),
	GoldDark    = Color3.fromRGB(255, 140, 80),
	TextPrimary = Color3.fromRGB(255, 255, 255),
}

local CONFIG = {
	Duration              = 8,
	MaxVisible            = 3,
	StartY                = 80,
	Spacing               = 12,
	AnimationSpeed        = 0.5,
	BackgroundTransparency = 0.2,
}

-- ============================================
-- TYPES
-- ============================================
type NotificationData = {
	donorName     : string,
	donorUsername : string,
	robuxAmount   : number,
	message       : string,
}

type ActiveNotification = {
	ScreenGui : ScreenGui,
	StartTime : number,
}

-- ============================================
-- STATE
-- ============================================
local activeNotifications : { ActiveNotification } = {}
local notificationQueue   : { NotificationData }   = {}

-- ============================================
-- FORWARD DECLARATIONS
-- FIX: Deklarasi local di awal agar RemoveNotification
--      bisa memanggil ProcessQueue dengan aman.
-- ============================================
local ProcessQueue : () -> ()
local ShowNotification : (data: NotificationData) -> ()

-- ============================================
-- HELPER FUNCTIONS
-- ============================================
local function CreateCorner(radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function CreateStroke(color: Color3, thickness: number, gradient: boolean?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	if gradient then
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.Gold),
			ColorSequenceKeypoint.new(1, COLORS.GoldDark),
		})
		grad.Rotation = 45
		grad.Parent = stroke
	end

	return stroke
end

local function CreatePadding(left: number, right: number, top: number, bottom: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0, left)
	padding.PaddingRight  = UDim.new(0, right)
	padding.PaddingTop    = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom)
	return padding
end

-- ============================================
-- UI CREATION
-- ============================================
local function CreateNotificationUI(data: NotificationData): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name            = "DonationNotification"
	screenGui.ResetOnSpawn    = false
	screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder    = 100
	screenGui.IgnoreGuiInset  = true

	-- Wrapper: menangani fade-in/out transparency tanpa konflik AutomaticSize
	local Wrapper = Instance.new("CanvasGroup")
	Wrapper.Name                  = "Wrapper"
	Wrapper.AnchorPoint           = Vector2.new(0.5, 0)
	Wrapper.BackgroundTransparency = 1
	Wrapper.BorderSizePixel       = 0
	Wrapper.Position              = UDim2.new(0.5, 0, 0, CONFIG.StartY)
	Wrapper.Size                  = UDim2.new(0, 420, 0, 0)
	Wrapper.AutomaticSize         = Enum.AutomaticSize.Y
	Wrapper.Parent                = screenGui

	-- Container: frame visual utama
	local Container = Instance.new("Frame")
	Container.Name                  = "Container"
	Container.AnchorPoint           = Vector2.new(0, 0)
	Container.BackgroundColor3      = COLORS.PrimaryBg
	Container.BackgroundTransparency = CONFIG.BackgroundTransparency
	Container.BorderSizePixel       = 0
	Container.Position              = UDim2.new(0, 0, 0, 0)
	Container.Size                  = UDim2.new(1, 0, 0, 0)
	Container.AutomaticSize         = Enum.AutomaticSize.Y
	Container.Parent                = Wrapper

	CreateCorner(12).Parent = Container
	CreateStroke(COLORS.Gold, 2, true).Parent = Container
	CreatePadding(16, 16, 12, 12).Parent = Container

	local Layout = Instance.new("UIListLayout")
	Layout.Padding     = UDim.new(0, 8)
	Layout.SortOrder   = Enum.SortOrder.LayoutOrder
	Layout.Parent      = Container

	-- Header
	local Header = Instance.new("Frame")
	Header.Name                  = "Header"
	Header.BackgroundTransparency = 1
	Header.Size                  = UDim2.new(1, 0, 0, 24)
	Header.LayoutOrder            = 1
	Header.Parent                 = Container

	local HeaderLayout = Instance.new("UIListLayout")
	HeaderLayout.FillDirection      = Enum.FillDirection.Horizontal
	HeaderLayout.Padding            = UDim.new(0, 8)
	HeaderLayout.VerticalAlignment  = Enum.VerticalAlignment.Center
	HeaderLayout.Parent             = Header

	local Icon = Instance.new("TextLabel")
	Icon.BackgroundTransparency = 1
	Icon.Size                   = UDim2.fromOffset(24, 24)
	Icon.Font                   = Enum.Font.GothamBold
	Icon.Text                   = "💬"
	Icon.TextColor3             = COLORS.Gold
	Icon.TextSize               = 20
	Icon.Parent                 = Header

	local HeaderText = Instance.new("TextLabel")
	HeaderText.AutomaticSize         = Enum.AutomaticSize.X
	HeaderText.BackgroundTransparency = 1
	HeaderText.Size                  = UDim2.fromOffset(0, 24)
	HeaderText.Font                  = Enum.Font.GothamBold
	HeaderText.Text                  = "New Donation Message"
	HeaderText.TextColor3            = COLORS.Gold
	HeaderText.TextSize              = 14
	HeaderText.TextXAlignment        = Enum.TextXAlignment.Left
	HeaderText.Parent                = Header

	-- Divider
	local Divider = Instance.new("Frame")
	Divider.BackgroundColor3      = COLORS.Gold
	Divider.BackgroundTransparency = 0.7
	Divider.BorderSizePixel       = 0
	Divider.Size                  = UDim2.new(1, 0, 0, 1)
	Divider.LayoutOrder           = 2
	Divider.Parent                = Container

	-- Donor Info
	local DonorInfo = Instance.new("Frame")
	DonorInfo.BackgroundTransparency = 1
	DonorInfo.Size                   = UDim2.new(1, 0, 0, 40)
	DonorInfo.LayoutOrder            = 3
	DonorInfo.Parent                 = Container

	local DonorLayout = Instance.new("UIListLayout")
	DonorLayout.Padding    = UDim.new(0, 4)
	DonorLayout.SortOrder  = Enum.SortOrder.LayoutOrder
	DonorLayout.Parent     = DonorInfo

	local DonorName = Instance.new("TextLabel")
	DonorName.BackgroundTransparency = 1
	DonorName.Size                   = UDim2.new(1, 0, 0, 20)
	DonorName.Font                   = Enum.Font.GothamBold
	DonorName.Text                   = string.format("%s (@%s)", data.donorName, data.donorUsername)
	DonorName.TextColor3             = COLORS.TextPrimary
	DonorName.TextSize               = 16
	DonorName.TextXAlignment         = Enum.TextXAlignment.Left
	DonorName.TextTruncate           = Enum.TextTruncate.AtEnd
	DonorName.LayoutOrder            = 1
	DonorName.Parent                 = DonorInfo

	local RobuxAmount = Instance.new("TextLabel")
	RobuxAmount.BackgroundTransparency = 1
	RobuxAmount.Size                   = UDim2.new(1, 0, 0, 18)
	RobuxAmount.Font                   = Enum.Font.Gotham
	RobuxAmount.Text                   = string.format("donated %s %d", utf8.char(0xE002), data.robuxAmount)
	RobuxAmount.TextColor3             = COLORS.Gold
	RobuxAmount.TextSize               = 14
	RobuxAmount.TextXAlignment         = Enum.TextXAlignment.Left
	RobuxAmount.LayoutOrder            = 2
	RobuxAmount.Parent                 = DonorInfo

	-- Message Box (hanya dibuat kalau ada pesan; donasi tanpa pesan = notif simpel)
	if data.message and data.message ~= "" then
		local MessageBox = Instance.new("Frame")
		MessageBox.BackgroundColor3      = COLORS.SecondaryBg
		MessageBox.BackgroundTransparency = CONFIG.BackgroundTransparency
		MessageBox.BorderSizePixel       = 0
		MessageBox.Size                  = UDim2.new(1, 0, 0, 0)
		MessageBox.AutomaticSize         = Enum.AutomaticSize.Y
		MessageBox.LayoutOrder           = 4
		MessageBox.Parent                = Container

		CreateCorner(8).Parent = MessageBox
		CreatePadding(12, 12, 10, 10).Parent = MessageBox

		local MessageText = Instance.new("TextLabel")
		MessageText.BackgroundTransparency = 1
		MessageText.Size                   = UDim2.new(1, 0, 0, 0)
		MessageText.AutomaticSize          = Enum.AutomaticSize.Y
		MessageText.Font                   = Enum.Font.Gotham
		MessageText.Text                   = string.format('"%s"', data.message)
		MessageText.TextColor3             = COLORS.TextPrimary
		MessageText.TextSize               = 14
		MessageText.TextWrapped            = true
		MessageText.TextXAlignment         = Enum.TextXAlignment.Left
		MessageText.TextYAlignment         = Enum.TextYAlignment.Top
		MessageText.Parent                 = MessageBox
	end

	return screenGui
end

-- ============================================
-- NOTIFICATION MANAGEMENT
-- ============================================
local function RepositionNotifications()
	local currentY = CONFIG.StartY

	for _, notif in ipairs(activeNotifications) do
		if notif.ScreenGui and notif.ScreenGui.Parent then
			local wrapper = notif.ScreenGui.Wrapper
			TweenService:Create(
				wrapper,
				TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0, currentY) }
			):Play()
			currentY += wrapper.AbsoluteSize.Y + CONFIG.Spacing
		end
	end
end

-- FIX: Hapus task.wait(0.1) yang menyebabkan jeda berbahaya.
--      Sekarang remove + ProcessQueue berjalan atomik dalam satu frame.
local function RemoveNotification(screenGui: ScreenGui)
	for i, notif in ipairs(activeNotifications) do
		if notif.ScreenGui == screenGui then
			table.remove(activeNotifications, i)
			break
		end
	end

	screenGui:Destroy()
	RepositionNotifications()

	-- Panggil ProcessQueue setelah tabel sudah diupdate,
	-- tanpa yield sehingga tidak ada race condition.
	ProcessQueue()
end

-- FIX: Implementasi ProcessQueue sebagai local function.
--      Guard condition dicek sekali di awal agar tidak bisa
--      dipanggil dua kali secara overlap.
ProcessQueue = function()
	while #activeNotifications < CONFIG.MaxVisible and #notificationQueue > 0 do
		local data = table.remove(notificationQueue, 1)
		ShowNotification(data)
	end
end

-- FIX: Implementasi ShowNotification sebagai local function.
--      Tween sekarang hanya pada Wrapper (transparency + posisi),
--      tidak menyentuh Size pada frame ber-AutomaticSize.
ShowNotification = function(data: NotificationData)
	local screenGui = CreateNotificationUI(data)

	-- Hitung posisi Y berdasarkan notifikasi yang sedang aktif
	local yOffset = CONFIG.StartY
	for _, notif in ipairs(activeNotifications) do
		if notif.ScreenGui and notif.ScreenGui.Parent then
			yOffset += notif.ScreenGui.Wrapper.AbsoluteSize.Y + CONFIG.Spacing
		end
	end

	local wrapper = screenGui.Wrapper
	wrapper.Position           = UDim2.new(0.5, 0, 0, yOffset)
	wrapper.GroupTransparency  = 1

	-- Tambahkan ke activeNotifications SEBELUM tween/delay
	-- agar tidak ada jendela waktu di mana slot tampak kosong.
	table.insert(activeNotifications, {
		ScreenGui = screenGui,
		StartTime = tick(),
	})

	-- Parent setelah masuk tabel agar tidak ada frame render yang bocor
	screenGui.Parent = player.PlayerGui

	-- Fade in: hanya transparency, tidak konflik dengan AutomaticSize
	TweenService:Create(
		wrapper,
		TweenInfo.new(CONFIG.AnimationSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	):Play()

	-- Auto-remove setelah durasi habis
	task.delay(CONFIG.Duration, function()
		if not screenGui.Parent then return end

		local fadeOut = TweenService:Create(
			wrapper,
			TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Wait()

		-- Cek lagi setelah yield, bisa jadi sudah di-destroy lebih awal
		if not screenGui.Parent then return end
		RemoveNotification(screenGui)
	end)
end

-- ============================================
-- EVENT LISTENER
-- ============================================
local RemoteFolder = ReplicatedStorage:WaitForChild("DonationMessageSystem", 10)
if not RemoteFolder then
	warn("⚠️ DonationMessageSystem folder not found!")
	return
end

local ShowMessageEvent = RemoteFolder:WaitForChild("ShowMessage", 5) :: RemoteEvent
if not ShowMessageEvent then
	warn("⚠️ ShowMessage event not found!")
	return
end

ShowMessageEvent.OnClientEvent:Connect(function(
	donorName    : string,
	donorUsername: string,
	robuxAmount  : number,
	message      : string
)
	local data: NotificationData = {
		donorName     = donorName,
		donorUsername = donorUsername,
		robuxAmount   = robuxAmount,
		message       = message,
	}

	-- FIX: Selalu lewat queue untuk menghindari jalur ganda.
	--      ProcessQueue yang mengatur apakah langsung tampil atau menunggu.
	table.insert(notificationQueue, data)
	ProcessQueue()
end)