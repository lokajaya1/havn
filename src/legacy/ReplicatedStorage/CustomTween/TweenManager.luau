local TweenService = game:GetService("TweenService")

local TweenManager = {}
TweenManager.__index = TweenManager

-- Constructor: Create a new TweenManager instance
function TweenManager.new()
	local self = setmetatable({}, TweenManager)
	self._activeTweens = {}  -- Table to store active tweens by target object
	return self
end

-- Cancel and destroy all active tweens managed by this instance
function TweenManager:CancelAll()
	for targetObject, tweenInstance in pairs(self._activeTweens) do
		tweenInstance:Cancel()
		tweenInstance:Destroy()
	end
	table.clear(self._activeTweens)
end

-- Create and play a tween, automatically managing conflicts
function TweenManager:Tween(targetObject, tweenInfo, propertyTable)
	-- If there's already a tween running on this object, cancel it first
	if self._activeTweens[targetObject] then
		self._activeTweens[targetObject]:Cancel()
		self._activeTweens[targetObject]:Destroy()
		self._activeTweens[targetObject] = nil
	end

	-- Create new tween using TweenService
	local newTween = TweenService:Create(targetObject, tweenInfo, propertyTable)
	newTween:Play()

	-- Store the tween for management
	self._activeTweens[targetObject] = newTween

	-- Auto-cleanup when tween completes
	newTween.Completed:Connect(function()
		if self._activeTweens[targetObject] == newTween then
			self._activeTweens[targetObject] = nil
		end
		newTween:Destroy()
	end)

	return newTween
end

-- Destroy the TweenManager and clean up all tweens
function TweenManager:Destroy()
	self:CancelAll()
end

return TweenManager


--[[
USAGE EXAMPLES:

-- Create a new TweenManager instance
local tweenManager = TweenManager.new()

-- Create tween info
local tweenInfo = TweenInfo.new(
	1,                          -- Duration (seconds)
	Enum.EasingStyle.Quad,      -- Easing style
	Enum.EasingDirection.Out,   -- Easing direction
	0,                          -- Repeat count (0 = no repeat)
	false,                      -- Reverse
	0                           -- Delay
)

-- Animate a part's position
local part = workspace.Part
tweenManager:Tween(part, tweenInfo, {
	Position = Vector3.new(10, 0, 10),
	Transparency = 0.5
})

-- If you tween the same part again, the previous tween will be cancelled automatically
tweenManager:Tween(part, tweenInfo, {
	Position = Vector3.new(20, 0, 20),
	Size = Vector3.new(4, 4, 4)
})

-- Animate multiple different objects
local gui = script.Parent.Frame
tweenManager:Tween(gui, tweenInfo, {
	BackgroundTransparency = 1,
	Size = UDim2.new(0, 200, 0, 200)
})

-- Cancel all active tweens at once
tweenManager:CancelAll()

-- Clean up when done (cancels all tweens and destroys the manager)
tweenManager:Destroy()


-- PRACTICAL USE CASE: UI Animation Manager
local UIAnimator = TweenManager.new()

-- Function to show a GUI element
local function showGUI(guiElement)
	UIAnimator:Tween(guiElement, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		BackgroundTransparency = 0,
		Size = UDim2.new(0, 300, 0, 200),
		Position = UDim2.new(0.5, -150, 0.5, -100)
	})
end

-- Function to hide a GUI element
local function hideGUI(guiElement)
	UIAnimator:Tween(guiElement, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0)
	})
end
--]]