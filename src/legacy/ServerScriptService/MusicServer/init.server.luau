-- ServerScriptService/MusicServer  (Script)
-- Bootstrap + handler aksi + lifecycle player. [FIX R5] ModuleScript anak:
--   Library (library global + My Library), Playback (Sound & antrian),
--   Live (siaran lintas server), Permissions, RateLimit, Volume.
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
local Live     = require(script:WaitForChild("Live")) -- [FIX L1] siaran live

-- ═══ IZIN & RATE LIMIT ════════════════════════════════════════════════════
local Perm = require(script:WaitForChild("Permissions")) -- [FIX R5]
local isAdmin, isPremium, isDJ = Perm.isAdmin, Perm.isPremium, Perm.isDJ
local liveBlocks, skipBlocked, queueLimit = Perm.liveBlocks, Perm.skipBlocked, Perm.queueLimit

local Rate   = require(script:WaitForChild("RateLimit"))
local Volume = require(script:WaitForChild("Volume"))
local checkRate, isNum, allowReport = Rate.check, Rate.isNum, Rate.allowReport

-- ═══ BOOT ═════════════════════════════════════════════════════════════════
Library.load()
Library.backfill()
Library.bindToClose()

Playback.init()
Playback.applyMode(Shared.spatial.mode)
Playback.setGlobalVolume(Shared.defaultVolume)

-- [FIX L1] Lagu yang mulai / diulang / berhenti di server ini dilaporkan ke Live
-- (hanya berefek kalau server ini sedang siaran). Status siaran ke semua pemain.
Playback.onSongStart = function(song) Live.songChanged(song, 0) end
Live.onChange(function(st)
	Playback.liveDjId = Live.djId() -- [FIX M6b] antrian DJ saja selama live
	Shared.all("LiveState", st)
end)
-- [FIX L2] Server ini ikut siaran server lain: posisi = jam sekarang − jam mulai.
Live.onFollow(function(st)
	if not st then return Playback.unfollow() end
	local song = st.song and table.clone(st.song) or nil
	if song then song.Requester = "LIVE - DJ " .. tostring(st.dj) end
	local offset = st.startedAtMs and (DateTime.now().UnixTimestampMillis - st.startedAtMs) / 1000 or 0
	Playback.follow(song, offset)
end)

local playerData = {}

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
-- [FIX R4] Peran + batas antrian, dikirim saat RequestState dan saat atribut peran berubah.
local function sendRole(p)
	Shared.to(p, "IsAdmin",    isAdmin(p))
	Shared.to(p, "IsDJ",       isDJ(p)) -- [FIX L1b]
	Shared.to(p, "QueueLimit", { current = Playback.queueSize(), max = Shared.maxGlobalQueue, myLimit = queueLimit(p) })
end
-- [FIX R2] Permintaan yang datang sebelum PlayerAdded diproses → dijawab
-- begitu data pemain siap (dulu dibuang, lalu ditambal push buta 0.5 & 3 dtk).
local pendingState = {}

