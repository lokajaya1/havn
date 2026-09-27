-- MusicServer/Library  (ModuleScript)
-- Library global (bersama) + "Library Saya" milik tiap player.
-- Tidak tahu apa-apa soal playback.
--
-- DataStore yang dipakai TETAP yang lama, tidak ada store baru:
--   SharedMusicLibrary_v2  -> key "GlobalLib"        (library global)
--   PlayerMusicVolume_v2   -> key "Vol_<UserId>"     (volume, dipakai MusicServer)
--                          -> key "MyLib_<UserId>"   (Library Saya)

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local DSS     = game:GetService("DataStoreService")

local Shared   = require(RS:WaitForChild("MusicShared"))
local DS       = DSS:GetDataStore("MusicLibrary")
local FavDS    = DSS:GetDataStore("MusicFavorites")

local Library = {}
local list = {}
local saveDirty, saveRunning = false, false
-- Operasi lokal sejak tulis terakhir. Tulis = nilai LAMA di DataStore
-- + operasi ini, jadi library global tidak pernah ditimpa daftar server ini.
local addedIds, removedIds = {}, {}

function Library.all()    return list end
function Library.isFull() return #list >= Shared.maxSharedLib end

-- ── info asset (cache) ────────────────────────────────────────────────────
local cache = {}

-- info aset (jaga jarak + ulang) & URL thumbnail ada di MusicShared.

function Library.info(rawId)
	local num = tonumber(rawId)
	if not num then return nil end

	local c = cache[num]
	if c and (os.time() - c.ts) < Shared.nameCacheTTL then return c end

	local info = Shared.productInfo(num)
	if not info then return nil end

	local cr    = info.Creator
	local isGrp = Shared.isGroupCreator(cr)

	local entry = {
		name         = info.Name or ("Audio " .. tostring(rawId)),
		creator      = (cr and cr.Name) or "Unknown",
		creatorType  = isGrp and "Group" or "User",
		creatorId    = (cr and cr.CreatorTargetId) or 0,
		thumbnailUrl = Shared.creatorThumb(cr),
		typeId       = info.AssetTypeId,
		ts           = os.time(),
	}
	cache[num] = entry

	local n = 0
	for _ in pairs(cache) do n += 1 end
	if n > 500 then
		local now = os.time()
		for k, e in pairs(cache) do
			if (now - e.ts) > Shared.nameCacheTTL then cache[k] = nil end
		end
	end
	return entry
end

function Library.validate(rawId)
	local info = Library.info(rawId)
	if not info         then return false, "Audio info unavailable, try again" end
	if info.typeId ~= 3 then return false, "Not an audio asset"      end
	return true, info
end

-- ── query global ──────────────────────────────────────────────────────────
function Library.find(songId)
	if songId == nil then return nil, nil end
	local id = tostring(songId)
	for i, s in ipairs(list) do
		if s.Id == id then return i, s end
	end
	return nil, nil
end

-- catat operasi supaya tulis berikutnya bisa digabung dengan nilai lama
function Library.insert(song)
	table.insert(list, song)
	local id = tostring(song.Id)
	addedIds[id], removedIds[id] = true, nil
end

function Library.removeAt(idx)
	local s = table.remove(list, idx)
	if s then
		local id = tostring(s.Id)
		removedIds[id], addedIds[id] = true, nil
	end
	return s
end

-- ── persistensi global ────────────────────────────────────────────────────
local function snapshotAll()
	local snap = {}
	for _, s in ipairs(list) do
		table.insert(snap, {
			Name = s.Name, Id = s.Id, RawId = s.RawId,
			AudioCreator = s.AudioCreator or "Unknown",
			creatorType  = s.creatorType  or "User",
			creatorId    = s.creatorId    or 0,
			thumbnailUrl = s.thumbnailUrl or "",
			Requester    = s.Requester, RequesterId = s.RequesterId,
			AddedTime    = s.AddedTime,
		})
	end
	return snap
end

