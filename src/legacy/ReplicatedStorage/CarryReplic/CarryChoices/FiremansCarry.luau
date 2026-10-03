local carryWeldModule = require(script.Parent.Parent.CarryRemotes.CarryWeld)

local offset = Vector3.new(0.5, 1, -1) -- Adjusted position offset for fireman's carry
local rotation = CFrame.Angles(math.rad(-90), 0, math.rad(180)) -- Adjusted rotation for orientation
local animIdFirstPlayer = script.FirstAnim.Value
local animIdSecondPlayer = script.SecondAnim.Value

local carryModule = function(args: {})
	if args then
		local success, errorMessage = pcall(function()
			local firstPlayer = args["Players"]["First"]
			local secondPlayer = args["Players"]["Second"]
			local baseCFrame = CFrame.new(0.9, 0.6, 1.04)
			local calculatedCFrame = baseCFrame * CFrame.new(offset) * rotation -- Combine position and rotation
			carryWeldModule(firstPlayer, secondPlayer, nil, calculatedCFrame, animIdFirstPlayer, animIdSecondPlayer)
		end)
		if not success then end
	else
		local success, result = pcall(function()
			local baseCFrame = CFrame.new(0.9, 0.6, 1.04)
			local calculatedCFrame = baseCFrame * CFrame.new(offset) * rotation -- Combine position and rotation
			return carryWeldModule(nil, nil, nil, calculatedCFrame, animIdFirstPlayer, animIdSecondPlayer)
		end)
		if success then
			return result
		else
			return result
		end
	end
end

return carryModule
