-- ═══════════════════════════════════════════════════════════
-- SHOP SERVER (Production) — FIXED
-- Location: ServerScriptService > ShopServer (Script)
--
-- PERUBAHAN vs versi lama:
--   [1] HAPUS: repeat until shared["_db/connect"]  (bikin server HANG selamanya
--       karena donation board tidak pernah set key itu → ShopRemotes tak dibuat
--       → tab Shop stuck "Waiting for content...").
--   [2] GANTI donation board integration: sekarang pakai ReceiptHandler
--       (ServerScriptService.ReceiptHandler) via RegisterProduct.
--   [3] Guard: kalau ReceiptHandler tidak ada, shop + gift GRATIS admin TETAP
--       jalan; hanya gift BERBAYAR yang dimatikan (dengan warning jelas).
-- ═══════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local Marketplace       = game:GetService("MarketplaceService")
local DataStoreService  = game:GetService("DataStoreService")
local MessagingService  = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

-- ── [FIX 1] ReceiptHandler (ganti shared["_db/connect"]) ──────
-- Tunggu ReceiptHandler dengan TIMEOUT, jangan hang selamanya.
local ReceiptHandler
do
	local rhInst = SSS:WaitForChild("ReceiptHandler", 15)
	if rhInst then
		local ok, mod = pcall(require, rhInst)
		if ok then
			ReceiptHandler = mod
		else
			warn("[ShopServer] require(ReceiptHandler) gagal:", mod)
		end
	else
		warn("[ShopServer] ReceiptHandler tidak ditemukan dalam 15s. "
			.. "Shop + gift GRATIS admin tetap jalan; gift BERBAYAR dimatikan.")
	end
end

local Config  = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Store   = DataStoreService:GetDataStore(Config.dataStore.name)
local Cache   = {}   -- [userId]  → data
local Intents = {}   -- [player]  → { recipient, passName, timestamp }
local RankCache = {} -- [userId]  → bool (isAdmin), cleared on leave
-- [FIX 2a] data gagal dimuat → JANGAN pernah SetAsync (akan menimpa data asli dengan data kosong)
local LoadFailed    = {} -- [userId] → true
local OwnCheckCache = {} -- ["uid|pass"] → { value, expires }  (CheckPlayerOwnership)
local LastCall      = {} -- [player] → { [remoteName] = os.clock() }
local function throttled(player, name, cooldown)
	local t = LastCall[player]
	if not t then t = {}; LastCall[player] = t end
	local now = os.clock()
	if t[name] and now - t[name] < cooldown then return true end
	t[name] = now
	return false
end

-- RemoteFunction dengan jeda: panggilan terlalu cepat dapat hasil terakhir (bukan hitung ulang)
local LastResult = {} -- [player] → { [key] = hasil terakhir }
local function limitedInvoke(player, key, cooldown, fallback, fn)
	if throttled(player, key, cooldown) then
		local r = LastResult[player]
		if r and r[key] ~= nil then return r[key] end
		return fallback
	end
	local res = fn()
	LastResult[player] = LastResult[player] or {}
	LastResult[player][key] = res
	return res
end

-- userId dari client: bilangan bulat positif (tolak NaN, pecahan, teks)
local function validUserId(v)
	v = tonumber(v)
	if not v or v ~= v or v <= 0 or v % 1 ~= 0 or v >= 2 ^ 53 then return nil end
	return v
end

local INTENT_TTL  = 300
local MAX_RETRIES = Config.dataStore.retryAttempts
local RETRY_BASE  = Config.dataStore.retryCooldown

-- ── Remotes ──────────────────────────────────────────────────
local RemoteFolder    = Instance.new("Folder")
RemoteFolder.Name     = "ShopRemotes"
RemoteFolder.Parent   = ReplicatedStorage

local function makeChild(class, name, parent)
	local o = Instance.new(class); o.Name = name; o.Parent = parent; return o
end