-- Gabung, jangan timpa. Dasar = nilai LAMA di DataStore, dikurangi
-- lagu yang dihapus di server ini, ditambah lagu yang ditambahkan di server ini.
-- Tambahan admin di server lain tidak hilang, lagu yang dihapus server lain
-- tidak hidup lagi, dan load yang gagal (daftar kosong) tidak bisa
-- mengosongkan library global.
local function mergeInto(old, snap, adds, dels)
	local byId = {}
	for _, s in ipairs(snap) do byId[s.Id] = s end
	local out, seen = {}, {}
	if type(old) == "table" then
		for _, s in ipairs(old) do
			if type(s) == "table" and s.Id then
				local id = tostring(s.Id)
				if not seen[id] and not dels[id] then
					seen[id] = true
					table.insert(out, byId[id] or s)
				end
			end
		end
	end
	for _, s in ipairs(snap) do
		if adds[s.Id] and not seen[s.Id] then
			seen[s.Id] = true
			table.insert(out, s)
		end
	end
	return out
end

-- Isi DataStore terbaru jadi daftar lokal. Objek lokal dipakai ulang supaya
-- status runtime (unavailable/failCount) tidak hilang, dan operasi yang terjadi
-- SELAMA tulis berjalan tetap berlaku.
local function adopt(data)
	local byId = {}
	for _, s in ipairs(list) do byId[s.Id] = s end
	local out, seen, changed = {}, {}, false
	for _, s in ipairs(data) do
		if type(s) == "table" and s.Id and s.Requester then
			local id = tostring(s.Id)
			if not seen[id] and not removedIds[id] then
				seen[id] = true
				local cur = byId[id]
				if not cur then
					changed = true
					cur = table.clone(s)
					cur.unavailable, cur.failCount = nil, nil
					cur.RawId = cur.RawId or Shared.rawId(cur.Id)
				end
				table.insert(out, cur)
			end
		end
	end
	for _, s in ipairs(list) do
		if not seen[s.Id] then
			if addedIds[s.Id] then
				seen[s.Id] = true
				table.insert(out, s)
			else
				changed = true
			end
		end
	end
	list = out
	if changed then Library.broadcast() end
end

local function writeNow()
	if saveRunning then return end
	saveRunning, saveDirty = true, false
	task.spawn(function()
		local snap = snapshotAll()
		local adds, dels = addedIds, removedIds
		addedIds, removedIds = {}, {}
		local ok, merged = Shared.retry(3, 1, function()
			return DS:UpdateAsync("GlobalLib", function(old)
				return mergeInto(old, snap, adds, dels)
			end)
		end)
		saveRunning = false
		if ok then
			if type(merged) == "table" then adopt(merged) end
			if saveDirty then task.delay(1, writeNow) end
			return
		end
		-- Gagal 3x: operasi dikembalikan (operasi yang lebih baru tetap menang)
		-- dan dicoba lagi oleh autosave, bukan diulang terus-menerus.
		for id in pairs(adds) do
			if addedIds[id] == nil and removedIds[id] == nil then addedIds[id] = true end
		end
		for id in pairs(dels) do
			if addedIds[id] == nil and removedIds[id] == nil then removedIds[id] = true end
		end
		saveDirty = true
		warn("[Music] gagal simpan library global, dicoba lagi saat autosave:", merged)
	end)
end
function Library.save()
	saveDirty = true
	if not saveRunning then task.delay(1, writeNow) end
end

function Library.saveNow()
	if saveRunning then saveDirty = true; return end
	writeNow()
end

function Library.load()
	local ok, data = Shared.retry(3, function(i) return 0.5 * i end, DS.GetAsync, DS, "GlobalLib")
	if ok then
		local clean, seen = {}, {}
		if type(data) == "table" then
			for _, s in ipairs(data) do
				if type(s) == "table" and s.Id and s.Requester and not seen[s.Id] then
					seen[s.Id]    = true
					s.unavailable = nil   -- status runtime, jangan dipersist
					s.failCount   = nil
					s.RawId       = s.RawId or Shared.rawId(s.Id)
					table.insert(clean, s)
				end
			end
		end
		list = clean
		Library.primeSync() -- semua client akan dapat daftar ini lewat kiriman penuh
		return true
	end
	-- Gagal dimuat: daftar kosong SEMENTARA. Aman, karena tulis selalu
	-- digabung dengan nilai lama. Dimuat ulang di latar sampai berhasil.
	list = {}
	warn("[Music] library global gagal dimuat, dicoba lagi tiap 30 dtk")
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(30)
			local okLate, late = pcall(DS.GetAsync, DS, "GlobalLib")
			if okLate then
				adopt(type(late) == "table" and late or {})
				print("[Music] library global termuat ulang:", #list, "lagu")
				return
			end
		end
	end)
	return false
