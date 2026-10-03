-- DanceHandler — ServerScriptService
-- Satu state per pemain (rig + track cache + favorit + watchdog) supaya tidak
-- ada tabel paralel yang harus dibersihkan di banyak tempat.
--
-- Penyebab dance pertama terasa lambat: AnimationTrack yang baru di-load punya
-- Length 0 sampai data keyframe turun, dan Play pada track Length 0 tidak
-- menampilkan apa pun. Karena itu:
--   • AnimationWarmup memanaskan cache asset satu kali per server: dance
--     populer dulu, lalu semua dance lain bertahap.
--   • ensureTrack menunggu Length > 0 sebelum dance benar-benar diputar.
--   • Fade dibuat pendek supaya respons terasa instan.
--   • Klik cepat beruntun tidak dibuang: permintaan TERAKHIR menunggu jeda /
--     kuota lalu dijalankan, jadi avatar selalu sama dengan baris di panel.
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
local Tracks            = require(script.Tracks)
local Motion            = require(script.Motion)

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
local getRig         = Tracks.getRig
local getTrack       = Tracks.getTrack
local clearTracks    = Tracks.clearTracks
local playDance      = Motion.playDance
local stopDance      = Motion.stopDance
local startWatch     = Motion.startWatch

-- ═══════════════════════════════════════════════════════════
-- REMOTE
-- ═══════════════════════════════════════════════════════════

-- Token bucket per pemain: `burst` langsung, lalu `refill` per detik.
local function refillBucket(s, key, burst, refill, now)
	local b = s.buckets[key]
	if not b then
		b = { tokens = burst, at = now }
		s.buckets[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.at) * refill)
	b.at = now
	return b
end

local function takeToken(s, key, burst, refill)
	local b = refillBucket(s, key, burst, refill, os.clock())
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

-- Detik sampai satu token tersedia (0 = sekarang), tanpa memakainya.
local function tokenWait(s, key, burst, refill, now)
	local b = refillBucket(s, key, burst, refill, now)
	if b.tokens >= 1 then return 0 end
	return (1 - b.tokens) / refill
end

local danceRemote     = DanceShared.remote("DanceRequest")
local favoritesRemote = DanceShared.remote("FavoritesRemote")

-- Pemain yang sudah keluar tidak dikirimi (FireClient ke pemain yang pergi = error).
local function sendFavorites(player, kind, list)
	if player.Parent then favoritesRemote:FireClient(player, kind, list) end
end
Favorites.setSend(sendFavorites)

-- Permintaan yang belum boleh jalan (jeda REQUEST_COOLDOWN, atau kuota ganti
-- dance habis) TIDAK dibuang lagi: hanya yang TERAKHIR disimpan (s.pending) dan
-- dijalankan begitu boleh (paling lama 1/SWITCH_REFILL dtk). Dulu klik cepat
-- beruntun dibuang diam-diam → panel menyorot dance baru padahal avatar masih
-- dance lama, dan nilai slider speed terakhir bisa hilang. Kuota tetap sama.
local runPending

-- Satu timer per waktu jatuh tempo: timer yang jatuh tempo lebih awal (atau
-- sama) sudah ada → tidak dibuat lagi. Timer yang terlambat aman: runPending
-- tidak berbuat apa-apa kalau pending sudah dijalankan.
local function schedulePending(player, s, delaySec)
	local due = os.clock() + delaySec
	if s.pendingDue and s.pendingDue <= due + 1e-3 then return end
	s.pendingDue = due
	task.delay(delaySec, function()
		if s.pendingDue == due then s.pendingDue = nil end
		runPending(player, s)
	end)
end