local R = {
	CheckOwnership       = makeChild("RemoteFunction", "CheckOwnership",       RemoteFolder),
	GetAllOwnership      = makeChild("RemoteFunction", "GetAllOwnership",      RemoteFolder), -- BATCH (1 call)
	GetOnlinePlayers     = makeChild("RemoteFunction", "GetOnlinePlayers",     RemoteFolder),
	CheckPlayerOwnership = makeChild("RemoteFunction", "CheckPlayerOwnership", RemoteFolder),
	InitiateGift         = makeChild("RemoteEvent",    "InitiateGift",         RemoteFolder),
	AdminGiftItem        = makeChild("RemoteEvent",    "AdminGiftItem",        RemoteFolder), -- FREE gift
	OwnershipUpdated     = makeChild("RemoteEvent",    "OwnershipUpdated",     RemoteFolder),
	GiftReceived         = makeChild("RemoteEvent",    "GiftReceived",         RemoteFolder),
	GiftChatNotif        = makeChild("RemoteEvent",    "GiftChatNotification", RemoteFolder),
}

-- ── Bindable (server → server: RankManager, ToolGiver, dll) ──
local EventFolder        = makeChild("Folder",        "ShopServerEvents",  SSS)
local OnOwnershipChanged = makeChild("BindableEvent", "OnOwnershipChanged", EventFolder)

-- ── Utilities ────────────────────────────────────────────────
local function defaultData()
	return { Gamepasses = {}, Purchases = {}, GiftHistory = {} }
end

local function ensureFields(data)
	data = data or defaultData()
	data.Gamepasses  = data.Gamepasses  or {}
	data.Purchases   = data.Purchases   or {}
	data.GiftHistory = data.GiftHistory or {}
	return data
end

local function retry(fn, ...)
	for i = 1, MAX_RETRIES do
		local ok, res = pcall(fn, ...)
		if ok then return true, res end
		if i < MAX_RETRIES then
			task.wait(math.min(RETRY_BASE * (2 ^ (i - 1)), 10))
		end
	end
	return false
end

-- ── Admin rank (cached per player) ───────────────────────────
-- rank >= adminRankMin → akses penuh shop + free gift
local function isAdminRank(player)
	local uid = player.UserId
	if RankCache[uid] ~= nil then return RankCache[uid] end
	local ok, rank = pcall(player.GetRankInGroup, player, Config.group.id)
	if not ok or type(rank) ~= "number" then return false end -- error API: jangan dicache, coba lagi nanti
	local result   = rank >= Config.group.adminRankMin
	RankCache[uid] = result
	return result
end

-- ── Notification helpers (single source of truth) ────────────
local function notifyClient(player, passName, senderName)
	R.OwnershipUpdated:FireClient(player, passName, true)
	if senderName then R.GiftReceived:FireClient(player, senderName, passName) end
end

local function notifyServerScripts(player, passName)
	OnOwnershipChanged:Fire(player, passName, true)
end

-- Pesan chat gift ditampilkan client (TextChannel:DisplaySystemMessage hanya jalan di
-- client; dari server selalu gagal — terbukti di Studio 2026-09-28 05:34).
local function broadcastGiftChat(recipientName, senderName, passName)
	R.GiftChatNotif:FireAllClients(senderName, recipientName, passName)
end

-- Dipanggil SEKALI setelah pass di-grant — tidak ada duplikasi
local function onPassGranted(player, passName, senderName)
	notifyClient(player, passName, senderName)
	notifyServerScripts(player, passName)
	if senderName then broadcastGiftChat(player.Name, senderName, passName) end
end

-- ── Ownership ─────────────────────────────────────────────────
-- Pass baru ATAU pass HAVN lama (Config legacyIds) = punya
-- Return: punya, errored (API gagal → cek lagi nanti)
local function robloxOwns(userId, pass)
	return Config.userOwnsPass(userId, pass)
end

local function hasPass(userId, passName, waitForData)
	local data = Cache[userId]
	if not data and waitForData then
		local p = Players:GetPlayerByUserId(userId)
		local t = tick()
		repeat task.wait(0.1); data = Cache[userId]
		until data or not p or not p.Parent or tick() - t > 10
	end
	return data and data.Gamepasses[passName] or false
end

-- 3-level check: memory → DataStore → Roblox API
local function deepOwnershipCheck(userId, passName)
	local data = Cache[userId]
	if data and data.Gamepasses[passName] then return true end
	local ok, stored = retry(Store.GetAsync, Store, userId)
	if ok and stored and stored.Gamepasses and stored.Gamepasses[passName] then return true end
	local pass = Config.getGamepassByName(passName)
	return pass and robloxOwns(userId, pass) or false
