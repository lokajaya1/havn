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