local function requestState(p, data)
	local d = playerData[p]
	if not d then pendingState[p] = true; return end
	if not checkRate(p, "State", 1.5, true) then return end
	task.spawn(function()
		Shared.to(p, "SoundLocation", Playback.path())
		-- [FIX R2] tombol reload hanya butuh status lagu, bukan library 130 KB;
		-- My Library dikirim lewat RequestMyLibrary / selesai dimuat (tidak dobel).
		if data ~= "reload" then Library.broadcast(p) end
		Shared.to(p, "QueueUpdate",  Playback.queue())
		Shared.to(p, "VolumeUpdate", d.volume or 0.7)
		sendRole(p)
		-- Setelan ruang dikirim ke SEMUA pemain: client memakainya untuk
		-- menempatkan salinan lokal saat audio server gagal dimuat.
		Shared.to(p, "SpatialSettings", table.clone(Shared.spatial))
		Shared.to(p, "LoudnessSync", loudnessPayload())
		Shared.to(p, "LiveState", Live.state()) -- [FIX L1]

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

-- ── LIBRARY GLOBAL (admin) ────────────────────────────────────────────────
local function addSong(p, data)
	if type(data) ~= "table" or not data.Id then return Shared.to(p, "SongError", "Invalid request") end
	if not isAdmin(p) then return Shared.to(p, "SongError", "Admins only") end

	local rawId = Shared.rawId(data.Id)
	if not rawId then return Shared.to(p, "SongError", "Invalid ID") end

	local ok, msg = checkRate(p, "AddSong", Shared.addSongCooldown)
	if not ok then return Shared.to(p, "SongError", msg) end

	local id = "rbxassetid://" .. rawId
	if Library.find(id) then return Shared.to(p, "SongError", "Already in the library") end
	if Library.isFull() then return Shared.to(p, "SongError", "Library is full") end

	task.spawn(function()
		Shared.to(p, "SongValidating", Shared.loadTimeout)
		local valid, info = Library.validate(rawId)
		if not valid        then return Shared.to(p, "SongError", info) end
		if Library.find(id) then return Shared.to(p, "SongError", "Already added") end

		Library.insert(Library.fromInfo(rawId, info, { -- [FIX R4]
			Requester = p.Name, RequesterId = p.UserId, AddedTime = os.time(),
		}))
		Library.broadcast()
		Library.save()
		Shared.to(p, "SongAdded", info.name)
	end)
end

local function removeSong(p, songId)
	if not songId then return Shared.to(p, "SongError", "Invalid request") end
	local idx, song = Library.find(tostring(songId))
	if not idx then return Shared.to(p, "SongError", "Not found") end

	local mine = song.RequesterId == p.UserId
		or (not song.RequesterId and song.Requester == p.Name)
	if not mine and not isAdmin(p) then
		return Shared.to(p, "SongError", "You can only remove your own songs")
	end

	Library.removeAt(idx)
	Playback.removeFromQueueById(song.Id)
	Library.myPurge(song.Id)
	Library.broadcast()
	Playback.broadcastQueue()
	Playback.broadcastIds()
	Shared.to(p, "SongRemoved", song.Name)
	Library.saveNow()
end

-- ── LIBRARY SAYA (semua player) ───────────────────────────────────────────
-- [FIX R2] My Library hanya dikirim kalau diminta client. Diminta saat masih
-- dimuat → dikirim SEKALI begitu selesai (dulu terkirim 3-4x saat join).
local wantMy = {}
local function sendMyIfWanted(p)
	if wantMy[p] and p.Parent then
		wantMy[p] = nil
		Library.myBroadcast(p)
	end
end

local function requestMyLibrary(p)
	if Library.myIsLoaded(p) then return Library.myBroadcast(p) end
	wantMy[p] = true
	task.spawn(function()
		Library.myLoad(p)
		sendMyIfWanted(p)
	end)
end

-- Toggle favorit: kalau lagu sudah ada di Library Saya -> dihapus,
-- kalau belum -> disalin dari library global.
-- Semua aksi Library Saya memuat datanya lebih dulu (idempotent), jadi tidak
-- pernah ada penolakan "masih dimuat" yang bikin tombol ♥ terasa mati.
local function toggleFavorite(p, songId)
	if not songId then return end
	local ok, msg = checkRate(p, "Fav", Shared.favCooldown)
	if not ok then return Shared.to(p, "MyLibError", msg) end

	task.spawn(function()
		Library.myLoad(p)
		if not p.Parent then return end

		local id = tostring(songId)
		local idx, existing = Library.myFind(p, id)
		if idx then
			Library.myRemoveAt(p, idx)
			Library.myBroadcast(p)
			return Shared.to(p, "FavUpdate", { added = false, name = existing and existing.Name or "?" })
		end

		local _, song = Library.find(id)
		if not song then return Shared.to(p, "MyLibError", "Song is not in the library") end

		local added, res = Library.myAdd(p, Library.meta(song, { source = "fav", AddedTime = os.time() })) -- [FIX R4]
		if not added then return Shared.to(p, "MyLibError", res) end

		Library.myBroadcast(p)
		Shared.to(p, "FavUpdate", { added = true, name = song.Name })
	end)
end

-- Player menambah lagu sendiri. Terbuka untuk SEMUA player (admin juga), dan
-- hanya masuk Library Saya milik pengirim.
local function addMySong(p, data)
	local rawId = Shared.rawId(type(data) == "table" and data.Id or data)
	if not rawId then return Shared.to(p, "MyLibError", "Invalid ID") end

	local ok, msg = checkRate(p, "AddMySong", Shared.addSongCooldown)
	if not ok then return Shared.to(p, "MyLibError", msg) end

	task.spawn(function()
		Library.myLoad(p)
		if not p.Parent then return end

		local id = "rbxassetid://" .. rawId
		if Library.myFind(p, id) then return Shared.to(p, "MyLibError", "Already in My Library") end
		if Library.myIsFull(p)   then return Shared.to(p, "MyLibError", "My Library is full") end

		-- Metadata dipakai ulang dari library global kalau lagunya sudah ada
		-- di sana: hemat panggilan Marketplace API.
		local _, exist = Library.find(id)
		local entry
		if exist then
			entry = Library.meta(exist, { source = "own", AddedTime = os.time() }) -- [FIX R4]
		else
			Shared.to(p, "SongValidating", Shared.loadTimeout)
			local valid, info = Library.validate(rawId)
			if not valid then return Shared.to(p, "MyLibError", info) end
			if not p.Parent then return end
			entry = Library.fromInfo(rawId, info, { source = "own", AddedTime = os.time() })
		end

		local added, res = Library.myAdd(p, entry)
		if not added then return Shared.to(p, "MyLibError", res) end

		Library.myBroadcast(p)
		Shared.to(p, "MySongAdded", entry.Name)
	end)
end

local function removeMySong(p, songId)
	if not songId then return end
	local okRate, msg = checkRate(p, "RemoveMySong", Shared.favCooldown) -- [FIX M3]
	if not okRate then return Shared.to(p, "MyLibError", msg) end
	task.spawn(function()
		Library.myLoad(p)
		if not p.Parent then return end
		local removed = Library.myRemove(p, tostring(songId))
		if not removed then return Shared.to(p, "MyLibError", "Not in My Library") end
		Library.myBroadcast(p)
		Shared.to(p, "FavUpdate", { added = false, name = removed.Name or "?" })
	end)
end

-- ── ANTRIAN ───────────────────────────────────────────────────────────────
local function addToQueue(p, songId)
	if not songId then return end
	if liveBlocks(p) then return Shared.to(p, "QueueError", "Live: song requests are paused") end -- [FIX L1b] [FIX M6]

	local ok, msg = checkRate(p, "AddQueue", Shared.addQueueCooldown)
	if not ok then return Shared.to(p, "QueueError", msg) end

	local id = tostring(songId)
	local _, song = Library.find(id)
	if not song then
		-- Boleh antre dari Library Saya walau tidak ada di library global.
		if not Library.myIsLoaded(p) then Library.myLoad(p) end
		local _, own = Library.myFind(p, id)
		song = own
	end

	if not song         then return Shared.to(p, "QueueError", "Song is not in the library") end
	if song.unavailable then return Shared.to(p, "QueueError", "Song unavailable") end

	local np = Playback.current()
	if np and np.Id == song.Id         then return Shared.to(p, "QueueError", "Already playing") end
	if Playback.queueContains(song.Id) then return Shared.to(p, "QueueError", "Already in the queue") end
	if Playback.queueFull() then
		return Shared.to(p, "QueueError", "Queue is full (" .. Shared.maxGlobalQueue .. ")")
	end

	local d = playerData[p]
	if not d then return Shared.to(p, "QueueError", "Your data is not ready yet") end
	local limit   = d.queueLimit or 1
	local myCount = Playback.queueCountBy(p.UserId)
	if myCount >= limit then
		return Shared.to(p, "QueueError",
			("Your queue limit is %d (currently %d)"):format(limit, myCount))
	end

	local entry = Playback.entry(song, p.Name, p.UserId) -- [FIX R4]

	local held = Playback.isFollowing() or (Live.isActive() and p.UserId ~= Live.djId()) -- [FIX M6b]
	if not Playback.isPlaying() and not held then -- [FIX L2] saat ikut siaran: masuk antrian lokal
		Playback.play(entry)
		Playback.broadcastQueue()
		Playback.broadcastIds()
		return
	end

	Playback.enqueue(entry, isPremium(p), isPremium)
	Playback.broadcastQueue()
	Playback.broadcastIds()
	if held then Shared.to(p, "QueueRemoveSuccess", "Queued - on hold until the live ends") end -- [FIX M6b]
end

local function removeFromQueue(p, data)
	local idx = type(data) == "table" and data.index or data
	local id  = type(data) == "table" and data.id or nil
	local okRate, msg = checkRate(p, "RemoveQueue", 0.5) -- [FIX M3]
	if not okRate then return Shared.to(p, "QueueError", msg) end
	if type(idx) == "number" and idx ~= idx then return Shared.to(p, "QueueError", "Invalid index") end

	-- Non-admin boleh menghapus antrian miliknya sendiri; DJ yang sedang live boleh menghapus semua. [FIX M6c]
	if not isAdmin(p) and not (Live.isActive() and p.UserId == Live.djId()) then
		local q, target = Playback.queue(), nil
		if id then
			for _, item in ipairs(q) do
				if item.Id == tostring(id) then target = item; break end
			end
		elseif type(idx) == "number" then
			target = q[idx]
		end
		if not target or target.RequesterId ~= p.UserId then
			return Shared.to(p, "QueueError", "You can only remove your own queue items")
		end
	end

	local removed = Playback.removeFromQueue(idx, id)
	if not removed then return Shared.to(p, "QueueError", "Invalid index") end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= p and other.UserId == removed.RequesterId then
			Shared.to(other, "QueueRemoved", '"' .. (removed.Name or "?") .. '" removed by an admin')
		end
	end
	Playback.broadcastQueue()
	Playback.broadcastIds()
	Shared.to(p, "QueueRemoveSuccess", 'Removed: "' .. (removed.Name or "?") .. '"')
end

local function forceSkip(p)
	if not (isAdmin(p) or (Live.isActive() and isDJ(p))) then return Shared.to(p, "SkipError", "Admin only!") end -- [FIX L1b] DJ saat live
	if Live.isActive() and p.UserId ~= Live.djId() then return Shared.to(p, "SkipError", "Live: only the DJ can skip") end -- [FIX M6b]
	if Live.isFollowing() then return Shared.to(p, "SkipError", "Live: controlled by the DJ on another server") end -- [FIX L2]
	Playback.resetVotes()
	Shared.all("AdminSkipped", p.Name)
	Playback.skip()
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

	local cfg, modeChanged = Shared.spatial, false -- [FIX M3] isNum: tolak NaN
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
	if type(s.autoplay) == "boolean" and cfg.autoplay ~= s.autoplay then -- [FIX A1]
		cfg.autoplay = s.autoplay
		if cfg.autoplay and not Playback.isPlaying() and not Playback.isFollowing() then task.defer(Playback.next) end -- [FIX L2]
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
	AddSong            = addSong,
	RemoveSong         = removeSong,
	AddToQueue         = addToQueue,
	RemoveFromQueue    = removeFromQueue,
	VoteSkip           = function(p)
		if skipBlocked(p) then return Shared.to(p, "SkipError", "Live: only the DJ can skip") end -- [FIX L1b] [FIX L2]
		local okRate, msg = checkRate(p, "VoteSkip", 1) -- [FIX M3]
		if not okRate then return Shared.to(p, "SkipError", msg) end
		Playback.voteSkip(p)
	end,
	ForceSkip          = forceSkip,
	SetVolume          = setVolume,
	SetSpatialSettings = setSpatialSettings,
	RequestState       = requestState,
	SetLive            = function(p, on) -- [FIX L1] admin, jeda 2 dtk
		if not isDJ(p) then return Shared.to(p, "SettingsError", "DJ only!") end -- [FIX L1b]
		if type(on) ~= "boolean" then return end
		local okRate, msg = checkRate(p, "Live", 2, true) -- [FIX R4]
		if not okRate then return Shared.to(p, "SettingsError", msg) end
		task.spawn(function()
			if on then
				local ok, err = Live.start(p, Playback.current(), Playback.elapsed())
				if not ok then Shared.to(p, "SettingsError", err) end
			else
				Live.stop("dimatikan oleh " .. p.Name)
			end
		end)
	end,

	RequestMyLibrary   = function(p) if checkRate(p, "MyLib", 1) then requestMyLibrary(p) end end, -- [FIX M3]
	RequestLibrary     = function(p) if checkRate(p, "Lib", 2) then Library.broadcast(p) end end, -- [FIX R1] delta terlewat
	ToggleFavorite     = toggleFavorite,
	AddMySong          = addMySong,
	RemoveMySong       = removeMySong,

	-- Client melaporkan durasi asli / posisi / kegagalan load. Server tidak
	-- me-render audio, jadi ini satu-satunya sumber yang bisa dipercaya.
	ReportDuration     = function(p, data) if allowReport(p) then Playback.report(p, data) end end, -- [FIX M3]
}

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

	task.spawn(function()
		Library.myLoad(p)
		sendMyIfWanted(p) -- [FIX R2]
	end)

	-- [FIX R2] Tidak ada lagi push buta 0.5 & 3 dtk (library terkirim 2-3x).
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
	for _, attr in ipairs({ "IsAdmin", "IsOwner", "IsVIP", "IsPremium", "GroupRank", "HasVIPGamepass", "HasVVIPGamepass", "Role" }) do -- [FIX L1b] Role: peran DJ
		pcall(function() p:GetAttributeChangedSignal(attr):Connect(onRankChanged) end)
	end
