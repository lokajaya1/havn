-- ═══════════════════════════════════════════════════════════
-- LIKE SYSTEM — Script
-- Location: ServerScriptService > LikeSystem
--
-- Tanggung jawab:
--   • satu-satunya pihak yang boleh mengubah Attribute "Likes"
--   • validasi semua permintaan like dari client (server-authoritative)
--   • persist ke DataStore pakai UpdateAsync + DELTA, bukan SetAsync,
--     supaya save "hantu" dari server lama tidak menimpa data baru
--
-- leaderstats TIDAK disentuh di sini. TeamSystem yang mirror
-- Attribute "Likes" → leaderstats.Likes.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local DSS     = game:GetService("DataStoreService")

local CONFIG = {
	StoreName        = "AvatarLikes",
	UseDataStore     = true,   -- false = mode sesi saja (Studio tanpa API Services)
	AllowUnlike      = true,   -- klik lagi = batal like
	AllowSelfLike    = false,
	ToggleCooldown   = 1.0,    -- detik, per pemain
	QueryCooldown    = 0.15,   -- detik, per pemain (cek state saat buka panel)
	MaxGivenStored   = 2000,   -- batas daftar "sudah di-like" yang disimpan
	AutosaveInterval = 180,

	-- Efek/notifikasi ke pemain yang di-like. Unlike TIDAK memicu apa pun.
	Notify           = true,
	NotifyCooldown   = 300,    -- detik, per PASANGAN (A→B), anti spam like/unlike

	-- Efek hati di atas kepala target yang terlihat SEMUA pemain di server.
	-- Dikirim lewat Attribute, bukan FireAllClients.
	BroadcastEffect  = true,
	PulseCooldown    = 2.0,    -- detik, per TARGET
}

