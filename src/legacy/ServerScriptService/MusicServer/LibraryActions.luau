-- MusicServer/LibraryActions  (ModuleScript)  [FIX R5b] dipindah dari init.server
-- Aksi remote untuk library global (admin) dan My Library (semua pemain).
-- init.server menggabungkan `handlers` ke tabel Actions-nya.

local RS = game:GetService("ReplicatedStorage")

local Shared   = require(RS:WaitForChild("MusicShared"))
local Library  = require(script.Parent:WaitForChild("Library"))
local Playback = require(script.Parent:WaitForChild("Playback"))
local isAdmin  = require(script.Parent:WaitForChild("Permissions")).isAdmin
local checkRate = require(script.Parent:WaitForChild("RateLimit")).check

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

local M = {}

M.handlers = {
	AddSong          = addSong,
	RemoveSong       = removeSong,
	RequestMyLibrary = function(p) if checkRate(p, "MyLib", 1) then requestMyLibrary(p) end end, -- [FIX M3]
	RequestLibrary   = function(p) if checkRate(p, "Lib", 2) then Library.broadcast(p) end end, -- [FIX R1] delta terlewat
	ToggleFavorite   = toggleFavorite,
	AddMySong        = addMySong,
	RemoveMySong     = removeMySong,
}

-- Pemain masuk: muat My Library, dikirim sekali kalau client sudah memintanya.
function M.onJoin(p)
	task.spawn(function()
		Library.myLoad(p)
		sendMyIfWanted(p) -- [FIX R2]
	end)
end

function M.forget(p) wantMy[p] = nil end

return M
