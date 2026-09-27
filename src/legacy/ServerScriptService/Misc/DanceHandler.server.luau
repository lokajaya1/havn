-- DanceHandler — ServerScriptService
-- Satu state per pemain (rig + track cache + favorit + watchdog) supaya tidak
-- ada tabel paralel yang harus dibersihkan di banyak tempat.
--
-- Penyebab dance pertama terasa lambat: AnimationTrack yang baru di-load punya
-- Length 0 sampai data keyframe turun, dan Play pada track Length 0 tidak
-- menampilkan apa pun. Karena itu:
--   • AnimationWarmup memanaskan cache asset satu kali per server.
--   • ensureTrack menunggu Length > 0 sebelum dance benar-benar diputar.
--   • Fade dibuat pendek supaya respons terasa instan.
--
-- Catatan:
--   • Animator punya batas 256 AnimationTrack dan track tidak dibersihkan
--     otomatis, jadi cache dibatasi dan track lama di-Destroy.
--   • WalkSpeed selama & sesudah carry tetap milik CarrySystemHandler;
--     di sini hanya menjaga dance solo tetap hidup.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local SmoothDanceHelper = require(ReplicatedStorage.Modules.SmoothDanceHelper)
local DanceAssets       = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)

-- Warm-up bersifat opsional: kalau modulnya belum dipasang, dance tetap jalan
-- (hanya kehilangan pemanasan asset), bukan mematikan seluruh handler.
local AnimationWarmup = { addByName = function() end }
do
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local module  = modules and modules:FindFirstChild("AnimationWarmup")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			AnimationWarmup = result
		else
			warn("[DanceHandler] AnimationWarmup gagal di-require:", result)
		end
	else
		warn("[DanceHandler] AnimationWarmup belum ada di ReplicatedStorage.Modules")
	end
end

local DANCES = DanceAssets.dances

local CONFIG = {
	DANCE_WALKSPEED   = 6,
	DEFAULT_WALKSPEED = 16,

	FADE_IN          = 0.12,
	FADE_OUT         = 0.18,
	STOP_FADE        = 0.22,
	REASSERT_FADE    = 0.1,
	SPEED_TRANSITION = 0.12,

	LOAD_TIMEOUT = 0.6,  -- batas tunggu asset dingin sebelum tetap diputar

	MIN_SPEED = 0.5,
	MAX_SPEED = 2.0,

	MAX_TRACKS       = 48,   -- jauh di bawah batas 256 track per Animator
	REQUEST_COOLDOWN = 0.05, -- anti spam FireServer

	-- Kuota GANTI dance (tiap dance baru = LoadAnimation di server + semua
	-- client mengunduh animasinya). Ubah speed dance yang sama tidak dihitung.
	SWITCH_BURST  = 6,
	SWITCH_REFILL = 3,       -- token per detik

	-- Kuota remote favorit: "load" menjawab dari memori, tambah/hapus
	-- mengirim ulang seluruh daftar.
	FAV_LOAD_GAP   = 2,
	FAV_EDIT_BURST = 10,
	FAV_EDIT_REFILL = 5,

	WARMUP_DELAY        = 0.4,
	SERVER_WARMUP_DELAY = 2,
	-- Nama harus sama persis dengan key di DanceAssets.dances (case-sensitive).
	-- Nama yang salah akan di-warn saat warm-up, tidak diam-diam dilewati.
	POPULAR_DANCES = {
		"Fresh", "Floss", "Gangnam Style", "Electro Shuffle",
		"Get Griddy", "Sturdy", "Breakdance", "Macarena",
		"Salsa", "Party", "Hip Hop Dancing", "Boogie Down",
	},

	-- Watchdog: jaga dance tetap hidup selama di-carry, lalu verifikasi
	-- sebentar setelah drop (Stop dari cleanup bisa pakai fade & telat).
	CARRY_INTERVAL = 0.15,
	DROP_INTERVAL  = 0.1,
	DROP_STEPS     = 10,

	FAVORITES_LIMIT   = 250,
	AUTOSAVE_INTERVAL = 60,
	DATASTORE_NAME    = "DanceFavorites",

	-- DataStore bisa gagal sementara (InternalServerError, throttle): tiap
	-- panggilan diulang, dan load yang gagal total dicoba lagi di latar.
	DS_TRIES       = 3,
	DS_RETRY_DELAY = 1,                  -- detik × nomor percobaan
	RELOAD_DELAYS  = { 5, 15, 30, 60 },  -- lalu tetap tiap 60 dtk
	CLOSE_WAIT     = 25,                 -- batas tunggu tulisan saat server tutup
}

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local states = {}

