-- ServerScriptService.DonationServer — donasi Robux (Developer Product).
-- Struk HANYA lewat ReceiptHandler.RegisterProduct (satu ProcessReceipt per game; tidak memakai
-- PromptProductPurchaseFinished — itu bukan bukti bayar dan ikut menyala untuk gift Shop).
-- Alur: pemain (opsional) kirim pesan → server filter PublicChat → pemain beli produk →
-- struk: total disimpan tepat sekali (Store) → antrean pengumuman: notifikasi + efek semua pemain + LiveScreen,
-- lalu dikirim ke server lain (Global): di sana notifikasi, papan & efek besar (tanpa partikel/LiveScreen).
-- Tes admin (TestDonation): pengumuman yang sama tanpa Marketplace & tanpa data, pesan berawalan [TES], papan tidak diisi.
-- Donasi luar bagibagi (Bagibagi): tanpa nominal (robux = 0), efek dari tier `fxRobux`, tidak masuk TOP DONATORS.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("DonationConfig"))
local Store = require(script:WaitForChild("Store"))
local ReceiptHandler = require(SSS:WaitForChild("ReceiptHandler"))

local MSG = Config.message
local suffix = RunService:IsStudio() and Config.store.studioSuffix or ""
local orderedStore = DataStoreService:GetOrderedDataStore(Config.store.ordered .. suffix)
local store = Store.new(DataStoreService:GetDataStore(Config.store.data .. suffix), orderedStore, Config.store, task.delay)
local Boards = require(script:WaitForChild("Boards"))
local boards = Boards.new({
	ordered = orderedStore,
	folder = workspace:FindFirstChild("DonationBoards"),
	services = { Players = Players, UserService = game:GetService("UserService") },
	cfg = Config,
	task = task,
	warn = warn,
})

