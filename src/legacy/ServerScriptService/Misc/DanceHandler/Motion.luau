-- DanceHandler/Motion — WalkSpeed, play/stop dance, dan watchdog carry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DancePlayer = require(script.Parent.Parent.DancePlayer)
local DanceShared = require(ReplicatedStorage.Modules.DanceShared)
local CONFIG      = require(script.Parent.Config)
local State       = require(script.Parent.State)
local Tracks      = require(script.Parent.Tracks)

local DANCES   = DanceShared.dances
local states   = State.states
local getState = State.getState

local getRig          = Tracks.getRig
local getTrack        = Tracks.getTrack
local ensureTrack     = Tracks.ensureTrack
local findTrack       = Tracks.findTrack
local stopDanceTracks = Tracks.stopDanceTracks
local isDanceAlive    = Tracks.isDanceAlive

-- ═══════════════════════════════════════════════════════════
-- WALKSPEED
-- ═══════════════════════════════════════════════════════════

local function setDanceWalkSpeed(player)
	local humanoid = getRig(player)
	if humanoid then humanoid.WalkSpeed = CONFIG.DANCE_WALKSPEED end
end

local function restoreWalkSpeed(player)
	local humanoid = getRig(player)
	if not humanoid then return end

	local s      = states[player.UserId]
	local target = (s and s.walkSpeed) or CONFIG.DEFAULT_WALKSPEED

	-- Saat carry aktif, CarrySystemHandler pemegang tunggal WalkSpeed.
	local function apply()
		if humanoid.Parent and not player:GetAttribute("InCarry") then
			humanoid.WalkSpeed = target
		end
	end

	apply()
	task.delay(CONFIG.STOP_FADE + 0.1, function()
		local current = states[player.UserId]
		if current and current.dance then return end
		apply()
	end)
end

-- ═══════════════════════════════════════════════════════════
-- PLAY / STOP
-- ═══════════════════════════════════════════════════════════

-- Jalur langsung lewat Animator; dipakai sebagai cadangan kalau DancePlayer gagal.
local function playDirect(player, danceName, speed, fadeIn)
	local humanoid = getRig(player)
	if not humanoid then return false end

	local track = ensureTrack(player, danceName)
	if not track then return false end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true

	local ok = pcall(function() track:Play(fadeIn, 1.0, speed) end)
	if not ok then return false end

	stopDanceTracks(humanoid, track, CONFIG.FADE_OUT)
	DanceShared.applyDanceWeight(player, 0) -- sedang di-carry → bobot kecil
	return true
end

-- seq: nomor permintaan dari remote. Load asset dingin bisa menunggu, jadi
-- permintaan lama tidak boleh menang atas permintaan yang datang sesudahnya.
local function playDance(player, danceName, speed, seq)
	if not DANCES[danceName] then return false end

	local humanoid = getRig(player)
	if not humanoid or humanoid.Health <= 0 then return false end -- mati: tunggu respawn

	local s = getState(player)
	speed = tonumber(speed); if speed ~= speed then speed = nil end -- tolak NaN ("nan" lolos math.clamp)
	speed = math.clamp(speed or 1.0, CONFIG.MIN_SPEED, CONFIG.MAX_SPEED)
	s.speed = speed
	setDanceWalkSpeed(player)

	-- Dance yang sama dan masih hidup: cukup ubah kecepatannya.
	if s.dance == danceName then
		if isDanceAlive(humanoid, danceName) then
			local called, changed = pcall(DancePlayer.setSpeed, s.slot, speed, CONFIG.SPEED_TRANSITION)
			if called and changed then return true end
		end
		s.dance = nil
	end

	-- Panaskan dulu, jadi DancePlayer tidak pernah memutar track dengan Length 0.
	ensureTrack(player, danceName)
	if seq and (states[player.UserId] ~= s or s.requestSeq ~= seq) then return false end

	-- Track yang sama dengan yang baru dipanaskan (cache LRU): satu track per dance.
	local called, ok = pcall(DancePlayer.play, s.slot, getTrack(player, danceName), {
		fadeIn  = CONFIG.FADE_IN,
		fadeOut = CONFIG.FADE_OUT,
		speed   = speed,
	})
	if not (called and ok) then
		ok = playDirect(player, danceName, speed, CONFIG.FADE_IN)
	end

	if not ok then
		restoreWalkSpeed(player)
		return false
	end

	s.dance = danceName
	player:SetAttribute("IsDancing", true)
	DanceShared.applyDanceWeight(player, 0) -- sedang di-carry → bobot kecil
	return true
