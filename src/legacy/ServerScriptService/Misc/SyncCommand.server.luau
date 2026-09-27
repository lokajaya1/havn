local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local DanceShared = require(ReplicatedStorage.Modules.DanceShared)

local SYNC_WALKSPEED    = DanceShared.WALKSPEED.dance
local DANCE_WALKSPEED   = DanceShared.WALKSPEED.dance
local DEFAULT_WALKSPEED = DanceShared.WALKSPEED.default
local FADE_IN           = 0.20
local FADE_OUT          = 0.20
local STOP_FADE         = 0.35
local DRIFT_RATE        = 0.1
local DRIFT_THRESHOLD   = 0.03
local SPEED_THRESHOLD   = 0.05
local LEAD_STOP_GRACE   = 0.25
local TIGHT_SYNC_TIME   = 0.4
local CARRY_WATCH_INTERVAL = 0.2 -- watchdog jaga mirror hidup selama follower di-carry
local START_STOP_GAP    = 0.5  -- jeda start/stop sync (remote maupun chat)
local STATUS_GAP        = 1    -- jeda getSyncStatus

local SyncRemote = DanceShared.remote("SyncRemote")

local syncData = {}

-- Animator dulu, lalu Humanoid (urutan lama dipertahankan untuk pemanggil).
local function getAnimator(player)
	local humanoid, animator = DanceShared.getRig(player)
	return animator, humanoid
end

local function getCurrentSyncDance(userId)
	local data = syncData[userId]
	if not data then return nil end
	for name, t in pairs(data.tracks) do
		if t and t.IsPlaying then return name end
	end
	return nil
end

local function resolveLeadPlayer(targetPlayer, requesterUserId)
	local resolved = targetPlayer
	local visited  = {}
	local maxDepth = 10

	for _ = 1, maxDepth do
		local data = syncData[resolved.UserId]
		if not data then break end
		if not (data.targetPlayer and data.targetPlayer.Parent) then break end
		if visited[resolved.UserId] then
			warn("[SyncCommand] Circular sync detected at:", resolved.Name)
			break
		end
		visited[resolved.UserId] = true
		resolved                 = data.targetPlayer
	end

	if resolved.UserId == requesterUserId then return nil end
	return resolved
end

local function setFollowerWalkSpeed(follower, speed)
	local _, h = getAnimator(follower)
	if h then h.WalkSpeed = speed end
end

local function restoreFollowerWalkSpeed(follower)
	local _, h = getAnimator(follower)
	if not h then return end
	h.WalkSpeed = follower:GetAttribute("IsDancing") and DANCE_WALKSPEED or DEFAULT_WALKSPEED
end

local function stopOwnDanceTracks(follower)
	local _, humanoid = getAnimator(follower)
	if not humanoid then return end

	DanceShared.stopDanceTracks(humanoid, nil, STOP_FADE)
	follower:SetAttribute("IsDancing", false)
end

local function notifyClient(follower, isSyncing, target, reason, currentDance)
	pcall(function()
		SyncRemote:FireClient(follower, "syncStatus", {
			isSyncing    = isSyncing,
			target       = target or "None",
			reason       = reason,
			currentDance = currentDance,
		})
	end)
end

local function pauseSync(follower)
	local userId = follower.UserId
	local data   = syncData[userId]
	if not data or data.paused then return end

	local snapshot = table.clone(data.tracks)
	data.tracks = {}
	data.paused = true

	for _, track in pairs(snapshot) do
		if track and track.IsPlaying then
			pcall(function() track:Stop(STOP_FADE) end)
		end
	end

	restoreFollowerWalkSpeed(follower)
	notifyClient(follower, true, data.targetPlayer.Name, "leadPaused", nil)
end

