local carryWeldModule = require(script.Parent.Parent.CarryRemotes.CarryWeld)
local calculatedCFrame = CFrame.new(0, 0.6, -1.2) * CFrame.fromEulerAnglesXYZ(-25, math.rad(165), 0)
local firstPlayerAnimId = script.FirstAnim.Value
local secondPlayerAnimId = script.SecondAnim.Value

local carryModule = function(params: {})

	if params then
		local success, errorMsg = pcall(function()
			local firstPlayer = params["Players"]["First"]
			local secondPlayer = params["Players"]["Second"]
			carryWeldModule(firstPlayer, secondPlayer, nil, calculatedCFrame, firstPlayerAnimId, secondPlayerAnimId)
		end)

		if not success then
			warn(errorMsg)
		end

	else
		local success, result = pcall(function()
			local dummies = carryWeldModule(nil, nil, nil, calculatedCFrame, firstPlayerAnimId, secondPlayerAnimId)
			return dummies
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