local function getState(player)
	local userId = player.UserId
	local s = states[userId]
	if not s then
		s = {
			userId     = userId,
			rig        = nil,   -- { humanoid, animator, character }
			tracks     = {},    -- danceName -> { track, used }
			trackCount = 0,
			clock      = 0,
			dance      = nil,
			speed      = 1.0,
			walkSpeed  = CONFIG.DEFAULT_WALKSPEED,
			favorites  = {},
			dirty      = false,
			-- Perubahan favorit yang dibuat sebelum data lama termuat; digabung
			-- ke data DataStore begitu terbaca (load atau UpdateAsync).
			pendingAdd    = {},
			pendingRemove = {},
			writing       = false,
			watchToken = 0,
			lastRequest = 0,
			requestSeq  = 0,     -- permintaan terakhir yang menang (lihat playDance)
			buckets     = {},
			initialized = false,
		}
		states[userId] = s
	end
	return s
end

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

	local animation       = Instance.new("Animation")
	animation.Name        = danceName
	animation.AnimationId = "rbxassetid://" .. animationId

	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok or not track then return nil end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true

	s.tracks[danceName] = { track = track, used = s.clock }
	s.trackCount += 1
	return track
end

-- Play pada track dengan Length 0 tidak menampilkan apa pun; ini penyebab
-- "diam" saat dance pertama. Menunggu hanya sekali per dance per karakter.
-- Animasi yang asset-nya rusak dicatat supaya tidak ditunggu berulang kali.
local brokenDances = {}

local function ensureTrack(player, danceName)
	local track = getTrack(player, danceName)
	if not track then return nil end
	if track.Length > 0 or brokenDances[danceName] then return track end

	local deadline = os.clock() + CONFIG.LOAD_TIMEOUT
	while track.Length == 0 and os.clock() < deadline do
		task.wait()
	end

	if track.Length == 0 then
		brokenDances[danceName] = true
		warn(string.format(
			"[DanceHandler] animasi '%s' (id %s) gagal dimuat — cek kepemilikan asset",
			danceName, tostring(DANCES[danceName])
			))
	end
	return track
end

-- ═══════════════════════════════════════════════════════════
-- TRACK YANG SEDANG BERMAIN
-- ═══════════════════════════════════════════════════════════

local function findTrack(humanoid, danceName)
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		local animation = track.Animation
		if animation and animation.Name == danceName then return track end
	end
	return nil
end

local function stopDanceTracks(humanoid, except, fade)
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		local animation = track.Animation
		if track ~= except and animation and DANCES[animation.Name] then
			pcall(function() track:Stop(fade) end)
		end
	end
end

local function isDanceAlive(humanoid, danceName)
	if not danceName then return false end
	local track = findTrack(humanoid, danceName)
	return track ~= nil and track.IsPlaying and track.WeightTarget >= 0.5
end

-- ═══════════════════════════════════════════════════════════
-- WALKSPEED
-- ═══════════════════════════════════════════════════════════

local function setDanceWalkSpeed(player)
	local humanoid = getRig(player)
	if humanoid then humanoid.WalkSpeed = CONFIG.DANCE_WALKSPEED end
end

local function restoreWalkSpeed(player)
	local humanoid = getRig(player)
	if not humanoid then return end

	local s      = states[player.UserId]
	local target = (s and s.walkSpeed) or CONFIG.DEFAULT_WALKSPEED

	-- Saat carry aktif, CarrySystemHandler pemegang tunggal WalkSpeed.
	local function apply()
		if humanoid.Parent and not player:GetAttribute("InCarry") then
			humanoid.WalkSpeed = target
		end
	end

	apply()
	task.delay(CONFIG.STOP_FADE + 0.1, function()
		local current = states[player.UserId]
		if current and current.dance then return end
		apply()
	end)
end

-- ═══════════════════════════════════════════════════════════
-- PLAY / STOP
-- ═══════════════════════════════════════════════════════════

-- Jalur langsung lewat Animator; dipakai sebagai cadangan kalau helper gagal.
local function playDirect(player, danceName, speed, fadeIn)
	local humanoid = getRig(player)
	if not humanoid then return false end

	local track = ensureTrack(player, danceName)
	if not track then return false end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true

	local ok = pcall(function() track:Play(fadeIn, 1.0, speed) end)
	if not ok then return false end

	stopDanceTracks(humanoid, track, CONFIG.FADE_OUT)
	return true
