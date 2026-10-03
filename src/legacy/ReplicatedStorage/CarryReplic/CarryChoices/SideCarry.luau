local carryWeldModule = require(script.Parent.Parent.CarryRemotes.CarryWeld)

local calculatedCFrame = CFrame.new(-0.7, -0.55, -0.35) * CFrame.Angles(math.rad(-90), 0, math.rad(0))


local firstPlayerAnimId = script.Carrier.Value
local secondPlayerAnimId = script.Carried.Value

local carryModule = function(args: {})

	if args then
		local success, errorMsg = pcall(function()
			local firstPlayer = args["Players"]["First"]
			local secondPlayer = args["Players"]["Second"]
			carryWeldModule(firstPlayer, secondPlayer, nil, calculatedCFrame, firstPlayerAnimId, secondPlayerAnimId)
		end)

		if not success then
			warn(errorMsg)
		end

	else
		local success, result = pcall(function()
			return carryWeldModule(nil, nil, nil, calculatedCFrame, firstPlayerAnimId, secondPlayerAnimId)
		end)

		if success then
			return result
		else
			warn(success)
			return result
		end
	end
end

return carryModule