runPending = function(player, s)
	local request = s.pending
	if not request then return end
	-- Keluar, mulai sync, atau state diganti → permintaan lama tidak berlaku.
	if states[player.UserId] ~= s or not player.Parent or player:GetAttribute("IsSyncing") then
		s.pending = nil
		return
	end

	local danceName = request.dance
	local now       = os.clock()
	local switching = danceName ~= nil and danceName ~= "" and danceName ~= s.dance
	local waitFor   = CONFIG.REQUEST_COOLDOWN - (now - s.lastRequest)
	if switching then
		waitFor = math.max(waitFor, tokenWait(s, "switch", CONFIG.SWITCH_BURST, CONFIG.SWITCH_REFILL, now))
	end
	if waitFor > 0 then
		schedulePending(player, s, waitFor)
		return
	end

	s.pending = nil
	if switching then takeToken(s, "switch", CONFIG.SWITCH_BURST, CONFIG.SWITCH_REFILL) end
	s.lastRequest = now

	if not danceName or danceName == "" then
		stopDance(player)
	else
		playDance(player, danceName, request.speed, s.requestSeq)
	end
end

danceRemote.OnServerEvent:Connect(function(player, danceName, speed)
	if danceName ~= nil and type(danceName) ~= "string" then return end
	if not player.Parent then return end

	-- Dance manual ditolak saat sync (mirror diurus SyncHandler).
	-- Dance saat di-carry diizinkan; stop hanya lewat drop-cleanup.
	if player:GetAttribute("IsSyncing") then return end
	if danceName ~= nil and danceName ~= "" and not DANCES[danceName] then return end

	local s = getState(player)
	-- Permintaan terbaru menang: playDance yang masih menunggu aset dingin dari
	-- permintaan sebelumnya berhenti begitu nomor ini naik (lihat Motion.playDance).
	s.requestSeq += 1
	s.pending = { dance = danceName, speed = speed }
	runPending(player, s)
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
	s.pending     = nil -- permintaan untuk karakter lama tidak dijalankan di karakter baru
	s.watchToken += 1  -- matikan watchdog carry dari karakter lama
	DancePlayer.reset(s.slot)
	clearTracks(s)
	player:SetAttribute("IsDancing", false)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	if not humanoid:WaitForChild("Animator", 10) then return end

	-- Mati → dance berhenti (badan ragdoll tidak ikut menari, baris padam).
	humanoid.Died:Connect(function()
		local current = states[player.UserId]
		if current and current.dance and player.Character == character then
			stopDance(player)
		end
	end)

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

	-- Yang digendong: pose gendong menang; dance (sendiri atau mirror sync)
	-- kembali penuh saat dilepas. Yang menggendong tetap menari.
	local function applyCarryWeight()
		DanceShared.applyDanceWeight(player, DanceShared.WEIGHT_FADE)
	end
	player:GetAttributeChangedSignal("Carried"):Connect(applyCarryWeight)

	player:GetAttributeChangedSignal("InCarry"):Connect(function()
		applyCarryWeight()
		if player:GetAttribute("IsSyncing") then return end
		startWatch(player, player:GetAttribute("InCarry") == true)
	end)

	player:GetAttributeChangedSignal("IsSyncing"):Connect(function()
		if not player:GetAttribute("IsSyncing") then return end
		local current = states[player.UserId]
		if current then
			current.dance   = nil
			current.pending = nil
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

-- Dance populer dipanaskan dulu, lalu SEMUA dance lain BERTAHAP
-- (SERVER_WARMUP_CHUNK nama tiap SERVER_WARMUP_STEP dtk, urut abjad seperti
-- panel). Dance yang pertama kali diputar di server ini jadi tidak menunggu aset
-- termuat (Tracks.ensureTrack, ≤ LOAD_TIMEOUT). Tidak sekaligus: ratusan animasi
-- sekaligus membanjiri asset request.
task.delay(CONFIG.SERVER_WARMUP_DELAY, function()
	AnimationWarmup.addByName(DANCES, CONFIG.POPULAR_DANCES)

	local rest = {}
	for name in pairs(DANCES) do
		if not table.find(CONFIG.POPULAR_DANCES, name) then
			table.insert(rest, name)
		end
	end
	table.sort(rest)

	task.wait(CONFIG.SERVER_WARMUP_REST_DELAY)
	local chunk = CONFIG.SERVER_WARMUP_CHUNK
	for i = 1, #rest, chunk do
		AnimationWarmup.addByName(DANCES, table.move(rest, i, math.min(i + chunk - 1, #rest), 1, {}))
		task.wait(CONFIG.SERVER_WARMUP_STEP)
	end
end)