end

-- seq: nomor permintaan dari remote. Load asset dingin bisa menunggu, jadi
-- permintaan lama tidak boleh menang atas permintaan yang datang sesudahnya.
local function playDance(player, danceName, speed, seq)
	if not DANCES[danceName] then return false end

	local humanoid = getRig(player)
	if not humanoid then return false end

	local s = getState(player)
	speed = tonumber(speed); if speed ~= speed then speed = nil end -- [FIX 2c3] tolak NaN ("nan" lolos math.clamp)
	speed = math.clamp(speed or 1.0, CONFIG.MIN_SPEED, CONFIG.MAX_SPEED)
	s.speed = speed
	setDanceWalkSpeed(player)

	-- Dance yang sama dan masih hidup: cukup ubah kecepatannya.
	if s.dance == danceName then
		if isDanceAlive(humanoid, danceName) then
			local called, changed = pcall(SmoothDanceHelper.setSpeed, player, speed, CONFIG.SPEED_TRANSITION)
			if called and changed then return true end
		end
		s.dance = nil
	end

	-- Panaskan dulu, jadi helper tidak pernah memutar track dengan Length 0.
	ensureTrack(player, danceName)
	if seq and (states[player.UserId] ~= s or s.requestSeq ~= seq) then return false end

	local called, ok = pcall(SmoothDanceHelper.playDance, player, danceName, {
		fadeIn    = CONFIG.FADE_IN,
		fadeOut   = CONFIG.FADE_OUT,
		speed     = speed,
		crossFade = true,
	})
	if not (called and ok) then
		ok = playDirect(player, danceName, speed, CONFIG.FADE_IN)
	end

	if not ok then
		restoreWalkSpeed(player)
		return false
	end

	s.dance = danceName
	player:SetAttribute("IsDancing", true)
	return true
end

local function stopDance(player)
	local s = states[player.UserId]
	if s then s.dance = nil end
	player:SetAttribute("IsDancing", false)

	local humanoid = getRig(player)
	if not humanoid then return end

	local called, ok = pcall(SmoothDanceHelper.stopDance, player, CONFIG.STOP_FADE)
	if not (called and ok) then
		stopDanceTracks(humanoid, nil, CONFIG.STOP_FADE)
	end

	restoreWalkSpeed(player)
end

-- Carry pose bisa menimpa/mematikan track dance; pulihkan sambil menjaga fase.
local function reassertDance(player)
	local s = states[player.UserId]
	if not s or not s.dance then return end
	if player:GetAttribute("IsSyncing") then return end

	local humanoid = getRig(player)
	if not humanoid then return end

	local danceName, speed = s.dance, s.speed or 1.0

	if isDanceAlive(humanoid, danceName) then
		setDanceWalkSpeed(player)
		return
	end

	local previous = findTrack(humanoid, danceName)
	local phase    = previous and previous.TimePosition or nil

	-- Reset state internal helper dulu; helper bisa mengira dance masih main.
	pcall(SmoothDanceHelper.stopDance, player, 0)
	s.dance = nil

	local ok = playDance(player, danceName, speed)

	if not isDanceAlive(humanoid, danceName) then
		stopDanceTracks(humanoid, nil, 0)
		ok = playDirect(player, danceName, speed, CONFIG.REASSERT_FADE)
		if ok then
			setDanceWalkSpeed(player)
			player:SetAttribute("IsDancing", true)
		end
	end

	s.dance = danceName
	s.speed = speed

	if ok and phase then
		local track = findTrack(humanoid, danceName)
		if track and track.IsPlaying then
			pcall(function() track.TimePosition = phase end)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- WATCHDOG CARRY x DANCE
-- Satu loop untuk dua kondisi: selama di-carry (tanpa batas) dan
-- verifikasi singkat setelah drop. Token per-generasi mematikan loop lama.
-- ═══════════════════════════════════════════════════════════