end

local function stopDance(player)
	local s = states[player.UserId]
	if s then s.dance = nil end
	player:SetAttribute("IsDancing", false)

	local humanoid = getRig(player)
	if not humanoid then return end

	local called, ok = pcall(DancePlayer.stop, s.slot, CONFIG.STOP_FADE)
	if not (called and ok) then
		stopDanceTracks(humanoid, nil, CONFIG.STOP_FADE)
	end

	restoreWalkSpeed(player)
end

-- Carry pose bisa menimpa/mematikan track dance; pulihkan sambil menjaga fase.
local function reassertDance(player)
	local s = states[player.UserId]
	if not s or not s.dance then return end
	if player:GetAttribute("IsSyncing") then return end

	local humanoid = getRig(player)
	if not humanoid then return end

	local danceName, speed = s.dance, s.speed or 1.0

	if isDanceAlive(humanoid, danceName) then
		setDanceWalkSpeed(player)
		return
	end

	local previous = findTrack(humanoid, danceName)
	local phase    = previous and previous.TimePosition or nil

	-- Reset slot dulu; slot bisa mengira dance masih main.
	pcall(DancePlayer.stop, s.slot, 0)
	s.dance = nil

	local ok = playDance(player, danceName, speed)

	if not isDanceAlive(humanoid, danceName) then
		stopDanceTracks(humanoid, nil, 0)
		ok = playDirect(player, danceName, speed, CONFIG.REASSERT_FADE)
		if ok then
			setDanceWalkSpeed(player)
			player:SetAttribute("IsDancing", true)
		end
	end

	s.dance = danceName
	s.speed = speed

	if ok and phase then
		local track = findTrack(humanoid, danceName)
		if track and track.IsPlaying then
			pcall(function() track.TimePosition = phase end)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- WATCHDOG CARRY x DANCE
-- Satu loop untuk dua kondisi: selama di-carry (tanpa batas) dan
-- verifikasi singkat setelah drop. Token per-generasi mematikan loop lama.
-- ═══════════════════════════════════════════════════════════

local function startWatch(player, carried)
	local s = states[player.UserId]
	if not s or not s.dance then return end

	local danceName = s.dance
	s.watchToken += 1
	local token = s.watchToken

	local interval = carried and CONFIG.CARRY_INTERVAL or CONFIG.DROP_INTERVAL
	local steps    = carried and math.huge or CONFIG.DROP_STEPS

	task.spawn(function()
		task.wait(carried and 0 or interval) -- beri waktu pose/weld carry settle

		local step = 0
		while step < steps do
			step += 1

			if not player.Parent then return end
			if player:GetAttribute("IsSyncing") then return end
			if (player:GetAttribute("InCarry") == true) ~= carried then return end

			local current = states[player.UserId]
			if not current or current.watchToken ~= token or not current.dance then return end
			-- Ganti dance saat digendong: jaga dance yang baru (dulu watchdog berhenti).
			danceName = current.dance

			local humanoid = getRig(player)
			if humanoid then
				if not isDanceAlive(humanoid, danceName) then
					reassertDance(player)
				elseif carried then
					setDanceWalkSpeed(player)
				end
			end

			task.wait(interval)
		end
	end)
end

return {
	playDance  = playDance,
	stopDance  = stopDance,
	startWatch = startWatch,
}
