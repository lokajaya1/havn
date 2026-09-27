-- MusicClient/Audio  (ModuleScript)
-- Semua urusan audio sisi client: melacak Sound milik server, volume personal,
-- fade in/out, dan mode darurat (clone Sound lokal).
--
-- Audio.hardResync(data, auto) juga dipakai sebagai penyelamat OTOMATIS saat
-- Sound milik server terbukti gagal dimuat di mesin ini. Sound server di-mute
-- lokal, clone lokal yang berbunyi, dan client tetap melaporkan posisi ke
-- server sehingga antrian tetap jalan.

local ContentProvider = game:GetService("ContentProvider")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = require(RS:WaitForChild("MusicShared"))
local UI     = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer
local Audio  = {}

-- Setelan ruang dari server. Dipakai untuk menempatkan salinan lokal supaya
-- terdengar SAMA dengan Sound milik server (di mode stage tetap ada jarak).
local spatial = { mode = "global", min = 10, max = 500, size = 100 }

local current            -- Sound aktif (milik server, atau clone darurat)
local ancestryConn, fadeConn
local lastPath = ""
local volume   = 0.7     -- volume personal player
local fade     = 1       -- pengali transisi 0..1, TERPISAH dari volume personal
-- [FIX M5] Volume global dari admin (Admin Settings → Global). Yang terdengar =
-- pribadi × global. Dulu nilai server tereplikasi ke Sound dan MENIMPA volume
-- pribadi semua pemain sampai lagu berganti.
local globalVol = 1
local volConn
local lastSongId

-- ── mencari Sound ─────────────────────────────────────────────────────────
-- HANYA nama persis Shared.soundName (sama seperti server), supaya tidak
-- nyangkut ke ambient/sfx milik sistem lain.
function Audio.find()
	local stage = workspace:FindFirstChild(Shared.stageName)
	if stage then
		local s = stage:FindFirstChild(Shared.soundName)
		if s and s:IsA("Sound") then return s end
	end
	local direct = workspace:FindFirstChild(Shared.soundName)
	if direct and direct:IsA("Sound") then return direct end
	local ss = SoundService:FindFirstChild(Shared.soundName)
	if ss and ss:IsA("Sound") then return ss end
	return nil
end

function Audio.get()       return current end
function Audio.lastPath()  return lastPath end
function Audio.getVolume() return volume end

function Audio.apply()
	if not current or not current.Parent then return end
	pcall(function() current.Volume = volume * fade * globalVol end) -- [FIX M5]
end

function Audio.setVolume(v)
	volume = math.clamp(v or 0, 0, 1)
	Audio.apply()
end

-- [FIX M5]
function Audio.setGlobalVolume(v)
	if type(v) ~= "number" or v ~= v then return end
	globalVol = math.clamp(v, 0, 1)
	Audio.apply()
end

-- [FIX M7] Dipakai penyembuh otomatis di init.client.
function Audio.getFade() return fade end
function Audio.isFading() return fadeConn ~= nil end
-- ── fade halus (smoothstep) ───────────────────────────────────────────────
function Audio.fadeTo(target, duration)
	target = math.clamp(target or 0, 0, 1)
	if fadeConn then fadeConn:Disconnect(); fadeConn = nil end
	if not duration or duration <= 0 then
		fade = target
		Audio.apply()
		return
	end
	local from, t0 = fade, os.clock()
	fadeConn = RunService.Heartbeat:Connect(function()
		local a = (os.clock() - t0) / duration
		if a >= 1 then
			fade = target
			Audio.apply()
			if fadeConn then fadeConn:Disconnect(); fadeConn = nil end
			return
		end
		fade = from + (target - from) * (a * a * (3 - 2 * a))
		Audio.apply()
	end)
end

-- Lagu berganti -> fade-in dari senyap. Kalau id-nya sama (mis. cuma reload
-- state), jangan nge-dip lagi.
function Audio.onNowPlaying(id)
	if not id then
		lastSongId = nil
		Audio.fadeTo(0, Shared.fadeOut)
		return
	end
	if id == lastSongId then return end
	lastSongId = id
	fade = 0
	Audio.apply()
	Audio.fadeTo(1, Shared.fadeIn)
end

-- ── melacak Sound ─────────────────────────────────────────────────────────
local function resolvePath(path)
	if not path or path == "" then return nil end
	local found
	pcall(function()
		local cur = game
		for _, part in ipairs(string.split(path, ".")) do
			if     part == "Workspace"    then cur = workspace
			elseif part == "SoundService" then cur = SoundService
			else   cur = cur:FindFirstChild(part) end
			if not cur then return end
		end
		if cur and cur:IsA("Sound") then found = cur end
	end)
	return found