end

-- ── Data management ───────────────────────────────────────────
-- Semua tulisan ShopData lewat UpdateAsync GABUNG, tidak pernah SetAsync: pass hadiah
-- dari server lain (pesan MessagingService bisa hilang) dan data sesi di server lain
-- (pindah server) tidak tertimpa. Tidak ada yang dihapus saat digabung.
local Dirty       = {} -- [userId] → true: cache punya perubahan yang belum pasti tersimpan
local PendingWant = {} -- [userId] → { [passName] = entry | false } (lihat PendingGifts di bawah)
local Inflight    = 0  -- tulisan latar yang sedang berjalan (ditunggu BindToClose)

local function entryKey(e)
	if type(e) ~= "table" then return tostring(e) end
	return table.concat({ tostring(e.PurchaseId), tostring(e.From), tostring(e.To),
		tostring(e.Pass), tostring(e.Time), tostring(e.Type) }, "|")
end

local function unionList(dst, src)
	if type(src) ~= "table" then return end
	local seen = {}
	for _, e in ipairs(dst) do seen[entryKey(e)] = true end
	for _, e in ipairs(src) do
		local k = entryKey(e)
		if not seen[k] then
			seen[k] = true
			table.insert(dst, e)
		end
	end
end

-- Masukkan isi src ke dst (keduanya sudah ensureFields). Return: pass yang baru jadi true.
local function absorb(dst, src)
	local added = {}
	for name, owned in pairs(src.Gamepasses) do
		if owned == true and dst.Gamepasses[name] ~= true then
			dst.Gamepasses[name] = true
			table.insert(added, name)
		end
	end
	for id, rec in pairs(src.Purchases) do
		if dst.Purchases[id] == nil then dst.Purchases[id] = rec end
	end
	unionList(dst.GiftHistory, src.GiftHistory)
	if type(src.GiftsSent) == "table" then
		if type(dst.GiftsSent) ~= "table" then dst.GiftsSent = {} end
		unionList(dst.GiftsSent, src.GiftsSent)
	end
	return added
end

-- Data tersimpan → cache pemain di server ini (tabel cache TIDAK diganti).
-- quiet = false → pass yang baru muncul diberitahukan (client, RankManager, ToolGiver).
local function adopt(userId, stored, quiet)
	local data = Cache[userId]
	if not data or type(stored) ~= "table" then return end
	stored = ensureFields(stored)
	local added = absorb(data, stored)
	if type(stored.PendingGifts) == "table" then
		local want = PendingWant[userId]
		if type(data.PendingGifts) ~= "table" then data.PendingGifts = {} end
		for name, e in pairs(stored.PendingGifts) do
			if data.PendingGifts[name] == nil and not (want and want[name] ~= nil) then
				data.PendingGifts[name] = e
			end
		end
	end
	LoadFailed[userId] = nil -- cache kini memuat data tersimpan
	local p = Players:GetPlayerByUserId(userId)
	if p and not quiet then
		for _, name in ipairs(added) do onPassGranted(p, name, nil) end
	end
end

-- Ubah sebagian data: UpdateAsync ke DataStore, lalu fungsi yang SAMA ke cache.
-- mutate harus aman dijalankan berulang (UpdateAsync bisa mengulang transform).
local function commit(userId, mutate)
	local ok = retry(function()
		return Store:UpdateAsync(userId, function(old) return mutate(ensureFields(old)) end)
	end)
	if ok and Cache[userId] then mutate(Cache[userId]) end
	return ok
end

-- Ubah cache SEKARANG, simpan di latar. Gagal → Dirty (disimpan lagi saat autosave/keluar).
local function persist(userId, mutate)
	local data = Cache[userId]
	if data then mutate(data) end
	Inflight += 1
	task.spawn(function()
		if not commit(userId, mutate) then Dirty[userId] = true end
		Inflight -= 1
	end)
end