local function startWatch(player, carried)
	local s = states[player.UserId]
	if not s or not s.dance then return end

	local danceName = s.dance
	s.watchToken += 1
	local token = s.watchToken

	local interval = carried and CONFIG.CARRY_INTERVAL or CONFIG.DROP_INTERVAL
	local steps    = carried and math.huge or CONFIG.DROP_STEPS

	task.spawn(function()
		task.wait(carried and 0 or interval) -- beri waktu pose/weld carry settle

		local step = 0
		while step < steps do
			step += 1

			if not player.Parent then return end
			if player:GetAttribute("IsSyncing") then return end
			if (player:GetAttribute("InCarry") == true) ~= carried then return end

			local current = states[player.UserId]
			if not current or current.watchToken ~= token or current.dance ~= danceName then return end

			local humanoid = getRig(player)
			if humanoid then
				if not isDanceAlive(humanoid, danceName) then
					reassertDance(player)
				elseif carried then
					setDanceWalkSpeed(player)
				end
			end

			task.wait(interval)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- FAVORIT (DataStore)
-- ═══════════════════════════════════════════════════════════

local favoritesStore
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)
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

-- Diisi di bagian REMOTE; FireClient hanya ke pemain yang masih ada.
local sendFavorites

-- Catat perubahan yang terjadi sebelum data lama termuat, supaya tidak hilang
-- saat data DataStore datang dan tidak menimpa favorit lama.
local function notePending(s, name, added)
	if s.favLoaded then return end
	if added then
		s.pendingAdd[name], s.pendingRemove[name] = true, nil
	else
		s.pendingRemove[name], s.pendingAdd[name] = true, nil
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
	s.pendingAdd, s.pendingRemove = {}, {}
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
			local loaded = s.favLoaded
			local snapshot = table.clone(s.favorites)
			local adds, removes = pendingAdds(s), table.clone(s.pendingRemove)

			local ok, result = retry(function()
				if loaded then
					favoritesStore:SetAsync(favoritesKey(userId), snapshot)
					return nil
				end
				-- Favorit lama belum pernah termuat → gabungkan, jangan timpa.
				return favoritesStore:UpdateAsync(favoritesKey(userId), function(old)
					return applyPending(sanitizeFavorites(old), adds, removes)
				end)
			end)

			if not ok then
				s.dirty = true
				warn("[DanceHandler] favorit gagal disimpan:", result)
			elseif not loaded and not s.favLoaded then
				-- UpdateAsync sudah membaca data lama: pakai hasil gabungannya.
				for _, name in ipairs(adds) do s.pendingAdd[name] = nil end
				for name in pairs(removes) do s.pendingRemove[name] = nil end
				adopt(s, result)
				local player = Players:GetPlayerByUserId(userId)
				if player then sendFavorites(player, "updated", s.favorites) end
			end
			s.writing = false
		end
		activeFlushes -= 1
	end

	if immediate then run() else task.spawn(run) end
end

-- ═══════════════════════════════════════════════════════════
-- REMOTE
-- ═══════════════════════════════════════════════════════════

-- Token bucket per pemain: `burst` langsung, lalu `refill` per detik.
local function takeToken(s, key, burst, refill)
	local now = os.clock()
	local b = s.buckets[key]
	if not b then
		b = { tokens = burst, at = now }
		s.buckets[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.at) * refill)
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

local function getRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote then return remote end
	remote        = Instance.new("RemoteEvent")
	remote.Name   = name
	remote.Parent = ReplicatedStorage
	return remote
end

local danceRemote     = getRemote("DanceRequest")
local favoritesRemote = getRemote("FavoritesRemote")

-- Pemain yang sudah keluar tidak dikirimi (FireClient ke pemain yang pergi = error).
sendFavorites = function(player, kind, list)
	if player.Parent then favoritesRemote:FireClient(player, kind, list) end
end

danceRemote.OnServerEvent:Connect(function(player, danceName, speed)
	if danceName ~= nil and type(danceName) ~= "string" then return end
	if not player.Parent then return end

	local s   = getState(player)
	local now = os.clock()
	if now - s.lastRequest < CONFIG.REQUEST_COOLDOWN then return end

	-- Dance manual ditolak saat sync (mirror diurus SyncHandler).
	-- Dance saat di-carry diizinkan; stop hanya lewat drop-cleanup.
	if player:GetAttribute("IsSyncing") then return end

	local switching = danceName ~= nil and danceName ~= "" and danceName ~= s.dance
	if switching then
		if not DANCES[danceName] then return end
		if not takeToken(s, "switch", CONFIG.SWITCH_BURST, CONFIG.SWITCH_REFILL) then return end
	end
	s.lastRequest = now
	s.requestSeq += 1

	if not danceName or danceName == "" then
		stopDance(player)
	else
		playDance(player, danceName, speed, s.requestSeq)
	end
end)

