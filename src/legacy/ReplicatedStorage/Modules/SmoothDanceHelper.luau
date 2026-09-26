-- SmoothDanceHelper ULTIMATE
-- Wrapper around SmoothDanceManager for use by DanceHandler & SyncHandler.
-- Initialization is CALLER-driven (DanceHandler calls initializePlayer).
-- No auto-PlayerAdded hooks → prevents double-init.

local SmoothDanceHelper = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")

local DanceAssets = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)

-- ═══════════════════════════════════════════════════════════
-- LOAD MANAGER  (optional, graceful fallback)
-- ═══════════════════════════════════════════════════════════
local SmoothDanceManager = nil
do
	local ok, result = pcall(function()
		return require(script.Parent.SmoothDanceManager)
	end)
	if ok then
		SmoothDanceManager = result
	else
		warn("[SmoothDanceHelper] SmoothDanceManager not found, using fallback mode")
	end
end

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════
local playerManagers  = {}  -- [player] = manager | false (false = fallback mode)
local playerFallback  = {}  -- [userId] = { track, name, speed }  (fallback only)

-- ═══════════════════════════════════════════════════════════
-- INITIALIZE  (called by DanceHandler, not auto)
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.initializePlayer(player)
	-- Destroy existing before creating new
	if playerManagers[player] and playerManagers[player] ~= false then
		pcall(function() playerManagers[player]:destroy() end)
		playerManagers[player] = nil
	end

	if SmoothDanceManager then
		local ok, manager = pcall(function()
			return SmoothDanceManager.new(player)
		end)
		if ok and manager then
			playerManagers[player] = manager
			return manager
		end
	end

	playerManagers[player] = false
	return false
end

function SmoothDanceHelper.getManager(player)
	local m = playerManagers[player]
	if m == nil then
		-- Not yet initialized — initialize now
		return SmoothDanceHelper.initializePlayer(player)
	elseif m == false then
		return nil  -- fallback mode
	end
	return m
end

-- ═══════════════════════════════════════════════════════════
-- PLAY DANCE
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.playDance(player, danceName, options)
	local manager = SmoothDanceHelper.getManager(player)
	if manager then
		return manager:playDance(danceName, options)
	end

	-- Fallback
	options = options or {}
	local character = player.Character
	if not character then return false end

	local humanoid = character:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")
	if not animator then return false end

	local animationId = DanceAssets.dances[danceName]
	if not animationId then return false end

	local userId = player.UserId

	-- Stop previous fallback track
	local prev = playerFallback[userId]
	if prev and prev.track and prev.track.IsPlaying then
		prev.track:Stop(options.fadeOut or 0.5)
	end

	local anim = Instance.new("Animation")
	anim.Name        = danceName
	anim.AnimationId = "rbxassetid://" .. animationId

	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	anim:Destroy()

	if not ok or not track then return false end

	-- FIX: was Enum.AnimationPriority.Action, one tier BELOW the Action4 used
	-- everywhere else a dance track gets created (DanceHandler's own fallback,
	-- and every mirrored track SyncHandler builds for followers). A track
	-- playing at a lower priority can be silently visually overridden by any
	-- other Action4 (or higher) animation on the same character - it stays
	-- `IsPlaying = true` in code, but you won't actually see it dancing.
	-- Standardized to Action4 so priority is consistent across the whole system.
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true
	track:Play(options.fadeIn or 0.5, 1.0, options.speed or 1.0)

	playerFallback[userId] = { track = track, name = danceName, speed = options.speed or 1.0 }
	return true
end

-- ═══════════════════════════════════════════════════════════
-- STOP DANCE
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.stopDance(player, fadeTime)
	fadeTime = fadeTime or 0.6

	local manager = playerManagers[player]
	if manager and manager ~= false then
		local ok, result = pcall(function() return manager:stopDance(fadeTime) end)
		if ok then return result end
	end

	-- Fallback
	local info = playerFallback[player.UserId]
	if info and info.track and info.track.IsPlaying then
		info.track:Stop(fadeTime)
		playerFallback[player.UserId] = nil
		return true
	end

	return false
end

function SmoothDanceHelper.stopAll(player)
	local manager = playerManagers[player]
	if manager and manager ~= false then
		pcall(function() manager:stopAll() end)
	else
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
			end
		end
	end
	playerFallback[player.UserId] = nil
end

