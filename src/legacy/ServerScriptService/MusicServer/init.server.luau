-- ServerScriptService/MusicServer  (Script)
-- Bootstrap + handler aksi + lifecycle player. ModuleScript anak:
--   Library (library global + My Library), Playback (Sound & antrian),
--   Live (siaran lintas server), Permissions, RateLimit, Volume,
--   LibraryActions (aksi library global & My Library).
--   QueueActions (antrian, skip, live).
--
-- FIX PENTING:
--   Actions.ReportDuration dulu memanggil Playback.report(data.id, data.len,
--   data.failed) padahal signature-nya report(player, data). Semua laporan
--   client dibuang -> server tidak pernah tahu durasi lagu -> lagu macet /
--   tidak lanjut sampai hard timeout. Sekarang diteruskan apa adanya.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Shared   = require(RS:WaitForChild("MusicShared"))
local Library  = require(script:WaitForChild("Library"))
local Playback = require(script:WaitForChild("Playback"))
local Live     = require(script:WaitForChild("Live")) -- siaran live

-- ═══ IZIN & RATE LIMIT ════════════════════════════════════════════════════
local Perm = require(script:WaitForChild("Permissions"))
local isAdmin, isDJ, queueLimit = Perm.isAdmin, Perm.isDJ, Perm.queueLimit

local Rate   = require(script:WaitForChild("RateLimit"))
local Volume = require(script:WaitForChild("Volume"))
local LibraryActions = require(script:WaitForChild("LibraryActions"))
local QueueActions   = require(script:WaitForChild("QueueActions"))
local checkRate, isNum, allowReport = Rate.check, Rate.isNum, Rate.allowReport

-- ═══ BOOT ═════════════════════════════════════════════════════════════════
Library.load()
Library.backfill()
Library.bindToClose()

Playback.init()
Playback.applyMode(Shared.spatial.mode)
Playback.setGlobalVolume(Shared.defaultVolume)

-- Lagu yang mulai / diulang / berhenti di server ini dilaporkan ke Live
-- (hanya berefek kalau server ini sedang siaran). Status siaran ke semua pemain.
Playback.onSongStart = function(song) Live.songChanged(song, 0) end
Live.onChange(function(st)
	Playback.liveDjId = Live.djId() -- antrian DJ saja selama live
	Shared.all("LiveState", st)
end)
-- Server ini ikut siaran server lain: posisi = jam sekarang − jam mulai.
Live.onFollow(function(st)
	if not st then return Playback.unfollow() end
	local song = st.song and table.clone(st.song) or nil
	if song then song.Requester = "LIVE - DJ " .. tostring(st.dj) end
	local offset = st.startedAtMs and (DateTime.now().UnixTimestampMillis - st.startedAtMs) / 1000 or 0
	Playback.follow(song, offset)
end)

local playerData = {}
QueueActions.bind(playerData) -- batas antrian per pemain

local function saveVolDebounced(p)
	local d = playerData[p]
	if d then Volume.saveLater(p, d) end
end
-- Loudness dikirim ke SEMUA player (bukan cuma admin): client butuh nilai
-- terbaru untuk clone Sound mode darurat.
local function loudnessPayload()
	local L = Shared.loudness
	return {
		enabled = L.enabled, compMakeupGain = L.compMakeupGain,
		eqLow = L.eqLow, eqMid = L.eqMid, eqHigh = L.eqHigh,
	}
end

-- ═══ AKSI ═════════════════════════════════════════════════════════════════
-- Satu RequestState mengirim seluruh library + antrian + state ke satu pemain.
-- Dibatasi supaya tombol yang ditekan berkali-kali (atau paket ulang) tidak
-- memicu banjir data.
-- Peran + batas antrian, dikirim saat RequestState dan saat atribut peran berubah.
local function sendRole(p)
	Shared.to(p, "IsAdmin",    isAdmin(p))
	Shared.to(p, "IsDJ",       isDJ(p))
	Shared.to(p, "QueueLimit", { current = Playback.queueSize(), max = Shared.maxGlobalQueue, myLimit = queueLimit(p) })
