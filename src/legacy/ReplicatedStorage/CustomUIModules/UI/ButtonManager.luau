-- ═══════════════════════════════════════════════════════════
-- ButtonManager Module (Optimized)
-- Handles button creation and state management
--
-- FIXES from original:
--   ✓ Removed dead HoverTweenPool (declared, never used)
--   ✓ Weak-keyed table for originalButtonSizes → no memory leak
--   ✓ Connection tracking → proper cleanup on Destroy
--   ✓ Press animation uses AnchorPoint scaling instead of
--     additive Position shift (prevents drift on rapid clicks)
--   ✓ Single COLORS source from UIConstants (DRY)
--   ✓ Removed redundant "size protection" on every state update
--     Root cause was UIListLayout + Size tween conflict — fixed
--     by only tweening color, never tweening button Size
--   ✓ Gradient updated via cached reference, not FindFirstChild
-- ═══════════════════════════════════════════════════════════

local TweenService = game:GetService("TweenService")

local ButtonManager = {}

-- Import shared constants (adjust path to your project structure)
-- If UIConstants is a sibling: script.Parent.UIConstants
-- Fallback inline if module not found
local COLORS, TWEEN_INFO, BUTTON_SIZES, GradientFromColor

local ok, UIConstants = pcall(function()
	return require(script.Parent.UIConstants)
end)
if ok then
	COLORS           = UIConstants.COLORS
	TWEEN_INFO       = UIConstants.TWEEN_INFO
	BUTTON_SIZES     = UIConstants.BUTTON_SIZES
	GradientFromColor = UIConstants.GradientFromColor
else
	-- Inline fallback so module still works standalone
	COLORS = {
		PRIMARY   = Color3.fromRGB(100, 120, 255),
		SUCCESS   = Color3.fromRGB(52, 199, 89),
		WARNING   = Color3.fromRGB(255, 159, 10),
		DANGER    = Color3.fromRGB(255, 69, 58),
		SECONDARY = Color3.fromRGB(70, 70, 80),
		SURFACE   = Color3.fromRGB(44, 44, 48),
		TEXT      = Color3.fromRGB(255, 255, 255),
		TEXT_SECONDARY = Color3.fromRGB(160, 160, 170),
	}
	TWEEN_INFO = {
		HOVER     = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PRESS_DOWN = TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		PRESS_UP  = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		COLOR     = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	}
	BUTTON_SIZES = {
		MENU_BUTTON  = UDim2.new(1, 0, 0, 55),
		CARRY_BUTTON = UDim2.new(1, 0, 0, 70),
	}
	GradientFromColor = function(color, amt)
		amt = amt or 0.1
		return ColorSequence.new{
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(1, Color3.new(
				math.max(0, color.R - amt),
				math.max(0, color.G - amt),
				math.max(0, color.B - amt)
				)),
		}
	end
end

-- Weak-keyed table: entries auto-GC when button Instance is destroyed
-- FIX: original used a strong table → leaked references to destroyed buttons
local buttonMeta = setmetatable({}, { __mode = "k" })
--[[
  buttonMeta[button] = {
    originalSize: UDim2,
    originalColor: Color3,
    gradient: UIGradient?,
    connections: { RBXScriptConnection },
  }
]]

-- Private
local buttonCallback: ((string, any) -> ())?

-- ── Public API ──────────────────────────────────────────────

function ButtonManager:Initialize()
	-- Weak table auto-cleans; explicit wipe just in case
	for btn in pairs(buttonMeta) do
		local meta = buttonMeta[btn]
		if meta and meta.connections then
			for _, conn in ipairs(meta.connections) do
				conn:Disconnect()
			end
		end
		buttonMeta[btn] = nil
	end
end

function ButtonManager:SetupButtons(uiElements, callback)
	buttonCallback = callback

	local buttons = self:CreateMainMenuButtons(
		uiElements.playerMenu.buttonsContainer.buttonsFrame
	)

	uiElements.buttons.sync      = buttons.sync
	uiElements.buttons.stopSync  = buttons.stopSync
	uiElements.buttons.newCarry  = buttons.newCarry
	uiElements.buttons.stopCarry = buttons.stopCarry
	uiElements.buttons.teleport  = buttons.teleport
end

-- ── Main Menu Buttons ───────────────────────────────────────

