-- SmoothDanceManager ULTIMATE
-- Uses Roblox native animation blending exclusively.
-- No Heartbeat-based fades (zero memory leak risk).
-- Track lifecycle managed via AnimationTrack.Stopped events.

local SmoothDanceManager = {}
SmoothDanceManager.__index = SmoothDanceManager

local RunService        = game:GetService("RunService")
local ContentProvider   = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DanceConfigHelper = require(ReplicatedStorage.Config.DanceConfigHelper)

-- ═══════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager.new(player)
	local self = setmetatable({}, SmoothDanceManager)

	self.player         = player
	self.character      = nil
	self.humanoid       = nil
	self.animator       = nil
	self.currentTrack   = nil
	self.animationCache = {}   -- [cacheKey] = track
	self.defaultFadeIn  = 0.5
	self.defaultFadeOut = 0.5
	self.defaultSpeed   = 1.0
	self._charConn      = nil
	self._speedConn     = nil

	self:_updateCharacterComponents()

	if player then
		self._charConn = player.CharacterAdded:Connect(function()
			task.wait(0.5)
			self:_updateCharacterComponents()
			self:_clearCache()
		end)
	end

	return self
end

-- ═══════════════════════════════════════════════════════════
-- CHARACTER COMPONENTS
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:_updateCharacterComponents()
	if not self.player then return false end

	self.character = self.player.Character
	if not self.character then return false end

	self.humanoid = self.character:FindFirstChild("Humanoid")
	if not self.humanoid then return false end

	self.animator = self.humanoid:FindFirstChild("Animator")
	return self.animator ~= nil
end

-- ═══════════════════════════════════════════════════════════
-- CACHE
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:_clearCache()
	for _, track in pairs(self.animationCache) do
		if track then pcall(function() track:Stop(0) end) end
	end
	self.animationCache = {}
	self.currentTrack   = nil
end

-- ═══════════════════════════════════════════════════════════
-- GET / LOAD TRACK
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:_getAnimationTrack(nameOrId)
	local animId = nameOrId
	if type(nameOrId) == "string" and not tonumber(nameOrId) then
		animId = DanceConfigHelper.getAnimationId(nameOrId)
		if not animId then
			warn("SmoothDanceManager: Animation not found:", nameOrId)
			return nil
		end
	end

	local cacheKey = tostring(animId)
	local cached   = self.animationCache[cacheKey]

	if cached and self.animator and cached.Animation then
		return cached
	end
	self.animationCache[cacheKey] = nil

	if not self:_updateCharacterComponents() then return nil end

	-- Try animation object from DanceConfigHelper first
	local animName = DanceConfigHelper.getAnimationName(animId)
	if animName then
		local animObj = DanceConfigHelper.getAnimationObject(animName)
		if animObj then
			local ok, track = pcall(function()
				return self.animator:LoadAnimation(animObj)
			end)
			if animObj.Parent == nil then
				pcall(function() animObj:Destroy() end)
			end
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped   = true
				self.animationCache[cacheKey] = track
				-- Auto-evict from cache when track stops (memory hygiene)
				track.Stopped:Once(function()
					if self.animationCache[cacheKey] == track then
						self.animationCache[cacheKey] = nil
					end
				end)
				return track
			end
		end
	end

	-- Fallback: create from ID
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)

	local ok, track = pcall(function() return self.animator:LoadAnimation(anim) end)
	anim:Destroy()

	if ok and track then
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped   = true
		self.animationCache[cacheKey] = track
		track.Stopped:Once(function()
			if self.animationCache[cacheKey] == track then
				self.animationCache[cacheKey] = nil
			end
		end)
		return track
	end

	warn("SmoothDanceManager: Failed to load track for", nameOrId)
	return nil
end

