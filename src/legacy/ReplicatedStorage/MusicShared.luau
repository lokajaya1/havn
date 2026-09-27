-- ReplicatedStorage/MusicShared  (ModuleScript)
-- Config + rantai loudness + RemoteEvent. Server dan client sama-sama
-- require file ini, jadi tidak ada tabel setting yang diduplikasi.
-- Catatan: server & client masing-masing punya SALINAN tabel ini, jadi
-- Shared.loudness di client boleh ditimpa "LoudnessSync" tanpa mempengaruhi
-- server.

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}

-- ── nama instance ─────────────────────────────────────────────────────────
M.remoteName = "MusicRequest"
M.soundName  = "GlobalMusic"
M.stageName  = "MusicStage"

-- ── batas & cooldown ──────────────────────────────────────────────────────
M.maxGlobalQueue   = 30
M.maxSharedLib     = 1200
M.maxPersonalLib   = 300     -- batas "Library Saya" per player
M.autoSaveInterval = 300
M.addSongCooldown  = 5
M.addQueueCooldown = 2
M.favCooldown      = 0.4
M.nameCacheTTL     = 3600
M.defaultVolume    = 1.0

-- ── TIMING PLAYBACK (inti fix "lagu keskip / macet") ──────────────────────
-- loadTimeout  : lama menunggu bukti audio benar-benar loaded.
-- endGrace     : buffer di ujung lagu untuk watchdog jam dinding.
-- spuriousGap  : ambang "Sound.Ended fire kepagian" = event palsu.
-- minPlayTime  : LANTAI. Tidak ada jalur otomatis yang boleh memajukan
--                antrian sebelum ini lewat. Skip manual/vote menembus lantai.
-- maxLoadRetry : berapa kali server mengulang :Play() lagu yang sama sebelum
--                lagu divonis gagal (HTTP 502 / Timedout itu sementara).
M.loadTimeout  = 25
M.endGrace     = 3
M.spuriousGap  = 2
M.probeDelay   = 5    -- lama menunggu sebelum client memeriksa aset ke CDN
M.minPlayTime  = 8
M.maxLoadRetry = 2

M.fadeIn  = 0.55
M.fadeOut = 0.45

-- [FIX L1b] Peran (atribut Role dari UnifiedRankManager) yang boleh jadi DJ siaran
-- live, selain admin. Tambah nama peran di sini kalau perlu.
M.liveDjRoles = { "DJGANTENG" }
M.spatial = { min = 10, max = 500, size = 100, volume = 1.0, mode = "global", autoplay = true } -- [FIX A1] autoplay: antrian kosong → lagu acak

M.loudness = {
	enabled        = true,
	compThreshold  = -20,
	compRatio      = 10,
	compAttack     = 0.1,
	compRelease    = 0.3,
	compMakeupGain = 15,
	eqLow          = 2,
	eqMid          = 3,
	eqHigh         = 3,
}

-- ── helper id ─────────────────────────────────────────────────────────────
function M.rawId(v)
	return v and tostring(v):match("%d+") or nil
end

function M.assetId(v)
	local raw = M.rawId(v)
	return raw and ("rbxassetid://" .. raw) or nil
end

-- ── rantai loudness ───────────────────────────────────────────────────────
-- Idempotent: aman dipanggil berkali-kali, tidak bikin SoundEffect dobel.
local function ensure(sound, className, name)
	local fx = sound:FindFirstChild(name)
	if not fx then
		fx = Instance.new(className)
		fx.Name = name
		fx.Parent = sound
	end
	return fx
end

function M.applyLoudness(sound)
	if not sound or typeof(sound) ~= "Instance" or not sound:IsA("Sound") then return end
	local L    = M.loudness
	local comp = ensure(sound, "CompressorSoundEffect", "MusicCompressor")
	local eq   = ensure(sound, "EqualizerSoundEffect",  "MusicEqualizer")

	if not L.enabled then
		pcall(function() comp.Enabled = false end)
		pcall(function() eq.Enabled   = false end)
		return
	end
	pcall(function()
		comp.Threshold  = L.compThreshold
		comp.Ratio      = L.compRatio
		comp.Attack     = L.compAttack
		comp.Release    = L.compRelease
		comp.GainMakeup = L.compMakeupGain
		comp.Priority   = 0
		comp.Enabled    = true
	end)
	pcall(function()
		eq.LowGain  = L.eqLow
		eq.MidGain  = L.eqMid
		eq.HighGain = L.eqHigh
		eq.Priority = 1
		eq.Enabled  = true
	end)
end

-- ── remote ────────────────────────────────────────────────────────────────
local remote
if RunService:IsServer() then
	remote = RS:FindFirstChild(M.remoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = M.remoteName
		remote.Parent = RS
	end
else
	remote = RS:WaitForChild(M.remoteName)
end
M.remote = remote

-- Helper kirim (server). Client cukup pakai M.remote:FireServer(...).
function M.to(p, action, data)
	if not p or not p.Parent then return end
	pcall(remote.FireClient, remote, p, action, data)
end

function M.all(action, data)
	for _, p in ipairs(Players:GetPlayers()) do
		pcall(remote.FireClient, remote, p, action, data)
	end
end

function M.filtered(predicate, action, data)
	for _, p in ipairs(Players:GetPlayers()) do
		if predicate(p) then pcall(remote.FireClient, remote, p, action, data) end
	end
end

return M