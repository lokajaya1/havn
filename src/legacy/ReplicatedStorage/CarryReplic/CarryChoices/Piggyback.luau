local carryWeldModule = require(script.Parent.Parent.CarryRemotes.CarryWeld)

local calculatedCFrame = CFrame.new(0, 1.18, 1.04)
local animIdFirstPlayer = script.FirstAnim.Value
local animIdSecondPlayer = script.SecondAnim.Value


local carryModule = function(args: {})

    if args then
        local success, errorMessage = pcall(function()
            local firstPlayer = args["Players"]["First"]
            local secondPlayer = args["Players"]["Second"]
            carryWeldModule(firstPlayer, secondPlayer, nil, calculatedCFrame, animIdFirstPlayer, animIdSecondPlayer)
        end)

        if not success then
            warn(errorMessage)
        end

    else
        local success, result = pcall(function()
            return carryWeldModule(nil, nil, nil, calculatedCFrame, animIdFirstPlayer, animIdSecondPlayer)
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