-- ── Remote ──────────────────────────────────────────────────
local remotes = RS:FindFirstChild("LikeRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "LikeRemotes"
	remotes.Parent = RS
end

local likeEvent = remotes:FindFirstChild("AvatarLike")
if not likeEvent then
	likeEvent = Instance.new("RemoteEvent")
	likeEvent.Name = "AvatarLike"
	likeEvent.Parent = remotes
end

-- ── DataStore (opsional) ────────────────────────────────────
local store
if CONFIG.UseDataStore then
	local ok, result = pcall(function() return DSS:GetDataStore(CONFIG.StoreName) end)
	if ok then
		store = result
	else
		warn("[LikeSystem] DataStore tidak tersedia, jalan mode sesi:", result)
	end
end

-- ── State sesi ──────────────────────────────────────────────
-- received  : nilai yang ditampilkan  = base tersimpan + delta belum tersimpan
-- delta     : selisih yang BELUM masuk DataStore (bisa negatif kalau unlike)
-- given     : set target yang sudah di-like pemain ini
-- givenDelta: perubahan set yang belum tersimpan ([id] = true tambah / false hapus)
local received   = {}
local delta      = {}
local given      = {}
local givenOrder = {}
local givenDelta = {}
local loaded     = {}
local dirty      = {}
local saving     = {}
local lastToggle = {}
local lastQuery  = {}
local notified   = {} -- [likerId] = { [targetId] = os.clock() } → anti spam toast
local lastPulse  = {} -- [targetId] = os.clock() → throttle efek broadcast
local pulseCounter = 0 -- attribute harus BERUBAH nilainya untuk memicu sinyal

local function key(userId) return "u_" .. userId end

local function publish(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Parent then
		player:SetAttribute("Likes", math.max(0, received[userId] or 0))
	end
end

local function ensure(uid)
	received[uid]   = received[uid]   or 0
	delta[uid]      = delta[uid]      or 0
	given[uid]      = given[uid]      or {}
	givenOrder[uid] = givenOrder[uid] or {}
	givenDelta[uid] = givenDelta[uid] or {}
end

local function retry(fn, attempts)
	local lastErr
	for i = 1, attempts or 3 do
		local ok, result = pcall(fn)
		if ok then return true, result end
		lastErr = result
		task.wait(1.5 * i)
	end
	return false, lastErr
end

-- ── Load ────────────────────────────────────────────────────
local function loadProfile(player)
	local uid = player.UserId
	-- Diinisialisasi DULU: like yang masuk selama GetAsync yield tidak boleh
	-- hilang, jadi nilai DataStore DITAMBAHKAN ke yang sudah ada.
	ensure(uid)

	if not store then
		loaded[uid] = true
		publish(uid)
		return
	end

	local ok, data = retry(function() return store:GetAsync(key(uid)) end)
	if not ok then
		-- Angka yang tampil bisa terlalu rendah, tapi tidak fatal: save berikutnya
		-- pakai delta + UpdateAsync, dan hasil UpdateAsync dipakai untuk koreksi.
		warn("[LikeSystem] Gagal load", player.Name, data)
		loaded[uid] = false
		publish(uid)
		return
	end

	if type(data) == "table" then
		received[uid] += (tonumber(data.likes) or 0)
		if type(data.given) == "table" then
			for _, raw in ipairs(data.given) do
				local t = tonumber(raw)
				if t and not given[uid][t] then
					given[uid][t] = true
					table.insert(givenOrder[uid], t)
				end
			end
		end
	end

	loaded[uid] = true
	publish(uid)
end

-- ── Save (delta + merge) ────────────────────────────────────
local function saveProfile(uid, playerName)
	if not store or not dirty[uid] then return end
	if saving[uid] then return end
	saving[uid] = true

	-- Diambil dulu lalu direset: like yang masuk SELAMA UpdateAsync yield
	-- akan tercatat sebagai delta baru, bukan hilang atau dobel.
	local pendingDelta = delta[uid] or 0
	local pendingGiven = givenDelta[uid] or {}
	delta[uid]      = 0
	givenDelta[uid] = {}
	dirty[uid]      = nil

	local ok, result = retry(function()
		return store:UpdateAsync(key(uid), function(old)
			local likes = 0
			local set, order = {}, {}

			if type(old) == "table" then
				likes = tonumber(old.likes) or 0
				if type(old.given) == "table" then
					for _, raw in ipairs(old.given) do
						local t = tonumber(raw)
						if t and not set[t] then
							set[t] = true
							table.insert(order, t)
						end
					end
				end
			end

			for id, add in pairs(pendingGiven) do
				if add and not set[id] then
					set[id] = true
					table.insert(order, id)
				elseif not add and set[id] then
					set[id] = nil
					for i = #order, 1, -1 do
						if order[i] == id then
							table.remove(order, i)
							break
						end
					end
				end
			end

			while #order > CONFIG.MaxGivenStored do
				table.remove(order, 1)
			end

			return {
				likes   = math.max(0, likes + pendingDelta),
				given   = order,
				updated = os.time(),
			}
		end)
	end)

	saving[uid] = nil

	if not ok then
		-- Rollback supaya perubahan tidak hilang; dicoba lagi di autosave berikutnya
		delta[uid] = (delta[uid] or 0) + pendingDelta
		for id, add in pairs(pendingGiven) do
			if givenDelta[uid][id] == nil then givenDelta[uid][id] = add end
		end
		dirty[uid] = true
		warn("[LikeSystem] Gagal save", playerName or uid, result)
		return
	end

	-- Koreksi: hasil UpdateAsync adalah nilai final di DataStore, jadi
	-- like yang masuk dari server lain (atau load yang gagal) ikut terperbaiki.
	if type(result) == "table" then
		received[uid] = math.max(0, (tonumber(result.likes) or 0) + (delta[uid] or 0))
		publish(uid)
	end
end

local function clearProfile(uid)
	received[uid], delta[uid] = nil, nil
	given[uid], givenOrder[uid], givenDelta[uid] = nil, nil, nil
	loaded[uid], dirty[uid], saving[uid] = nil, nil, nil
	lastToggle[uid], lastQuery[uid] = nil, nil
	notified[uid] = nil
	lastPulse[uid] = nil
	-- Memo di pemain lain yang menunjuk ke uid ini juga dibuang, supaya
	-- tabelnya tidak tumbuh terus di server yang hidup berjam-jam.
	for _, memo in pairs(notified) do
		memo[uid] = nil
	end
end

-- ── Inti: toggle like ───────────────────────────────────────
local function removeGiven(uid, targetId)
	given[uid][targetId] = nil
	local order = givenOrder[uid]
	for i = #order, 1, -1 do
		if order[i] == targetId then
			table.remove(order, i)
			break
		end
	end
end

local function reject(player, targetId, reason)
	likeEvent:FireClient(player, "reject", targetId, reason)
end

local function sendState(player, targetId)
	local set = given[player.UserId]
	likeEvent:FireClient(player, "state", targetId, (set and set[targetId]) or false)
end

local function handleToggle(liker, targetId)
	local likerId = liker.UserId

	if not CONFIG.AllowSelfLike and targetId == likerId then
		return reject(liker, targetId, "self")
	end

	-- Target WAJIB ada di server ini. Ini yang menahan client mengirim userId
	-- sembarangan untuk memompa akun lain dari jauh.
	local target = Players:GetPlayerByUserId(targetId)
	if not target or not target.Parent then
		return reject(liker, targetId, "offline")
	end

	if loaded[likerId] == nil then
		return reject(liker, targetId, "loading")
	end

	ensure(likerId)
	ensure(targetId)

	if given[likerId][targetId] then
		if not CONFIG.AllowUnlike then
			return reject(liker, targetId, "already")
		end
		removeGiven(likerId, targetId)
		givenDelta[likerId][targetId] = false
		received[targetId] = math.max(0, received[targetId] - 1)
		delta[targetId]    -= 1
	else
		given[likerId][targetId] = true
		table.insert(givenOrder[likerId], targetId)
		givenDelta[likerId][targetId] = true
		received[targetId] += 1
		delta[targetId]    += 1

		-- Pulse: dilihat SEMUA pemain lewat replikasi attribute.
		-- Di-throttle per target (bukan per pasangan) supaya target yang
		-- sedang ramai di-like tidak berkedip terus-terusan.
		if CONFIG.BroadcastEffect then
			local now  = os.clock()
			local last = lastPulse[targetId]
			if not last or now - last >= CONFIG.PulseCooldown then
				lastPulse[targetId] = now
				pulseCounter += 1
				target:SetAttribute("LikePulse", pulseCounter)
			end
		end

		-- Notifikasi HANYA saat like baru, satu paket ke satu pemain.
		-- Throttle per pasangan supaya like → unlike → like tidak jadi
		-- alat spam toast ke muka orang.
		if CONFIG.Notify then
			notified[likerId] = notified[likerId] or {}
			local last = notified[likerId][targetId]
			local now  = os.clock()
			if not last or now - last >= CONFIG.NotifyCooldown then
				notified[likerId][targetId] = now
				likeEvent:FireClient(target, "received", likerId, liker.DisplayName)
			end
		end
	end

	dirty[likerId]  = true
	dirty[targetId] = true

	publish(targetId)
	sendState(liker, targetId)
end

-- ── Remote handler ──────────────────────────────────────────
likeEvent.OnServerEvent:Connect(function(player, action, targetUserId)
	if typeof(action) ~= "string" then return end
	if typeof(targetUserId) ~= "number" then return end
	if targetUserId ~= targetUserId or targetUserId < 1 then return end -- NaN / invalid
	targetUserId = math.floor(targetUserId)

	local now = os.clock()

	if action == "query" then
		local last = lastQuery[player.UserId]
		if last and now - last < CONFIG.QueryCooldown then return end
		lastQuery[player.UserId] = now
		sendState(player, targetUserId)

	elseif action == "toggle" then
		local last = lastToggle[player.UserId]
		if last and now - last < CONFIG.ToggleCooldown then
			return reject(player, targetUserId, "cooldown")
		end
		lastToggle[player.UserId] = now
		handleToggle(player, targetUserId)
	end
end)

-- ── Lifecycle ───────────────────────────────────────────────
local function onPlayerAdded(player)
	ensure(player.UserId)
	publish(player.UserId) -- attribute ada sejak awal supaya UI tidak nil
	task.spawn(loadProfile, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local uid  = player.UserId
	local name = player.Name
	task.spawn(saveProfile, uid, name)
	-- Jangan langsung dibersihkan: like yang masuk sesaat sebelum leave
	-- masih perlu ikut tersimpan.
	task.delay(8, function()
		if not Players:GetPlayerByUserId(uid) then
			saveProfile(uid, name)
			clearProfile(uid)
		end
	end)
end)

task.spawn(function()
	while true do
		task.wait(CONFIG.AutosaveInterval)
		for uid in pairs(dirty) do
			saveProfile(uid)
			task.wait(0.2) -- ratakan pemakaian budget DataStore
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for uid in pairs(dirty) do
		pending += 1
		task.spawn(function()
			saveProfile(uid)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 20
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

-- ── API untuk script server lain ────────────────────────────
_G.LikeSystem = {
	Get      = function(userId) return math.max(0, received[userId] or 0) end,
	HasLiked = function(giverId, targetId)
		local set = given[giverId]
		return (set and set[targetId]) or false
	end,
}

print("[LikeSystem] Ready | DataStore:", store ~= nil)