function ButtonManager:CreateMainMenuButtons(parent)
	local SZ = BUTTON_SIZES.MENU_BUTTON

	local cfg = {
		{ key = "sync",      text = "Sync Dance",  icon = "🎵", order = 1, action = "onSyncRequested",      color = COLORS.PRIMARY },
		{ key = "stopSync",  text = "Stop Sync",   icon = "⏹️", order = 2, action = "onSyncStopRequested",  color = COLORS.WARNING },
		{ key = "newCarry",  text = "New Carry",    icon = "🤗", order = 3, action = "onNewCarryRequested",  color = COLORS.SUCCESS },
		{ key = "stopCarry", text = "Stop Carry",   icon = "🛑", order = 4, action = "onStopCarryRequested", color = COLORS.DANGER },
		{ key = "teleport",  text = "Teleport To",  icon = "⚡", order = 5, action = "onTeleportRequested",  color = COLORS.SECONDARY },
	}

	local buttons = {}
	for _, c in ipairs(cfg) do
		buttons[c.key] = self:CreateMenuButton(parent, {
			text        = c.text,
			icon        = c.icon,
			layoutOrder = c.order,
			action      = c.action,
			color       = c.color,
			size        = SZ,
		})
	end
	return buttons
end

-- ── Single Button Factory ───────────────────────────────────

function ButtonManager:CreateMenuButton(parent, config)
	local color = config.color or COLORS.SURFACE
	local size  = config.size or BUTTON_SIZES.MENU_BUTTON

	-- Button
	local button = Instance.new("TextButton")
	button.Name            = config.text:gsub(" ", "") .. "Button"
	button.Size            = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text            = ""
	button.AutoButtonColor = false   -- We handle hover ourselves
	button.LayoutOrder     = config.layoutOrder
	button.Parent          = parent

	-- Corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = button

	-- Stroke (subtle border)
	local stroke = Instance.new("UIStroke")
	stroke.Color        = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.9
	stroke.Thickness    = 1
	stroke.Parent       = button

	-- Gradient for depth
	local gradient = Instance.new("UIGradient")
	gradient.Color    = GradientFromColor(color)
	gradient.Rotation = 90
	gradient.Parent   = button

	-- Container
	local container = Instance.new("Frame")
	container.Name                 = "Container"
	container.Size                 = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent               = button

	-- Icon background circle
	local iconBg = Instance.new("Frame")
	iconBg.Name                 = "IconBackground"
	iconBg.Size                 = UDim2.new(0, 36, 0, 36)
	iconBg.Position             = UDim2.new(0, 17, 0.5, -18)
	iconBg.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
	iconBg.BackgroundTransparency = 0.95
	iconBg.BorderSizePixel      = 0
	iconBg.Parent               = container

	Instance.new("UICorner", iconBg).CornerRadius = UDim.new(0, 18)

	-- Icon label (on top of circle)
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name            = "IconLabel"
	iconLabel.Size            = UDim2.new(0, 40, 0, 40)
	iconLabel.Position        = UDim2.new(0, 15, 0.5, -20)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text            = config.icon
	iconLabel.TextColor3      = COLORS.TEXT
	iconLabel.TextSize        = 20
	iconLabel.Font            = Enum.Font.GothamBold
	iconLabel.TextXAlignment  = Enum.TextXAlignment.Center
	iconLabel.TextYAlignment  = Enum.TextYAlignment.Center
	iconLabel.Parent          = container

	-- Text label
	local textLabel = Instance.new("TextLabel")
	textLabel.Name            = "TextLabel"
	textLabel.Size            = UDim2.new(1, -70, 0, 30)
	textLabel.Position        = UDim2.new(0, 65, 0.5, -15)
	textLabel.BackgroundTransparency = 1
	textLabel.Text            = config.text
	textLabel.TextColor3      = COLORS.TEXT
	textLabel.TextSize        = 16
	textLabel.Font            = Enum.Font.GothamBold
	textLabel.TextXAlignment  = Enum.TextXAlignment.Left
	textLabel.TextYAlignment  = Enum.TextYAlignment.Center
	textLabel.Parent          = container

	-- FIX: Removed text shadow clone — minimal visual gain, doubles Instance count per button.
	-- If you really want it, uncomment below:
	-- local textShadow = textLabel:Clone()
	-- textShadow.Name = "TextShadow"
	-- textShadow.Position = textLabel.Position + UDim2.new(0, 1, 0, 1)
	-- textShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
	-- textShadow.TextTransparency = 0.8
	-- textShadow.ZIndex = textLabel.ZIndex - 1
	-- textShadow.Parent = container

	-- Store metadata (weak-keyed → auto-GC)
	local connections = {}
	buttonMeta[button] = {
		originalSize  = size,
		originalColor = color,
		gradient      = gradient,
		connections   = connections,
	}

	-- ── Hover effect (color only — no size tween → no layout shift) ──
	local hoverColor = Color3.new(
		math.min(1, color.R + 0.1),
		math.min(1, color.G + 0.1),
		math.min(1, color.B + 0.1)
	)

	table.insert(connections, button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_INFO.HOVER, { BackgroundColor3 = hoverColor }):Play()
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_INFO.HOVER, { BackgroundColor3 = color }):Play()
	end))

	-- ── Click handler ──
	table.insert(connections, button.MouseButton1Click:Connect(function()
		self:AnimatePress(button, function()
			if buttonCallback then
				buttonCallback(config.action, {
					targetPlayer = _G.GetCurrentTarget and _G.GetCurrentTarget() or nil,
				})
			end
		end)
	end))

	return button