end
-- Dulu SELURUH library (±565 lagu ≈ 150-200 KB) dikirim ulang ke
-- SEMUA pemain tiap ada perubahan. Sekarang:
--   broadcast(p) → daftar lengkap ke satu pemain (join / diminta), + versi;
--   broadcast()  → hanya lagu yang berubah sejak kiriman terakhir, ke semua.
-- Perubahan beruntun tetap digabung jadi satu kiriman per 0.4 dtk.
local bcTimer
local libVer = 0
local sentSig = {} -- [Id] = tanda isi lagu yang terakhir dikirim ke semua pemain

local function sig(o)
	local parts = {}
	for i, k in ipairs(Shared.libFields) do parts[i] = tostring(o[k]) end
	return table.concat(parts, "|")
end

-- Daftar sekarang dianggap sudah dimiliki semua client (dipanggil setelah load).
function Library.primeSync()
	sentSig = {}
	for _, s in ipairs(list) do sentSig[s.Id] = sig(Shared.libSlim(s)) end
end

local function sendDelta()
	local set, del, seen = {}, {}, {}
	for _, s in ipairs(list) do
		seen[s.Id] = true
		local o = Shared.libSlim(s)
		local g = sig(o)
		if sentSig[s.Id] ~= g then
			sentSig[s.Id] = g
			table.insert(set, o)
		end
	end
	for id in pairs(sentSig) do
		if not seen[id] then
			sentSig[id] = nil
			table.insert(del, id)
		end
	end
	if #set == 0 and #del == 0 then return end
	libVer += 1
	Shared.all("LibDelta", { base = libVer - 1, ver = libVer, set = set, del = del })
end