local function stopSync(follower, reason)
	local userId = follower.UserId
	local data   = syncData[userId]
	if not data then return end

	if data.animPlayedConn then
		pcall(function() data.animPlayedConn:Disconnect() end)
		data.animPlayedConn = nil
	end
	for _, conn in ipairs(data.connections) do
		pcall(function() conn:Disconnect() end)
	end
	data.connections = {}

	for _, track in pairs(data.tracks) do
		if track and track.IsPlaying then
			pcall(function() track:Stop(STOP_FADE) end)
		end
	end
	data.tracks = {}

	syncData[userId] = nil

	follower:SetAttribute("IsSyncing", false)

	restoreFollowerWalkSpeed(follower)
	notifyClient(follower, false, "None", reason, nil)
end

local startSync

local function rehomeFollowers(oldLead, newLead)
	local ids = {}
	for uid, data in pairs(syncData) do
		if data.targetPlayer == oldLead then
			ids[#ids + 1] = uid
		end
	end

	for _, uid in ipairs(ids) do
		if uid ~= newLead.UserId then
			local f = Players:GetPlayerByUserId(uid)
			if f then
				startSync(f, newLead)
			end
		end
	end
end

local function tightSync(follower, followerTrack, targetTrack, duration)
	local userId = follower.UserId
	local startT = os.clock()

	local conn
	conn = RunService.Heartbeat:Connect(function()
		local d = syncData[userId]
		if not d
			or not followerTrack.IsPlaying
			or not targetTrack.IsPlaying then
			conn:Disconnect()
			return
		end

		followerTrack.TimePosition = targetTrack.TimePosition
		if math.abs(followerTrack.Speed - targetTrack.Speed) > 0.001 then
			followerTrack:AdjustSpeed(targetTrack.Speed)
		end

		if os.clock() - startT >= duration then
			conn:Disconnect()
		end
	end)
end

local mirrorTrack

mirrorTrack = function(follower, targetTrack, isInitial)
	if not (targetTrack and targetTrack.Animation) then return end
	local animName = targetTrack.Animation.Name
	if not DanceShared.isDanceName(animName) then return end

	local userId = follower.UserId
	local data   = syncData[userId]
	if not data then return end

	local animator = getAnimator(follower)
	if not animator then return end

	if data.paused then
		data.paused = false
		setFollowerWalkSpeed(follower, SYNC_WALKSPEED)
	end

	local oldTrack = data.tracks[animName]

	local newTrack = DanceShared.loadTrack(animator, animName)
	if not newTrack then return end

	local fIn  = isInitial and 0 or FADE_IN
	local fOut = isInitial and 0 or FADE_OUT

	newTrack:Play(fIn, 1.0, targetTrack.Speed)
	if oldTrack and oldTrack.IsPlaying then
		oldTrack:Stop(fOut)
	end
	if oldTrack then
		-- Bebaskan track lama; tanpa ini track menumpuk sampai batas 256 per Animator.
		task.delay(fOut + 0.1, function() pcall(oldTrack.Destroy, oldTrack) end)
	end

	local snapTarget = targetTrack
	if snapTarget.IsPlaying then
		newTrack.TimePosition = snapTarget.TimePosition
	end
	tightSync(follower, newTrack, snapTarget, TIGHT_SYNC_TIME)

	data.tracks[animName] = newTrack
	notifyClient(follower, true, data.targetPlayer.Name, nil, animName)

	snapTarget.Stopped:Once(function()
		local d = syncData[userId]
		if not d or d.tracks[animName] ~= newTrack then return end

		if newTrack.IsPlaying then
			pcall(function() newTrack:Stop(FADE_OUT) end)
		end
		d.tracks[animName] = nil

		for stillName, t in pairs(d.tracks) do
			if t and t.IsPlaying then
				notifyClient(follower, true, d.targetPlayer.Name, nil, stillName)
				return
			end
		end

		task.delay(LEAD_STOP_GRACE, function()
			local d2 = syncData[userId]
			if not d2 or d2 ~= d then return end

			for _, t in pairs(d2.tracks) do
				if t and t.IsPlaying then return end
			end

			local followerRef = Players:GetPlayerByUserId(userId)
			if not followerRef then return end

			local targetAnimator = getAnimator(d2.targetPlayer)
			if targetAnimator then
				local playing = DanceShared.playingDanceTracks(targetAnimator)
				if playing[1] then
					mirrorTrack(followerRef, playing[1], true)
					return
				end
			end

			pauseSync(followerRef)
		end)
	end)
end

-- Pastikan follower me-mirror SEMUA dance yang SEDANG dimainkan lead.
-- Idempotent: track yang benar-benar hidup (main penuh, WeightTarget>=0.5)
-- TIDAK di-restart (anti-stutter); hanya yang mati/belum ada yang di-mirror
-- ulang. Return true kalau lead memang sedang menari. Dipakai untuk MENJAGA
-- dance follower tetap jalan saat & sesudah di-carry.
local function ensureMirrorAlive(follower)
	local userId = follower.UserId
	local data   = syncData[userId]
	if not data then return false end
	if not (data.targetPlayer and data.targetPlayer.Parent) then return false end

	local targetAnimator = getAnimator(data.targetPlayer)
	if not targetAnimator then return false end

	local leadDancing = false
	for _, track in ipairs(DanceShared.playingDanceTracks(targetAnimator)) do
		leadDancing = true
		local name     = track.Animation.Name
		local existing = data.tracks[name]
		if not (existing and existing.IsPlaying and existing.WeightTarget >= 0.5) then
			mirrorTrack(follower, track, false)
		end
	end
	return leadDancing
end

startSync = function(follower, targetPlayer)
	-- CATATAN (carry-sync): guard "InCarry -> tolak sync" LAMA DIHAPUS. Dance/sync
	-- memang boleh & wajib tetap jalan saat di-carry, jadi follower yang di-carry
	-- TETAP boleh mulai / dipindah (rehome). Carry cuma nge-weld root; animasi
	-- anggota badan tetap jalan.

	local userId         = follower.UserId
	local resolvedTarget = resolveLeadPlayer(targetPlayer, userId)

	if not resolvedTarget then
		warn("[SyncCommand] Self-sync blocked after chain resolution for:", follower.Name)
		return false
	end

	targetPlayer = resolvedTarget

	if targetPlayer == follower then return false end

	local existingData = syncData[userId]
	if existingData and existingData.targetPlayer == targetPlayer then return true end

	if syncData[userId] then stopSync(follower, nil) end

	local targetChar = targetPlayer.Character
	if not targetChar then return false end

	local targetAnimator, targetHumanoid = getAnimator(targetPlayer)
	if not targetAnimator then return false end
	-- Lead atau follower yang sedang mati (ragdoll) tidak bisa di-sync.
	if targetHumanoid and targetHumanoid.Health <= 0 then return false end
	local _, followerHumanoid = getAnimator(follower)
	if followerHumanoid and followerHumanoid.Health <= 0 then return false end

	stopOwnDanceTracks(follower)

	syncData[userId] = {
		targetPlayer   = targetPlayer,
		tracks         = {},
		connections    = {},
		animPlayedConn = nil,
		paused         = false,
	}

	follower:SetAttribute("IsSyncing", true)

	setFollowerWalkSpeed(follower, SYNC_WALKSPEED)

	local currentDanceName = nil
	for _, track in ipairs(DanceShared.playingDanceTracks(targetAnimator)) do
		mirrorTrack(follower, track, true)
		if not currentDanceName then
			currentDanceName = track.Animation.Name
		end
	end

	if not currentDanceName then
		syncData[userId].paused = true
		restoreFollowerWalkSpeed(follower)
	end

	local animPlayedConn = targetAnimator.AnimationPlayed:Connect(function(track)
		if syncData[userId] then
			mirrorTrack(follower, track, false)
		end
	end)
	syncData[userId].animPlayedConn = animPlayedConn

	local charConn
	charConn = targetChar.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			pcall(function() charConn:Disconnect() end)
			local d = syncData[userId]
			if d and d.targetPlayer == targetPlayer then
				stopSync(follower, "targetInvalid")
			end
		end
	end)
	table.insert(syncData[userId].connections, charConn)

	-- Lead mati → sync langsung putus. Kalau menunggu karakternya dihapus
	-- (±5 dtk ragdoll), follower terus me-mirror track lead yang berhenti/jalan
	-- lagi dan terlihat kejang.
	if targetHumanoid then
		local diedConn = targetHumanoid.Died:Connect(function()
			local d = syncData[userId]
			if d and d.targetPlayer == targetPlayer then
				stopSync(follower, "targetInvalid")
			end
		end)
		table.insert(syncData[userId].connections, diedConn)
	end

	notifyClient(follower, true, targetPlayer.Name, nil, currentDanceName)

	rehomeFollowers(follower, targetPlayer)

	return true
