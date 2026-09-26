-- Custom Tweening Library for Roblox (Fixed Version)
-- Provides smooth animations between values with custom easing functions

local TweenLibrary = {}

-- Apple-style cubic easing function (smooth acceleration/deceleration)
local function appleEasing(progress)
	if progress < 0.5 then
		return progress * progress * progress * 4
	else
		return (progress - 1) * (progress * 2 - 2) * (progress * 2 - 2) + 1
	end
end

-- Linear interpolation for numbers
local function lerpNumber(startValue, endValue, progress)
	return startValue + (endValue - startValue) * progress
end

-- Linear interpolation for Color3 objects
local function lerpColor3(startColor, endColor, progress)
	local newRed = startColor.R + (endColor.R - startColor.R) * progress
	local newGreen = startColor.G + (endColor.G - startColor.G) * progress
	local newBlue = startColor.B + (endColor.B - startColor.B) * progress
	return Color3.new(newRed, newGreen, newBlue)
end

-- Linear interpolation for UDim2 objects
local function lerpUDim2(startUDim2, endUDim2, progress)
	local newXScale = startUDim2.X.Scale + (endUDim2.X.Scale - startUDim2.X.Scale) * progress
	local newXOffset = startUDim2.X.Offset + (endUDim2.X.Offset - startUDim2.X.Offset) * progress
	local newYScale = startUDim2.Y.Scale + (endUDim2.Y.Scale - startUDim2.Y.Scale) * progress
	local newYOffset = startUDim2.Y.Offset + (endUDim2.Y.Offset - startUDim2.Y.Offset) * progress

	return UDim2.new(newXScale, newXOffset, newYScale, newYOffset)
end

-- Linear interpolation for Vector3 objects
local function lerpVector3(startVector, endVector, progress)
	local newX = startVector.X + (endVector.X - startVector.X) * progress
	local newY = startVector.Y + (endVector.Y - startVector.Y) * progress
	local newZ = startVector.Z + (endVector.Z - startVector.Z) * progress
	return Vector3.new(newX, newY, newZ)
end

-- Linear interpolation for Vector2 objects
local function lerpVector2(startVector, endVector, progress)
	local newX = startVector.X + (endVector.X - startVector.X) * progress
	local newY = startVector.Y + (endVector.Y - startVector.Y) * progress
	return Vector2.new(newX, newY)
end

-- Function to determine the correct interpolation function based on value type
local function getInterpolationFunction(startValue)
	local valueType = typeof(startValue)

	if valueType == "Color3" then
		return lerpColor3
	elseif valueType == "UDim2" then
		return lerpUDim2
	elseif valueType == "Vector3" then
		return lerpVector3
	elseif valueType == "Vector2" then
		return lerpVector2
	elseif valueType == "number" then
		return lerpNumber
	else
		-- Fallback for other types (will likely error if not compatible)
		warn("TweenLibrary: Unsupported value type: " .. valueType .. ". Using number interpolation as fallback.")
		return lerpNumber
	end
end

-- Main function to create a tween animation
function TweenLibrary.create(tweenInfo)
	local duration = tweenInfo.time or 1
	local easingFunction = tweenInfo.easingStyle or appleEasing
	local startValue = tweenInfo.startValue

	-- Choose appropriate interpolation function based on value type
	local interpolationFunction = getInterpolationFunction(startValue)

	-- Start the animation coroutine
	local animationCoroutine = task.spawn(function()
		local startTime = os.clock()

		while true do
			local currentTime = os.clock()
			local rawProgress = (currentTime - startTime) / duration
			local clampedProgress = math.clamp(rawProgress, 0, 1)

			-- Stop animation when complete
			if clampedProgress >= 1 then
				break
			end

			-- Apply easing and calculate current value
			local easedProgress = easingFunction(clampedProgress)
			local currentValue = interpolationFunction(tweenInfo.startValue, tweenInfo.endValue, easedProgress)

			-- Call the callback with current value
			tweenInfo.callback(currentValue)
			task.wait()
		end

		-- Ensure final value is set exactly
		tweenInfo.callback(tweenInfo.endValue)
	end)

	-- Return cancel function
	return function()
		if animationCoroutine then
			task.cancel(animationCoroutine)
			animationCoroutine = nil
		end
	end
end

-- Predefined easing functions
TweenLibrary.Easings = {
	-- Smooth cubic easing (Apple-style)
	["Apple"] = appleEasing,

	-- Quartic in-out easing (fast start/end, slow middle)
	["QuartInOut"] = function(progress)
		local progressSquared = progress * progress
		if progress < 0.5 then
			return progressSquared * 8 * progressSquared
		else
			local offsetProgress = progress - 1
			return 1 - offsetProgress * 8 * offsetProgress * offsetProgress * offsetProgress
		end
	end,

	-- Sine in-out easing (smooth wave-like motion)
	["SineInOut"] = function(progress)
		local angle = math.pi * progress
		return -(math.cos(angle) - 1) / 2
	end,

	-- Linear easing (constant speed)
	["Linear"] = function(progress)
		return progress
	end,

	-- Quad in-out easing
	["QuadInOut"] = function(progress)
		if progress < 0.5 then
			return 2 * progress * progress
		else
			return 1 - 2 * (1 - progress) * (1 - progress)
		end
	end,

	-- Back easing (slight overshoot)
	["BackOut"] = function(progress)
		local c1 = 1.70158
		local c3 = c1 + 1
		return 1 + c3 * math.pow(progress - 1, 3) + c1 * math.pow(progress - 1, 2)
	end
}

return TweenLibrary

--[[
USAGE EXAMPLES:

local TweenLib = require(script.TweenLibrary)

-- Animate UDim2 position
local cancelTween = TweenLib.create({
	time = 2,
	startValue = UDim2.new(0, 0, 0, 0),
	endValue = UDim2.new(0.5, -150, 0.5, -200),
	easingStyle = TweenLib.Easings.Apple,
	callback = function(currentPos)
		frame.Position = currentPos
	end
})

-- Animate Color3
TweenLib.create({
	time = 1,
	startValue = Color3.fromRGB(255, 0, 0),
	endValue = Color3.fromRGB(0, 255, 0),
	easingStyle = TweenLib.Easings.SineInOut,
	callback = function(currentColor)
		part.Color = currentColor
	end
})

-- Animate Vector3
TweenLib.create({
	time = 3,
	startValue = Vector3.new(0, 0, 0),
	endValue = Vector3.new(10, 5, -10),
	easingStyle = TweenLib.Easings.BackOut,
	callback = function(currentPos)
		part.Position = currentPos
	end
})

-- Animate number (transparency, size, etc.)
TweenLib.create({
	time = 0.5,
	startValue = 0,
	endValue = 1,
	easingStyle = TweenLib.Easings.QuadInOut,
	callback = function(alpha)
		gui.BackgroundTransparency = alpha
	end
})

-- Cancel a tween
cancelTween()
--]]