favoritesRemote.OnServerEvent:Connect(function(player, action, data)
	if not player.Parent then return end
	local s = getState(player)

	if action == "load" then
		local now = os.clock()
		if s.lastLoadRequest and now - s.lastLoadRequest < CONFIG.FAV_LOAD_GAP then return end
		s.lastLoadRequest = now
		sendFavorites(player, "loaded", loadFavorites(player))
		return
	end
	if action ~= "add" and action ~= "remove" then return end
	if not takeToken(s, "fav", CONFIG.FAV_EDIT_BURST, CONFIG.FAV_EDIT_REFILL) then return end

	if action == "add" and type(data) == "string" and DANCES[data] then
		if #s.favorites < CONFIG.FAVORITES_LIMIT and not table.find(s.favorites, data) then
			table.insert(s.favorites, data)
			notePending(s, data, true)
			s.dirty = true
			favoritesRemote:FireClient(player, "updated", s.favorites)
		end

	elseif action == "remove" and type(data) == "string" then
		local index = table.find(s.favorites, data)
		if index then
			table.remove(s.favorites, index)
			notePending(s, data, false)
			s.dirty = true
			favoritesRemote:FireClient(player, "updated", s.favorites)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════
-- SIKLUS PEMAIN
-- ═══════════════════════════════════════════════════════════

-- Memuat AnimationTrack ke Animator pemain supaya dance pertama tidak
-- tersendat. Tambah nama ke POPULAR_DANCES kalau perlu; biayanya murah.
local function warmUpPlayer(player)
	if not player.Parent then return end
	local _, animator = getRig(player)
	if not animator then return end

	pcall(SmoothDanceHelper.initializePlayer, player)
	pcall(SmoothDanceHelper.preloadPopularAnimations, player, CONFIG.POPULAR_DANCES)

	for _, danceName in ipairs(CONFIG.POPULAR_DANCES) do
		if DANCES[danceName] then
			getTrack(player, danceName)
		else
			warn("[DanceHandler] POPULAR_DANCES berisi nama yang tidak ada: " .. danceName)
		end
	end
end

local function onCharacterAdded(player, character)
	local s = getState(player)

	s.rig         = nil
	s.dance       = nil
	s.watchToken += 1  -- matikan watchdog carry dari karakter lama
	clearTracks(s)
	player:SetAttribute("IsDancing", false)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	if not humanoid:WaitForChild("Animator", 10) then return end

	s.walkSpeed = humanoid.WalkSpeed
	task.delay(CONFIG.WARMUP_DELAY, warmUpPlayer, player)
end

local function onPlayerAdded(player)
	local s = getState(player)
	if s.initialized then return end
	s.initialized = true

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	player:GetAttributeChangedSignal("InCarry"):Connect(function()
		if player:GetAttribute("IsSyncing") then return end
		startWatch(player, player:GetAttribute("InCarry") == true)
	end)

	player:GetAttributeChangedSignal("IsSyncing"):Connect(function()
		if not player:GetAttribute("IsSyncing") then return end
		local current = states[player.UserId]
		if current then
			current.dance = nil
			current.watchToken += 1
		end
		player:SetAttribute("IsDancing", false)
	end)

	task.spawn(function()
		sendFavorites(player, "loaded", loadFavorites(player))
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	pcall(SmoothDanceHelper.cleanupPlayer, player)
	flushFavorites(userId, true)

	local s = states[userId]
	if s then clearTracks(s) end
	states[userId] = nil
end)

-- Tunggu SEMUA tulisan, termasuk yang dimulai PlayerRemoving/autosave;
-- kalau tidak, server bisa tutup sebelum tulisan terakhir sampai.
game:BindToClose(function()
	for userId in pairs(states) do
		task.spawn(flushFavorites, userId, true)
	end
	local t0 = os.clock()
	while activeFlushes > 0 and os.clock() - t0 < CONFIG.CLOSE_WAIT do
		task.wait(0.1)
	end
end)

task.spawn(function()
	while true do
		task.wait(CONFIG.AUTOSAVE_INTERVAL)
		for userId in pairs(states) do
			flushFavorites(userId, false)
		end
	end
end)

-- Hanya dance populer yang dipanaskan di server. Sisanya dipanaskan saat
-- benar-benar dibutuhkan; memanaskan 200+ animasi sekaligus justru bikin lag.
task.delay(CONFIG.SERVER_WARMUP_DELAY, function()
	AnimationWarmup.addByName(DANCES, CONFIG.POPULAR_DANCES)
end)