end

local function cleanupPlayer(p)
	task.spawn(function()
		Library.myFlush(p)
		Library.myUnload(p)
	end)
	Playback.clearVote(p)
	if Playback.removeQueueByRequester(p.UserId) > 0 then -- [FIX M6] antrian pemain yang keluar dihapus
		Playback.broadcastQueue()
		Playback.broadcastIds()
	end
	Live.playerLeft(p) -- [FIX L1] DJ keluar → siaran berhenti
	pendingState[p], wantMy[p] = nil, nil -- [FIX R2]
	Rate.forget(p) -- [FIX R5] jeda & kuota laporan

	local d = playerData[p]
	if not d then return end
	Volume.flush(p, d) -- [FIX M2] ditulis hanya kalau diubah
	playerData[p] = nil
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(initPlayer, p) end

-- [FIX A1] Auto play mulai begitu ada pendengar (server kosong tidak memutar apa pun).
local function kickAutoplay()
	task.delay(2, function()
		if Shared.spatial.autoplay and not Playback.isPlaying() and not Playback.isFollowing() and #Players:GetPlayers() > 0 then -- [FIX L2]
			Playback.next()
		end
	end)
end
Players.PlayerAdded:Connect(kickAutoplay)
kickAutoplay()

-- [FIX L3] DJ tiba dari server lain di tengah siaran → ambil alih otomatis.
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