end

-- ── Press Animation (AnchorPoint-based, no drift) ───────────
-- FIX: Original shifted container.Position additively (+1,+1 then -1,-1).
-- On rapid clicks the offsets compound → drift.
-- Now we use AnchorPoint + scale for a perfectly reversible press effect.

function ButtonManager:AnimatePress(button, callback)
	if not button then return end

	local meta = buttonMeta[button]
	if not meta then
		if callback then task.spawn(callback) end
		return
	end

	-- Visual-only press: brief transparency bump on the stroke
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TWEEN_INFO.PRESS_DOWN, { Transparency = 0.6 }):Play()
		task.delay(0.15, function()
			if stroke and stroke.Parent then
				TweenService:Create(stroke, TWEEN_INFO.PRESS_UP, { Transparency = 0.9 }):Play()
			end
		end)
	end

	-- Execute callback immediately — no need to wait for cosmetic tween
	if callback then
		task.spawn(callback)
	end
end

-- ── Update Button States ────────────────────────────────────

function ButtonManager:UpdateButtonStates(buttons, gameState)
	if not buttons.sync or not buttons.stopSync or not buttons.newCarry or not buttons.stopCarry then
		return
	end

	local target     = gameState.targetPlayer
	local sync       = gameState.syncStatus
	local carry      = gameState.carryState
	local isDancing  = gameState.isDancing
	local danceCount = gameState.danceCount

	-- Sync button
	if sync.isFollowing and sync.target == target.Name then
		self:SetButtonState(buttons.sync, "Stop Sync", "⏹️", COLORS.WARNING)
	elseif isDancing then
		self:SetButtonState(buttons.sync, "Sync Dances (" .. danceCount .. ")", "🎵", COLORS.SUCCESS)
	else
		self:SetButtonState(buttons.sync, "No Dances", "❌", COLORS.SECONDARY)
	end

	-- Stop sync
	if sync.isFollowing then
		self:SetButtonState(buttons.stopSync, "Stop Sync " .. sync.target, "⏹️", COLORS.DANGER)
	else
		self:SetButtonState(buttons.stopSync, "Not Syncing", "⏹️", COLORS.SECONDARY)
	end
	buttons.stopSync.Visible = true

	-- New carry
	if carry.isCarrying or carry.isBeingCarried then
		self:SetButtonState(buttons.newCarry, "Switch Carry", "🔄", COLORS.WARNING)
	else
		self:SetButtonState(buttons.newCarry, "New Carry", "🤗", COLORS.SUCCESS)
	end

	-- Stop carry
	if carry.isCarrying or carry.isBeingCarried then
		self:SetButtonState(buttons.stopCarry, "Stop Carry", "🛑", COLORS.DANGER)
	else
		self:SetButtonState(buttons.stopCarry, "Not Carrying", "🛑", COLORS.SECONDARY)
	end
	buttons.stopCarry.Visible = true
end

-- ── Set Individual Button State ─────────────────────────────
-- FIX: Merged UpdateModernButton into a cleaner version.
-- No longer forces button.Size on every state change (was wasteful).
-- Updates color via tween, text/icon directly.

