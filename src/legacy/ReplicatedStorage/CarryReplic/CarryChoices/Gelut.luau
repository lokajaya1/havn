local carryWeldModule = require(script.Parent.Parent.CarryRemotes.CarryWeld)

local calculatedCFrame = CFrame.new(0, 1.5, -1.7) * CFrame.fromEulerAnglesXYZ(-25, math.rad(175), 0)
local animIdFirstPlayer = script.FirstAnim.Value
local animIdSecondPlayer = script.SecondAnim.Value

local carryModule = function(params: {})

	if params then
		local success, errMessage = pcall(function()
			local firstPlayer = params["Players"]["First"]
			local secondPlayer = params["Players"]["Second"]
			carryWeldModule(firstPlayer, secondPlayer, nil, calculatedCFrame, animIdFirstPlayer, animIdSecondPlayer)
		end)

		if not success then
			warn(errMessage)
		end

	else
		local success, result = pcall(function()
			local dummyCarry = carryWeldModule(nil, nil, nil, calculatedCFrame, animIdFirstPlayer, animIdSecondPlayer)
			return dummyCarry
		end)

		if success then
			return result
		else
			warn(success, result)
			return result
		end
	end
end

return carryModule
