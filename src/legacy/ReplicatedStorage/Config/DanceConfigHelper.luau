-- DanceConfigHelper.lua - FIXED FOR MODULE SCRIPT ONLY
-- Place this in ReplicatedStorage.Config (next to DanceConfig)
-- Helper functions for smooth dance integration with pure ModuleScript approach

local DanceConfigHelper = {}

-- Cache untuk performance
local nameToIdCache = {}
local idToNameCache = {}
local initialized = false

-- Initialize caches
local function initializeCaches()
	if initialized then return end

	local DanceConfig = require(script.Parent.DanceConfig)
	local dances = DanceConfig:getDances() -- Uses ModuleScript only

	-- Build dance name to ID mapping
	for danceName, animId in pairs(dances) do
		nameToIdCache[string.lower(danceName)] = animId
		idToNameCache[tostring(animId)] = danceName
	end

	initialized = true
	print("✅ DanceConfigHelper initialized with " .. #DanceConfig:getDanceNames() .. " animations from ModuleScript")
end

-- Get animation ID from dance name (case-insensitive)
function DanceConfigHelper.getAnimationId(name)
	initializeCaches()

	if not name or name == "" then
		return nil
	end

	return nameToIdCache[string.lower(name)]
end

-- Get dance name from animation ID
function DanceConfigHelper.getAnimationName(animId)
	initializeCaches()

	if not animId then
		return nil
	end

	-- Handle both number and string IDs, including format "rbxassetid://123456"
	local idStr = tostring(animId):match("(%d+)")
	if idStr then
		return idToNameCache[idStr]
	end

	return nil
end

-- Check if animation ID is a dance - FIXED FOR MODULE SCRIPT ONLY
function DanceConfigHelper.isDance(nameOrId)
	initializeCaches()

	local DanceConfig = require(script.Parent.DanceConfig)
	local dances = DanceConfig:getDances() -- Gets from ModuleScript

	-- If it's a name, check directly
	if type(nameOrId) == "string" and not tonumber(nameOrId) then
		return dances[nameOrId] ~= nil
	end

	-- If it's an ID, convert and check
	local animId = nameOrId
	if type(nameOrId) == "string" then
		animId = tonumber(nameOrId:match("(%d+)"))
	end

	-- Check if ID exists in dances
	for _, danceId in pairs(dances) do
		if danceId == animId then
			return true
		end
	end

	return false
end

-- Check if animation ID is an emote - DISABLED FOR MODULE SCRIPT ONLY SYSTEM
function DanceConfigHelper.isEmote(nameOrId)
	-- Since we're using pure ModuleScript approach with dances only, return false
	return false
end

-- Get all dance names from ModuleScript
function DanceConfigHelper.getAllDanceNames()
	local DanceConfig = require(script.Parent.DanceConfig)
	return DanceConfig:getDanceNames() -- Gets from ModuleScript
end

-- Get all emote names - DISABLED FOR MODULE SCRIPT ONLY SYSTEM
function DanceConfigHelper.getAllEmoteNames()
	-- Since we're using pure ModuleScript approach with dances only, return empty table
	return {}
end

-- Get animation object from dance name - PURE MODULE SCRIPT APPROACH
function DanceConfigHelper.getAnimationObject(name)
	local DanceConfig = require(script.Parent.DanceConfig)

	-- Only try dance (no emotes in pure ModuleScript system)
	return DanceConfig:getDanceAnimationObject(name)
end

-- Search dances by partial name
function DanceConfigHelper.searchDances(query, maxResults)
	if not query or query == "" then
		return DanceConfigHelper.getAllDanceNames()
	end

	maxResults = maxResults or 50
	local results = {}
	local query_lower = string.lower(query)
	local danceNames = DanceConfigHelper.getAllDanceNames()

	for _, danceName in ipairs(danceNames) do
		if string.find(string.lower(danceName), query_lower, 1, true) then
			table.insert(results, danceName)

			if #results >= maxResults then
				break
			end
		end
	end

	table.sort(results)
	return results
end

-- Validate animation for smooth playback
function DanceConfigHelper.validateAnimation(nameOrId)
	local animId = nameOrId

	-- Convert name to ID if needed
	if type(nameOrId) == "string" and not tonumber(nameOrId) then
		animId = DanceConfigHelper.getAnimationId(nameOrId)
	end

	if not animId then
		return false, "Animation not found"
	end

	-- Check if it's a valid Roblox asset ID
	local idNumber = tonumber(tostring(animId):match("(%d+)"))
	if not idNumber or idNumber <= 0 then
		return false, "Invalid animation ID"
	end

	return true, "Animation valid"
end

-- Get random dance name (for shuffle feature)
function DanceConfigHelper.getRandomDance()
	local danceNames = DanceConfigHelper.getAllDanceNames()
	if #danceNames == 0 then return nil end

	math.randomseed(tick())
	return danceNames[math.random(1, #danceNames)]
end

-- Get random emote name - DISABLED FOR MODULE SCRIPT ONLY SYSTEM
function DanceConfigHelper.getRandomEmote()
	-- Since we're using pure ModuleScript approach with dances only, return nil
	return nil
end

-- Wrapper functions for compatibility with existing DanceConfig methods
function DanceConfigHelper.getDanceAnimationObject(danceName)
	local DanceConfig = require(script.Parent.DanceConfig)
	return DanceConfig:getDanceAnimationObject(danceName)
end

-- Get emote animation object - DISABLED FOR MODULE SCRIPT ONLY SYSTEM
function DanceConfigHelper.getEmoteAnimationObject(emoteName)
	-- Since we're using pure ModuleScript approach with dances only, return nil
	return nil
end

-- Get dance ID by name
function DanceConfigHelper.getDanceId(danceName)
	local DanceConfig = require(script.Parent.DanceConfig)
	local dances = DanceConfig:getDances()
	return dances[danceName]
end

-- Get emote ID by name - DISABLED FOR MODULE SCRIPT ONLY SYSTEM  
function DanceConfigHelper.getEmoteId(emoteName)
	-- Since we're using pure ModuleScript approach with dances only, return nil
	return nil
end

-- Check if animation should be synced (simplified version for SmoothDanceManager)
function DanceConfigHelper.shouldSyncAnimation(animationTrack)
	if not animationTrack or not animationTrack.Animation then
		return false
	end

	local animationId = animationTrack.Animation.AnimationId

	-- Quick check - if it's a dance from our ModuleScript, sync it
	if DanceConfigHelper.getAnimationName(animationId) then
		return true
	end

	-- Check animation priority - avoid movement animations
	local priority = animationTrack.Priority

	-- NEVER sync Movement or Core priority animations
	if priority == Enum.AnimationPriority.Movement or 
		priority == Enum.AnimationPriority.Core then
		return false
	end

	-- For Action priorities, check if it's likely a dance
	if priority == Enum.AnimationPriority.Action or 
		priority == Enum.AnimationPriority.Action2 or
		priority == Enum.AnimationPriority.Action3 or
		priority == Enum.AnimationPriority.Action4 then

		-- Check animation length (very short animations are likely movements)
		if animationTrack.Length and animationTrack.Length < 1.0 then
			return false
		end

		-- If it has reasonable length and Action priority, likely syncable
		return true
	end

	-- Conservative approach for other priorities
	return false
end

-- Get animation info (for debugging smooth dance manager) - FIXED
function DanceConfigHelper.getAnimationInfo(nameOrId)
	local animId = nameOrId
	local animName = nameOrId

	-- If input is name, get ID
	if type(nameOrId) == "string" and not tonumber(nameOrId) then
		animId = DanceConfigHelper.getAnimationId(nameOrId)
	else
		-- If input is ID, get name
		animName = DanceConfigHelper.getAnimationName(nameOrId)
	end

	return {
		name = animName,
		id = animId,
		isDance = DanceConfigHelper.isDance(nameOrId),
		isEmote = false, -- Always false in pure ModuleScript system
		animationObject = DanceConfigHelper.getAnimationObject(animName)
	}
end

-- Debug function
function DanceConfigHelper.debug()
	initializeCaches()

	local DanceConfig = require(script.Parent.DanceConfig)
	local danceNames = DanceConfig:getDanceNames()

	print("=== DANCE CONFIG HELPER DEBUG ===")
	print("Initialized:", initialized)
	print("Total dances in ModuleScript:", #danceNames)
	print("Total cached mappings:", #danceNames)

	-- Test some mappings
	print("\nSample dance mappings:")
	for i = 1, math.min(5, #danceNames) do
		local danceName = danceNames[i]
		local animId = DanceConfigHelper.getDanceId(danceName)
		print("  " .. danceName .. " -> " .. (animId or "NOT FOUND"))
	end
end

-- Clear caches (for testing)
function DanceConfigHelper.clearCache()
	nameToIdCache = {}
	idToNameCache = {}
	initialized = false
	print("🧹 DanceConfigHelper cache cleared")
end

return DanceConfigHelper