-- ═══════════════════════════════════════════════════════════
-- PREWARM  (non-blocking, async)
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:_prewarmTrack(track)
	if not track then return end
	task.spawn(function()
		pcall(function()
			track:Play(0, 0, 0.001)
			task.wait()        -- single frame yield
			track:Stop(0)
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- PRELOAD POPULAR ANIMATIONS
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:preloadPopularAnimations(animIds, options)
	options = options or {}
	local batchSize   = options.batchSize or 8
	local prewarm     = options.prewarm ~= false
	local loadToCache = options.loadToCache ~= false

	if not animIds or #animIds == 0 then
		return { ok = true, count = 0, results = {} }
	end

	-- Build Animation instances for ContentProvider
	local animations = {}
	for _, id in ipairs(animIds) do
		if id and tostring(id) ~= "" then
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. tostring(id)
			table.insert(animations, a)
		end
	end

	-- Batch CDN preload
	local i = 1
	while i <= #animations do
		local batch = {}
		for j = i, math.min(i + batchSize - 1, #animations) do
			table.insert(batch, animations[j])
		end
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync(batch) end)
		end)
		i = i + batchSize
	end

	local successCount = 0
	local results      = {}

	for _, animInst in ipairs(animations) do
		local id = tonumber(animInst.AnimationId:match("(%d+)")) or animInst.AnimationId

		if loadToCache then
			local ok, track = pcall(function() return self:_getAnimationTrack(id) end)
			if ok and track then
				if prewarm then self:_prewarmTrack(track) end
				results[id] = { ok = true }
				successCount += 1
			else
				results[id] = { ok = false }
			end
		else
			results[id] = { ok = true }
			successCount += 1
		end

		animInst:Destroy()
	end

	return { ok = successCount == #animations, count = successCount, total = #animations, results = results }
end

-- ═══════════════════════════════════════════════════════════
-- PLAY DANCE  (Roblox native blending)
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:playDance(nameOrId, options)
	options = options or {}

	local fadeIn         = options.fadeIn or self.defaultFadeIn
	local fadeOut        = options.fadeOut or self.defaultFadeOut
	local speed          = options.speed or self.defaultSpeed
	local normalizedTime = options.normalizedTime
	local serverTime     = options.serverTime

	if not nameOrId or nameOrId == "" then
		warn("SmoothDanceManager: Invalid name/ID")
		return false
	end

	local newTrack = self:_getAnimationTrack(nameOrId)
	if not newTrack then return false end

	-- Same track already playing → only adjust speed / time
	if self.currentTrack == newTrack and newTrack.IsPlaying then
		if math.abs(speed - newTrack.Speed) > 0.01 then
			self:setSpeed(speed, 0.15)
		end
		if normalizedTime then
			newTrack.TimePosition = normalizedTime
		end
		return true
	end

	-- Fade out old track (native Roblox blend)
	local oldTrack = self.currentTrack
	if oldTrack and oldTrack.IsPlaying then
		oldTrack:Stop(fadeOut)
	end

	-- Play new track with native blend-in
	self.currentTrack = newTrack
	newTrack:Play(fadeIn, 1.0, speed)

	-- Apply sync timing if provided
	if serverTime and normalizedTime then
		task.spawn(function()
			RunService.Heartbeat:Wait()
			if newTrack.IsPlaying then
				local diff   = tick() - serverTime
				local syncPos = (normalizedTime + diff * speed) % math.max(newTrack.Length, 0.01)
				newTrack.TimePosition = syncPos
			end
		end)
	elseif normalizedTime then
		task.spawn(function()
			RunService.Heartbeat:Wait()
			if newTrack.IsPlaying then
				newTrack.TimePosition = normalizedTime
			end
		end)
	end

	return true
end

-- ═══════════════════════════════════════════════════════════
-- STOP DANCE
-- WalkSpeed is DanceHandler's responsibility, NOT ours.
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:stopDance(fadeTime)
	fadeTime = fadeTime or self.defaultFadeOut

	if self.currentTrack and self.currentTrack.IsPlaying then
		self.currentTrack:Stop(fadeTime)
		self.currentTrack = nil
		return true
	end

	return false
end

function SmoothDanceManager:stopAll()
	if self.currentTrack then
		pcall(function() self.currentTrack:Stop(0) end)
		self.currentTrack = nil
	end
	-- Also stop any lingering cached tracks
	for _, track in pairs(self.animationCache) do
		if track then pcall(function() track:Stop(0) end) end
	end
end

-- ═══════════════════════════════════════════════════════════
-- GET CURRENT INFO
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:getCurrentInfo()
	if self.currentTrack and self.currentTrack.IsPlaying then
		local animId   = self.currentTrack.Animation.AnimationId:match("(%d+)")
		local animInfo = DanceConfigHelper.getAnimationInfo(animId)
		return {
			animId       = animId,
			name         = animInfo.name,
			speed        = self.currentTrack.Speed,
			timePosition = self.currentTrack.TimePosition,
			weight       = self.currentTrack.WeightCurrent,
			length       = self.currentTrack.Length,
			isDance      = animInfo.isDance,
			isPlaying    = true,
		}
	end
	return { isPlaying = false }
end

-- ═══════════════════════════════════════════════════════════
-- SET SPEED  (smooth Heartbeat tween, self-disconnecting)
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:setSpeed(newSpeed, smoothTime)
	if not self.currentTrack or not self.currentTrack.IsPlaying then return false end

	-- Disconnect any in-progress speed tween
	if self._speedConn then
		self._speedConn:Disconnect()
		self._speedConn = nil
	end

	if smoothTime and smoothTime > 0 then
		local startSpeed = self.currentTrack.Speed
		local startTime  = tick()
		local track      = self.currentTrack

		self._speedConn = RunService.Heartbeat:Connect(function()
			if not track or not track.IsPlaying then
				self._speedConn:Disconnect()
				self._speedConn = nil
				return
			end

			local progress = math.min((tick() - startTime) / smoothTime, 1)
			local t        = 0.5 * (1 - math.cos(progress * math.pi))  -- cosine ease
			track:AdjustSpeed(startSpeed + (newSpeed - startSpeed) * t)

			if progress >= 1 then
				self._speedConn:Disconnect()
				self._speedConn = nil
			end
		end)
	else
		self.currentTrack:AdjustSpeed(newSpeed)
	end

	return true
end

-- ═══════════════════════════════════════════════════════════
-- SYNC
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:syncAnimation(animId, speed, serverTime, currentTime)
	local elapsed     = (currentTime or tick()) - serverTime
	local normalizedT = (elapsed * speed) % math.max((self.currentTrack and self.currentTrack.Length) or 10, 0.01)

	return self:playDance(animId, {
		speed          = speed,
		normalizedTime = normalizedT,
	})
end

-- ═══════════════════════════════════════════════════════════
-- DESTROY
-- ═══════════════════════════════════════════════════════════
function SmoothDanceManager:destroy()
	if self._speedConn then self._speedConn:Disconnect() end
	if self._charConn  then self._charConn:Disconnect()  end
	self:stopAll()
	self:_clearCache()
	self.player    = nil
	self.character = nil
	self.humanoid  = nil
	self.animator  = nil
end

return SmoothDanceManager