end

-- [FIX M5] Server mengubah Sound.Volume (volume global) → nilai itu tereplikasi
-- dan menimpa nilai lokal. Begitu terjadi, volume pribadi × global dipasang lagi.
local function watchVolume()
	if volConn then volConn:Disconnect(); volConn = nil end
	local snd = current
	if not snd then return end
	volConn = snd:GetPropertyChangedSignal("Volume"):Connect(function()
		if current ~= snd then return end
		if math.abs(snd.Volume - volume * fade * globalVol) > 1e-3 then Audio.apply() end
	end)
end
local function bindAncestry()
	if ancestryConn then ancestryConn:Disconnect(); ancestryConn = nil end
	watchVolume() -- [FIX M5]
	if not current then return end
	ancestryConn = current.AncestryChanged:Connect(function()
		if current and current.Parent then return end
		current = nil
		task.delay(1, function()
			if current then return end
			current = Audio.find()
			bindAncestry()
			Audio.apply()
		end)
	end)
end

function Audio.track(path)
	if path and path ~= "" then lastPath = path end

	-- Bongkar clone darurat lama supaya tidak dobel dengan Sound server.
	if current and current.Parent and current:GetAttribute("LocalResync") then
		pcall(function() current:Stop() end)
		pcall(function() current:Destroy() end)
		current = nil
	end

	local found = resolvePath(path) or Audio.find()
	if not found then
		if ancestryConn then ancestryConn:Disconnect(); ancestryConn = nil end
		task.delay(3, function()
			current = Audio.find()
			bindAncestry()
			Audio.apply()
		end)
		return
	end

	current = found
	bindAncestry()
	Audio.apply()
end

function Audio.isEmergency()
	return current ~= nil and current:GetAttribute("LocalResync") == true
end

function Audio.emergencySoundId()
	if not current then return nil end
	return tostring(current.SoundId):match("%d+")
end

-- ── penempatan salinan lokal ──────────────────────────────────────────────
-- Mode "global": non-positional di SoundService.
-- Mode "stage" : ikut di-parent ke MusicStage + roll-off yang sama, supaya
-- pemain tidak tiba-tiba mendengar musik dari seluruh map saat mode darurat.
local function placeClone(s)
	if spatial.mode == "stage" then
		local stage = workspace:FindFirstChild(Shared.stageName)
		if stage and stage:IsA("BasePart") then
			s.Parent = stage
			pcall(function()
				s.RollOffMode        = Enum.RollOffMode.Linear
				s.RollOffMinDistance = spatial.min  or 10
				s.RollOffMaxDistance = spatial.max  or 500
				s.EmitterSize        = spatial.size or 100
			end)
			return
		end
	end
	s.Parent = SoundService
end

function Audio.setSpatial(cfg)
	if type(cfg) ~= "table" then return end
	for _, k in ipairs({ "mode", "min", "max", "size" }) do
		if cfg[k] ~= nil then spatial[k] = cfg[k] end
	end
	if Audio.isEmergency() and current then placeClone(current) end
end

-- ── pra-muat & pemeriksaan aset ───────────────────────────────────────────
-- INI kunci masalah "HTTP 502 tepat saat lagu ganti": aset baru diminta ke CDN
-- pada detik lagu itu mulai. Dengan memuatnya lebih dulu selagi lagu sekarang
-- masih jalan, saat gilirannya tiba aset sudah ada di cache.
local preloaded = {}

function Audio.preload(rawId)
	local id = Shared.rawId(rawId)
	if not id or preloaded[id] then return end

	local n = 0
	for _ in pairs(preloaded) do n += 1 end
	if n > 120 then preloaded = {} end
	preloaded[id] = true

	task.spawn(function()
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. id
		s.Volume  = 0
		s.Parent  = SoundService
		pcall(function() ContentProvider:PreloadAsync({ s }) end)
		s:Destroy()
	end)
end

-- Menjawab pertanyaan yang tidak bisa dijawab Sound.IsLoaded: asetnya yang
-- rusak, atau instance Sound-nya yang nyangkut? PreloadAsync memberi status
-- per aset, jadi kita tidak perlu menebak lewat timer panjang.
-- MEMBLOKIR (yield) — panggil dari thread terpisah.
function Audio.probe(rawId)
	local id = Shared.rawId(rawId)
	if not id then return false end
	local probe = Instance.new("Sound")
	probe.SoundId = "rbxassetid://" .. id
	probe.Volume  = 0
	probe.Parent  = SoundService

	local ok = false
	pcall(function()
		ContentProvider:PreloadAsync({ probe }, function(_, status)
			ok = (status == Enum.AssetFetchStatus.Success)
		end)
	end)
	probe:Destroy()
	if ok then preloaded[id] = true end
	return ok
