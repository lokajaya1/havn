-- AnimationCacheManager - FIXED FOR MODULE SCRIPT ONLY
-- Place this in: ReplicatedStorage > AnimationCache > AnimationCacheManager (ModuleScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

-- Load DanceAssets ModuleScript - REQUIRED
local DanceAssets = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)

local AnimationCacheManager = {}

-- Cache configuration
local CACHE_CONFIG = {
	BATCH_SIZE = 15,
	ID_BATCH_SIZE = 20,
	BATCH_DELAY = 0.1,
	POPULAR_DANCES = {"Fresh", "Floss", "Gangnam style", "New Dance 01", "New Dance 02"},
	MAX_PRECACHED_TRACKS = 10
}

-- Cache storage
local CacheData = {
	preloadedAnimations = {},
	animationTracks = {},
	preloadProgress = 0,
	totalAnimations = 0,
	isPreloading = false,
	preloadComplete = false,
	idsPreloaded = false
}

-- Utility function to create progress notification
local function notifyProgress(message, isComplete)
	if RunService:IsClient() then
		print(message)
		if isComplete then
			print("Animation caching completed! Dances will load instantly.")
		end
	else
		print(message)
	end
end

-- Method: Preload Animation IDs from ModuleScript
local function preloadAnimationIds()
	if not DanceAssets or not DanceAssets.dances then
		warn("DanceAssets ModuleScript not found or invalid!")
		return false, "DanceAssets ModuleScript not found"
	end

	local animationIds = {}

	-- Collect all animation IDs from ModuleScript
	for danceName, animationId in pairs(DanceAssets.dances) do
		local fullId = "rbxassetid://" .. animationId
		table.insert(animationIds, fullId)
	end

	if #animationIds == 0 then
		return false, "No animations found in DanceAssets ModuleScript"
	end

	CacheData.totalAnimations = #animationIds
	notifyProgress("Starting ID preloading from ModuleScript (" .. #animationIds .. " animations)")

	-- Preload in batches
	local batchSize = CACHE_CONFIG.ID_BATCH_SIZE
	local totalBatches = math.ceil(#animationIds / batchSize)
	local successfulBatches = 0

	for i = 1, #animationIds, batchSize do
		local batch = {}
		for j = i, math.min(i + batchSize - 1, #animationIds) do
			table.insert(batch, animationIds[j])
		end

		local batchNumber = math.ceil(i / batchSize)

		local success, err = pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)

		if success then
			successfulBatches = successfulBatches + 1

			-- Mark animations as preloaded
			for _, animId in pairs(batch) do
				CacheData.preloadedAnimations[animId] = true
			end

			CacheData.preloadProgress = math.min(i + batchSize - 1, #animationIds)

			--notifyProgress(string.format("Cached Animation IDs batch %d/%d (%d animations)", 
			--	batchNumber, totalBatches, #batch))
		else
			warn(string.format("Failed to cache Animation IDs batch %d: %s", 
				batchNumber, tostring(err)))
		end

		task.wait(CACHE_CONFIG.BATCH_DELAY)
	end

	CacheData.idsPreloaded = true
	notifyProgress(string.format("Animation IDs caching completed (%d/%d batches successful)", 
		successfulBatches, totalBatches))

	return true, successfulBatches == totalBatches
end

-- Pre-cache animation tracks for instant playback (client-side only)
local function precacheAnimationTracks(player)
	if not RunService:IsClient() or not player or not player.Character then
		return
	end

	local humanoid = player.Character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then return end

	local cachedCount = 0

	-- Pre-cache popular dances for instant playback
	for _, danceName in pairs(CACHE_CONFIG.POPULAR_DANCES) do
		if cachedCount >= CACHE_CONFIG.MAX_PRECACHED_TRACKS then
			break
		end

		-- Check if dance exists in ModuleScript
		if DanceAssets.dances[danceName] then
			-- Create Animation object from ModuleScript data
			local animation = Instance.new("Animation")
			animation.Name = danceName
			animation.AnimationId = "rbxassetid://" .. DanceAssets.dances[danceName]

			local success, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			-- Clean up Animation object
			animation:Destroy()

			if success and track then
				CacheData.animationTracks[danceName] = track
				cachedCount = cachedCount + 1
				--notifyProgress("Pre-cached animation track: " .. danceName)
			end
		end
		task.wait(0.1)
	end

	--notifyProgress(string.format("Pre-cached %d animation tracks for instant playback", cachedCount))
end

-- Main caching function - FIXED FOR MODULE SCRIPT ONLY
function AnimationCacheManager:startCaching(player)
	if CacheData.isPreloading then
		return false, "Already caching animations"
	end

	CacheData.isPreloading = true
	notifyProgress("Starting ModuleScript-based animation caching system...")

	-- Method 1: Preload Animation IDs from ModuleScript
	task.spawn(function()
		local success, result = preloadAnimationIds()
		if not success then
			warn("Animation IDs preloading failed: " .. tostring(result))
		end

		-- Mark caching as complete
		CacheData.preloadComplete = true
		CacheData.isPreloading = false
		notifyProgress("Animation caching system completed!", true)
	end)

	-- Method 2: Pre-cache tracks (client-side only)
	if RunService:IsClient() and player then
		task.spawn(function()
			-- Wait for character and initial caching
			task.wait(3)
			precacheAnimationTracks(player)
		end)
	end

	return true, "Caching started successfully"
end

-- Check if animation is preloaded
function AnimationCacheManager:isAnimationPreloaded(animationId)
	local fullId = type(animationId) == "number" and ("rbxassetid://" .. animationId) or animationId
	return CacheData.preloadedAnimations[fullId] or false
end

-- Get cached animation track
function AnimationCacheManager:getCachedAnimationTrack(danceName)
	return CacheData.animationTracks[danceName]
end

-- Get cache status
function AnimationCacheManager:getCacheStatus()
	return {
		isPreloading = CacheData.isPreloading,
		preloadComplete = CacheData.preloadComplete,
		idsPreloaded = CacheData.idsPreloaded,
		preloadProgress = CacheData.preloadProgress,
		totalAnimations = CacheData.totalAnimations,
		cachedTracksCount = 0 -- Count cached tracks
	}
end

-- Count cached tracks
function AnimationCacheManager:getCachedTracksCount()
	local count = 0
	for _ in pairs(CacheData.animationTracks) do
		count = count + 1
	end
	return count
end

-- Clear cache (for debugging)
function AnimationCacheManager:clearCache()
	-- Stop any existing tracks
	for _, track in pairs(CacheData.animationTracks) do
		if track and track.IsPlaying then
			track:Stop()
		end
	end

	-- Reset cache data
	CacheData = {
		preloadedAnimations = {},
		animationTracks = {},
		preloadProgress = 0,
		totalAnimations = 0,
		isPreloading = false,
		preloadComplete = false,
		idsPreloaded = false
	}

	notifyProgress("Animation cache cleared")
end

-- Auto-start caching on client
if RunService:IsClient() then
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer

	local function onCharacterAdded(character)
		task.wait(2) -- Wait for character to load
		AnimationCacheManager:startCaching(player)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

-- Debug functions
_G.GetAnimationCacheStatus = function()
	local status = AnimationCacheManager:getCacheStatus()
	print("=== ANIMATION CACHE STATUS ===")
	print("Is Preloading:", status.isPreloading)
	print("Preload Complete:", status.preloadComplete)
	print("IDs Preloaded:", status.idsPreloaded)
	print("Progress:", status.preloadProgress .. "/" .. status.totalAnimations)
	print("Cached Tracks:", AnimationCacheManager:getCachedTracksCount())

	-- List preloaded animations
	local count = 0
	print("\n=== PRELOADED ANIMATIONS ===")
	for animId, _ in pairs(CacheData.preloadedAnimations) do
		print("✅ " .. animId)
		count = count + 1
		if count >= 10 then
			print("... and " .. (status.totalAnimations - count) .. " more")
			break
		end
	end
end

return AnimationCacheManager