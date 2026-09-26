-- StateManager Module (ReplicatedStorage Version)
-- Manages all state data for the CustomUI system

local Players = game:GetService("Players")

local StateManager = {}

-- Private variables
local player = Players.LocalPlayer
local allCarryStates = {} -- Track ALL players' carry states
local currentCarryState = {
	isCarrying = false,
	isBeingCarried = false,
	carrier = nil,
	carried = nil,
	carryType = nil,
	carrierTrack = nil,
	carriedTrack = nil,
	carryWeld = nil
}

-- Initialize the state manager
function StateManager:Initialize()
	-- -- -- print("📊 StateManager initialized")
end

-- Carry State Management
function StateManager:GetCarryState()
	return currentCarryState
end

function StateManager:SetCarryState(newState)
	for key, value in pairs(newState) do
		currentCarryState[key] = value
	end
end

function StateManager:ResetCarryState()
	currentCarryState = {
		isCarrying = false,
		isBeingCarried = false,
		carrier = nil,
		carried = nil,
		carryType = nil,
		carrierTrack = nil,
		carriedTrack = nil,
		carryWeld = nil
	}

	-- Clear from global tracking
	allCarryStates[player.UserId] = nil
end

function StateManager:UpdateGlobalCarryState(userId, state)
	if state then
		allCarryStates[userId] = state
	else
		allCarryStates[userId] = nil
	end
end

function StateManager:ForceWalkSpeedRestore(player)
	-- This can be called from other modules to force walkspeed restoration
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16 -- Default Roblox walkspeed
			print("🚶 StateManager: Force restored walkspeed for " .. player.Name)
		end
	end
end

function StateManager:GetGlobalCarryState(userId)
	return allCarryStates[userId]
end

function StateManager:GetAllCarryStates()
	return allCarryStates
end

function StateManager:ClearGlobalCarryState(userId)
	allCarryStates[userId] = nil
end

-- Animation track management
function StateManager:SetCarrierTrack(track)
	currentCarryState.carrierTrack = track
end

function StateManager:SetCarriedTrack(track)
	currentCarryState.carriedTrack = track
end

function StateManager:SetCarryWeld(weld)
	currentCarryState.carryWeld = weld
end

function StateManager:CleanupTracks()
	if currentCarryState.carrierTrack then
		currentCarryState.carrierTrack:Stop()
		currentCarryState.carrierTrack:Destroy()
		currentCarryState.carrierTrack = nil
	end

	if currentCarryState.carriedTrack then
		currentCarryState.carriedTrack:Stop()
		currentCarryState.carriedTrack:Destroy()
		currentCarryState.carriedTrack = nil
	end

	if currentCarryState.carryWeld then
		currentCarryState.carryWeld:Destroy()
		currentCarryState.carryWeld = nil
	end
end

-- Debug functions
function StateManager:CarryState()
	-- -- -- print("🤗 Carry System Status:")
	-- -- -- print("   Is Carrying: " .. tostring(currentCarryState.isCarrying))
	-- -- -- print("   Is Being Carried: " .. tostring(currentCarryState.isBeingCarried))
	-- -- -- print("   Carry Type: " .. (currentCarryState.carryType or "None"))
	-- -- -- print("   Carrier: " .. (currentCarryState.carrier and currentCarryState.carrier.Name or "None"))
	-- -- -- print("   Carried: " .. (currentCarryState.carried and currentCarryState.carried.Name or "None"))
end

function StateManager:AllCarryStates()
	-- -- -- print("🗂️ All Carry States:")
	for userId, state in pairs(allCarryStates) do
		local targetPlayer = Players:GetPlayerByUserId(userId)
		if targetPlayer then
			-- -- -- print("   " .. targetPlayer.Name .. ":")
			if state.isCarrying then
				-- -- -- print("      Carrying: " .. (state.carried and state.carried.Name or "Unknown"))
			end
			if state.isBeingCarried then
				-- -- -- print("      Being Carried by: " .. (state.carrier and state.carrier.Name or "Unknown"))
			end
			if state.carryType then
				-- -- -- print("      Type: " .. state.carryType)
			end
		end
	end
end

return StateManager