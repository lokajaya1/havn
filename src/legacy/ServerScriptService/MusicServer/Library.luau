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
local Market  = game:GetService("MarketplaceService")

local Shared   = require(RS:WaitForChild("MusicShared"))
local DS       = DSS:GetDataStore("MusicLibrary")
local PlayerDS = DSS:GetDataStore("MusicVolume")
local FavDS    = DSS:GetDataStore("MusicFavorites")

local Library = {}
local list = {}
local saveDirty, saveRunning = false, false

function Library.all()    return list end
function Library.isFull() return #list >= Shared.maxSharedLib end

-- ── info asset (cache) ────────────────────────────────────────────────────
local cache = {}

local function thumbUrl(creator)
	if not creator then return "" end
	local id = creator.CreatorTargetId
	if not id or id == 0 then return "" end
	local ct = tostring(creator.CreatorType)
	if ct == "Group" or ct == "Enum.CreatorType.Group" or ct == "2" then
		return "rbxthumb://type=GroupIcon&id=" .. id .. "&w=150&h=150"
	end
	return "rbxthumb://type=AvatarBust&id=" .. id .. "&w=150&h=150"
end

-- Marketplace API bisa gagal walau izin asetnya sudah benar (throttle server,
-- HTTP 429/502). Satu kegagalan sementara TIDAK boleh membuat lagu dianggap
-- tidak valid, jadi setiap panggilan dijaga jaraknya lalu diulang.
local MARKET_GAP = 0.12
local lastMarket = 0

local function fetchInfo(num)
	for attempt = 1, 3 do
		local gap = MARKET_GAP - (os.clock() - lastMarket)
		if gap > 0 then task.wait(gap) end
		lastMarket = os.clock()

		local ok, info = pcall(Market.GetProductInfo, Market, num, Enum.InfoType.Asset)
		if ok and info then return info end
		task.wait(0.4 * attempt)
	end
	return nil
end

function Library.info(rawId)
	local num = tonumber(rawId)
	if not num then return nil end

	local c = cache[num]
	if c and (os.time() - c.ts) < Shared.nameCacheTTL then return c end

	local info = fetchInfo(num)
	if not info then return nil end

	local cr    = info.Creator
	local ct    = cr and tostring(cr.CreatorType) or ""
	local isGrp = ct == "Group" or ct == "Enum.CreatorType.Group" or ct == "2"

	local entry = {
		name         = info.Name or ("Audio " .. tostring(rawId)),
		creator      = (cr and cr.Name) or "Unknown",
		creatorType  = isGrp and "Group" or "User",
		creatorId    = (cr and cr.CreatorTargetId) or 0,
		thumbnailUrl = thumbUrl(cr),
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

function Library.insert(song)   table.insert(list, song) end
function Library.removeAt(idx)  return table.remove(list, idx) end

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

local function writeNow()
	if saveRunning then return end
	saveRunning, saveDirty = true, false
	task.spawn(function()
		local snap = snapshotAll()
		for i = 1, 3 do
			local ok = pcall(function()
				DS:UpdateAsync("GlobalLib", function() return snap end)
			end)
			if ok then break end
			if i < 3 then task.wait(1) end
		end
		saveRunning = false
		if saveDirty then task.delay(1, writeNow) end
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
	for _ = 1, 3 do
		local ok, data = pcall(DS.GetAsync, DS, "GlobalLib")
		if ok and type(data) == "table" then
			local clean, seen = {}, {}
			for _, s in ipairs(data) do
				if type(s) == "table" and s.Id and s.Requester and not seen[s.Id] then
					seen[s.Id]    = true
					s.unavailable = nil   -- status runtime, jangan dipersist
					s.failCount   = nil
					s.RawId       = s.RawId or Shared.rawId(s.Id)
					table.insert(clean, s)
				end
			end
			list = clean
			return
		end
		task.wait(0.5)
	end
	list = {}
end

-- Library bisa berisi ratusan lagu, dan satu aksi admin memicu beberapa
-- broadcast beruntun. Semua digabung jadi SATU kiriman per 0.4 detik supaya
-- tidak membanjiri jaringan tiap client.
local bcTimer

function Library.broadcast(target)
	if target then
		Shared.to(target, "SharedLibrary", list)
		return
	end
	if bcTimer then return end
	bcTimer = task.delay(0.4, function()
		bcTimer = nil
		Shared.all("SharedLibrary", list)
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
function Library.myLoad(p)
	local uid = uidOf(p)
	local s   = slot(uid)
	if s.loaded then return s.list end
	s.loaded = true   -- kunci lebih dulu supaya tidak dobel-load

	local ok, data
	for i = 1, 3 do
		ok, data = pcall(FavDS.GetAsync, FavDS, "MyLib_" .. uid)
		if ok then break end
		task.wait(0.5)
	end

	local out, seen = {}, {}
	if ok and type(data) == "table" then
		for _, song in ipairs(data) do
			if type(song) == "table" and song.Id and not seen[tostring(song.Id)] then
				seen[tostring(song.Id)] = true
				table.insert(out, clean(song))
			end
		end
	end
	s.list = out
	s.failed = not ok -- [FIX 2c2] load gagal → myWrite menggabungkan, bukan menimpa
	return s.list
end

local function myWrite(uid)
	local s = mine[uid]
	if not s or not s.loaded then return end
	s.dirty = false
	local snap = {}
	for _, song in ipairs(s.list) do table.insert(snap, clean(song)) end
	local merge = s.failed
	for i = 1, 3 do
		local ok = pcall(function()
			FavDS:UpdateAsync("MyLib_" .. uid, function(old)
				if not merge then return snap end
				-- [FIX 2c2] library lama belum pernah termuat → gabung (lama + baru), jangan timpa
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
		if ok then return end
		task.wait(1)
	end
	warn("[Music] gagal simpan Library Saya untuk UserId", uid)
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
		if saveDirty or saveRunning then
			pcall(function()
				DS:UpdateAsync("GlobalLib", function() return snapshotAll() end)
			end)
		end
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