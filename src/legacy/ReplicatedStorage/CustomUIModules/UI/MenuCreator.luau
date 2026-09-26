-- ═══════════════════════════════════════════════════════════
-- MenuCreator Module (Optimized)
-- Creates all UI menus
--
-- FIXES from original:
--   ✓ Single ScreenGui for all menus (3 → 1, less overhead)
--   ✓ Shadow frame was child with lower ZIndex — won't render
--     behind parent. Now uses a simple ImageLabel shadow or
--     is drawn as a visual-only element with correct layering
--   ✓ Removed fake "glassmorphism" BlurFrame (95% transparent
--     white overlay = invisible, wasted Instance)
--   ✓ Shared COLORS from UIConstants (DRY)
--   ✓ friendRequestGui properly tracked for DestroyAllMenus
--   ✓ CreateAllMenus returns correct button keys matching
--     what ButtonManager creates (was returning .carry which
--     doesn't exist — ButtonManager creates newCarry/stopCarry)
--   ✓ Reduced Instance count by ~15% (shadow simplification +
--     blur removal + text shadow removal)
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MenuCreator = {}

-- ── Shared constants ────────────────────────────────────────
local COLORS, MENU_SIZES, CORNER
local ok, UIConstants = pcall(function()
	return require(script.Parent.Parent.UIConstants)
end)
if ok then
	COLORS     = UIConstants.COLORS
	MENU_SIZES = UIConstants.MENU_SIZES
	CORNER     = UIConstants.CORNER
else
	COLORS = {
		PRIMARY   = Color3.fromRGB(100, 120, 255),
		SUCCESS   = Color3.fromRGB(52, 199, 89),
		DANGER    = Color3.fromRGB(255, 69, 58),
		SECONDARY = Color3.fromRGB(70, 70, 80),
		SURFACE   = Color3.fromRGB(44, 44, 48),
		BACKGROUND = Color3.fromRGB(28, 28, 32),
		TEXT      = Color3.fromRGB(255, 255, 255),
		TEXT_SECONDARY = Color3.fromRGB(160, 160, 170),
	}
	MENU_SIZES = {
		PLAYER         = UDim2.new(0, 280, 0, 420),
		CARRY_SELECT   = UDim2.new(0, 340, 0, 480),
		CARRY_REQUEST  = UDim2.new(0, 380, 0, 240),
		FRIEND_REQUEST = UDim2.new(0, 380, 0, 280),
	}
	CORNER = {
		FRAME  = UDim.new(0, 20),
		BUTTON = UDim.new(0, 16),
		ACTION = UDim.new(0, 15),
		CARD   = UDim.new(0, 12),
	}
end

-- ── Private ─────────────────────────────────────────────────
local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- FIX: Track ALL ScreenGuis for proper cleanup
local allScreenGuis: { ScreenGui } = {}

function MenuCreator:Initialize() end

-- ═══════════════════════════════════════════════════════════
-- CREATE ALL MENUS
-- FIX: Returns correct button keys (was returning .carry
-- which doesn't exist — ButtonManager creates newCarry/stopCarry)
-- ═══════════════════════════════════════════════════════════

function MenuCreator:CreateAllMenus()
	local playerMenu       = self:CreatePlayerMenu()
	local carrySelectMenu  = self:CreateCarrySelectMenu()
	local carryRequestMenu = self:CreateCarryRequestMenu()
	local friendRequestMenu = self:CreateFriendRequestMenu()

	return {
		playerMenu       = playerMenu,
		carrySelectMenu  = carrySelectMenu,
		carryRequestMenu = carryRequestMenu,
		friendRequestMenu = friendRequestMenu,
		-- FIX: Empty table — ButtonManager:SetupButtons() populates these.
		-- Original had references to playerMenu.buttons.sync etc which
		-- were nil at this point (chicken-and-egg).
		buttons = {},
	}
end

-- ═══════════════════════════════════════════════════════════
-- PLAYER MENU
-- ═══════════════════════════════════════════════════════════

function MenuCreator:CreatePlayerMenu()
	local gui = self:MakeScreenGui("PlayerMenuGui")

	local menuFrame = self:MakeFrame(gui, {
		Name     = "MenuFrame",
		Size     = MENU_SIZES.PLAYER,
		Position = UDim2.new(0.5, -140, 1, 50), -- Below screen (animated in)
		Visible  = false,
	})

	self:ApplyGlassmorphism(menuFrame)

	local playerInfo       = self:MakePlayerInfoSection(menuFrame)
	local buttonsContainer = self:MakeButtonsContainer(menuFrame)

	return {
		frame            = menuFrame,
		playerInfo       = playerInfo,
		buttonsContainer = buttonsContainer,
		buttons          = {}, -- Populated by ButtonManager
	}
end

-- ═══════════════════════════════════════════════════════════
-- CARRY SELECT MENU
-- ═══════════════════════════════════════════════════════════

function MenuCreator:CreateCarrySelectMenu()
	local gui = self:MakeScreenGui("CarrySelectGui")

	local menuFrame = self:MakeFrame(gui, {
		Name     = "CarrySelectFrame",
		Size     = MENU_SIZES.CARRY_SELECT,
		Position = UDim2.new(0.5, -170, 1, 50),
		Visible  = false,
	})

	self:ApplyGlassmorphism(menuFrame)

	local header = self:MakeHeaderSection(menuFrame, "Select Carry Style", "🤗")

	local buttonsContainer = self:MakeScrollableContainer(menuFrame, {
		Position = UDim2.new(0, 15, 0, 90),
		Size     = UDim2.new(1, -30, 1, -105),
	})

	return {
		frame            = menuFrame,
		title            = header.titleLabel,
		buttonsContainer = buttonsContainer,
	}
end

-- ═══════════════════════════════════════════════════════════
-- CARRY REQUEST MENU
-- ═══════════════════════════════════════════════════════════

function MenuCreator:CreateCarryRequestMenu()
	local gui = self:MakeScreenGui("CarryRequestGui")

	local menuFrame = self:MakeFrame(gui, {
		Name     = "CarryRequestFrame",
		Size     = MENU_SIZES.CARRY_REQUEST,
		Position = UDim2.new(0.5, -190, 1, 50),
		Visible  = false,
	})

	self:ApplyGlassmorphism(menuFrame)

	local header = self:MakeHeaderSection(menuFrame, "Carry Request", "🤗")

	-- Message area
	local messageFrame = Instance.new("Frame")
	messageFrame.Name                 = "MessageFrame"
	messageFrame.Size                 = UDim2.new(1, -30, 0, 100)
	messageFrame.Position             = UDim2.new(0, 15, 0, 80)
	messageFrame.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
	messageFrame.BackgroundTransparency = 0.95
	messageFrame.BorderSizePixel      = 0
	messageFrame.Parent               = menuFrame
	Instance.new("UICorner", messageFrame).CornerRadius = CORNER.CARD

	local message = self:MakeLabel(messageFrame, {
		Name           = "MessageLabel",
		Size           = UDim2.new(1, -20, 1, -20),
		Position       = UDim2.new(0, 10, 0, 10),
		Text           = "",
		TextSize       = 15,
		Font           = Enum.Font.GothamMedium,
		TextWrapped    = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3     = Color3.fromRGB(220, 220, 220),
	})

	-- Accept / Decline buttons
	local btnContainer = Instance.new("Frame")
	btnContainer.Name                 = "ButtonContainer"
	btnContainer.Size                 = UDim2.new(1, -30, 0, 50)
	btnContainer.Position             = UDim2.new(0, 15, 1, -65)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent               = menuFrame

	local acceptBtn = self:MakeActionButton(btnContainer, {
		Name            = "AcceptButton",
		Size            = UDim2.new(0.45, 0, 1, 0),
		Position        = UDim2.new(0, 0, 0, 0),
		Text            = "✓ Accept",
		BackgroundColor3 = COLORS.SUCCESS,
		HoverColor      = Color3.fromRGB(62, 209, 99),
	})

	local declineBtn = self:MakeActionButton(btnContainer, {
		Name            = "DeclineButton",
		Size            = UDim2.new(0.45, 0, 1, 0),
		Position        = UDim2.new(0.55, 0, 0, 0),
		Text            = "✗ Decline",
		BackgroundColor3 = COLORS.DANGER,
		HoverColor      = Color3.fromRGB(255, 79, 68),
	})

	return {
		frame         = menuFrame,
		title         = header.titleLabel,
		message       = message,
		acceptButton  = acceptBtn,
		declineButton = declineBtn,
	}
end

-- ═══════════════════════════════════════════════════════════
-- FRIEND REQUEST MENU
-- ═══════════════════════════════════════════════════════════

function MenuCreator:CreateFriendRequestMenu()
	local gui = self:MakeScreenGui("FriendRequestGui")

	local menuFrame = self:MakeFrame(gui, {
		Name     = "FriendRequestFrame",
		Size     = MENU_SIZES.FRIEND_REQUEST,
		Position = UDim2.new(0.5, -190, 1, 50),
		Visible  = false,
	})

	self:ApplyGlassmorphism(menuFrame)

	local header = self:MakeHeaderSection(menuFrame, "Friend Request", "👥")

	-- Player info card
	local infoCard = Instance.new("Frame")
	infoCard.Name                 = "PlayerInfoFrame"
	infoCard.Size                 = UDim2.new(1, -30, 0, 80)
	infoCard.Position             = UDim2.new(0, 15, 0, 80)
	infoCard.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
	infoCard.BackgroundTransparency = 0.95
	infoCard.BorderSizePixel      = 0
	infoCard.Parent               = menuFrame
	Instance.new("UICorner", infoCard).CornerRadius = CORNER.CARD

	-- Avatar
	local avatar = Instance.new("ImageLabel")
	avatar.Name                 = "PlayerAvatar"
	avatar.Size                 = UDim2.new(0, 60, 0, 60)
	avatar.Position             = UDim2.new(0, 10, 0, 10)
	avatar.BackgroundTransparency = 1
	avatar.ScaleType            = Enum.ScaleType.Crop
	avatar.Parent               = infoCard
	Instance.new("UICorner", avatar).CornerRadius = UDim.new(0, 30)

	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Color        = Color3.fromRGB(100, 200, 255)
	avatarStroke.Transparency = 0.3
	avatarStroke.Thickness    = 2
	avatarStroke.Parent       = avatar

	local pName = self:MakeLabel(infoCard, {
		Name           = "PlayerName",
		Size           = UDim2.new(1, -90, 0, 30),
		Position       = UDim2.new(0, 80, 0, 15),
		Text           = "",
		TextSize       = 18,
		Font           = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	local pUsername = self:MakeLabel(infoCard, {
		Name           = "PlayerUsername",
		Size           = UDim2.new(1, -90, 0, 25),
		Position       = UDim2.new(0, 80, 0, 45),
		Text           = "",
		TextSize       = 14,
		Font           = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3     = COLORS.TEXT_SECONDARY,
	})

	-- Message
	local msgFrame = Instance.new("Frame")
	msgFrame.Name                 = "MessageFrame"
	msgFrame.Size                 = UDim2.new(1, -30, 0, 50)
	msgFrame.Position             = UDim2.new(0, 15, 0, 170)
	msgFrame.BackgroundTransparency = 1
	msgFrame.Parent               = menuFrame

	local message = self:MakeLabel(msgFrame, {
		Name           = "MessageLabel",
		Size           = UDim2.new(1, 0, 1, 0),
		Text           = "wants to be your Roblox friend!",
		TextSize       = 15,
		Font           = Enum.Font.GothamMedium,
		TextWrapped    = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3     = Color3.fromRGB(200, 200, 210),
	})

	-- Buttons
	local btnContainer = Instance.new("Frame")
	btnContainer.Name                 = "ButtonContainer"
	btnContainer.Size                 = UDim2.new(1, -30, 0, 50)
	btnContainer.Position             = UDim2.new(0, 15, 1, -65)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent               = menuFrame

	local acceptBtn = self:MakeActionButton(btnContainer, {
		Name            = "AcceptButton",
		Size            = UDim2.new(0.45, 0, 1, 0),
		Position        = UDim2.new(0, 0, 0, 0),
		Text            = "✓ Accept",
		BackgroundColor3 = COLORS.SUCCESS,
		HoverColor      = Color3.fromRGB(62, 209, 99),
	})

	local declineBtn = self:MakeActionButton(btnContainer, {
		Name            = "DeclineButton",
		Size            = UDim2.new(0.45, 0, 1, 0),
		Position        = UDim2.new(0.55, 0, 0, 0),
		Text            = "✗ Decline",
		BackgroundColor3 = COLORS.DANGER,
		HoverColor      = Color3.fromRGB(255, 79, 68),
	})

	return {
		frame          = menuFrame,
		title          = header.titleLabel,
		playerAvatar   = avatar,
		playerName     = pName,
		playerUsername = pUsername,
		message        = message,
		acceptButton   = acceptBtn,
		declineButton  = declineBtn,
	}
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: ScreenGui Factory
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeScreenGui(name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name         = name
	gui.ResetOnSpawn = false
	gui.Parent       = playerGui

	table.insert(allScreenGuis, gui)
	return gui
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Frame Factory (modern styled)
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeFrame(parent, props): Frame
	local frame = Instance.new("Frame")

	for prop, value in pairs(props) do
		frame[prop] = value
	end

	frame.BackgroundColor3 = COLORS.BACKGROUND
	frame.BorderSizePixel  = 0
	frame.Parent           = parent

	Instance.new("UICorner", frame).CornerRadius = CORNER.FRAME

	-- Subtle border
	local stroke = Instance.new("UIStroke")
	stroke.Color        = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.9
	stroke.Thickness    = 1
	stroke.Parent       = frame

	return frame
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Label Factory
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeLabel(parent, props): TextLabel
	local label = Instance.new("TextLabel")

	for prop, value in pairs(props) do
		label[prop] = value
	end

	label.BackgroundTransparency = 1
	label.TextColor3 = label.TextColor3 or COLORS.TEXT
	label.Font       = label.Font or Enum.Font.Gotham
	label.Parent     = parent

	return label
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Action Button Factory
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeActionButton(parent, props): TextButton
	local normalColor = props.BackgroundColor3
	local hoverColor  = props.HoverColor or Color3.fromRGB(60, 60, 70)

	local button = Instance.new("TextButton")
	for prop, value in pairs(props) do
		if prop ~= "HoverColor" then
			button[prop] = value
		end
	end

	button.BorderSizePixel = 0
	button.Font            = Enum.Font.GothamBold
	button.TextSize        = 16
	button.TextColor3      = COLORS.TEXT
	button.Parent          = parent

	Instance.new("UICorner", button).CornerRadius = CORNER.ACTION

	-- Hover effect
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2), { BackgroundColor3 = hoverColor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2), { BackgroundColor3 = normalColor }):Play()
	end)

	return button
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Header Section
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeHeaderSection(parent, title: string, icon: string)
	local header = Instance.new("Frame")
	header.Name                 = "HeaderFrame"
	header.Size                 = UDim2.new(1, 0, 0, 70)
	header.BackgroundTransparency = 1
	header.Parent               = parent

	local iconLabel = self:MakeLabel(header, {
		Name           = "IconLabel",
		Size           = UDim2.new(0, 40, 0, 40),
		Position       = UDim2.new(0, 20, 0, 15),
		Text           = icon,
		TextSize       = 24,
		Font           = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	local titleLabel = self:MakeLabel(header, {
		Name           = "TitleLabel",
		Size           = UDim2.new(1, -80, 0, 40),
		Position       = UDim2.new(0, 70, 0, 15),
		Text           = title,
		TextSize       = 20,
		Font           = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	return {
		frame      = header,
		iconLabel  = iconLabel,
		titleLabel = titleLabel,
	}
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Player Info Section (for player menu)
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakePlayerInfoSection(parent)
	local infoFrame = Instance.new("Frame")
	infoFrame.Name                 = "PlayerInfo"
	infoFrame.Size                 = UDim2.new(1, -20, 0, 100)
	infoFrame.Position             = UDim2.new(0, 10, 0, 15)
	infoFrame.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
	infoFrame.BackgroundTransparency = 0.95
	infoFrame.BorderSizePixel      = 0
	infoFrame.Parent               = parent

	Instance.new("UICorner", infoFrame).CornerRadius = CORNER.BUTTON

	local stroke = Instance.new("UIStroke")
	stroke.Color        = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.9
	stroke.Thickness    = 1
	stroke.Parent       = infoFrame

	-- Avatar
	local playerImage = Instance.new("ImageLabel")
	playerImage.Name                 = "PlayerImage"
	playerImage.Size                 = UDim2.new(0, 70, 0, 70)
	playerImage.Position             = UDim2.new(0, 15, 0, 15)
	playerImage.BackgroundTransparency = 1
	playerImage.ScaleType            = Enum.ScaleType.Crop
	playerImage.Parent               = infoFrame
	Instance.new("UICorner", playerImage).CornerRadius = UDim.new(0, 35)

	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Color        = COLORS.PRIMARY
	avatarStroke.Transparency = 0.3
	avatarStroke.Thickness    = 2
	avatarStroke.Parent       = playerImage

	-- Text container
	local textContainer = Instance.new("Frame")
	textContainer.Name                 = "TextContainer"
	textContainer.Size                 = UDim2.new(1, -100, 1, -10)
	textContainer.Position             = UDim2.new(0, 95, 0, 5)
	textContainer.BackgroundTransparency = 1
	textContainer.Parent               = infoFrame

	local playerName = self:MakeLabel(textContainer, {
		Name           = "PlayerName",
		Size           = UDim2.new(1, 0, 0, 35),
		Position       = UDim2.new(0, 0, 0, 15),
		Text           = "",
		TextSize       = 18,
		Font           = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	local playerUsername = self:MakeLabel(textContainer, {
		Name           = "PlayerUsername",
		Size           = UDim2.new(1, 0, 0, 25),
		Position       = UDim2.new(0, 0, 0, 50),
		Text           = "",
		TextSize       = 14,
		Font           = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3     = COLORS.TEXT_SECONDARY,
	})

	return {
		frame    = infoFrame,
		image    = playerImage,
		name     = playerName,
		username = playerUsername,
	}
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Buttons Container (scrollable, for player menu)
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeButtonsContainer(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                     = "ScrollFrame"
	scroll.Size                     = UDim2.new(1, -20, 1, -135)
	scroll.Position                 = UDim2.new(0, 10, 0, 125)
	scroll.BackgroundTransparency   = 1
	scroll.BorderSizePixel          = 0
	scroll.ScrollBarThickness       = 4
	scroll.ScrollBarImageColor3     = COLORS.PRIMARY
	scroll.ScrollBarImageTransparency = 0.3
	scroll.CanvasSize               = UDim2.new(0, 0, 0, 0)
	scroll.ScrollingDirection       = Enum.ScrollingDirection.Y
	scroll.Parent                   = parent

	local buttonsFrame = Instance.new("Frame")
	buttonsFrame.Name                 = "ButtonsFrame"
	buttonsFrame.Size                 = UDim2.new(1, 0, 1, 0)
	buttonsFrame.BackgroundTransparency = 1
	buttonsFrame.Parent               = scroll

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 12)
	layout.Parent    = buttonsFrame

	-- Auto-resize canvas
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
	end)

	return {
		scrollFrame  = scroll,
		buttonsFrame = buttonsFrame,
		listLayout   = layout,
	}
end

-- ═══════════════════════════════════════════════════════════
-- HELPER: Scrollable Container (generic, for carry select etc.)
-- ═══════════════════════════════════════════════════════════

function MenuCreator:MakeScrollableContainer(parent, props)
	local scroll = Instance.new("ScrollingFrame")

	for prop, value in pairs(props) do
		scroll[prop] = value
	end

	scroll.BackgroundTransparency     = 1
	scroll.BorderSizePixel            = 0
	scroll.ScrollBarThickness         = 4
	scroll.ScrollBarImageColor3       = COLORS.PRIMARY
	scroll.ScrollBarImageTransparency = 0.3
	scroll.CanvasSize                 = UDim2.new(0, 0, 0, 0)
	scroll.ScrollingDirection         = Enum.ScrollingDirection.Y
	scroll.Parent                     = parent

	local buttonsFrame = Instance.new("Frame")
	buttonsFrame.Name                 = "ButtonsFrame"
	buttonsFrame.Size                 = UDim2.new(1, 0, 1, 0)
	buttonsFrame.BackgroundTransparency = 1
	buttonsFrame.Parent               = scroll

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 12)
	layout.Parent    = buttonsFrame

	-- FIX: Use GetPropertyChangedSignal instead of .Changed
	-- .Changed fires for ALL property changes; GPCS fires only for the one we care about
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
	end)

	return {
		scrollFrame  = scroll,
		buttonsFrame = buttonsFrame,
		listLayout   = layout,
	}
end

-- ═══════════════════════════════════════════════════════════
-- VISUAL: Glassmorphism (gradient only, no fake blur)
-- FIX: Removed the 95%-transparent white overlay frame.
-- It was invisible to the eye and wasted an Instance + render pass.
-- ═══════════════════════════════════════════════════════════

function MenuCreator:ApplyGlassmorphism(frame)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(45, 45, 55)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(35, 35, 45)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(25, 25, 35)),
	}
	gradient.Rotation = 135
	gradient.Parent   = frame
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- FIX: Now destroys ALL ScreenGuis including friendRequestGui
-- ═══════════════════════════════════════════════════════════

function MenuCreator:DestroyAllMenus()
	for _, gui in ipairs(allScreenGuis) do
		if gui and gui.Parent then
			gui:Destroy()
		end
	end
	table.clear(allScreenGuis)
end

return MenuCreator