-- Simpan seluruh cache dengan cara GABUNG ke data tersimpan, lalu ambil hasil gabungannya.
local function mergeSave(userId)
	local data = Cache[userId]
	if not data then return false end
	local ok, merged = retry(function()
		return Store:UpdateAsync(userId, function(old)
			old = ensureFields(old)
			absorb(old, data)
			local want = PendingWant[userId]
			if want then
				if type(old.PendingGifts) ~= "table" then old.PendingGifts = {} end
				for name, e in pairs(want) do old.PendingGifts[name] = e or nil end
			end
			return old
		end)
	end)
	if ok and merged then
		Dirty[userId] = nil
		adopt(userId, merged, false)
	else
		warn(("[ShopServer] simpan uid %d gagal, dicoba lagi di autosave"):format(userId))
	end
	return ok
end

-- Baca data tersimpan dan gabungkan ke cache (tanpa menulis).
local function reconcile(userId)
	local ok, stored = retry(Store.GetAsync, Store, userId)
	if ok and Cache[userId] then adopt(userId, stored or {}, false) end
	return ok
end

local function grantPass(userId, passName)
	if not Cache[userId] then return false end
	persist(userId, function(d)
		d.Gamepasses[passName] = true
		return d
	end)
	return true
end

-- Load DataStore gagal → coba baca lagi di latar (pass hadiah muncul tanpa rejoin)
local RELOAD_DELAYS = { 5, 15, 30, 60 }
local function reloadLater(player)
	for _, d in ipairs(RELOAD_DELAYS) do
		task.wait(d)
		if not player.Parent or not LoadFailed[player.UserId] then return end
		if reconcile(player.UserId) then
			print(("[ShopServer] data uid %d termuat ulang"):format(player.UserId))
			return
		end
	end
end

-- Cek gamepass Roblox error saat join → cek lagi (pemilik tidak ditolak sepanjang sesi)
local RECHECK_DELAYS = { 10, 30, 60 }
local function recheckPasses(player, passes)
	for _, d in ipairs(RECHECK_DELAYS) do
		task.wait(d)
		if not player.Parent then return end
		local left = {}
		for _, pass in ipairs(passes) do
			if not hasPass(player.UserId, pass.name, false) then
				local owned, errored = robloxOwns(player.UserId, pass)
				if owned then
					grantPass(player.UserId, pass.name)
					onPassGranted(player, pass.name, nil)
				elseif errored then
					table.insert(left, pass)
				end
			end
		end
		if #left == 0 then return end
		passes = left
	end
end

local function loadData(player)
	local uid = player.UserId
	if Cache[uid] then return Cache[uid] end
	local ok, data = retry(Store.GetAsync, Store, uid)
	if not ok then
		LoadFailed[uid] = true
		warn(("[ShopServer] load data GAGAL uid %d → dicoba lagi di latar"):format(uid))
	end
	data = ensureFields(ok and data or nil)
	if not player.Parent then return nil end
	Cache[uid] = data
	if not ok then task.spawn(reloadLater, player) end
	-- Sync Roblox-purchased passes (pass baru ATAU lama) → dicatat di ShopData
	local synced, recheck = {}, {}
	for _, pass in ipairs(Config.gamepasses) do
		if not data.Gamepasses[pass.name] then
			local owned, errored = robloxOwns(uid, pass)
			if owned then
				table.insert(synced, pass.name)
			elseif errored then
				table.insert(recheck, pass)
			end
		end
	end
	if #synced > 0 then
		persist(uid, function(d)
			for _, name in ipairs(synced) do d.Gamepasses[name] = true end
			return d
		end)
	end
	if #recheck > 0 then task.spawn(recheckPasses, player, recheck) end
	return data
end

-- Keluar / autosave / tutup server: tulis hanya kalau ada yang belum pasti tersimpan
local function saveData(player)
	local uid = player.UserId
	if not Cache[uid] then return end
	if Dirty[uid] or LoadFailed[uid] then mergeSave(uid) end
end

local function updateData(userId, fn)
	local ok, newData = retry(function()
		return Store:UpdateAsync(userId, function(old) return fn(ensureFields(old)) end)
	end)
	-- Cache hanya untuk pemain di server ini (dulu: pemain offline ikut dicache → basi)
	if ok and newData and Cache[userId] then adopt(userId, newData, true) end
	return ok, newData
end

