-- ServerScriptService/MusicServer  (Script)
-- Bootstrap + izin + rate limit + handler aksi + lifecycle player + bulk import.
-- Logika berat ada di dua ModuleScript anak: Library dan Playback.
--
-- FIX PENTING:
--   Actions.ReportDuration dulu memanggil Playback.report(data.id, data.len,
--   data.failed) padahal signature-nya report(player, data). Semua laporan
--   client dibuang -> server tidak pernah tahu durasi lagu -> lagu macet /
--   tidak lanjut sampai hard timeout. Sekarang diteruskan apa adanya.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local DSS     = game:GetService("DataStoreService")
local SSS     = game:GetService("ServerScriptService")

local Shared   = require(RS:WaitForChild("MusicShared"))
local Library  = require(script:WaitForChild("Library"))
local Playback = require(script:WaitForChild("Playback"))

local VolDS = DSS:GetDataStore("MusicVolume")

-- ═══ IZIN ═════════════════════════════════════════════════════════════════
local RankConfig = (function()
	local mod = SSS:FindFirstChild("RankConfig")
	if not mod then return nil end
	local ok, m = pcall(require, mod)
	return (ok and type(m) == "table") and m or nil
end)()

local function isAdmin(p)   return p ~= nil and p:GetAttribute("IsAdmin")   == true end
local function isPremium(p) return p ~= nil and p:GetAttribute("IsPremium") == true end

local function queueLimit(p)
	if isAdmin(p) then return 999 end
	if RankConfig and RankConfig.GetQueueLimit then
		return RankConfig.GetQueueLimit(
			p:GetAttribute("GroupRank") or 0,
			p:GetAttribute("HasVIPGamepass")  == true,
			p:GetAttribute("HasVVIPGamepass") == true
		)
	end
	if isPremium(p) then return 3 end
	if p:GetAttribute("IsVVIP") == true or p:GetAttribute("HasVVIPGamepass") == true then return 2 end
	return 1
end

-- ═══ RATE LIMIT ═══════════════════════════════════════════════════════════
local rateHits = {}

local function checkRate(p, action, cooldown)
	if isAdmin(p) then return true end
	local key  = p.UserId .. "_" .. action
	local now  = os.clock()
	local last = rateHits[key]
	if last and (now - last) < cooldown then
		return false, ("Wait %ds"):format(math.ceil(cooldown - (now - last)))
	end
	rateHits[key] = now
	return true
end

task.spawn(function()
	while true do
		task.wait(300)
		local now = os.clock()
		for k, t in pairs(rateHits) do
			if (now - t) > 120 then rateHits[k] = nil end
		end
	end
end)

-- [FIX M3] Angka dari client wajib angka sungguhan: NaN lolos math.clamp.
local function isNum(v) return type(v) == "number" and v == v end

-- [FIX M3] ReportDuration: kuota token per pemain (5 token, terisi 1/dtk).
-- Laporan sah: posisi tiap 3 dtk + durasi sekali + gagal ≤2 → tidak pernah habis.
-- Spam dibuang supaya tidak memicu SongDuration ke semua pemain.
local reportBucket = {}
local function allowReport(p)
	local now = os.clock()
	local b = reportBucket[p]
	if not b then b = { tokens = 5, at = now }; reportBucket[p] = b end
	b.tokens = math.min(5, b.tokens + (now - b.at))
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

-- ═══ BOOT ═════════════════════════════════════════════════════════════════
Library.load()
Library.backfill()
Library.bindToClose()

Playback.init()
Playback.applyMode(Shared.spatial.mode)
Playback.setGlobalVolume(Shared.defaultVolume)

local playerData = {}
local volTimers  = {}

-- DataStore bisa gagal sesaat walau API Services aktif. Diulang dulu sebelum
-- jatuh ke nilai bawaan, supaya setelan volume pemain tidak "hilang" sendiri.
local function loadVol(p)
	for attempt = 1, 3 do
		local ok, v = pcall(VolDS.GetAsync, VolDS, "Vol_" .. p.UserId)
		if ok then
			return (type(v) == "number") and math.clamp(v, 0, 1) or 0.7
		end
		task.wait(0.5 * attempt)
	end
	return 0.7
end

-- [FIX M2] Volume hanya disimpan kalau pemain benar-benar menggesernya. Dulu:
-- load gagal → 0.7, lalu saat keluar SELALU SetAsync → setelan asli tertimpa.
local pendingVol = 0

