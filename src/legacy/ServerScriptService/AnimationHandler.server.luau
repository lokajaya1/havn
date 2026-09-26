-- ═══════════════════════════════════════════════════════════
-- ANIMATION HANDLER - FIXED MODULE PATHS
-- ═══════════════════════════════════════════════════════════
-- ServerScriptService > AnimationHandler
-- FIX: Now uses correct paths:
--   DanceAssets from ReplicatedStorage.Assets.Animations.Dances.DanceAssets
--   Built-in animation cache (no external AnimationCache module needed)
-- Handles: PlayAnimation, Sync, Unsync remotes
-- ═══════════════════════════════════════════════════════════

--// SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

--// MODULE IMPORTS (FIXED PATHS)
local DanceAssets
local function loadDanceAssets()
	-- Try the correct path: ReplicatedStorage.Assets.Animations.Dances.DanceAssets
	local success, result = pcall(function()
		return require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)
	end)
	if success and result then
		print("[AnimationHandler] ✅ DanceAssets loaded from Assets.Animations.Dances.DanceAssets")
		return result
	end

	-- Fallback: try other common locations
	local fallbackPaths = {
		{"Config", "DanceAssets"},
		{"DanceAssets"},
		{"Modules", "DanceAssets"},
	}

	for _, path in ipairs(fallbackPaths) do
		local current = ReplicatedStorage
		local found = true
		for _, segment in ipairs(path) do
			current = current:FindFirstChild(segment)
			if not current then
				found = false
				break
			end
		end
		if found and current:IsA("ModuleScript") then
			local s, r = pcall(require, current)
			if s and r then
				print("[AnimationHandler] ✅ DanceAssets loaded from fallback:", table.concat(path, "."))
				return r
			end
		end
	end

	warn("[AnimationHandler] ❌ DanceAssets not found in any known location!")
	return nil
end

DanceAssets = loadDanceAssets()

--// BUILT-IN ANIMATION CACHE (replaces missing AnimationCache module)
local AnimCache = {}
local cachedAnimations = {}

function AnimCache:Get(animationId)
	if cachedAnimations[animationId] then
		return cachedAnimations[animationId]
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId
	cachedAnimations[animationId] = anim
	return anim
end

function AnimCache:Preload(idList)
	local toPreload = {}
	for _, id in ipairs(idList) do
		if not cachedAnimations[id] then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			cachedAnimations[id] = anim
			table.insert(toPreload, anim)
		end
	end
	if #toPreload > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end
end

--// NETWORKING FOLDER (don't duplicate if exists)
local NetFolder = ReplicatedStorage:FindFirstChild("AnimationNetwork")
if not NetFolder then
	NetFolder = Instance.new("Folder")
	NetFolder.Name = "AnimationNetwork"
	NetFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemote(parent, name)
	local remote = parent:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
	end
	return remote
end

local playAnimRemote = getOrCreateRemote(NetFolder, "PlayAnimation")
local syncRemote = getOrCreateRemote(NetFolder, "Sync")
local unsyncRemote = getOrCreateRemote(NetFolder, "Unsync")

--// LOGIC VARIABLES
local syncedAnimations = {}
local syncingPlayers = {}
local targetMap = {}
local currentDances = {}
local syncConnections = {} -- Track connections for proper cleanup

--// SYNCING CONFIGURATION
local IGNORED_ANIMATION_PRIORITY = { Enum.AnimationPriority.Core }
local IGNORED_EMOTE_NAMES = {
	"running", "swimming", "platformstanding", "seated",
	"fallingdown", "gettingup", "jumping", "climbing", "walking"
}

--// ═══════════════════════════════════════════════════════════
--// SYNC FUNCTIONS
--// ═══════════════════════════════════════════════════════════

local function stopSyncing(player)
	if not syncingPlayers[player.UserId] then return end

	syncingPlayers[player.UserId] = nil
	syncedAnimations[player.UserId] = nil

	-- Disconnect all sync connections for this player
	if syncConnections[player.UserId] then
		for _, conn in ipairs(syncConnections[player.UserId]) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
		syncConnections[player.UserId] = nil
	end

	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then return end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Name == "SyncedTrack" then
			track:Stop()
			track:Destroy()
		end
	end
