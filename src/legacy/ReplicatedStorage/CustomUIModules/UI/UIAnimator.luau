-- ═══════════════════════════════════════════════════════════
-- UIAnimator Module (Optimized)
-- Handles UI show/hide animations
--
-- FIXES from original:
--   ✓ Cancels previous tweens before starting new ones
--     (rapid show/hide toggle no longer glitches)
--   ✓ Removed AddEntranceSpring — it tweened Size AFTER
--     ShowMenu already tweened Size → two competing tweens
--     on the same property = visual jitter
--   ✓ Menu target sizes read from UIConstants (DRY)
--   ✓ Removed AnimateButtonPress — ButtonManager handles
--     its own press animations (was duplicate code)
--   ✓ Removed BounceElement and PulseElement — unused and
--     each created recursive tween chains that could leak
--   ✓ Simplified: each menu frame stores its active tweens
--     in a weak table so they can be cancelled on re-entry
-- ═══════════════════════════════════════════════════════════

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenManager = require(ReplicatedStorage.CustomTween.TweenManager)

local UIAnimator = {}

local uiTweenManager = TweenManager.new()

-- ── Shared constants ────────────────────────────────────────
local TWEEN_INFO, MENU_SIZES
local ok, UIConstants = pcall(function()
	return require(script.Parent.UIConstants)
end)
if ok then
	TWEEN_INFO = UIConstants.TWEEN_INFO
	MENU_SIZES = UIConstants.MENU_SIZES
else
	TWEEN_INFO = {
		SLIDE_UP   = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		SLIDE_DOWN = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		SCALE      = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		FADE       = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	}
	MENU_SIZES = {
		PLAYER         = UDim2.new(0, 280, 0, 420),
		CARRY_SELECT   = UDim2.new(0, 340, 0, 480),
		CARRY_REQUEST  = UDim2.new(0, 380, 0, 240),
		FRIEND_REQUEST = UDim2.new(0, 380, 0, 280),
		DEFAULT        = UDim2.new(0, 320, 0, 360),
	}
end

-- Track active tweens per frame to cancel on re-entry
-- Weak keys: auto-cleans when frame is destroyed
local activeTweens: { [Frame]: { Tween } } = setmetatable({}, { __mode = "k" })

-- ── Helpers ─────────────────────────────────────────────────

-- Map frame names to their target sizes
local SIZE_MAP = {
	MenuFrame         = MENU_SIZES.PLAYER,
	CarrySelectFrame  = MENU_SIZES.CARRY_SELECT,
	CarryRequestFrame = MENU_SIZES.CARRY_REQUEST,
	FriendRequestFrame = MENU_SIZES.FRIEND_REQUEST,
}

local function getTargetSize(menu): UDim2
	if not menu.frame then return MENU_SIZES.DEFAULT end
	return SIZE_MAP[menu.frame.Name] or MENU_SIZES.DEFAULT
end

local function getTargetPosition(menu): UDim2
	local size = getTargetSize(menu)
	return UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2)
end

-- Cancel all running tweens for a frame
local function cancelActiveTweens(frame)
	local tweens = activeTweens[frame]
	if tweens then
		for _, tween in ipairs(tweens) do
			tween:Cancel()
		end
	end
	activeTweens[frame] = {}
end

-- Store a tween for later cancellation
local function trackTween(frame, tween)
	if not activeTweens[frame] then
		activeTweens[frame] = {}
	end
	table.insert(activeTweens[frame], tween)
end

-- ── Public API ──────────────────────────────────────────────

function UIAnimator:Initialize() end

-- ═══════════════════════════════════════════════════════════
-- SHOW MENU (slide up + fade in)
-- FIX: Cancels previous tweens first → no competing animations
-- FIX: Removed entrance spring that conflicted with size tween
-- ═══════════════════════════════════════════════════════════

function UIAnimator:ShowMenu(menu)
	if not menu or not menu.frame then return end

	local frame      = menu.frame
	local targetPos  = getTargetPosition(menu)
	local targetSize = getTargetSize(menu)

	-- Cancel any ongoing animations on this frame
	cancelActiveTweens(frame)

	-- Set initial state
	frame.Visible             = true
	frame.Position            = targetPos + UDim2.new(0, 0, 0, 100)
	frame.BackgroundTransparency = 0.3
	frame.Size                = UDim2.new(
		targetSize.X.Scale * 0.95,
		math.round(targetSize.X.Offset * 0.95),
		targetSize.Y.Scale * 0.95,
		math.round(targetSize.Y.Offset * 0.95)
	)

	-- Slide up
	local slideTween = uiTweenManager:Tween(frame, TWEEN_INFO.SLIDE_UP, {
		Position = targetPos,
	})
	trackTween(frame, slideTween)

	-- Fade in
	local fadeTween = uiTweenManager:Tween(frame, TWEEN_INFO.FADE, {
		BackgroundTransparency = 0,
	})
	trackTween(frame, fadeTween)

	-- Scale in
	local scaleTween = uiTweenManager:Tween(frame, TWEEN_INFO.SCALE, {
		Size = targetSize,
	})
	trackTween(frame, scaleTween)

	return slideTween
