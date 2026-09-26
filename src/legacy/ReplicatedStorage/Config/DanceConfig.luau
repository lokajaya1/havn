-- Place this in: ReplicatedStorage > Config > DanceConfig (ModuleScript)
-- OPTIMIZED FOR PURE MODULE SCRIPT APPROACH - NO ANIMATION INSTANCE DETECTION

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DanceConfig = {}

-- Load DanceAssets ModuleScript - REQUIRED
local DanceAssets = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)

-- Cache variables for performance
local _cachedDanceNames = nil
local _cachedDances = nil
local _lastCacheUpdate = 0
local CACHE_REFRESH_INTERVAL = 300 -- Refresh cache every 5 minutes (much longer since ModuleScript doesn't change)

-- Function to refresh dance cache from ModuleScript ONLY
local function refreshDanceCache()
	local currentTime = tick()
	if _cachedDances and _cachedDanceNames and (currentTime - _lastCacheUpdate) < CACHE_REFRESH_INTERVAL then
		return
	end

	local dances = {}
	local danceNames = {}

	-- Load from DanceAssets ModuleScript - NO FALLBACK
	if DanceAssets and DanceAssets.dances then
		for danceName, animationId in pairs(DanceAssets.dances) do
			dances[danceName] = animationId
			table.insert(danceNames, danceName)
		end

		table.sort(danceNames)
		_cachedDances = dances
		_cachedDanceNames = danceNames
		_lastCacheUpdate = currentTime
		return
	else
		error("❌ DanceConfig: DanceAssets ModuleScript is required! Cannot find ReplicatedStorage.Assets.Animations.Dances.DanceAssets")
	end
end

-- Dynamic property getters
function DanceConfig:getDanceNames()
	refreshDanceCache()
	return _cachedDanceNames or {}
end

function DanceConfig:getDances()
	refreshDanceCache()
	return _cachedDances or {}
end

-- Legacy properties for backward compatibility (now dynamic)
DanceConfig.__index = function(self, key)
	if key == "danceName" then
		return self:getDanceNames()
	elseif key == "dances" then
		return self:getDances()
	end
	return rawget(self, key)
end

setmetatable(DanceConfig, DanceConfig)

-- Initialize cache immediately
refreshDanceCache()

-- Enhanced movement animation detection by name
function DanceConfig:isLikelyMovementAnimation(animationName)
	if not animationName then return false end

	local lowerName = animationName:lower()

	-- Movement animation name patterns
	local movementPatterns = {
		"walk", "run", "jump", "fall", "climb", "swim", "idle", "sit", 
		"crouch", "crawl", "sprint", "jog", "step", "move", "locomotion",
		"forward", "backward", "left", "right", "up", "down", "movement"
	}

	for _, pattern in pairs(movementPatterns) do
		if lowerName:find(pattern) then
			return true
		end
	end

	return false
end

-- Function to get dance name by ID
function DanceConfig:getDanceName(animationId)
	if not animationId then return nil end

	local idNumber = tonumber(string.match(tostring(animationId), "(%d+)"))
	if not idNumber then return nil end

	local dances = self:getDances()
	for danceName, danceId in pairs(dances) do
		if danceId == idNumber then
			return danceName
		end
	end

	return nil
end

-- Function to get all dance names (alias for backward compatibility)
function DanceConfig:getAllDanceNames()
	return self:getDanceNames()
end

-- Function to get dance ID by name
function DanceConfig:getDanceId(danceName)
	local dances = self:getDances()
	return dances[danceName]
end

-- GET DANCE ANIMATION OBJECT - PURE MODULE SCRIPT APPROACH
function DanceConfig:getDanceAnimationObject(danceName)
	local dances = self:getDances()
	local animationId = dances[danceName]

	if not animationId then
		warn("❌ DanceConfig: Dance not found in ModuleScript: " .. tostring(danceName))
		return nil
	end

	-- Create Animation object from ModuleScript data
	local animationObject = Instance.new("Animation")
	animationObject.Name = danceName
	animationObject.AnimationId = "rbxassetid://" .. animationId
	return animationObject
end

-- Function to manually refresh cache (useful for real-time updates)
function DanceConfig:refreshCache()
	_lastCacheUpdate = 0
	refreshDanceCache()
end

-- Debug function to list all available animations from ModuleScript
function DanceConfig:listAnimationObjects()

	local dances = self:getDances()
	local danceCount = 0

	for danceName, animId in pairs(dances) do
		print("   ✓ " .. danceName .. " (ID: " .. animId .. ")")
		danceCount = danceCount + 1
	end
end

-- Function to get count of dances
function DanceConfig:getCounts()
	local danceNames = self:getDanceNames()

	return {
		dances = #danceNames,
		emotes = 0, -- No emotes in this pure system
		total = #danceNames
	}
end

-- Function to check if a dance exists
function DanceConfig:danceExists(danceName)
	local dances = self:getDances()
	return dances[danceName] ~= nil
end

-- Function to search dances by partial name
function DanceConfig:searchDances(searchTerm)
	if not searchTerm or searchTerm == "" then
		return self:getDanceNames()
	end

	local results = {}
	local lowerSearchTerm = searchTerm:lower()
	local danceNames = self:getDanceNames()

	for _, danceName in pairs(danceNames) do
		if danceName:lower():find(lowerSearchTerm) then
			table.insert(results, danceName)
		end
	end

	return results
end

-- Function to get random dance name
function DanceConfig:getRandomDance()
	local danceNames = self:getDanceNames()
	if #danceNames == 0 then return nil end

	math.randomseed(tick())
	return danceNames[math.random(1, #danceNames)]
end

-- Performance test function
function DanceConfig:performanceTest()

	local startTime = tick()

	-- Test 1: Get all dance names
	local names = self:getDanceNames()
	local nameTime = tick() - startTime

	-- Test 2: Get all dances
	startTime = tick()
	local dances = self:getDances()
	local danceTime = tick() - startTime

	-- Test 3: Create animation objects
	startTime = tick()
	local objectCount = 0
	for _, danceName in pairs(names) do
		local obj = self:getDanceAnimationObject(danceName)
		if obj then
			obj:Destroy() -- Clean up
			objectCount = objectCount + 1
		end
	end
	local objectTime = tick() - startTime

	return {
		nameTime = nameTime,
		danceTime = danceTime,
		objectTime = objectTime,
		averageObjectTime = objectTime / objectCount
	}
end

return DanceConfig