-- ═══════════════════════════════════════════════════════════
-- SET SPEED
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.setSpeed(player, newSpeed, smoothTime)
	local manager = playerManagers[player]
	if manager and manager ~= false then
		return manager:setSpeed(newSpeed, smoothTime or 0.15)
	end

	local info = playerFallback[player.UserId]
	if info and info.track and info.track.IsPlaying then
		info.track:AdjustSpeed(newSpeed)
		info.speed = newSpeed
		return true
	end

	return false
end

-- ═══════════════════════════════════════════════════════════
-- GET CURRENT INFO
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.getCurrentInfo(player)
	local manager = playerManagers[player]
	if manager and manager ~= false then
		return manager:getCurrentInfo()
	end

	local info = playerFallback[player.UserId]
	if info then
		return {
			isPlaying    = info.track and info.track.IsPlaying or false,
			name         = info.name,
			speed        = info.speed or 1.0,
			timePosition = info.track and info.track.TimePosition or 0,
		}
	end

	return { isPlaying = false, name = nil, speed = 1.0 }
end

-- ═══════════════════════════════════════════════════════════
-- SYNC ANIMATION
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.syncAnimation(player, danceName, speed, serverTime, options)
	local manager = SmoothDanceHelper.getManager(player)
	options = options or {}

	local mergedOptions = {
		speed          = speed,
		serverTime     = serverTime,
		normalizedTime = options.normalizedTime or 0,
		fadeIn         = options.fadeIn or 0.25,
		fadeOut        = options.fadeOut or 0.25,
	}

	if manager then
		return manager:playDance(danceName, mergedOptions)
	end
	return SmoothDanceHelper.playDance(player, danceName, mergedOptions)
end

-- ═══════════════════════════════════════════════════════════
-- PRELOAD POPULAR ANIMATIONS
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.preloadPopularAnimations(player, animationNames)
	local manager = SmoothDanceHelper.getManager(player)

	local animIds = {}
	for _, name in ipairs(animationNames or {}) do
		local id = DanceAssets.dances[name]
		if id then table.insert(animIds, id) end
	end

	if manager then
		if #animIds > 0 then
			return manager:preloadPopularAnimations(animIds, {
				batchSize   = 6,
				prewarm     = true,
				loadToCache = true,
			})
		end
		return { ok = true, count = 0, total = 0 }
	end

	-- Fallback: ContentProvider only
	if #animIds > 0 then
		task.spawn(function()
			local urls = {}
			for _, id in ipairs(animIds) do
				table.insert(urls, "rbxassetid://" .. id)
			end
			pcall(function() ContentProvider:PreloadAsync(urls) end)
		end)
	end

	return { ok = true, count = #animIds, total = #animIds }
end

-- ═══════════════════════════════════════════════════════════
-- SYNC TO PLAYER
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.syncToPlayer(player, targetPlayer, options)
	local manager = SmoothDanceHelper.getManager(player)
	if not manager then return false end

	options = options or {}
	local targetManager = playerManagers[targetPlayer]

	if targetManager and targetManager ~= false then
		local info = targetManager:getCurrentInfo()
		if info.isPlaying then
			return manager:playDance(info.name, {
				speed          = info.speed,
				normalizedTime = info.timePosition,
				fadeIn         = options.fadeIn or 0.2,
				fadeOut        = options.fadeOut or 0.3,
			})
		end
	else
		local info = playerFallback[targetPlayer.UserId]
		if info and info.track and info.track.IsPlaying then
			return SmoothDanceHelper.playDance(player, info.name, {
				speed   = info.speed,
				fadeIn  = options.fadeIn or 0.2,
				fadeOut = options.fadeOut or 0.3,
			})
		end
	end

	return false
end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════
function SmoothDanceHelper.cleanupPlayer(player)
	if playerManagers[player] and playerManagers[player] ~= false then
		pcall(function() playerManagers[player]:destroy() end)
	end
	playerManagers[player] = nil

	local info = playerFallback[player.UserId]
	if info and info.track then
		pcall(function() info.track:Stop(0) end)
	end
	playerFallback[player.UserId] = nil
end

-- ═══════════════════════════════════════════════════════════
-- ALIASES
-- ═══════════════════════════════════════════════════════════
SmoothDanceHelper.playDanceWithAnimationObject = SmoothDanceHelper.playDance
SmoothDanceHelper.stopAllDances               = SmoothDanceHelper.stopAll
SmoothDanceHelper.stopSync                    = SmoothDanceHelper.stopDance
SmoothDanceHelper.getAllManagers              = function() return playerManagers end

return SmoothDanceHelper