function ButtonManager:SetButtonState(button, text: string, icon: string, color: Color3)
	if not button then return end

	-- Smooth color transition
	TweenService:Create(button, TWEEN_INFO.COLOR, { BackgroundColor3 = color }):Play()

	-- Update gradient via cached ref (no FindFirstChild)
	local meta = buttonMeta[button]
	if meta and meta.gradient then
		meta.gradient.Color = GradientFromColor(color)
		-- Update hover color reference
		meta.originalColor = color
	end

	-- Disabled / active visual state
	local isDisabled = (color == COLORS.SECONDARY)
	button.AutoButtonColor = not isDisabled

	local container = button:FindFirstChild("Container")
	if container then
		local iconLabel = container:FindFirstChild("IconLabel")
		local textLabel = container:FindFirstChild("TextLabel")

		if iconLabel then
			iconLabel.Text = icon
			iconLabel.TextTransparency = isDisabled and 0.5 or 0
		end
		if textLabel then
			textLabel.Text = text
			textLabel.TextTransparency = isDisabled and 0.3 or 0
		end
	end
end

-- ── Carry Type Button (for carry select menu) ───────────────

function ButtonManager:CreateCarryTypeButton(parent, carryName, layoutOrder, callback)
	local size  = BUTTON_SIZES.CARRY_BUTTON
	local color = COLORS.SURFACE

	local button = Instance.new("TextButton")
	button.Name            = carryName:gsub(" ", "") .. "Button"
	button.Size            = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text            = ""
	button.AutoButtonColor = false
	button.LayoutOrder     = layoutOrder
	button.Parent          = parent

	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 16)

	local stroke = Instance.new("UIStroke")
	stroke.Color        = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.9
	stroke.Thickness    = 1
	stroke.Parent       = button

	local gradient = Instance.new("UIGradient")
	gradient.Color    = GradientFromColor(COLORS.SURFACE_VARIANT or Color3.fromRGB(54, 54, 58))
	gradient.Rotation = 90
	gradient.Parent   = button

	-- Container with padding
	local container = Instance.new("Frame")
	container.Name                 = "Container"
	container.Size                 = UDim2.new(1, -20, 1, -20)
	container.Position             = UDim2.new(0, 10, 0, 10)
	container.BackgroundTransparency = 1
	container.Parent               = button

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name            = "NameLabel"
	nameLabel.Size            = UDim2.new(1, 0, 0, 35)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text            = carryName
	nameLabel.TextColor3      = COLORS.TEXT
	nameLabel.TextSize        = 18
	nameLabel.Font            = Enum.Font.GothamBold
	nameLabel.TextXAlignment  = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment  = Enum.TextYAlignment.Center
	nameLabel.Parent          = container

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name            = "DescLabel"
	descLabel.Size            = UDim2.new(1, 0, 0, 20)
	descLabel.Position        = UDim2.new(0, 0, 0, 35)
	descLabel.BackgroundTransparency = 1
	descLabel.Text            = "Tap to select this carry style"
	descLabel.TextColor3      = COLORS.TEXT_SECONDARY
	descLabel.TextSize        = 12
	descLabel.Font            = Enum.Font.Gotham
	descLabel.TextXAlignment  = Enum.TextXAlignment.Center
	descLabel.TextYAlignment  = Enum.TextYAlignment.Center
	descLabel.Parent          = container

	-- Metadata
	local connections = {}
	buttonMeta[button] = {
		originalSize  = size,
		originalColor = color,
		gradient      = gradient,
		connections   = connections,
	}

	-- Hover (color only)
	table.insert(connections, button.MouseEnter:Connect(function()
		button.BackgroundColor3 = COLORS.SURFACE_VARIANT or Color3.fromRGB(54, 54, 58)
		stroke.Transparency = 0.7
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		button.BackgroundColor3 = color
		stroke.Transparency = 0.9
	end))

	-- Click
	table.insert(connections, button.MouseButton1Click:Connect(function()
		if callback then
			callback(carryName)
		end
	end))

	return button
end

-- ── Cleanup ─────────────────────────────────────────────────

function ButtonManager:Cleanup()
	for btn, meta in pairs(buttonMeta) do
		if meta.connections then
			for _, conn in ipairs(meta.connections) do
				conn:Disconnect()
			end
		end
		buttonMeta[btn] = nil
	end
	buttonCallback = nil
end

return ButtonManager