end

local function startSyncing(player, targetPlayer)
	-- Validate inputs
	if not targetPlayer or not targetPlayer:IsA("Player") then return end
	if player == targetPlayer then return end

	stopSyncing(player)

	local humanoid1 = player.Character and player.Character:FindFirstChild("Humanoid")
	local humanoid2 = targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid")
	if not humanoid1 or not humanoid2 then return end

	local animator1 = humanoid1:FindFirstChild("Animator")
	local animator2 = humanoid2:FindFirstChild("Animator")
	if not animator1 or not animator2 then return end

	syncedAnimations[player.UserId] = {}
	syncingPlayers[player.UserId] = true
	syncConnections[player.UserId] = {}
	currentDances[player.UserId] = nil

	-- Register in targetMap (avoid duplicates)
	targetMap[targetPlayer.UserId] = targetMap[targetPlayer.UserId] or {}
	if not table.find(targetMap[targetPlayer.UserId], player) then
		table.insert(targetMap[targetPlayer.UserId], player)
	end

	local function syncTrack(targetTrack)
		if not syncingPlayers[player.UserId] then return end

		local anim = targetTrack.Animation
		local name = (anim and anim.Name or ""):lower()
		if not anim or not anim:IsA("Animation") then return end
		if table.find(IGNORED_ANIMATION_PRIORITY, targetTrack.Priority) then return end
		if table.find(IGNORED_EMOTE_NAMES, name) then return end

		local animId = anim.AnimationId
		local cachedAnim = AnimCache:Get(animId)
		if not cachedAnim then return end

		-- Stop existing synced track for this animation
		if syncedAnimations[player.UserId] and syncedAnimations[player.UserId][animId] then
			local old = syncedAnimations[player.UserId][animId]
			if old and old.IsPlaying then
				old:Stop()
				old:Destroy()
			end
		end

		local newTrack = animator1:LoadAnimation(cachedAnim)
		newTrack.Name = "SyncedTrack"
		newTrack.Priority = Enum.AnimationPriority.Action
		newTrack:Play()
		newTrack.TimePosition = targetTrack.TimePosition
		newTrack:AdjustSpeed(targetTrack.Speed)

		if syncedAnimations[player.UserId] then
			syncedAnimations[player.UserId][animId] = newTrack
		end
		Debris:AddItem(newTrack, 7200)

		-- Speed sync
		local speedConn = targetTrack:GetPropertyChangedSignal("Speed"):Connect(function()
			if newTrack and newTrack.Parent then
				newTrack:AdjustSpeed(targetTrack.Speed)
			end
		end)
		table.insert(syncConnections[player.UserId], speedConn)

		-- Stop when target stops
		local stopConn = targetTrack.Stopped:Connect(function()
			if newTrack and newTrack.Parent then
				newTrack:Stop()
				newTrack:Destroy()
				if syncedAnimations[player.UserId] then
					syncedAnimations[player.UserId][animId] = nil
				end
			end
		end)
		table.insert(syncConnections[player.UserId], stopConn)
	end

	-- Sync currently playing animations
	for _, track in ipairs(animator2:GetPlayingAnimationTracks()) do
		syncTrack(track)
	end

	-- Listen for new animations from target
	local animPlayedConn = animator2.AnimationPlayed:Connect(function(track)
		if syncingPlayers[player.UserId] then
			syncTrack(track)
		end
	end)
	table.insert(syncConnections[player.UserId], animPlayedConn)

	-- If target dies → stop sync
	local deathConn2 = humanoid2.Died:Connect(function()
		stopSyncing(player)
	end)
	table.insert(syncConnections[player.UserId], deathConn2)

	-- If syncing player dies → stop sync
	local deathConn1 = humanoid1.Died:Connect(function()
		stopSyncing(player)
	end)
	table.insert(syncConnections[player.UserId], deathConn1)
end

--// ═══════════════════════════════════════════════════════════
--// ANIMATION PLAYBACK
--// ═══════════════════════════════════════════════════════════

