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
local TextChatService   = game:GetService("TextChatService")
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
	local result   = ok and type(rank) == "number" and rank >= Config.group.adminRankMin
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

local function broadcastGiftChat(recipientName, senderName, passName)
	local ch  = TextChatService:FindFirstChild("TextChannels")
	local gen = ch and ch:FindFirstChild("RBXGeneral")
	if gen then
		pcall(gen.DisplaySystemMessage, gen,
			("🎁 %s gifted %s to %s!"):format(senderName, passName, recipientName))
	end
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
local function grantPass(userId, passName)
	local data = Cache[userId]
	if not data then return false end
	data.Gamepasses[passName] = true
	task.spawn(function()
		-- [FIX 2a] data belum termuat → lewati SetAsync, langsung UpdateAsync (gabung ke data tersimpan)
		if LoadFailed[userId] or not retry(Store.SetAsync, Store, userId, data) then
			task.wait(2)
			retry(function()
				return Store:UpdateAsync(userId, function(old)
					old = ensureFields(old)
					old.Gamepasses[passName] = true
					return old
				end)
			end)
		end
	end)
	return true
end

local function loadData(player)
	local uid = player.UserId
	if Cache[uid] then return Cache[uid] end
	local ok, data = retry(Store.GetAsync, Store, uid)
	if not ok then
		LoadFailed[uid] = true -- [FIX 2a]
		warn(("[ShopServer] load data GAGAL uid %d → simpan hanya lewat UpdateAsync gabung"):format(uid))
	end
	data = ensureFields(ok and data or nil)
	if not player.Parent then return nil end
	Cache[uid] = data
	-- Sync Roblox-purchased passes
	for _, pass in ipairs(Config.gamepasses) do
		if not data.Gamepasses[pass.name] and robloxOwns(uid, pass) then
			data.Gamepasses[pass.name] = true
		end
	end
	return data
end

local function saveData(player)
	local uid  = player.UserId
	local data = Cache[uid]
	if not data then return end
	if not LoadFailed[uid] then
		retry(Store.SetAsync, Store, uid, data)
		return
	end
	-- [FIX 2a] data sesi ini dibuat dari nol (load gagal) → gabungkan, jangan timpa
	local ok, merged = retry(function()
		return Store:UpdateAsync(uid, function(old)
			old = ensureFields(old)
			for name, owned in pairs(data.Gamepasses) do
				if owned then old.Gamepasses[name] = true end
			end
			for id, rec in pairs(data.Purchases) do
				if old.Purchases[id] == nil then old.Purchases[id] = rec end
			end
			return old
		end)
	end)
	if ok and merged then
		LoadFailed[uid] = nil
		if Cache[uid] then Cache[uid] = ensureFields(merged) end
		print(("[ShopServer] data uid %d dipulihkan lewat UpdateAsync gabung"):format(uid))
	else
		warn(("[ShopServer] simpan uid %d dilewati (data belum pernah termuat)"):format(uid))
	end
end

local function updateData(userId, fn)
	local ok, newData = retry(function()
		return Store:UpdateAsync(userId, function(old) return fn(ensureFields(old)) end)
	end)
	if ok and newData then
		Cache[userId] = newData
		LoadFailed[userId] = nil -- [FIX 2a] cache kini = data tersimpan
	end
	return ok, newData
end

-- Ubah sebagian data: UpdateAsync ke DataStore, lalu fungsi yang SAMA ke cache.
-- Cache tidak diganti, jadi perubahan sesi yang belum tersimpan tetap ada.
-- mutate harus aman dijalankan berulang (UpdateAsync bisa mengulang transform).
local function commit(userId, mutate)
	local ok = retry(function()
		return Store:UpdateAsync(userId, function(old) return mutate(ensureFields(old)) end)
	end)
	if ok and Cache[userId] then mutate(Cache[userId]) end
	return ok
end

-- ── Tujuan gift tersimpan (PendingGifts) ──────────────────────
-- Struk gift bisa diulang Roblox di sesi LAIN (pembeli keluar/server mati sebelum
-- selesai). Tujuan disimpan di data pembeli: PendingGifts[passName] = { To, Time }.
-- PendingWant = keadaan terakhir yang diminta server ini; tulisan yang telat
-- selalu menulis keadaan terakhir (urutan tulis tidak penting).
local PendingWant = {} -- [userId] → { [passName] = entry | false }

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
	recipientId = tonumber(recipientId)
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

	-- Record on sender side
	task.spawn(function()
		local sd = Cache[senderId]
		if sd then
			sd.GiftsSent = sd.GiftsSent or {}
			local r = Players:GetPlayerByUserId(recipientId)
			table.insert(sd.GiftsSent, {
				To=recipientId, ToName=r and r.Name or "Unknown",
				Pass=passName, Time=os.time(),
			})
		end
	end)

	-- Notify if recipient is on this server
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
	if type(passName) ~= "string" then return false end
	-- Admin rank = semua pass dianggap owned
	if isAdminRank(player) then return true end
	return hasPass(player.UserId, passName, false)
end

-- BATCH: 1 call untuk semua pass + flag isAdmin
-- Menggantikan N sequential CheckOwnership calls di client
R.GetAllOwnership.OnServerInvoke = function(player)
	local admin  = isAdminRank(player)
	local result = { _isAdmin = admin }
	for _, pass in ipairs(Config.gamepasses) do
		-- Admin = semua true; lainnya baca cache memory (sudah loaded di PlayerAdded)
		result[pass.name] = admin or hasPass(player.UserId, pass.name, false)
	end
	return result
end

-- Daftar player online untuk modal gift
R.GetOnlinePlayers.OnServerInvoke = function(player, passName)
	if not player then return {} end
	local list   = {}
	local isPass = type(passName) == "string"
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
	recipientId = tonumber(recipientId)
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
	-- Security: validasi rank server-side, tidak percaya client
	if not isAdminRank(player) then
		warn(("[ShopServer] AdminGift ditolak (rank tidak cukup): %s"):format(player.Name))
		return
	end
	recipientId = tonumber(recipientId)
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
	local data = Cache[player.UserId]
	if not data then return end
	data.Gamepasses[pass.name] = true
	saveData(player)
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
	PendingWant[uid] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadData, p) end

-- Auto-save tiap 5 menit
task.spawn(function()
	while true do
		task.wait(300)
		for _, p in ipairs(Players:GetPlayers()) do task.spawn(saveData, p) end
	end
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do saveData(p) end
	task.wait(3)
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