function Library.broadcast(target)
	if target then
		local full = table.create(#list)
		for i, s in ipairs(list) do full[i] = Shared.libSlim(s) end
		Shared.to(target, "SharedLibrary", { ver = libVer, full = full })
		return
	end
	if bcTimer then return end
	bcTimer = task.delay(0.4, function()
		bcTimer = nil
		sendDelta()
	end)
end

-- ── status "tidak tersedia" ───────────────────────────────────────────────
-- Butuh 2 kegagalan di percobaan TERPISAH; data lagu tidak pernah dihapus.
function Library.markFail(song)
	local _, libSong = Library.find(song and song.Id or "")
	if not libSong then return false end
	libSong.failCount = (libSong.failCount or 0) + 1
	if libSong.failCount < 2 then
		warn("[Music] Gagal load percobaan #1 (tidak dihukum):", song.Name, song.RawId)
		return false
	end
	libSong.unavailable = true
	warn("[Music] Ditandai tidak tersedia (gagal 2x):", song.Name, song.RawId)
	return true
end

-- Dipanggil Playback begitu ada client yang benar-benar memutar lagunya,
-- supaya satu kegagalan lama tidak menghukum lagu selamanya.
function Library.markOk(song)
	local _, libSong = Library.find(song and song.Id or "")
	if not libSong then return end
	if (libSong.failCount or 0) > 0 then libSong.failCount = 0 end
	if libSong.unavailable then
		libSong.unavailable = nil
		Library.broadcast()
	end
end

-- Lengkapi metadata lagu lama tanpa membanjiri Market API.
function Library.backfill()
	task.spawn(function()
		task.wait(8)
		local dirty, batch = false, 0
		for _, song in ipairs(list) do
			if song.RawId then
				local noThumb    = not song.thumbnailUrl or song.thumbnailUrl == ""
				local wrongGroup = song.creatorType == "Group" and song.thumbnailUrl
					and song.thumbnailUrl:find("AvatarBust", 1, true) ~= nil
				local noName     = not song.AudioCreator or (song.Name or ""):sub(1, 6) == "Audio "
				if noThumb or wrongGroup or noName then
					local info = Library.info(song.RawId)
					if info then
						if noName then song.Name = info.name; song.AudioCreator = info.creator end
						if not song.creatorType or song.creatorType == "" then song.creatorType = info.creatorType end
						if not song.creatorId or song.creatorId == 0 then song.creatorId = info.creatorId end
						if noThumb or wrongGroup then song.thumbnailUrl = info.thumbnailUrl end
						dirty = true
						batch += 1
						if batch >= 10 then batch = 0; Library.broadcast(); task.wait(1) end
					else
						task.wait(0.2)
					end
				end
			end
		end
		if dirty then Library.save(); Library.broadcast() end
	end)
end

-- ══ LIBRARY SAYA (per player) ═════════════════════════════════════════════
-- [userId] = { list = {}, loaded = bool, dirty = bool, timer = thread }
local mine = {}

local function uidOf(p)
	if typeof(p) == "Instance" and p:IsA("Player") then return p.UserId end
	return tonumber(p) or 0
end

local function slot(uid)
	local s = mine[uid]
	if not s then s = { list = {}, loaded = false, dirty = false }; mine[uid] = s end
	return s
end

local function clean(song)
	return {
		Id           = tostring(song.Id),
		RawId        = song.RawId or Shared.rawId(song.Id),
		Name         = song.Name or "Audio",
		AudioCreator = song.AudioCreator or "Unknown",
		creatorType  = song.creatorType or "User",
		creatorId    = song.creatorId or 0,
		thumbnailUrl = song.thumbnailUrl or "",
		source       = (song.source == "own") and "own" or "fav",
		AddedTime    = song.AddedTime or os.time(),
	}
end

-- YIELDS. Panggil dari task.spawn.
-- `loaded` baru dipasang SETELAH data datang. Pemanggil yang datang
-- selagi load berjalan menunggu, bukan memakai daftar kosong (dulu ♥ di detik
-- awal hilang ditimpa hasil load walau notifikasi bilang "Saved").
function Library.myLoad(p)
	local uid = uidOf(p)
	local s   = slot(uid)
	if s.loaded then return s.list end
	if s.loading then
		local t0 = os.clock()
		while s.loading and os.clock() - t0 < 30 do task.wait(0.1) end
		return s.list
	end
	s.loading = true

	local ok, data = Shared.retry(3, 0.5, FavDS.GetAsync, FavDS, "MyLib_" .. uid)

	local out, seen = {}, {}
	if ok and type(data) == "table" then
		for _, song in ipairs(data) do
			if type(song) == "table" and song.Id and not seen[tostring(song.Id)] then
				seen[tostring(song.Id)] = true
				table.insert(out, clean(song))
			end
		end
	end
	s.list    = out
	s.failed  = not ok -- load gagal → myWrite menggabungkan, bukan menimpa
	s.loaded  = true
	s.loading = false
	return s.list
end

-- jumlah tulis Library Saya yang sedang berjalan (ditunggu BindToClose)
local myPending = 0

local function myWrite(uid)
	local s = mine[uid]
	if not s or not s.loaded then return end
	s.dirty = false
	local snap = {}
	for _, song in ipairs(s.list) do table.insert(snap, clean(song)) end
	local merge = s.failed
	myPending += 1
	local ok, res = Shared.retry(3, 1, function()
		return FavDS:UpdateAsync("MyLib_" .. uid, function(old)
			if not merge then return snap end
			-- library lama belum pernah termuat → gabung (lama + baru), jangan timpa
			local out, seen = {}, {}
			if type(old) == "table" then
				for _, song in ipairs(old) do
					if type(song) == "table" and song.Id and not seen[tostring(song.Id)] then
						seen[tostring(song.Id)] = true
						table.insert(out, clean(song))
					end
				end
			end
			for _, song in ipairs(snap) do
				if not seen[song.Id] then seen[song.Id] = true; table.insert(out, song) end
			end
			return out
		end)
	end)
	myPending -= 1
	if not ok then
		s.dirty = true -- jangan dibuang diam-diam: ikut ditulis saat keluar / shutdown
		warn("[Music] gagal simpan Library Saya untuk UserId", uid)
		return
	end
	-- Gabungan berhasil → daftar lokal = hasil gabungan dan mode gabung
	-- dimatikan. Dulu `failed` tidak pernah direset, jadi hapus favorit
	-- sesudahnya tidak pernah tersimpan (lagu lama selalu ikut kembali).
	if merge and not s.dirty and type(res) == "table" and mine[uid] == s then
		local out = {}
		for _, song in ipairs(res) do table.insert(out, clean(song)) end
		s.list, s.failed = out, false
		local p = Players:GetPlayerByUserId(uid)
		if p then Library.myBroadcast(p) end
	end
end

function Library.mySave(p)
	local uid = uidOf(p)
	local s   = slot(uid)
	s.dirty = true
	if s.timer then task.cancel(s.timer) end
	s.timer = task.delay(4, function()
		s.timer = nil
		task.spawn(myWrite, uid)
	end)
end

function Library.myFlush(p)
	local uid = uidOf(p)
	local s   = mine[uid]
	if not s then return end
	if s.timer then task.cancel(s.timer); s.timer = nil end
	if s.dirty then myWrite(uid) end
end

function Library.myUnload(p) mine[uidOf(p)] = nil end

function Library.myGet(p)      return slot(uidOf(p)).list end
function Library.myIsLoaded(p) return slot(uidOf(p)).loaded end
function Library.myIsFull(p)   return #slot(uidOf(p)).list >= Shared.maxPersonalLib end

function Library.myFind(p, songId)
	if songId == nil then return nil, nil end
	local id = tostring(songId)
	for i, s in ipairs(slot(uidOf(p)).list) do
		if s.Id == id then return i, s end
	end
	return nil, nil
end

function Library.myAdd(p, song)
	local s = slot(uidOf(p))
	local entry = clean(song)
	if Library.myFind(p, entry.Id) then return false, "Already in My Library" end
	if #s.list >= Shared.maxPersonalLib then
		return false, ("My Library is full (max %d)"):format(Shared.maxPersonalLib)
	end
	table.insert(s.list, entry)
	Library.mySave(p)
	return true, entry
end

function Library.myRemoveAt(p, idx)
	local s = slot(uidOf(p))
	local removed = table.remove(s.list, idx)
	if removed then Library.mySave(p) end
	return removed
end

function Library.myRemove(p, songId)
	local idx = Library.myFind(p, songId)
	if not idx then return nil end
	return Library.myRemoveAt(p, idx)
end

-- Pembuat entri lagu (dulu disusun manual di 5 tempat).
--   meta(src, extra)            : salin metadata lagu yang sudah ada + field tambahan
--   fromInfo(rawId, info, extra): entri baru dari hasil Library.info / validate
local META = { "Id", "RawId", "Name", "AudioCreator", "creatorType", "creatorId", "thumbnailUrl" }

function Library.meta(src, extra)
	local e = {}
	for _, k in ipairs(META) do e[k] = src[k] end
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

function Library.fromInfo(rawId, info, extra)
	return Library.meta({
		Id = "rbxassetid://" .. rawId, RawId = rawId,
		Name = info.name, AudioCreator = info.creator,
		creatorType = info.creatorType, creatorId = info.creatorId,
		thumbnailUrl = info.thumbnailUrl,
	}, extra)
end
function Library.myBroadcast(p)
	if typeof(p) ~= "Instance" or not p.Parent then return end
	Shared.to(p, "MyLibrary", slot(p.UserId).list)
end

-- Kalau lagu dihapus dari library global, entri favorit di player online ikut
-- dibersihkan supaya tidak jadi entri hantu (lagu tambahan sendiri tetap aman).
function Library.myPurge(songId)
	local id = tostring(songId)
	for _, p in ipairs(Players:GetPlayers()) do
		local s = mine[p.UserId]
		if s and s.loaded then
			for i = #s.list, 1, -1 do
				if s.list[i].Id == id and s.list[i].source == "fav" then
					table.remove(s.list, i)
					Library.mySave(p)
					Library.myBroadcast(p)
				end
			end
		end
	end
end

-- ── shutdown ──────────────────────────────────────────────────────────────
function Library.bindToClose()
	game:BindToClose(function()
		-- tunggu tulis yang sedang jalan, lalu tulis sisa operasi (digabung)
		local t0 = os.clock()
		while saveRunning and os.clock() - t0 < 15 do task.wait(0.2) end
		if saveDirty or next(addedIds) or next(removedIds) then
			local snap, adds, dels = snapshotAll(), addedIds, removedIds
			pcall(function()
				DS:UpdateAsync("GlobalLib", function(old)
					return mergeInto(old, snap, adds, dels)
				end)
			end)
		end
		-- tunggu tulis Library Saya dari PlayerRemoving, lalu tulis sisanya
		while myPending > 0 and os.clock() - t0 < 25 do task.wait(0.2) end
		for uid, s in pairs(mine) do
			if s.dirty then pcall(myWrite, uid) end
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(Shared.autoSaveInterval)
		if saveDirty then Library.save() end
	end
end)

return Library