-- ── Tujuan gift tersimpan (PendingGifts) ──────────────────────
-- Struk gift bisa diulang Roblox di sesi LAIN (pembeli keluar/server mati sebelum
-- selesai). Tujuan disimpan di data pembeli: PendingGifts[passName] = { To, Time }.
-- PendingWant = keadaan terakhir yang diminta server ini; tulisan yang telat
-- selalu menulis keadaan terakhir (urutan tulis tidak penting).
local function setPending(userId, passName, entry)
	PendingWant[userId] = PendingWant[userId] or {}
	PendingWant[userId][passName] = entry or false
	local data = Cache[userId]
	if data then
		if type(data.PendingGifts) ~= "table" then data.PendingGifts = {} end
		data.PendingGifts[passName] = entry
	end
end

local function syncPending(userId, passName)
	return commit(userId, function(d)
		local want = PendingWant[userId]
		if want == nil or want[passName] == nil then return d end -- pemain sudah keluar: jangan ubah
		if type(d.PendingGifts) ~= "table" then d.PendingGifts = {} end
		d.PendingGifts[passName] = want[passName] or nil
		return d
	end)
end

-- ── Gift intent ───────────────────────────────────────────────
local function setIntent(player, recipientId, passName)
	Intents[player] = { recipient = recipientId, passName = passName, timestamp = os.time() }
	task.delay(INTENT_TTL, function()
		local i = Intents[player]
		if i and os.time() - i.timestamp >= INTENT_TTL then Intents[player] = nil end
	end)
	setPending(player.UserId, passName, { To = recipientId, Time = os.time() })
	task.spawn(syncPending, player.UserId, passName)
end

-- ── Gift validation (paid path) ────────────────────────────────
local function validateGift(sender, recipientId, passName)
	recipientId = validUserId(recipientId)
	if not recipientId or type(passName) ~= "string" then return false end
	local pass = Config.getGamepassByName(passName)
	if not pass or pass.giftProduct == 0 then return false end
	local ok, _ = pcall(Players.GetNameFromUserIdAsync, Players, recipientId)
	if not ok then return false end
	if deepOwnershipCheck(recipientId, passName) then return false end
	return true
end

-- ── Gift processing (paid path) ────────────────────────────────
local function processGift(receipt, intent)
	local passName    = intent.passName
	local recipientId = intent.recipient
	local senderId    = receipt.PlayerId
	local sender      = Players:GetPlayerByUserId(senderId)
	local senderName  = sender and sender.Name or "Someone"

	if not Config.getGamepassByName(passName) then return false end
	if deepOwnershipCheck(recipientId, passName) then
		warn(("[ShopServer] gift %s dari uid %d: penerima uid %d sudah punya → struk %s diterima tanpa hadiah")
			:format(passName, senderId, recipientId, tostring(receipt.PurchaseId)))
		return true
	end

	local ok = updateData(recipientId, function(data)
		data.Gamepasses[passName] = true
		table.insert(data.GiftHistory, {
			From=senderId, FromName=senderName,
			Pass=passName, Time=os.time(), PurchaseId=receipt.PurchaseId,
		})
		return data
	end)
	if not ok then return false end

	-- Record on sender side (disimpan gabung, dulu hanya di cache sampai keluar)
	if Cache[senderId] then
		local r = Players:GetPlayerByUserId(recipientId)
		local sent = {
			To=recipientId, ToName=r and r.Name or "Unknown",
			Pass=passName, Time=os.time(),
		}
		persist(senderId, function(d)
			if type(d.GiftsSent) ~= "table" then d.GiftsSent = {} end
			unionList(d.GiftsSent, { sent })
			return d
		end)
	end

	-- Notify if recipient is on this server (cache sudah diisi updateData)
	local recipient = Players:GetPlayerByUserId(recipientId)
	if recipient then
		grantPass(recipientId, passName)
		onPassGranted(recipient, passName, senderName)
	end

	-- Cross-server
	task.spawn(function()
		retry(MessagingService.PublishAsync, MessagingService, Config.messaging.giftTopic, {
			SenderId=senderId, SenderName=senderName,
			RecipientId=recipientId, PassName=passName,
		})
	end)

	return true
end