local function stopAllDances(animator)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Priority ~= Enum.AnimationPriority.Core then
			track:Stop()
			track:Destroy()
		end
	end
end

local function playAnimation(player, animName)
	-- Validate input
	if typeof(animName) ~= "string" then return end

	local char = player.Character
	local humanoid = char and char:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then return end

	stopSyncing(player)

	-- Toggle: same dance = stop
	if currentDances[player.UserId] == animName then
		stopAllDances(animator)
		currentDances[player.UserId] = nil
		return
	end

	stopAllDances(animator)

	-- Try to get animation ID from DanceAssets first
	local animId = nil
	if DanceAssets and DanceAssets.dances and DanceAssets.dances[animName] then
		animId = "rbxassetid://" .. DanceAssets.dances[animName]
	else
		-- Fallback: check Animations folder (created by this script or others)
		local animsFolder = ReplicatedStorage:FindFirstChild("Animations")
		if animsFolder then
			local animInstance = animsFolder:FindFirstChild(animName)
			if animInstance and animInstance:IsA("Animation") then
				animId = animInstance.AnimationId
			end
		end
	end

	if not animId then
		warn("[AnimationHandler] Animation not found:", animName)
		currentDances[player.UserId] = nil
		return
	end

	local cachedAnim = AnimCache:Get(animId)
	if not cachedAnim then
		warn("[AnimationHandler] Could not create animation:", animName)
		currentDances[player.UserId] = nil
		return
	end

	local animationTrack = animator:LoadAnimation(cachedAnim)
	animationTrack.Priority = Enum.AnimationPriority.Action
	animationTrack:Play()

	currentDances[player.UserId] = animName
	Debris:AddItem(animationTrack, 7200)
end

--// ═══════════════════════════════════════════════════════════
--// SETUP ANIMATIONS FOLDER
--// ═══════════════════════════════════════════════════════════

local function setupAnimations()
	if not DanceAssets or not DanceAssets.dances then
		warn("[AnimationHandler] ⚠️ DanceAssets not available — skipping Animations folder setup")
		return
	end

	-- Don't duplicate if already exists
	local existing = ReplicatedStorage:FindFirstChild("Animations")
	if existing then
		print("[AnimationHandler] ✅ Animations folder already exists, skipping creation")
		return
	end

	local animsFolder = Instance.new("Folder")
	animsFolder.Name = "Animations"

	local idsToPreload = {}
	local count = 0

	for danceName, animationId in pairs(DanceAssets.dances) do
		local fullId = "rbxassetid://" .. animationId
		local anim = Instance.new("Animation")
		anim.Name = danceName
		anim.AnimationId = fullId
		anim.Parent = animsFolder
		table.insert(idsToPreload, fullId)
		count += 1
	end

	animsFolder.Parent = ReplicatedStorage

	-- Preload in background
	task.spawn(function()
		AnimCache:Preload(idsToPreload)
		print(string.format("[AnimationHandler] ✅ %d animations loaded and cached", count))
	end)
end

--// ═══════════════════════════════════════════════════════════
--// CONNECTIONS
--// ═══════════════════════════════════════════════════════════

playAnimRemote.OnServerEvent:Connect(playAnimation)
syncRemote.OnServerEvent:Connect(startSyncing)
unsyncRemote.OnServerEvent:Connect(stopSyncing)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	currentDances[leavingPlayer.UserId] = nil
	stopSyncing(leavingPlayer)

	-- Stop all players synced TO the leaving player
	local dependents = targetMap[leavingPlayer.UserId]
	if dependents then
		for _, player in ipairs(dependents) do
			if player and player:IsDescendantOf(Players) then
				stopSyncing(player)
			end
		end
		targetMap[leavingPlayer.UserId] = nil
	end

	-- Remove leaving player from other players' targetMap
	for targetId, deps in pairs(targetMap) do
		for i = #deps, 1, -1 do
			if deps[i] == leavingPlayer then
				table.remove(deps, i)
			end
		end
	end
end)

--// STARTUP
setupAnimations()
print("[AnimationHandler] ✅ Ready — using DanceAssets + built-in cache")