-- ── Remote (folder & nama lama dipertahankan: src/client/DonationNotif mendengar ShowMessage) ──
local function ensure(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if inst and not inst:IsA(className) then
		inst:Destroy()
		inst = nil
	end
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end
local folder = ensure(ReplicatedStorage, "Folder", "DonationMessageSystem")
local showMessage = ensure(folder, "RemoteEvent", "ShowMessage") -- (displayName, username, robux, message, userId)
local setMessage = ensure(folder, "RemoteFunction", "SetMessage") -- client → server: teks → true/false
local remotes = ensure(ReplicatedStorage, "Folder", "DonationRemotes")
local effectEvent = ensure(remotes, "RemoteEvent", "Effect") -- server → client: (userId, robux)
local testFn = ensure(remotes, "RemoteFunction", "TestDonation") -- admin: (robux, pesan, semuaServer) → ok, alasan
-- Efek besar (Nuke / Smite / BlackHole): (username, penerima, robux, userId) — dipakai StarterGui.DonationBigFX.
local bigEvents = {}
for _, tier in Config.tiers do
	if tier.big and not bigEvents[tier.big] then
		bigEvents[tier.big] = ensure(remotes, "RemoteEvent", tier.big)
	end
end

local liveSystem = ReplicatedStorage:FindFirstChild("LiveSystem")
local function screenSignal()
	return liveSystem and liveSystem:FindFirstChild("DonationScreenSignal")
end

-- ── Pesan donatur ────────────────────────────────────────────
local pending = {} -- [Player] = { text, at }
local lastSet = {} -- [Player] = os.clock()

local function cutChars(s, n)
	local len = utf8.len(s)
	if not len then
		return nil -- UTF-8 rusak
	end
	if len <= n then
		return s
	end
	return string.sub(s, 1, utf8.offset(s, n + 1) - 1)
end

local function filterPublic(text, userId)
	local ok, result = pcall(function()
		local r = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

setMessage.OnServerInvoke = function(player, text)
	local now = os.clock()
	if lastSet[player] and now - lastSet[player] < MSG.cooldown then
		return false
	end
	if type(text) ~= "string" or #text > MSG.maxBytes then
		return false
	end
	lastSet[player] = now
	text = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	if text == "" then
		pending[player] = nil -- donasi tanpa pesan
		return true
	end
	local cut = cutChars(text, MSG.maxChars)
	if not cut then
		return false
	end
	local clean = filterPublic(cut, player.UserId)
	if not clean then
		pending[player] = nil -- fail-closed: filter gagal → tanpa pesan
		warn("[Donation] filter pesan gagal untuk " .. player.Name .. ", donasi tampil tanpa pesan")
		return false
	end
	pending[player] = { text = clean, at = now }
	return true
end

local function takeMessage(player)
	local p = pending[player]
	pending[player] = nil
	if p and os.clock() - p.at <= MSG.ttl then
		return p.text
	end
	return ""
end

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
	lastSet[player] = nil
end)

-- ── Antrean pengumuman (satu per satu) ───────────────────────
local queue = {}
local running = false

-- item.remote = donasi dari server lain: partikel & LiveScreen dilewati (donatur tidak ada di server ini).
-- item.test = tes admin: pesan berawalan [TES], papan tidak diisi.
-- item.external = donasi luar (bagibagi): partikel & LiveScreen di SEMUA server kalau donatur (nama akun
-- Roblox) ada di server itu; nominal tidak ditampilkan (robux = 0).
local function announce(item)
	local message = item.message
	if item.test then
		message = message ~= "" and (Config.test.prefix .. " " .. message) or Config.test.prefix
	end
	showMessage:FireAllClients(item.displayName, item.name, item.robux, message, item.userId)
	-- donasi luar: donatur hanya "ada" kalau namanya akun Roblox yang sedang di server ini
	local donor = item.external and item.userId > 0 and Players:GetPlayerByUserId(item.userId)
	if item.external then
		if donor and item.fxRobux then
			effectEvent:FireAllClients(item.userId, item.fxRobux)
		end
	elseif not item.remote then
		effectEvent:FireAllClients(item.userId, item.robux)
	end
	if not item.test then
		local okBoard, errBoard = pcall(boards.onDonation, boards, item)
		if not okBoard then
			warn("[Donation] papan gagal: " .. tostring(errBoard))
		end
	end
	local big = item.big and bigEvents[item.big]
	if big then
		big:FireAllClients(item.name, Config.bigRecipient, item.robux, item.userId)
	end
	local sig = screenSignal()
	if sig and item.external then
		if donor and item.fxRobux then
			sig:Fire(donor.Name, item.fxRobux)
		end
	elseif sig and not item.remote then
		sig:Fire(item.name, item.robux) -- LiveScreenServer mencari anak Players berdasarkan Player.Name
	end
end

local function pump()
	if running then
		return
	end
	running = true
	while #queue > 0 do
		local item = table.remove(queue, 1)
		local ok, err = pcall(announce, item)
		if not ok then
			warn("[Donation] pengumuman gagal: " .. tostring(err))
		end
		task.wait(item.gap)
	end
	running = false
end

local function enqueue(item)
	if #queue >= Config.queueMax then
		warn("[Donation] antrean penuh, pengumuman " .. item.name .. " dilewati (data tetap tersimpan)")
		return
	end
	table.insert(queue, item)
	task.spawn(pump)
end

-- ── Semua server ─────────────────────────────────────────────
-- Studio memakai topik ber-akhiran _studio: beli uji tidak pernah tampil di server live.
local jobId = (game.JobId ~= "" and game.JobId) or ("studio-" .. HttpService:GenerateGUID(false))
local Global = require(script:WaitForChild("Global"))
local global = Global.new({
	messaging = MessagingService,
	jobId = jobId,
	topic = Config.global.topic .. suffix,
	cfg = Config,
	enqueue = enqueue,
	task = task,
	warn = warn,
})

-- ── Struk ────────────────────────────────────────────────────
local function onReceipt(receipt, player)
	local tier = Config.tierForProduct(receipt.ProductId)
	if not tier then
		return false
	end
	local robux = math.floor(tonumber(receipt.CurrencySpent) or 0)
	if robux <= 0 then
		robux = tier.robux
	end
	local ok, total, isNew = store:record(receipt.PlayerId, receipt.PurchaseId, robux)
	if not ok then
		return false
	end
	if isNew then
		print(("[Donation] %s +%d R$ (total %d)"):format(player.Name, robux, total))
		local item = {
			displayName = player.DisplayName,
			name = player.Name,
			userId = player.UserId,
			robux = robux,
			message = takeMessage(player),
			gap = tier.gap,
			big = tier.big,
			tier = tier.robux,
			purchaseId = tostring(receipt.PurchaseId),
		}
		enqueue(item)
		global:publish(item)
	end
	return true
end

for _, tier in Config.tiers do
	ReceiptHandler.RegisterProduct(tier.productId, onReceipt)
end

-- ── Tes donasi admin ─────────────────────────────────────────
-- Admin = rank grup >= RankConfig.ADMIN_MIN_RANK (sama dengan /global); rank gagal dibaca → ditolak.
local lastTest = {} -- [Player] = os.clock()
local testCount = 0

local RankConfig -- dimuat saat tes pertama (jalur donasi tidak bergantung padanya)
local function isAdmin(player)
	RankConfig = RankConfig or require(SSS:WaitForChild("RankConfig"))
	local ok, rank = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
	return ok and type(rank) == "number" and rank >= RankConfig.ADMIN_MIN_RANK
end

testFn.OnServerInvoke = function(player, robux, text, everywhere)
	if type(robux) ~= "number" or type(text) ~= "string" or type(everywhere) ~= "boolean" then
		return false, "invalid"
	end
	local now = os.clock()
	if lastTest[player] and now - lastTest[player] < Config.test.cooldown then
		return false, "cooldown"
	end
	lastTest[player] = now -- dicatat sebelum cek rank (yield) supaya spam tetap terbatas
	local tier
	for _, t in Config.tiers do
		if t.robux == robux then
			tier = t
		end
	end
	if not tier or #text > MSG.maxBytes then
		return false, "invalid"
	end
	if not isAdmin(player) then
		return false, "admin"
	end
	text = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	local message = ""
	if text ~= "" then
		local cut = cutChars(text, MSG.maxChars)
		message = cut and filterPublic(cut, player.UserId)
		if not message then
			return false, "filter"
		end
	end
	testCount += 1
	local item = {
		displayName = player.DisplayName,
		name = player.Name,
		userId = player.UserId,
		robux = tier.robux,
		message = message,
		gap = tier.gap,
		big = tier.big,
		tier = tier.robux,
		purchaseId = ("test-%s-%d"):format(jobId, testCount),
		test = true,
	}
	print(("[Donation] TES oleh %s: %d R$ (%s)"):format(player.Name, tier.robux, everywhere and "semua server" or "server ini"))
	enqueue(item)
	if everywhere then
		global:publish(item)
	end
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastTest[player] = nil
end)

boards:start()
global:start()

-- ── Donasi luar bagibagi (opsional; gagal dipasang → donasi Robux tetap jalan) ──
local bagibagiModule = script:FindFirstChild("Bagibagi")
if bagibagiModule and Config.bagibagi and Config.bagibagi.enabled then
	local okB, errB = pcall(function()
		local Bagibagi = require(bagibagiModule)
		local BB = Config.bagibagi
		Bagibagi.new({
			cfg = Config,
			http = HttpService,
			store = DataStoreService:GetDataStore(BB.store .. suffix),
			memory = game:GetService("MemoryStoreService"):GetSortedMap(BB.memory .. suffix),
			jobId = jobId,
			players = Players,
			filter = filterPublic,
			enqueue = enqueue,
			publish = function(item)
				global:publish(item)
			end,
			task = task,
			warn = warn,
			print = print,
		}):start()
	end)
	if not okB then
		warn("[Donation] bagibagi tidak aktif: " .. tostring(errB))
	end
end

print(("[Donation] Ready | %d produk | store %s%s"):format(#Config.tiers, Config.store.data, suffix))