-- ── Free gift (admin path, rank >= adminRankMin) ───────────────
local function processAdminGift(sender, recipientId, passName)
	if not Config.getGamepassByName(passName) then return end
	if deepOwnershipCheck(recipientId, passName) then return end

	local senderName = sender.Name

	local ok = updateData(recipientId, function(data)
		data.Gamepasses[passName] = true
		table.insert(data.GiftHistory, {
			From=sender.UserId, FromName=senderName,
			Pass=passName, Time=os.time(), Type="AdminGift",
		})
		return data
	end)
	if not ok then
		warn(("[ShopServer] AdminGift DataStore gagal: %s → uid %d"):format(passName, recipientId))
		return
	end

	local recipient = Players:GetPlayerByUserId(recipientId)
	if recipient then
		grantPass(recipientId, passName)
		onPassGranted(recipient, passName, senderName)
	end

	-- Cross-server
	task.spawn(function()
		retry(MessagingService.PublishAsync, MessagingService, Config.messaging.giftTopic, {
			SenderId=sender.UserId, SenderName=senderName,
			RecipientId=recipientId, PassName=passName,
		})
	end)
end

-- ══════════════════════════════════════════════════════════════
-- REMOTE HANDLERS
-- ══════════════════════════════════════════════════════════════

-- Single ownership check (backward compat)
R.CheckOwnership.OnServerInvoke = function(player, passName)
	if type(passName) ~= "string" or not Config.getGamepassByName(passName) then return false end
	return limitedInvoke(player, "CheckOwnership|" .. passName, 0.5, false, function()
		-- Admin rank = semua pass dianggap owned
		if isAdminRank(player) then return true end
		return hasPass(player.UserId, passName, false)
	end)
end

-- BATCH: 1 call untuk semua pass + flag isAdmin
-- Menggantikan N sequential CheckOwnership calls di client
R.GetAllOwnership.OnServerInvoke = function(player)
	return limitedInvoke(player, "GetAllOwnership", 0.5, nil, function()
		local admin  = isAdminRank(player)
		local result = { _isAdmin = admin }
		for _, pass in ipairs(Config.gamepasses) do
			-- Admin = semua true; lainnya tunggu data termuat (maks 10 dtk) supaya pass
			-- sendiri tidak tampil "Beli" kalau Shop dibuka sebelum loadData selesai
			result[pass.name] = admin or hasPass(player.UserId, pass.name, true)
		end
		return result
	end)
end

-- Daftar player online untuk modal gift
R.GetOnlinePlayers.OnServerInvoke = function(player, passName)
	if not player then return {} end
	if type(passName) ~= "string" or not Config.getGamepassByName(passName) then passName = nil end
	return limitedInvoke(player, "GetOnlinePlayers|" .. tostring(passName), 0.5, {}, function()
		local list   = {}
		local isPass = passName ~= nil
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				table.insert(list, {
					UserId      = other.UserId,
					Name        = other.Name,
					DisplayName = other.DisplayName,
					-- Gunakan memory cache saja (cukup untuk daftar online, lebih cepat)
					OwnsPass    = isPass and hasPass(other.UserId, passName, false) or false,
				})
			end
		end
		return list
	end)
end

R.CheckPlayerOwnership.OnServerInvoke = function(player, targetId, passName)
	-- [FIX 2a] validasi + cache 60 dtk + batas 1 panggilan/dtk (dulu: GetAsync ke userId bebas tanpa batas)
	targetId = tonumber(targetId)
	if not targetId or targetId ~= targetId or targetId <= 0 or targetId % 1 ~= 0 then return false end
	if type(passName) ~= "string" or not Config.getGamepassByName(passName) then return false end
	local key = targetId .. "|" .. passName
	local hit = OwnCheckCache[key]
	if hit and hit.expires > os.clock() then return hit.value end
	if throttled(player, "CheckPlayerOwnership", 1) then return hit and hit.value or false end
	local value = deepOwnershipCheck(targetId, passName) and true or false
	OwnCheckCache[key] = { value = value, expires = os.clock() + 60 }
	return value
end