end

task.spawn(function()
	while true do
		task.wait(DRIFT_RATE)

		local activeIds = {}
		for userId in pairs(syncData) do
			activeIds[#activeIds + 1] = userId
		end

		for _, userId in ipairs(activeIds) do
			local data = syncData[userId]
			if not data or data.paused then continue end
			if not (data.targetPlayer and data.targetPlayer.Parent) then continue end

			local targetAnimator = getAnimator(data.targetPlayer)
			if not targetAnimator then continue end

			local targetMap = {}
			for _, t in ipairs(DanceShared.playingDanceTracks(targetAnimator)) do
				targetMap[t.Animation.Name] = t
			end

			for animName, followerTrack in pairs(data.tracks) do
				if not followerTrack.IsPlaying then continue end
				local targetTrack = targetMap[animName]
				if not (targetTrack and targetTrack.IsPlaying) then continue end

				if math.abs(followerTrack.TimePosition - targetTrack.TimePosition) > DRIFT_THRESHOLD then
					followerTrack.TimePosition = targetTrack.TimePosition
				end

				if math.abs(followerTrack.Speed - targetTrack.Speed) > SPEED_THRESHOLD then
					followerTrack:AdjustSpeed(targetTrack.Speed)
				end
			end
		end
	end
end)

-- Jeda per pemain per jenis aksi; dipakai remote DAN perintah chat.
local lastAction = {} -- [player] → { [kind] = os.clock() }
local function allow(player, kind, gap)
	local now = os.clock()
	local slot = lastAction[player]
	if not slot then
		slot = {}
		lastAction[player] = slot
	end
	if slot[kind] and now - slot[kind] < gap then return false end
	slot[kind] = now
	return true
end
Players.PlayerRemoving:Connect(function(p) lastAction[p] = nil end)

SyncRemote.OnServerEvent:Connect(function(player, action, targetName)
	if type(action) ~= "string" then return end
	if action == "start" or action == "stop" then
		if not allow(player, "startStop", START_STOP_GAP) then return end
	elseif action == "getSyncStatus" then
		if not allow(player, "status", STATUS_GAP) then return end
	end
	if action == "getSyncStatus" then
		local data = syncData[player.UserId]
		if data and data.targetPlayer and data.targetPlayer.Parent then
			notifyClient(player, true, data.targetPlayer.Name, nil, getCurrentSyncDance(player.UserId))
		else
			if data then stopSync(player, nil) end
			notifyClient(player, false, "None", nil, nil)
		end

	elseif action == "start" then
		if type(targetName) ~= "string" then return end
		local targetChar   = workspace:FindFirstChild(targetName)
		if not targetChar then return end
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if not targetPlayer or targetPlayer == player then return end
		startSync(player, targetPlayer)

	elseif action == "stop" then
		stopSync(player, nil)
	end
end)

local function handleChatCommand(player, message)
	local trimmed = message:match("^%s*(.-)%s*$"):lower()

	local syncTarget = trimmed:match("^/sync%s+(.+)$")
	if syncTarget then
		syncTarget    = syncTarget:match("^%s*(.-)%s*$")
		local lowerT  = syncTarget:lower()
		local found   = nil

		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and (p.Name:lower() == lowerT or p.DisplayName:lower() == lowerT) then
				found = p; break
			end
		end
		if not found then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and (
					p.Name:lower():find(lowerT, 1, true) or
						p.DisplayName:lower():find(lowerT, 1, true)
					) then
					found = p; break
				end
			end
		end

		if found and allow(player, "startStop", START_STOP_GAP) then startSync(player, found) end
		return
	end

	if trimmed == "/unsync" or trimmed == "/stopsync" or trimmed == "/sync stop" then
		if allow(player, "startStop", START_STOP_GAP) then stopSync(player, nil) end
	end
end

-- Nomor generasi watchdog carry per pemain: InCarry yang berkedip cepat
-- tidak boleh menjalankan dua loop sekaligus.
local carryWatch = {}
Players.PlayerRemoving:Connect(function(p) carryWatch[p.UserId] = nil end)

local function onPlayerAdded(player)
	player.Chatted:Connect(function(msg)
		handleChatCommand(player, msg)
	end)

	-- Follower mati → sync putus saat itu juga (badan ragdoll tidak ikut di-sync).
	local function watchDeath(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or player.Character ~= character then return end
		humanoid.Died:Connect(function()
			if syncData[player.UserId] then
				stopSync(player, "followerDied")
			end
		end)
	end

	player.CharacterAdded:Connect(function(character)
		if syncData[player.UserId] then
			stopSync(player, "followerRespawned")
		end
		task.spawn(watchDeath, character)
	end)
	if player.Character then task.spawn(watchDeath, player.Character) end

	-- ═══════════════════════════════════════════════════════════
	-- CARRY x SYNC (FIX BUG SYNC-STOP)
	-- Dulu: MASUK carry -> pauseSync() nge-Stop mirror -> dance follower MATI.
	-- Sekarang: JANGAN pause. JAGA mirror tetap hidup lewat watchdog selama
	-- di-carry (idempotent, anti-stutter). Saat DROP, pastikan lagi.
	-- ═══════════════════════════════════════════════════════════
	player:GetAttributeChangedSignal("InCarry"):Connect(function()
		local userId = player.UserId

		carryWatch[userId] = (carryWatch[userId] or 0) + 1
		local generation = carryWatch[userId]

		if player:GetAttribute("InCarry") then
			if not syncData[userId] then return end
			task.spawn(function()
				task.wait() -- 1 frame biar carry pose/weld settle
				while player.Parent and player:GetAttribute("InCarry") and syncData[userId]
					and carryWatch[userId] == generation do
					ensureMirrorAlive(player)
					task.wait(CARRY_WATCH_INTERVAL)
				end
			end)
		else
			local data = syncData[userId]
			if not data then return end

			if not (data.targetPlayer and data.targetPlayer.Parent) then
				stopSync(player, "targetInvalid")
				return
			end

			local mirroredAny = ensureMirrorAlive(player)

			if mirroredAny then
				notifyClient(player, true, data.targetPlayer.Name, "resumed", getCurrentSyncDance(userId))
			else
				-- Lead memang lagi nggak nari -> baru paused beneran.
				data.paused = true
				restoreFollowerWalkSpeed(player)
				notifyClient(player, true, data.targetPlayer.Name, "leadPaused", nil)
			end
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	if syncData[player.UserId] then
		stopSync(player, nil)
	end

	local followersToStop = {}
	for userId, data in pairs(syncData) do
		if data.targetPlayer == player then
			table.insert(followersToStop, userId)
		end
	end

	for _, userId in ipairs(followersToStop) do
		local follower = Players:GetPlayerByUserId(userId)
		if follower then
			stopSync(follower, "leadLeft")
			task.delay(0.3, function()
				pcall(function()
					SyncRemote:FireClient(follower, "leadDisconnected", { leadName = player.Name })
				end)
			end)
		else
			syncData[userId] = nil
		end
	end
end)

for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end