end

-- ── mode darurat / penyelamat otomatis ────────────────────────────────────
function Audio.hardResync(data, auto, quiet) -- [FIX M7] quiet: tanpa notifikasi (penyembuh otomatis)
	local id = data and data.Id and tostring(data.Id):match("%d+")
	if not id then
		if not auto then UI.notify("No song to reload", UI.C.danger, 2) end
		return false
	end

	if ancestryConn then ancestryConn:Disconnect(); ancestryConn = nil end

	local prev = current
	if prev and prev.Parent then
		if prev:GetAttribute("LocalResync") then
			pcall(function() prev:Stop() end)
			pcall(function() prev:Destroy() end)
		else
			-- Sound MILIK SERVER: jangan :Stop() dari client -- server terus
			-- me-replikasi status Playing-nya sehingga langsung nyala lagi dan
			-- bentrok. Cukup mute lokal; Audio.track() nanti meng-unmute.
			pcall(function() prev.Volume = 0 end)
		end
	end

	-- Bersihkan sisa clone lama kalau ada.
	for _, c in ipairs(SoundService:GetChildren()) do
		if c:IsA("Sound") and c:GetAttribute("LocalResync") and c ~= prev then
			pcall(function() c:Destroy() end)
		end
	end

	local s = Instance.new("Sound")
	s.Name    = "LocalMusicResync_" .. player.UserId
	s.SoundId = "rbxassetid://" .. id
	s.Looped  = false
	s.Volume  = volume
	s:SetAttribute("LocalResync", true)
	placeClone(s)

	-- Clone ini instance terpisah -> tidak mewarisi SoundEffect server, jadi
	-- rantai loudness dipasang manual dari nilai yang sudah disinkron.
	Shared.applyLoudness(s)

	local played = false
	local function play()
		if played or not s.Parent then return end
		played = true
		pcall(function() s.TimePosition = math.max(0, data.Elapsed or 0) end)
		s:Play()
	end

	-- Cek IsLoaded DULU: kalau audio sudah ter-cache, event Loaded tidak fire.
	if s.IsLoaded then
		play()
	else
		local conn
		conn = s.Loaded:Once(function()
			play()
			if conn then conn:Disconnect() end
		end)
		task.delay(6, play)
	end

	current = s
	fade = 1
	Audio.apply()

	-- Kalau salinan lokal ikut gagal dimuat, jangan biarkan pemain terjebak
	-- pada Sound mati: kembalikan ke Sound server (sekaligus meng-unmute-nya),
	-- siapa tahu di sana justru berhasil menyusul.
	task.delay(8, function()
		if current ~= s or not s.Parent then return end
		local okRead, loaded, len = pcall(function() return s.IsLoaded, s.TimeLength end)
		if okRead and (loaded == true or (len and len > 0)) then return end
		if not quiet then UI.notify("Audio unavailable on your device", UI.C.danger, 3) end -- [FIX M7]
		Audio.track(lastPath)
	end)

	-- selene: allow(empty_if)
	if quiet then -- [FIX M7]
	elseif auto then
		UI.notify("Playing locally", UI.C.accent, 2)
	else
		UI.notify("Local playback active", UI.C.accent, 2)
	end
	return true
end

-- Server mengirim ini ke SEMUA player supaya nilai loudness lokal (dipakai
-- clone darurat) selalu sinkron real-time.
function Audio.syncLoudness(data)
	if not data then return end
	for _, k in ipairs({ "enabled", "compMakeupGain", "eqLow", "eqMid", "eqHigh" }) do
		if data[k] ~= nil then Shared.loudness[k] = data[k] end
	end
	if Audio.isEmergency() then Shared.applyLoudness(current) end
end

function Audio.cleanup()
	if ancestryConn then ancestryConn:Disconnect(); ancestryConn = nil end
	if volConn     then volConn:Disconnect();     volConn = nil end -- [FIX M5]
	if fadeConn     then fadeConn:Disconnect();     fadeConn = nil end
	for _, c in ipairs(SoundService:GetChildren()) do
		if c:IsA("Sound") and c:GetAttribute("LocalResync") then
			pcall(function() c:Destroy() end)
		end
	end
	current = nil
end

current = Audio.find()
bindAncestry()

return Audio