-- PAID gift: server prompts purchase, ReceiptHandler processes
R.InitiateGift.OnServerEvent:Connect(function(player, recipientId, passName)
	-- Kalau ReceiptHandler tidak ada, gift berbayar dimatikan (jangan prompt sia-sia)
	if not ReceiptHandler then
		warn("[ShopServer] Gift berbayar dinonaktifkan (ReceiptHandler tidak ada).")
		return
	end
	if throttled(player, "InitiateGift", 2) then return end -- [FIX 2a] anti-spam
	if not validateGift(player, recipientId, passName) then return end
	recipientId = validUserId(recipientId)
	setIntent(player, recipientId, passName)

	local pass       = Config.getGamepassByName(passName)
	local useRegional = false
	if pass.giftProductRegional ~= 0 then
		local ok, data = retry(Marketplace.GetUsersPriceLevelsAsync, Marketplace,
			{ player.UserId, tonumber(recipientId) })
		if ok and data then
			local sLvl, rLvl = 1, 1
			for _, info in ipairs(data) do
				if info.UserId == player.UserId     then sLvl = info.PriceLevel end
				if info.UserId == tonumber(recipientId) then rLvl = info.PriceLevel end
			end
			useRegional = sLvl >= rLvl
		end
	end

	Marketplace:PromptProductPurchase(player,
		useRegional and pass.giftProductRegional or pass.giftProduct)
end)

-- FREE gift: hanya untuk rank >= adminRankMin
R.AdminGiftItem.OnServerEvent:Connect(function(player, recipientId, passName)
	if throttled(player, "AdminGiftItem", 0.5) then return end -- juga membatasi warn di bawah
	-- Security: validasi rank server-side, tidak percaya client
	if not isAdminRank(player) then
		warn(("[ShopServer] AdminGift ditolak (rank tidak cukup): %s"):format(player.Name))
		return
	end
	recipientId = validUserId(recipientId)
	if not recipientId or type(passName) ~= "string" then return end
	processAdminGift(player, recipientId, passName)
end)

-- ══════════════════════════════════════════════════════════════
-- [FIX 2] ReceiptHandler integration (paid gift processor)
-- Menggantikan shared["_db/connect"]:AddProcessor(...)
--
-- ReceiptHandler.RegisterProduct(productId, func) — func harus balikin true/false.
-- ReceiptHandler yang urus PurchaseGranted + anti-duplicate (PurchaseHistoryDS).
-- Kita tetap simpan Purchases[purchaseId] di data pemain sebagai pengaman dobel.
-- ══════════════════════════════════════════════════════════════
local function handleGiftReceipt(receipt, player)
	local userId     = receipt.PlayerId
	local productId  = receipt.ProductId
	local purchaseId = receipt.PurchaseId

	local pass = Config.getGamepassByProduct(productId)
	if not pass then return false end  -- bukan produk shop → biar handler lain urus

	-- Pastikan data pemain sudah loaded
	local data = Cache[userId]
	if not data then
		local t = tick()
		repeat task.wait(0.1); data = Cache[userId]
		until data or not player.Parent or tick() - t > 10
		if not data or not player.Parent then
			return false  -- ReceiptHandler → NotProcessedYet, dicoba lagi nanti
		end
	end

	ensureFields(data)

	-- Anti-duplicate lapis kedua (selain PurchaseHistoryDS milik ReceiptHandler).
	-- Purchases dicatat HANYA setelah hadiah benar-benar tersimpan.
	if data.Purchases[purchaseId] then
		return true
	end
	local record = { Time=os.time(), ProductId=productId, PassName=pass.name, Type="Gift" }
	local function markDone(d)
		d.Purchases[purchaseId] = d.Purchases[purchaseId] or record
		if type(d.PendingGifts) == "table" then d.PendingGifts[pass.name] = nil end
		return d
	end

	-- Tujuan: intent sesi ini; kalau tidak ada → PendingGifts tersimpan (struk diulang di sesi lain)
	local intent = Intents[player]
	if not intent or intent.passName ~= pass.name then
		local saved = type(data.PendingGifts) == "table" and data.PendingGifts[pass.name]
		local to = type(saved) == "table" and tonumber(saved.To)
		intent = to and { recipient = to, passName = pass.name } or nil
	end

	if not intent then
		-- Tanpa tujuan → pass untuk pembeli sendiri; disimpan DULU, baru struk diterima
		local ok = commit(userId, function(d)
			d.Gamepasses[pass.name] = true
			return markDone(d)
		end)
		if not ok then return false end
		onPassGranted(player, pass.name, nil)
		return true
	end

	-- Gagal → tujuan tetap tersimpan, Roblox mengulang struk ke penerima yang sama
	if not processGift(receipt, intent) then return false end

	local cur = Intents[player]
	if cur and cur.passName == pass.name then Intents[player] = nil end
	if PendingWant[userId] then PendingWant[userId][pass.name] = false end
	commit(userId, markDone) -- gagal tidak apa: hadiah sudah tersimpan, processGift idempoten
	return true