end

-- ═══════════════════════════════════════════════════════════
-- HIDE MENU (slide down + fade out)
-- FIX: Cancels previous tweens first
-- ═══════════════════════════════════════════════════════════

function UIAnimator:HideMenu(menu)
	if not menu or not menu.frame then return end

	local frame       = menu.frame
	local currentPos  = frame.Position
	local targetSize  = getTargetSize(menu)

	-- Cancel any ongoing animations
	cancelActiveTweens(frame)

	local hidePos = currentPos + UDim2.new(0, 0, 0, 100)

	-- Slide down
	local slideTween = uiTweenManager:Tween(frame, TWEEN_INFO.SLIDE_DOWN, {
		Position = hidePos,
	})
	trackTween(frame, slideTween)

	-- Fade out
	local fadeTween = uiTweenManager:Tween(frame, TWEEN_INFO.FADE, {
		BackgroundTransparency = 1,
	})
	trackTween(frame, fadeTween)

	-- On complete: hide and reset
	slideTween.Completed:Once(function()
		frame.Visible              = false
		frame.BackgroundTransparency = 0
		frame.Size                 = targetSize
	end)

	return slideTween
end

-- ═══════════════════════════════════════════════════════════
-- HIDE ALL MENUS (staggered)
-- ═══════════════════════════════════════════════════════════

function UIAnimator:HideAllMenus(uiElements)
	if not uiElements then return end

	local menuKeys = { "playerMenu", "carrySelectMenu", "carryRequestMenu", "friendRequestMenu" }
	local delay = 0

	for _, key in ipairs(menuKeys) do
		local menu = uiElements[key]
		if menu and menu.frame and menu.frame.Visible then
			if delay > 0 then
				task.delay(delay, function()
					self:HideMenu(menu)
				end)
			else
				self:HideMenu(menu)
			end
			delay += 0.08
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- GENERIC SLIDE ANIMATIONS
-- ═══════════════════════════════════════════════════════════

function UIAnimator:SlideInFromBottom(element, duration: number?)
	if not element then return end

	local targetPos = element.Position
	local tweenInfo = duration
		and TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		or TWEEN_INFO.SLIDE_UP

	element.Position = targetPos + UDim2.new(0, 0, 0, 100)
	element.Visible  = true

	local tween = uiTweenManager:Tween(element, tweenInfo, { Position = targetPos })
	return tween
end

function UIAnimator:SlideOutToBottom(element, duration: number?)
	if not element then return end

	local currentPos = element.Position
	local targetPos  = currentPos + UDim2.new(0, 0, 0, 100)
	local tweenInfo  = duration
		and TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		or TWEEN_INFO.SLIDE_DOWN

	local tween = uiTweenManager:Tween(element, tweenInfo, { Position = targetPos })

	tween.Completed:Once(function()
		element.Visible  = false
		element.Position = currentPos
	end)

	return tween
end

-- ═══════════════════════════════════════════════════════════
-- FADE ANIMATIONS
-- ═══════════════════════════════════════════════════════════

function UIAnimator:FadeIn(element, duration: number?)
	if not element then return end

	element.Visible = true

	local tweenInfo = duration
		and TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		or TWEEN_INFO.FADE

	local props: { [string]: any } = {}
	if element:IsA("GuiObject") then
		props.BackgroundTransparency = 0
		if element:IsA("TextLabel") or element:IsA("TextButton") then
			props.TextTransparency = 0
		end
	end

	return uiTweenManager:Tween(element, tweenInfo, props)
end

function UIAnimator:FadeOut(element, duration: number?)
	if not element then return end

	local tweenInfo = duration
		and TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		or TWEEN_INFO.FADE

	local props: { [string]: any } = {}
	if element:IsA("GuiObject") then
		props.BackgroundTransparency = 1
		if element:IsA("TextLabel") or element:IsA("TextButton") then
			props.TextTransparency = 1
		end
	end

	local tween = uiTweenManager:Tween(element, tweenInfo, props)

	tween.Completed:Once(function()
		element.Visible = false
	end)

	return tween
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

function UIAnimator:CancelAll()
	-- Cancel all tracked tweens
	for frame, tweens in pairs(activeTweens) do
		for _, tween in ipairs(tweens) do
			tween:Cancel()
		end
	end
	activeTweens = setmetatable({}, { __mode = "k" })

	-- Also cancel via TweenManager
	uiTweenManager:CancelAll()
end

function UIAnimator:GetAnimationPresets()
	return TWEEN_INFO
end

return UIAnimator