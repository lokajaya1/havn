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

local DancePlayer       = require(script.Parent.DancePlayer)
local DanceShared       = require(ReplicatedStorage.Modules.DanceShared)
local CONFIG            = require(script.Config)
local State             = require(script.State)
local Favorites         = require(script.Favorites)

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

local DANCES = DanceShared.dances

local states         = State.states
local getState       = State.getState
local loadFavorites  = Favorites.load
local flushFavorites = Favorites.flush
local notePending    = Favorites.notePending

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

	local track = DanceShared.loadTrack(animator, danceName)
	if not track then return nil end

	s.tracks[danceName] = { track = track, used = s.clock }
	s.trackCount += 1
	return track
end

-- Play pada track dengan Length 0 tidak menampilkan apa pun; ini penyebab
-- "diam" saat dance pertama. Menunggu hanya sekali per dance per karakter.
-- Animasi yang asset-nya rusak dicatat supaya tidak ditunggu berulang kali.
-- Asset yang hanya LAMBAT (lewat LOAD_TIMEOUT tapi termuat kemudian) tetap
-- diputar dan tidak dicap rusak; cap rusak baru setelah BROKEN_CHECK detik.
local brokenDances = {}
local brokenCheck  = {}

local function checkBrokenLater(player, danceName, track)
	if brokenCheck[danceName] or brokenDances[danceName] then return end
	brokenCheck[danceName] = true
	task.delay(CONFIG.BROKEN_CHECK, function()
		brokenCheck[danceName] = nil
		-- Track sudah diganti (respawn / cache) → tidak bisa dinilai.
		local s     = states[player.UserId]
		local entry = s and s.tracks[danceName]
		if not entry or entry.track ~= track or track.Length > 0 then return end
		brokenDances[danceName] = true
		warn(string.format(
			"[DanceHandler] animasi '%s' (id %s) gagal dimuat — cek kepemilikan asset",
			danceName, tostring(DANCES[danceName])
			))
	end)
end

local function ensureTrack(player, danceName)
	local track = getTrack(player, danceName)
	if not track then return nil end
	if track.Length > 0 or brokenDances[danceName] then return track end

	local deadline = os.clock() + CONFIG.LOAD_TIMEOUT
	while track.Length == 0 and os.clock() < deadline do
		task.wait()
	end

	if track.Length == 0 then checkBrokenLater(player, danceName, track) end
	return track
end

-- ═══════════════════════════════════════════════════════════
-- TRACK YANG SEDANG BERMAIN
-- ═══════════════════════════════════════════════════════════

local function findTrack(humanoid, danceName)
	for _, track in ipairs(DanceShared.playingTracks(humanoid)) do
		local animation = track.Animation
		if animation and animation.Name == danceName then return track end
	end
	return nil
end

local function stopDanceTracks(humanoid, except, fade)
	DanceShared.stopDanceTracks(humanoid, except, fade)
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

-- Jalur langsung lewat Animator; dipakai sebagai cadangan kalau DancePlayer gagal.
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
			local called, changed = pcall(DancePlayer.setSpeed, s.slot, speed, CONFIG.SPEED_TRANSITION)
			if called and changed then return true end
		end
		s.dance = nil
	end

	-- Panaskan dulu, jadi DancePlayer tidak pernah memutar track dengan Length 0.
	ensureTrack(player, danceName)
	if seq and (states[player.UserId] ~= s or s.requestSeq ~= seq) then return false end

	-- Track yang sama dengan yang baru dipanaskan (cache LRU): satu track per dance.
	local called, ok = pcall(DancePlayer.play, s.slot, getTrack(player, danceName), {
		fadeIn  = CONFIG.FADE_IN,
		fadeOut = CONFIG.FADE_OUT,
		speed   = speed,
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

	local called, ok = pcall(DancePlayer.stop, s.slot, CONFIG.STOP_FADE)
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

	-- Reset slot dulu; slot bisa mengira dance masih main.
	pcall(DancePlayer.stop, s.slot, 0)
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

local danceRemote     = DanceShared.remote("DanceRequest")
local favoritesRemote = DanceShared.remote("FavoritesRemote")

-- Pemain yang sudah keluar tidak dikirimi (FireClient ke pemain yang pergi = error).
local function sendFavorites(player, kind, list)
	if player.Parent then favoritesRemote:FireClient(player, kind, list) end
end
Favorites.setSend(sendFavorites)

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
	DancePlayer.reset(s.slot)
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
	local s = states[userId]
	if s then DancePlayer.reset(s.slot) end
	flushFavorites(userId, true)

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
	while Favorites.activeFlushes() > 0 and os.clock() - t0 < CONFIG.CLOSE_WAIT do
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