end

-- Daftarkan semua gift product (reguler + regional) ke ReceiptHandler
if ReceiptHandler then
	local registered = 0
	for _, pass in ipairs(Config.gamepasses) do
		if pass.giftProduct and pass.giftProduct ~= 0 then
			ReceiptHandler.RegisterProduct(pass.giftProduct, handleGiftReceipt)
			registered += 1
		end
		if pass.giftProductRegional and pass.giftProductRegional ~= 0 then
			ReceiptHandler.RegisterProduct(pass.giftProductRegional, handleGiftReceipt)
			registered += 1
		end
	end
	print(("[ShopServer] ReceiptHandler terhubung | %d gift product terdaftar"):format(registered))
else
	warn("[ShopServer] ReceiptHandler tidak ada → gift BERBAYAR nonaktif. "
		.. "Shop + BUY + gift GRATIS admin tetap jalan.")
end

-- ── Direct gamepass purchase (bukan gift) ─────────────────────
Marketplace.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	local pass = Config.getGamepassById(passId)
	if not pass then return end
	if not grantPass(player.UserId, pass.name) then return end
	onPassGranted(player, pass.name, nil)
end)

-- ── Cross-server gift via MessagingService ─────────────────────
task.spawn(function()
	retry(function()
		return MessagingService:SubscribeAsync(Config.messaging.giftTopic, function(msg)
			local d         = msg.Data
			local recipient = Players:GetPlayerByUserId(d.RecipientId)
			if not recipient then return end
			if hasPass(d.RecipientId, d.PassName, false) then return end -- sudah di-grant server ini
			grantPass(d.RecipientId, d.PassName)
			onPassGranted(recipient, d.PassName, d.SenderName or "Someone")
		end)
	end)
end)

-- ── Player lifecycle ───────────────────────────────────────────
Players.PlayerAdded:Connect(loadData)

Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	saveData(player)
	Cache[uid]     = nil
	Intents[player] = nil
	RankCache[uid] = nil   -- bersihkan rank cache saat player keluar
	LoadFailed[uid] = nil
	LastCall[player] = nil
	LastResult[player] = nil
	PendingWant[uid] = nil
	Dirty[uid] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadData, p) end

-- Tiap 5 menit: simpan yang belum pasti tersimpan; yang lain dibaca ulang
-- (pass hadiah dari server lain yang pesannya hilang ikut masuk)
task.spawn(function()
	while true do
		task.wait(300)
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				local uid = p.UserId
				if Dirty[uid] or LoadFailed[uid] then saveData(p) elseif Cache[uid] then reconcile(uid) end
			end)
		end
	end
end)

-- Tutup server: simpan semua pemain BERSAMAAN + tunggu tulisan latar (maks 25 dtk)
game:BindToClose(function()
	local left = 0
	for _, p in ipairs(Players:GetPlayers()) do
		left += 1
		task.spawn(function()
			pcall(saveData, p)
			left -= 1
		end)
	end
	local t = os.clock()
	while (left > 0 or Inflight > 0) and os.clock() - t < 25 do task.wait(0.1) end
end)

-- ── Global API (RankManager, ToolGiver, dll) ──────────────────
_G.ShopHasGamepass = function(player, passName)
	if not player or type(passName) ~= "string" then return false end
	-- Admin rank = akses semua pass
	if isAdminRank(player) then return true end
	return hasPass(player.UserId, passName, true)
end

_G.ShopServer = {
	HasGamepass   = hasPass,
	IsAdminRank   = isAdminRank,
	GetPlayerData = function(uid) return Cache[uid] end,
}

print(("[ShopServer] Ready | %d gamepasses | adminRankMin=%d | Gift system %s"):format(
	#Config.gamepasses, Config.group.adminRankMin,
	ReceiptHandler and "active" or "GRATIS-only (no ReceiptHandler)"))