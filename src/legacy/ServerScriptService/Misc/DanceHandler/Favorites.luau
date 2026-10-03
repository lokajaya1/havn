-- DanceHandler/Favorites — favorit dance di DataStore (DanceFavorites / favorites_<uid>;
-- Studio: DanceFavorites_studio lewat Config/StudioData).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")

local DanceShared = require(ReplicatedStorage.Modules.DanceShared)
local StudioData  = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StudioData"))
local CONFIG      = require(script.Parent.Config)
local State       = require(script.Parent.State)

local DANCES   = DanceShared.dances
local states   = State.states
local getState = State.getState

-- ═══════════════════════════════════════════════════════════
-- FAVORIT (DataStore)
-- ═══════════════════════════════════════════════════════════

local IS_STUDIO  = RunService:IsStudio()
local STORE_NAME = StudioData.name(CONFIG.DATASTORE_NAME, IS_STUDIO)
if IS_STUDIO then
	print("[DataStudio] DanceHandler: " .. STORE_NAME)
end

local favoritesStore
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		favoritesStore = result
	else
		warn("[DanceHandler] DataStore tidak tersedia:", result)
	end
end

local function favoritesKey(userId)
	return "favorites_" .. userId
end

local function sanitizeFavorites(list)
	local clean, seen = {}, {}
	if type(list) ~= "table" then return clean end
	for _, name in ipairs(list) do
		if type(name) == "string" and DANCES[name] and not seen[name] then
			seen[name] = true
			clean[#clean + 1] = name
			if #clean >= CONFIG.FAVORITES_LIMIT then break end
		end
	end
	return clean
end

local function retry(fn)
	local ok, result
	for attempt = 1, CONFIG.DS_TRIES do
		ok, result = pcall(fn)
		if ok then return true, result end
		if attempt < CONFIG.DS_TRIES then task.wait(CONFIG.DS_RETRY_DELAY * attempt) end
	end
	return false, result
end

-- Diisi init (bagian REMOTE) lewat Favorites.setSend; FireClient hanya ke pemain yang masih ada.
local sendFavorites

-- Catat setiap tambah/hapus sebagai perubahan tertunda. Tulisan ke DataStore
-- selalu MENGGABUNG perubahan ini ke data terbaru (UpdateAsync), bukan menimpa
-- seluruh daftar: saat pindah server, server lama masih bisa menulis setelah
-- server baru membaca, dan SetAsync dari server baru dulu menghapus perubahan
-- terakhir di server lama. Nilai = nomor edit, supaya perubahan yang terjadi
-- selagi tulisan berjalan tidak ikut dianggap sudah tersimpan.
local function notePending(s, name, added)
	s.editSeq = (s.editSeq or 0) + 1
	if added then
		s.pendingAdd[name], s.pendingRemove[name] = s.editSeq, nil
	else
		s.pendingRemove[name], s.pendingAdd[name] = s.editSeq, nil
	end
end

-- Tambahan tertunda, urut sesuai urutan di daftar lokal.
local function pendingAdds(s)
	local list = {}
	for _, name in ipairs(s.favorites) do
		if s.pendingAdd[name] then list[#list + 1] = name end
	end
	return list
end

local function applyPending(base, adds, removes)
	local out = {}
	for _, name in ipairs(base) do
		if not removes[name] then out[#out + 1] = name end
	end
	for _, name in ipairs(adds) do
		if #out >= CONFIG.FAVORITES_LIMIT then break end
		if not table.find(out, name) then out[#out + 1] = name end
	end
	return out
end

-- Data DataStore sudah terbaca: gabungkan dengan perubahan tertunda.
local function adopt(s, stored)
	local hadPending = next(s.pendingAdd) ~= nil or next(s.pendingRemove) ~= nil
	local merged = sanitizeFavorites(stored)
	if hadPending then merged = applyPending(merged, pendingAdds(s), s.pendingRemove) end
	s.favorites = merged
	-- Perubahan tertunda tetap dicatat sampai benar-benar tertulis (flush).
	s.favLoaded = true
	if hadPending then s.dirty = true end
end

local scheduleReload

local function loadFavorites(player)
	local s = getState(player)
	-- Sudah termuat → pakai memori; spam "load" dibatasi 1x/2 dtk.
	if s.favLoading then
		-- Load lain (mis. saat join) sedang berjalan → tunggu hasilnya, jangan jawab kosong.
		local t0 = os.clock()
		repeat task.wait(0.1) until not s.favLoading or os.clock() - t0 > 10
	end
	if s.favLoaded then return s.favorites end
	local now = os.clock()
	if s.lastFavLoad and now - s.lastFavLoad < 2 then return s.favorites end
	s.lastFavLoad = now
	if favoritesStore then
		s.favLoading = true
		local ok, data = retry(function()
			return favoritesStore:GetAsync(favoritesKey(s.userId))
		end)
		s.favLoading = false
		if ok then
			-- Tulisan mode gabung bisa lebih dulu memuat data lama.
			if not s.favLoaded then adopt(s, data) end
		else
			warn("[DanceHandler] favorit gagal dimuat, dicoba lagi nanti:", data)
			scheduleReload(player)
		end
	end
	return s.favorites
end

-- Load gagal total → coba lagi di latar, lalu kirim hasilnya ke client.
scheduleReload = function(player)
	local s = states[player.UserId]
	if not s or s.reloadPending then return end
	s.reloadPending = true
	s.reloadCount = (s.reloadCount or 0) + 1
	local delays = CONFIG.RELOAD_DELAYS
	task.delay(delays[math.min(s.reloadCount, #delays)], function()
		s.reloadPending = false
		if not player.Parent or states[player.UserId] ~= s or s.favLoaded then return end
		local list = loadFavorites(player)
		if s.favLoaded then sendFavorites(player, "loaded", list) end
	end)
end

-- Jumlah flush yang masih berjalan; BindToClose menunggu sampai nol.
local activeFlushes = 0

-- Tulis hanya kalau ada perubahan; tap bintang tidak lagi memicu SetAsync.
-- Satu tulisan per pemain pada satu waktu, supaya tulisan lama tidak
-- mendarat setelah tulisan baru.
local function flushFavorites(userId, immediate)
	local s = states[userId]
	if not s or not favoritesStore then return end
	if s.writing and not immediate then return end

	local function run()
		activeFlushes += 1
		local t0 = os.clock()
		while s.writing and os.clock() - t0 < CONFIG.CLOSE_WAIT do task.wait(0.1) end

		if s.dirty and not s.writing then
			s.dirty = false
			s.writing = true
			local addSeq, removes = table.clone(s.pendingAdd), table.clone(s.pendingRemove)
			local adds = pendingAdds(s)

			local ok, result = retry(function()
				return favoritesStore:UpdateAsync(favoritesKey(userId), function(old)
					return applyPending(sanitizeFavorites(old), adds, removes)
				end)
			end)

			if not ok then
				s.dirty = true
				warn("[DanceHandler] favorit gagal disimpan:", result)
			else
				-- Hapus hanya perubahan yang ikut tertulis (belum diubah lagi sejak itu).
				for name, seq in pairs(addSeq) do
					if s.pendingAdd[name] == seq then s.pendingAdd[name] = nil end
				end
				for name, seq in pairs(removes) do
					if s.pendingRemove[name] == seq then s.pendingRemove[name] = nil end
				end
				local player = Players:GetPlayerByUserId(userId)
				if not s.favLoaded then
					adopt(s, result)
					if player then sendFavorites(player, "updated", s.favorites) end
				else
					-- Data terbaru bisa berisi perubahan dari server lain.
					local merged = applyPending(sanitizeFavorites(result), pendingAdds(s), s.pendingRemove)
					if table.concat(merged, "\0") ~= table.concat(s.favorites, "\0") then
						s.favorites = merged
						if player then sendFavorites(player, "updated", s.favorites) end
					end
				end
			end
			s.writing = false
		end
		activeFlushes -= 1
	end

	if immediate then run() else task.spawn(run) end
end

return {
	load          = loadFavorites,
	flush         = flushFavorites,
	notePending   = notePending,
	activeFlushes = function() return activeFlushes end,
	setSend       = function(fn) sendFavorites = fn end,
}