end
-- Permintaan yang datang sebelum PlayerAdded diproses → dijawab
-- begitu data pemain siap (dulu dibuang, lalu ditambal push buta 0.5 & 3 dtk).
local pendingState = {}

local function requestState(p, data)
	local d = playerData[p]
	if not d then pendingState[p] = true; return end
	if not checkRate(p, "State", Shared.stateCooldown, true) then return end
	task.spawn(function()
		Shared.to(p, "SoundLocation", Playback.path())
		-- tombol reload hanya butuh status lagu, bukan library 130 KB;
		-- My Library dikirim lewat RequestMyLibrary / selesai dimuat (tidak dobel).
		if data ~= "reload" then Library.broadcast(p) end
		Shared.to(p, "QueueUpdate",  Playback.queue())
		Shared.to(p, "VolumeUpdate", d.volume or 0.7)
		sendRole(p)
		-- Setelan ruang dikirim ke SEMUA pemain: client memakainya untuk
		-- menempatkan salinan lokal saat audio server gagal dimuat.
		Shared.to(p, "SpatialSettings", table.clone(Shared.spatial))
		Shared.to(p, "LoudnessSync", loudnessPayload())
		Shared.to(p, "LiveState", Live.state())

		local np = Playback.current()
		if np then
			np = table.clone(np)
			np.Elapsed = Playback.elapsed()
		else
			np = { Name = "No song playing", Requester = "" }
		end
		Shared.to(p, "NowPlaying",     np)
		Shared.to(p, "SkipVoteUpdate", Playback.votes())
		Shared.to(p, "QueueIds",       Playback.queueIds())
	end)
end

local function setVolume(p, vol)
	if type(vol) ~= "number" or vol ~= vol then return end
	local d = playerData[p]
	if not d then return end
	d.volume = math.clamp(vol, 0, 1)
	saveVolDebounced(p)
end

local function setSpatialSettings(p, s)
	if not isAdmin(p)     then return Shared.to(p, "SettingsError", "Admin only!") end
	if type(s) ~= "table" then return Shared.to(p, "SettingsError", "Invalid data") end

	local cfg, modeChanged = Shared.spatial, false -- isNum: tolak NaN
	if s.mode ~= nil then
		if s.mode ~= "stage" and s.mode ~= "global" then
			return Shared.to(p, "SettingsError", "Invalid music mode")
		end
		if cfg.mode ~= s.mode then cfg.mode = s.mode; modeChanged = true end
	end

	if isNum(s.min)     then cfg.min    = math.clamp(s.min,     1, 10000) end
	if isNum(s.max)     then cfg.max    = math.clamp(s.max,    10, 10000) end
	if isNum(s.size)    then cfg.size   = math.clamp(s.size,    1, 1000)  end
	if isNum(s.volume)  then cfg.volume = math.clamp(s.volume,  0, 1)     end
	if cfg.max <= cfg.min then cfg.max = cfg.min + 50 end
	if type(s.autoplay) == "boolean" and cfg.autoplay ~= s.autoplay then
		cfg.autoplay = s.autoplay
		if cfg.autoplay and not Playback.isPlaying() and not Playback.isFollowing() then task.defer(Playback.next) end
	end

	if modeChanged then Playback.applyMode(cfg.mode) else Playback.applySpatial(cfg) end
	Playback.setGlobalVolume(cfg.volume)

	local L = Shared.loudness
	if type(s.loudnessEnabled) == "boolean" then L.enabled        = s.loudnessEnabled end
	if isNum(s.compMakeupGain)    then L.compMakeupGain = math.clamp(s.compMakeupGain, 0, 30) end
	if isNum(s.eqLow)   then L.eqLow  = math.clamp(s.eqLow,  -12, 12) end
	if isNum(s.eqMid)   then L.eqMid  = math.clamp(s.eqMid,  -12, 12) end
	if isNum(s.eqHigh)  then L.eqHigh = math.clamp(s.eqHigh, -12, 12) end
	Playback.applyLoudness()
	Shared.all("LoudnessSync", loudnessPayload())

	Shared.all("SpatialSettings", table.clone(cfg))
end