local function writeVol(uid, vol)
	pendingVol += 1
	local ok = false
	for i = 1, 3 do
		ok = pcall(VolDS.SetAsync, VolDS, "Vol_" .. uid, vol)
		if ok then break end
		if i < 3 then task.wait(i) end
	end
	pendingVol -= 1
	return ok
end

local function saveVolDebounced(p)
	local d = playerData[p]
	if not d then return end
	d.volDirty = true
	if volTimers[p] then task.cancel(volTimers[p]) end
	volTimers[p] = task.delay(5, function()
		volTimers[p] = nil
		local v = d.volume
		if writeVol(p.UserId, v) and d.volume == v then d.volDirty = false end
	end)
end

game:BindToClose(function()
	local t0 = os.clock()
	while pendingVol > 0 and os.clock() - t0 < 25 do task.wait(0.2) end
end)

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
local lastState = {}

local function requestState(p)
	local d = playerData[p]
	if not d then return end
	local now = os.clock()
	if lastState[p] and (now - lastState[p]) < 1.5 then return end
	lastState[p] = now
	task.spawn(function()
		Shared.to(p, "SoundLocation", Playback.path())
		Library.broadcast(p)
		Library.myBroadcast(p)
		Shared.to(p, "QueueUpdate",  Playback.queue())
		Shared.to(p, "VolumeUpdate", d.volume or 0.7)
		Shared.to(p, "IsAdmin",      isAdmin(p))
		Shared.to(p, "QueueLimit",   { current = Playback.queueSize(), max = Shared.maxGlobalQueue, myLimit = queueLimit(p) })
		-- Setelan ruang dikirim ke SEMUA pemain: client memakainya untuk
		-- menempatkan salinan lokal saat audio server gagal dimuat.
		Shared.to(p, "SpatialSettings", table.clone(Shared.spatial))
		Shared.to(p, "LoudnessSync", loudnessPayload())

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

		Library.insert({
			Id = id, RawId = rawId,
			Name = info.name, AudioCreator = info.creator,
			creatorType = info.creatorType, creatorId = info.creatorId,
			thumbnailUrl = info.thumbnailUrl,
			Requester = p.Name, RequesterId = p.UserId,
			AddedTime = os.time(),
		})
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
local function requestMyLibrary(p)
	if Library.myIsLoaded(p) then return Library.myBroadcast(p) end
	task.spawn(function()
		Library.myLoad(p)
		Library.myBroadcast(p)
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

		local added, res = Library.myAdd(p, {
			Id = song.Id, RawId = song.RawId, Name = song.Name,
			AudioCreator = song.AudioCreator, creatorType = song.creatorType,
			creatorId = song.creatorId, thumbnailUrl = song.thumbnailUrl,
			source = "fav", AddedTime = os.time(),
		})
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
			entry = {
				Id = exist.Id, RawId = exist.RawId, Name = exist.Name,
				AudioCreator = exist.AudioCreator, creatorType = exist.creatorType,
				creatorId = exist.creatorId, thumbnailUrl = exist.thumbnailUrl,
				source = "own", AddedTime = os.time(),
			}
		else
			Shared.to(p, "SongValidating", Shared.loadTimeout)
			local valid, info = Library.validate(rawId)
			if not valid then return Shared.to(p, "MyLibError", info) end
			if not p.Parent then return end
			entry = {
				Id = id, RawId = rawId,
				Name = info.name, AudioCreator = info.creator,
				creatorType = info.creatorType, creatorId = info.creatorId,
				thumbnailUrl = info.thumbnailUrl,
				source = "own", AddedTime = os.time(),
			}
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

	local entry = {
		Name = song.Name, Id = song.Id, RawId = song.RawId or Shared.rawId(song.Id),
		thumbnailUrl = song.thumbnailUrl or "",
		creatorType = song.creatorType,
		AudioCreator = song.AudioCreator,
		Requester = p.Name, RequesterId = p.UserId,
		LibOwner = song.Requester,
	}

	if not Playback.isPlaying() then
		Playback.play(entry)
		Playback.broadcastQueue()
		Playback.broadcastIds()
		return
	end

	Playback.enqueue(entry, isPremium(p), isPremium)
	Playback.broadcastQueue()
	Playback.broadcastIds()
end

local function removeFromQueue(p, data)
	local idx = type(data) == "table" and data.index or data
	local id  = type(data) == "table" and data.id or nil
	local okRate, msg = checkRate(p, "RemoveQueue", 0.5) -- [FIX M3]
	if not okRate then return Shared.to(p, "QueueError", msg) end
	if type(idx) == "number" and idx ~= idx then return Shared.to(p, "QueueError", "Invalid index") end

	-- Non-admin boleh menghapus antrian miliknya sendiri.
	if not isAdmin(p) then
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
	if not isAdmin(p) then return Shared.to(p, "SkipError", "Admin only!") end
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
		local okRate, msg = checkRate(p, "VoteSkip", 1) -- [FIX M3]
		if not okRate then return Shared.to(p, "SkipError", msg) end
		Playback.voteSkip(p)
	end,
	ForceSkip          = forceSkip,
	SetVolume          = setVolume,
	SetSpatialSettings = setSpatialSettings,
	RequestState       = requestState,

	RequestMyLibrary   = function(p) if checkRate(p, "MyLib", 1) then requestMyLibrary(p) end end, -- [FIX M3]
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
		local v = loadVol(p)
		if playerData[p] then
			playerData[p].volume = v
			Shared.to(p, "VolumeUpdate", v)
		end
	end)

	task.spawn(function()
		Library.myLoad(p)
		if p.Parent then Library.myBroadcast(p) end
	end)

	for _, delay in ipairs({ 0.5, 3 }) do
		task.delay(delay, function()
			if p.Parent and playerData[p] then requestState(p) end
		end)
	end

	local function onRankChanged()
		local d = playerData[p]
		if not p.Parent or not d then return end
		d.queueLimit = queueLimit(p)
		Shared.to(p, "IsAdmin",    isAdmin(p))
		Shared.to(p, "QueueLimit", { current = Playback.queueSize(), max = Shared.maxGlobalQueue, myLimit = d.queueLimit })
		if isAdmin(p) then Shared.to(p, "SpatialSettings", table.clone(Shared.spatial)) end
	end
	for _, attr in ipairs({ "IsAdmin", "IsOwner", "IsVIP", "IsPremium", "GroupRank", "HasVIPGamepass", "HasVVIPGamepass" }) do
		pcall(function() p:GetAttributeChangedSignal(attr):Connect(onRankChanged) end)
	end
end

local function cleanupPlayer(p)
	task.spawn(function()
		Library.myFlush(p)
		Library.myUnload(p)
	end)
	Playback.clearVote(p)
	lastState[p] = nil
	reportBucket[p] = nil -- [FIX M3]

	local d = playerData[p]
	if not d then return end
	local uid, vol = p.UserId, d.volume
	if volTimers[p] then task.cancel(volTimers[p]); volTimers[p] = nil end
	if d.volDirty then task.spawn(writeVol, uid, vol) end -- [FIX M2] hanya kalau diubah
	playerData[p] = nil
	local prefix = p.UserId .. "_"
	for k in pairs(rateHits) do
		if k:sub(1, #prefix) == prefix then rateHits[k] = nil end
	end
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(initPlayer, p) end

-- ═══ BULK IMPORT ══════════════════════════════════════════════════════════
-- Tempel ID di bawah, jalankan server SEKALI. Idempotent: ID yang sudah ada
-- dilewati, jadi blok ini boleh dibiarkan selamanya.
local BULK_IDS = {
	-- "1234567890",
}
local BULK_OWNER_ID   = 0            -- isi UserId-mu supaya tombol × muncul
local BULK_OWNER_NAME = "BulkImport"

task.spawn(function()
	local todo = {}
	for _, raw in ipairs(BULK_IDS) do
		local rawId = Shared.rawId(raw)
		if rawId then table.insert(todo, rawId) end
	end
	if #todo == 0 then return end

	task.wait(5) -- biar library selesai load
	local added, skipped, failed = 0, 0, 0
	for _, rawId in ipairs(todo) do
		local id = "rbxassetid://" .. rawId
		if Library.find(id) then
			skipped += 1
		elseif Library.isFull() then
			warn("[BulkImport] Library penuh, berhenti."); break
		else
			local valid, info = Library.validate(rawId)
			if valid then
				Library.insert({
					Id = id, RawId = rawId,
					Name = info.name, AudioCreator = info.creator,
					creatorType = info.creatorType, creatorId = info.creatorId,
					thumbnailUrl = info.thumbnailUrl,
					Requester = BULK_OWNER_NAME, RequesterId = BULK_OWNER_ID,
					AddedTime = os.time(),
				})
				added += 1
			else
				failed += 1
				warn("[BulkImport] Gagal:", rawId, "-", tostring(info))
			end
			task.wait(0.5) -- throttle Market API
		end
	end
	if added > 0 then Library.broadcast(); Library.saveNow() end
	print(("[BulkImport] Selesai — ditambah:%d dilewati:%d gagal:%d"):format(added, skipped, failed))
end)

print("✅ MusicServer ready")