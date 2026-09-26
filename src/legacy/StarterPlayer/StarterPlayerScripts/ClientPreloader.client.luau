-- ClientPreloader.lua
-- Place this in: StarterPlayer > StarterPlayerScripts
-- Aggressive client-side preloading for instant dance access

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Load DanceAssets ModuleScript
local DanceAssets = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)
local DanceConfig = require(ReplicatedStorage.Config.DanceConfig)

local ClientPreloader = {}

-- Preloading state
local preloadingState = {
	idsPreloaded = false,
	tracksPreloaded = false,
	totalDances = 0,
	preloadedCount = 0,	
	ready = false
}

-- Animation track cache for instant access
local animationTrackCache = {}

local function notifyPreloadProgress(message, isComplete)
	--print("[CLIENT_PRELOADER] " .. message)
	if isComplete then
		print("🎉 Client: All dances preloaded! Ready for instant dancing!")
	end
end

-- PHASE 2: Preload animation tracks for instant access
local function preloadAnimationTracks(animationObjects)
	-- Wait for character and animator
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator")

	notifyPreloadProgress("Starting aggressive track preloading...")

	-- Preload tracks in smaller batches to avoid performance issues
	local trackBatchSize = 10
	local completedTracks = 0
	local totalObjects = #animationObjects

	for i = 1, totalObjects, trackBatchSize do
		local batchEnd = math.min(i + trackBatchSize - 1, totalObjects)

		task.spawn(function()
			for j = i, batchEnd do
				local animationObject = animationObjects[j]

				task.spawn(function()
					local success, track = pcall(function()
						return animator:LoadAnimation(animationObject)
					end)

					if success and track then
						-- Configure track for instant use
						track.Priority = Enum.AnimationPriority.Action
						track.Looped = true

						-- Store in cache
						animationTrackCache[animationObject.Name] = track

						completedTracks = completedTracks + 1
						preloadingState.preloadedCount = completedTracks

						-- Progress notification every 10 tracks
						if completedTracks % 10 == 0 then
							notifyPreloadProgress(string.format("🎭 Loaded %d/%d animation tracks", 
								completedTracks, totalObjects))
						end

						-- Check if all tracks are loaded
						if completedTracks >= totalObjects then
							preloadingState.tracksPreloaded = true
							preloadingState.ready = true
							notifyPreloadProgress("🎉 All animation tracks preloaded! Ready for instant dancing!", true)
						end
					else
						warn("❌ Failed to preload track for: " .. animationObject.Name)
					end

					-- Clean up Animation object
					animationObject:Destroy()
				end)

				task.wait(0.05) -- Small delay between individual tracks
			end
		end)

		task.wait(0.1) -- Small delay between batches
	end
end

