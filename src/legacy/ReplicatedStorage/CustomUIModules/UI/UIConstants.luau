-- ═══════════════════════════════════════════════════════════
-- UIConstants Module
-- Single source of truth for colors, sizes, and animation presets
-- Prevents duplication across ButtonManager, MenuController, etc.
-- ═══════════════════════════════════════════════════════════

local UIConstants = {}

-- ── Colors ──────────────────────────────────────────────────
UIConstants.COLORS = {
	PRIMARY        = Color3.fromRGB(100, 120, 255),
	SUCCESS        = Color3.fromRGB(52, 199, 89),
	WARNING        = Color3.fromRGB(255, 159, 10),
	DANGER         = Color3.fromRGB(255, 69, 58),
	SECONDARY      = Color3.fromRGB(70, 70, 80),
	SURFACE        = Color3.fromRGB(44, 44, 48),
	SURFACE_VARIANT = Color3.fromRGB(54, 54, 58),
	BACKGROUND     = Color3.fromRGB(28, 28, 32),
	TEXT           = Color3.fromRGB(255, 255, 255),
	TEXT_SECONDARY = Color3.fromRGB(160, 160, 170),
	ACCENT         = Color3.fromRGB(255, 45, 85),
	SHADOW         = Color3.fromRGB(0, 0, 0),
}

-- ── Menu Sizes ──────────────────────────────────────────────
UIConstants.MENU_SIZES = {
	PLAYER       = UDim2.new(0, 280, 0, 420),
	CARRY_SELECT = UDim2.new(0, 340, 0, 480),
	CARRY_REQUEST = UDim2.new(0, 380, 0, 240),
	FRIEND_REQUEST = UDim2.new(0, 380, 0, 280),
	DEFAULT      = UDim2.new(0, 320, 0, 360),
}

-- ── Button Sizes ────────────────────────────────────────────
UIConstants.BUTTON_SIZES = {
	MENU_BUTTON  = UDim2.new(1, 0, 0, 55),
	CARRY_BUTTON = UDim2.new(1, 0, 0, 70),
	CARRY_TYPE   = UDim2.new(1, 0, 0, 80),
}

-- ── Animation Presets ───────────────────────────────────────
UIConstants.TWEEN_INFO = {
	SLIDE_UP   = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	SLIDE_DOWN = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
	SCALE      = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	FADE       = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	HOVER      = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	PRESS_DOWN = TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	PRESS_UP   = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	COLOR      = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- ── Corner Radii ────────────────────────────────────────────
UIConstants.CORNER = {
	FRAME   = UDim.new(0, 20),
	BUTTON  = UDim.new(0, 16),
	ACTION  = UDim.new(0, 15),
	CARD    = UDim.new(0, 12),
	CIRCLE  = UDim.new(0, 9999),
}

-- ── Utility ─────────────────────────────────────────────────

-- Lighten a color by a fraction (0-1)
function UIConstants.Lighten(color: Color3, amount: number): Color3
	return Color3.new(
		math.min(1, color.R + amount),
		math.min(1, color.G + amount),
		math.min(1, color.B + amount)
	)
end

-- Darken a color by a fraction (0-1)
function UIConstants.Darken(color: Color3, amount: number): Color3
	return Color3.new(
		math.max(0, color.R - amount),
		math.max(0, color.G - amount),
		math.max(0, color.B - amount)
	)
end

-- Create a gradient ColorSequence from a base color (top-to-bottom darkening)
function UIConstants.GradientFromColor(color: Color3, darkenAmount: number?): ColorSequence
	local amt = darkenAmount or 0.1
	return ColorSequence.new{
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(1, UIConstants.Darken(color, amt)),
	}
end

-- Scale a UDim2 uniformly (for press animations)
function UIConstants.ScaleUDim2(udim: UDim2, factor: number): UDim2
	return UDim2.new(
		udim.X.Scale * factor, math.round(udim.X.Offset * factor),
		udim.Y.Scale * factor, math.round(udim.Y.Offset * factor)
	)
end

return table.freeze(UIConstants)