local Actions = {
	SetVolume          = setVolume,
	SetSpatialSettings = setSpatialSettings,
	RequestState       = requestState,

	-- Client melaporkan durasi asli / posisi / kegagalan load. Server tidak
	-- me-render audio, jadi ini satu-satunya sumber yang bisa dipercaya.
	ReportDuration     = function(p, data) if allowReport(p) then Playback.report(p, data) end end,
}

for name, h in pairs(LibraryActions.handlers) do Actions[name] = h end
for name, h in pairs(QueueActions.handlers) do Actions[name] = h end

Shared.remote.OnServerEvent:Connect(function(p, action, data)
	if type(action) ~= "string" or not p or not p.Parent then return end
	local h = Actions[action]
	if not h then return end
	local ok, err = pcall(h, p, data)
	if not ok then warn("[Music] aksi '" .. action .. "' error:", err) end
end)

-- ═══ LIFECYCLE PLAYER ═════════════════════════════════════════════════════
local function initPlayer(p)
	playerData[p] = { volume = 0.7, queueLimit = queueLimit(p) }

	task.spawn(function()
		local v = Volume.load(p)
		if playerData[p] then
			playerData[p].volume = v
			Shared.to(p, "VolumeUpdate", v)
		end
	end)

	LibraryActions.onJoin(p)

	-- Tidak ada lagi push buta 0.5 & 3 dtk (library terkirim 2-3x).
	-- Client meminta sendiri saat UI-nya siap; yang terlanjur datang dijawab di sini.
	if pendingState[p] then
		pendingState[p] = nil
		requestState(p)
	end

	local function onRankChanged()
		local d = playerData[p]
		if not p.Parent or not d then return end
		d.queueLimit = queueLimit(p)
		sendRole(p)
		if isAdmin(p) then Shared.to(p, "SpatialSettings", table.clone(Shared.spatial)) end
	end
	for _, attr in ipairs({ "IsAdmin", "IsOwner", "IsVIP", "IsPremium", "GroupRank", "HasVIPGamepass", "HasVVIPGamepass", "Role", "QueueLimit" }) do -- Role: peran DJ
		pcall(function() p:GetAttributeChangedSignal(attr):Connect(onRankChanged) end)
	end
end

local function cleanupPlayer(p)
	task.spawn(function()
		Library.myFlush(p)
		Library.myUnload(p)
	end)
	Playback.clearVote(p)
	if Playback.removeQueueByRequester(p.UserId) > 0 then -- antrian pemain yang keluar dihapus
		Playback.broadcastQueue()
		Playback.broadcastIds()
	end
	Live.playerLeft(p) -- DJ keluar → siaran berhenti
	pendingState[p] = nil
	LibraryActions.forget(p)
	Rate.forget(p) -- jeda & kuota laporan

	local d = playerData[p]
	if not d then return end
	Volume.flush(p, d) -- ditulis hanya kalau diubah
	playerData[p] = nil
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(initPlayer, p) end

-- Auto play mulai begitu ada pendengar (server kosong tidak memutar apa pun).
local function kickAutoplay()
	task.delay(2, function()
		if Shared.spatial.autoplay and not Playback.isPlaying() and not Playback.isFollowing() and #Players:GetPlayers() > 0 then
			Playback.next()
		end
	end)
end
Players.PlayerAdded:Connect(kickAutoplay)
kickAutoplay()

-- DJ tiba dari server lain di tengah siaran → ambil alih otomatis.
-- Dicoba 2x karena atribut peran (IsAdmin/Role) dipasang beberapa detik setelah join.
local function tryTakeover(p)
	if not p.Parent or Live.isActive() or not isDJ(p) then return end
	if not Live.handoverFor(p.UserId) then return end
	if Playback.isFollowing() then Playback.adopt() end
	local ok, err = Live.start(p, Playback.current(), Playback.elapsed(), true)
	if ok then
		Shared.to(p, "LiveState", Live.state())
	else
		warn("[Live] ambil alih gagal:", err)
	end
end
Players.PlayerAdded:Connect(function(p)
	task.delay(4, tryTakeover, p)
	task.delay(10, tryTakeover, p)
end)

print("✅ MusicServer ready")