-- PHASE 1: Preload all animation IDs aggressively
local function preloadAnimationIds()
	local animationIds = {}
	local animationObjects = {}

	-- Collect from ModuleScript
	for danceName, animationId in pairs(DanceAssets.dances) do
		local fullId = "rbxassetid://" .. animationId
		table.insert(animationIds, fullId)

		-- Also create Animation objects for track preloading
		local animation = Instance.new("Animation")
		animation.Name = danceName
		animation.AnimationId = fullId
		table.insert(animationObjects, animation)
	end

	preloadingState.totalDances = #animationIds
	notifyPreloadProgress("Starting aggressive ID preloading (" .. #animationIds .. " animations)")

	-- Preload IDs in large batches (client can handle aggressive preloading)
	local batchSize = 30 -- Larger batches for faster preloading
	local completedBatches = 0
	local totalBatches = math.ceil(#animationIds / batchSize)

	for i = 1, #animationIds, batchSize do
		local batch = {}
		for j = i, math.min(i + batchSize - 1, #animationIds) do
			table.insert(batch, animationIds[j])
		end

		local batchNumber = math.ceil(i / batchSize)

		task.spawn(function()
			local success, err = pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)

			completedBatches = completedBatches + 1

			if success then
				notifyPreloadProgress(string.format("✅ ID batch %d/%d complete (%d IDs)", 
					batchNumber, totalBatches, #batch))
			else
				warn(string.format("❌ ID batch %d failed: %s", batchNumber, tostring(err)))
			end

			-- Check if all ID batches are complete
			if completedBatches >= totalBatches then
				preloadingState.idsPreloaded = true
				notifyPreloadProgress("🚀 All animation IDs preloaded!")

				-- Immediately start track preloading
				task.spawn(function()
					task.wait(0.5) -- Brief pause
					preloadAnimationTracks(animationObjects)
				end)
			end
		end)

		task.wait(0.02) -- Very small delay between batches
	end
end

-- Get preloaded track for instant access
function ClientPreloader.getPreloadedTrack(danceName)
	return animationTrackCache[danceName]
end

-- Check if preloading is complete
function ClientPreloader.isReady()
	return preloadingState.ready
end

-- Get preloading status
function ClientPreloader.getStatus()
	return {
		idsPreloaded = preloadingState.idsPreloaded,
		tracksPreloaded = preloadingState.tracksPreloaded,
		ready = preloadingState.ready,
		totalDances = preloadingState.totalDances,
		preloadedCount = preloadingState.preloadedCount,
		percentage = preloadingState.totalDances > 0 and 
			(preloadingState.preloadedCount / preloadingState.totalDances) * 100 or 0
	}
end

-- Force refresh preloaded tracks (for character respawn)
function ClientPreloader.refreshTracks()
	if not player.Character then return end

	local humanoid = player.Character:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")
	if not animator then return end

	notifyPreloadProgress("Refreshing animation tracks after respawn...")

	-- Clear old cache
	for _, track in pairs(animationTrackCache) do
		if track then
			pcall(function() track:Destroy() end)
		end
	end
	animationTrackCache = {}

	-- Reload popular tracks
	local popularDances = {"Fresh", "Floss", "Gangnam style", "New Dance 01", "New Dance 02", "Dougie"}
	local refreshedCount = 0

	for _, danceName in pairs(popularDances) do
		if DanceAssets.dances[danceName] then
			task.spawn(function()
				local animation = Instance.new("Animation")
				animation.Name = danceName
				animation.AnimationId = "rbxassetid://" .. DanceAssets.dances[danceName]

				local success, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)

				if success and track then
					track.Priority = Enum.AnimationPriority.Action
					track.Looped = true
					animationTrackCache[danceName] = track
					refreshedCount = refreshedCount + 1

					notifyPreloadProgress("✅ Refreshed track: " .. danceName)
				end

				animation:Destroy()
			end)

			task.wait(0.1)
		end
	end

	notifyPreloadProgress("🔄 Refreshed " .. refreshedCount .. " popular tracks")
end

-- Auto-start preloading when character spawns
local function onCharacterAdded(character)
	task.wait(1) -- Wait for character to fully load

	-- Reset state
	preloadingState = {
		idsPreloaded = false,
		tracksPreloaded = false,
		totalDances = #DanceConfig:getDanceNames(),
		preloadedCount = 0,
		ready = false
	}

	-- Start aggressive preloading
	notifyPreloadProgress("Character loaded, starting aggressive preloading...")
	preloadAnimationIds()
end

-- Character respawn handling
player.CharacterAdded:Connect(onCharacterAdded)

-- Initialize if character already exists
if player.Character then
	onCharacterAdded(player.Character)
end

-- Export functions globally
_G.ClientPreloader = ClientPreloader

-- Debug functions
_G.GetPreloadStatus = function()
	local status = ClientPreloader.getStatus()
	print("=== CLIENT PRELOAD STATUS ===")
	print("IDs Preloaded:", status.idsPreloaded)
	print("Tracks Preloaded:", status.tracksPreloaded)
	print("Ready:", status.ready)
	print("Progress:", status.preloadedCount .. "/" .. status.totalDances)
	print("Percentage:", string.format("%.1f%%", status.percentage))

	-- List cached tracks
	local cacheCount = 0
	print("\n=== CACHED TRACKS ===")
	for danceName, track in pairs(animationTrackCache) do
		print("✅ " .. danceName)
		cacheCount = cacheCount + 1
	end
	print("Total cached:", cacheCount)
end

_G.TestInstantDance = function(danceName)
	local track = ClientPreloader.getPreloadedTrack(danceName or "Fresh")
	if track then
		print("✅ Found preloaded track for:", danceName or "Fresh")
		print("Track ready:", track.IsLoaded)
		print("Can play instantly!")
		return true
	else
		print("❌ No preloaded track found for:", danceName or "Fresh")
		return false
	end
end

print("✅ ClientPreloader: Ready to aggressively preload dances!")