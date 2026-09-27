-- DanceHandler/Tracks — rig pemain, cache LRU track dance, dan track yang sedang main.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DanceShared = require(ReplicatedStorage.Modules.DanceShared)
local CONFIG      = require(script.Parent.Config)
local State       = require(script.Parent.State)

local DANCES = DanceShared.dances
local states = State.states

-- ═══════════════════════════════════════════════════════════
-- RIG & TRACK CACHE
-- ═══════════════════════════════════════════════════════════

local function getRig(player)
	-- Dipanggil juga dari thread tertunda; pemain yang sudah keluar tidak
	-- boleh mendapat state baru lagi.
	local s = states[player.UserId]
	if not s then return nil, nil end
	local rig = s.rig
	if rig and rig.character.Parent and rig.humanoid.Parent and rig.animator.Parent then
		return rig.humanoid, rig.animator
	end

	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	local animator  = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		s.rig = nil
		return nil, nil
	end

	s.rig = { character = character, humanoid = humanoid, animator = animator }
	return humanoid, animator
end

local function releaseTrack(entry)
	pcall(function()
		entry.track:Stop(0)
		entry.track:Destroy()
	end)
end

local function clearTracks(s)
	for _, entry in pairs(s.tracks) do
		releaseTrack(entry)
	end
	s.tracks     = {}
	s.trackCount = 0
	s.clock      = 0
end

-- Cache LRU: track dipakai ulang, yang paling lama menganggur dibuang.
local function getTrack(player, danceName)
	local animationId = DANCES[danceName]
	if not animationId then return nil end

	local s = states[player.UserId]
	if not s then return nil end
	s.clock += 1

	local entry = s.tracks[danceName]
	if entry and entry.track.Animation then
		entry.used = s.clock
		return entry.track
	end

	local _, animator = getRig(player)
	if not animator then return nil end

	if s.trackCount >= CONFIG.MAX_TRACKS then
		local oldestName, oldestUsed = nil, math.huge
		for name, e in pairs(s.tracks) do
			if e.used < oldestUsed then
				oldestName, oldestUsed = name, e.used
			end
		end
		if oldestName then
			releaseTrack(s.tracks[oldestName])
			s.tracks[oldestName] = nil
			s.trackCount -= 1
		end
	end

	local track = DanceShared.loadTrack(animator, danceName)
	if not track then return nil end

	s.tracks[danceName] = { track = track, used = s.clock }
	s.trackCount += 1
	return track
end

-- Play pada track dengan Length 0 tidak menampilkan apa pun; ini penyebab
-- "diam" saat dance pertama. Menunggu hanya sekali per dance per karakter.
-- Animasi yang asset-nya rusak dicatat supaya tidak ditunggu berulang kali.
-- Asset yang hanya LAMBAT (lewat LOAD_TIMEOUT tapi termuat kemudian) tetap
-- diputar dan tidak dicap rusak; cap rusak baru setelah BROKEN_CHECK detik.
local brokenDances = {}
local brokenCheck  = {}

local function checkBrokenLater(player, danceName, track)
	if brokenCheck[danceName] or brokenDances[danceName] then return end
	brokenCheck[danceName] = true
	task.delay(CONFIG.BROKEN_CHECK, function()
		brokenCheck[danceName] = nil
		-- Track sudah diganti (respawn / cache) → tidak bisa dinilai.
		local s     = states[player.UserId]
		local entry = s and s.tracks[danceName]
		if not entry or entry.track ~= track or track.Length > 0 then return end
		brokenDances[danceName] = true
		warn(string.format(
			"[DanceHandler] animasi '%s' (id %s) gagal dimuat — cek kepemilikan asset",
			danceName, tostring(DANCES[danceName])
			))
	end)
end

local function ensureTrack(player, danceName)
	local track = getTrack(player, danceName)
	if not track then return nil end
	if track.Length > 0 or brokenDances[danceName] then return track end

	local deadline = os.clock() + CONFIG.LOAD_TIMEOUT
	while track.Length == 0 and os.clock() < deadline do
		task.wait()
	end

	if track.Length == 0 then checkBrokenLater(player, danceName, track) end
	return track
end

-- ═══════════════════════════════════════════════════════════
-- TRACK YANG SEDANG BERMAIN
-- ═══════════════════════════════════════════════════════════

local function findTrack(humanoid, danceName)
	for _, track in ipairs(DanceShared.playingTracks(humanoid)) do
		local animation = track.Animation
		if animation and animation.Name == danceName then return track end
	end
	return nil
end

local function stopDanceTracks(humanoid, except, fade)
	DanceShared.stopDanceTracks(humanoid, except, fade)
end

local function isDanceAlive(humanoid, danceName)
	if not danceName then return false end
	local track = findTrack(humanoid, danceName)
	return track ~= nil and track.IsPlaying and track.WeightTarget >= 0.5
end

return {
	getRig          = getRig,
	clearTracks     = clearTracks,
	getTrack        = getTrack,
	ensureTrack     = ensureTrack,
	findTrack       = findTrack,
	stopDanceTracks = stopDanceTracks,
	isDanceAlive    = isDanceAlive,
}
