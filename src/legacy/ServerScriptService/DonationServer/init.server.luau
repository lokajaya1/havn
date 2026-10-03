-- ServerScriptService.DonationServer — donasi Robux (Developer Product).
-- Struk HANYA lewat ReceiptHandler.RegisterProduct (satu ProcessReceipt per game; tidak memakai
-- PromptProductPurchaseFinished — itu bukan bukti bayar dan ikut menyala untuk gift Shop).
-- Alur: pemain (opsional) kirim pesan → server filter PublicChat → pemain beli produk →
-- struk: total disimpan tepat sekali (Store) → antrean pengumuman: notifikasi + efek semua pemain + LiveScreen,
-- lalu dikirim ke server lain (Global): di sana notifikasi, papan & efek besar (tanpa partikel/LiveScreen).
-- Tes admin (TestDonation): pengumuman yang sama tanpa Marketplace & tanpa data, pesan berawalan [TES], papan tidak diisi;
-- donatur boleh pemain lain di server ini (Admin panel). TestEffect: efek tier saja (tanpa notifikasi/data/papan).
-- Donasi luar bagibagi (Bagibagi): robux = 0 + poin `gold`, efek dari tier `fxRobux`, tampil di papan Gold (bukan Robux).
-- Setelan produk (Tiers, opsional): admin rank >= Config.tierEdit.rank mengubah nama/partikel/kamera/efek besar per
-- Developer Product & menambah produk lewat DonationRemotes.TierEdit; daftar tier ke client lewat atribut DonationRemotes.Tiers.
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
-- [SOCIAL] pesan donatur tampil ke semua (semua server) → teks publik 1× per menit per pemain (pedoman resmi Roblox,
-- Config/Social PUBLIC_TEXT). Yang dihitung = pesan yang benar-benar TAMPIL (atribut Player diisi saat struk).
local PUBLIC = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Social")).PUBLIC_TEXT
local SocialRules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SocialRules"))
local suffix = RunService:IsStudio() and Config.store.studioSuffix or ""
local orderedStore = DataStoreService:GetOrderedDataStore(Config.store.ordered .. suffix)
local store = Store.new(DataStoreService:GetDataStore(Config.store.data .. suffix), orderedStore, Config.store, task.delay)
-- Papan & baris "You": di Studio boleh MEMBACA peringkat live (Config.store.studioReadsLive) — hanya GetSortedAsync /
-- GetAsync; semua tulisan (beli uji) tetap ke store _studio di atas.
local boardsLive = suffix ~= "" and Config.store.studioReadsLive == true
local boardOrdered = boardsLive and DataStoreService:GetOrderedDataStore(Config.store.ordered) or orderedStore
local Boards = require(script:WaitForChild("Boards"))
local boards = Boards.new({
	ordered = boardOrdered,
	folder = workspace:FindFirstChild("DonationBoards"),
	services = { Players = Players, UserService = game:GetService("UserService") },
	cfg = Config,
	task = task,
	warn = warn,
	now = function()
		return workspace:GetServerTimeNow()
	end,
})

-- LIVE DONATIONS = donasi hari ini (WIB) lintas server & tahan restart (Feed, opsional; gagal → papan memori saja).
local feed
local feedModule = script:FindFirstChild("Feed")
if feedModule and Config.feed and Config.feed.enabled then
	local okF, errF = pcall(function()
		local Feed = require(feedModule)
		feed = Feed.new({
			cfg = Config,
			memory = game:GetService("MemoryStoreService"),
			descending = Enum.SortDirection.Descending,
			suffix = suffix,
			now = function()
				return workspace:GetServerTimeNow()
			end,
			warn = warn,
		})
		boards.feedSource = function(kind)
			return feed:read(kind)
		end
	end)
	if not okF then
		feed = nil
		warn("[Donation] feed harian tidak aktif: " .. tostring(errF))
	end
end

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
local showMessage = ensure(folder, "RemoteEvent", "ShowMessage") -- (displayName, username, robux, message, userId, gold)
local setMessage = ensure(folder, "RemoteFunction", "SetMessage") -- client → server: teks → true/false
local remotes = ensure(ReplicatedStorage, "Folder", "DonationRemotes")
local effectEvent = ensure(remotes, "RemoteEvent", "Effect") -- server → client: (userId, robux, cam?, fxName?)
local testFn = ensure(remotes, "RemoteFunction", "TestDonation") -- admin: (robux, pesan, semuaServer, targetUserId?) → ok, alasan
local testFxFn = ensure(remotes, "RemoteFunction", "TestEffect") -- admin: (fx?, cam?, big?, targetUserId?) → ok, alasan
-- Efek besar (Nuke / Smite / BlackHole): (username, penerima, robux, userId) — dipakai StarterGui.DonationBigFX.
local bigEvents = {}
for _, b in Config.bigList do
	bigEvents[b.name] = ensure(remotes, "RemoteEvent", b.name)
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
	local left = SocialRules.textWait(player:GetAttribute(PUBLIC.ATTR.DONATION), workspace:GetServerTimeNow(), PUBLIC.COOLDOWN)
	if left > 0 then
		pending[player] = nil
		return false, math.ceil(left) -- client: "bisa menulis pesan lagi dalam N dtk"
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
		local now = workspace:GetServerTimeNow()
		if SocialRules.textWait(player:GetAttribute(PUBLIC.ATTR.DONATION), now, PUBLIC.COOLDOWN) > 0 then
			return "" -- pesan lain baru tampil < 1 menit lalu: donasi tetap tampil, pesannya dibuang
		end
		player:SetAttribute(PUBLIC.ATTR.DONATION, now)
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
	showMessage:FireAllClients(item.displayName, item.name, item.robux, message, item.userId, item.gold)
	-- donasi luar: donatur hanya "ada" kalau namanya akun Roblox yang sedang di server ini
	local donor = item.external and item.userId > 0 and Players:GetPlayerByUserId(item.userId)
	-- partikel & kamera: dari produk yang dibeli (item.fx/cam, false = OFF) atau tier harga (bagibagi)
	local fx, cam
	if item.fx ~= nil or item.cam ~= nil then
		fx, cam = item.fx or nil, item.cam or nil
	else
		local fxTier = Config.tierForRobux(item.fxRobux or item.robux)
		fx, cam = fxTier and fxTier.fx, fxTier and fxTier.cam
	end
	if not item.remote then
		print(("[Donation] efek %s: partikel %s · kamera %s · efek besar %s"):format(item.name, fx or "OFF", cam or "OFF",
			item.big or "OFF"))
	end
	if item.external then
		if donor and item.fxRobux then
			effectEvent:FireAllClients(item.userId, item.fxRobux, cam, fx)
		end
	elseif not item.remote then
		effectEvent:FireAllClients(item.userId, item.robux, cam, fx)
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
	if feed and not item.remote and not item.test then
		task.spawn(feed.record, feed, item) -- server asal: simpan ke feed harian (latar, tidak menahan antrean)
	end
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
-- Produk tambahan yang sudah dihapus admin tetap diterima (tanpa efek) supaya struk tidak menggantung.
local function onReceipt(receipt, player)
	local tier = Config.tierForProduct(receipt.ProductId) or { robux = 0, gap = Config.bagibagi.gap }
	local robux = math.floor(tonumber(receipt.CurrencySpent) or 0)
	if robux <= 0 then
		robux = tier.robux
	end
	if robux <= 0 then
		return false
	end
	local ok, total, isNew = store:record(receipt.PlayerId, receipt.PurchaseId, robux)
	if not ok then
		return false
	end
	if isNew then
		print(("[Donation] %s +%d R$ (total %d)"):format(player.Name, robux, total))
		if not boardsLive then
			pcall(player.SetAttribute, player, "DonationTotal", total)
		end
		local item = {
			displayName = player.DisplayName,
			name = player.Name,
			userId = player.UserId,
			robux = robux,
			message = takeMessage(player),
			gap = tier.gap,
			big = tier.big,
			fx = tier.fx or false,
			cam = tier.cam or false,
			tier = tier.robux ~= 0 and tier.robux or nil,
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

-- Donatur tes: diri sendiri, atau pemain lain yang sedang di server ini (targetUserId dari Admin panel).
local function testDonor(player, targetUserId)
	if targetUserId == nil then
		return player
	end
	if type(targetUserId) ~= "number" or targetUserId % 1 ~= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(targetUserId)
end

testFn.OnServerInvoke = function(player, robux, text, everywhere, targetUserId)
	if type(robux) ~= "number" or type(text) ~= "string" or type(everywhere) ~= "boolean" then
		return false, "invalid"
	end
	local now = os.clock()
	if lastTest[player] and now - lastTest[player] < Config.test.cooldown then
		return false, "cooldown"
	end
	lastTest[player] = now -- dicatat sebelum cek rank (yield) supaya spam tetap terbatas
	local tier = Config.tierForProduct(robux) -- Admin panel mengirim productId; panel lama mengirim harga
	if not tier then
		for _, t in Config.tiers do
			if t.robux == robux then
				tier = t
			end
		end
	end
	if not tier or #text > MSG.maxBytes then
		return false, "invalid"
	end
	if not isAdmin(player) then
		return false, "admin"
	end
	local donor = testDonor(player, targetUserId)
	if not donor then
		return false, "target"
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
		displayName = donor.DisplayName,
		name = donor.Name,
		userId = donor.UserId,
		robux = tier.robux,
		message = message,
		gap = tier.gap,
		big = tier.big,
		fx = tier.fx or false,
		cam = tier.cam or false,
		tier = tier.robux,
		purchaseId = ("test-%s-%d"):format(jobId, testCount),
		test = true,
	}
	print(("[Donation] TES oleh %s: %d R$%s (%s)"):format(player.Name, tier.robux,
		donor ~= player and (" atas nama " .. donor.Name) or "", everywhere and "semua server" or "server ini"))
	enqueue(item)
	if everywhere then
		global:publish(item)
	end
	return true
end

-- Tes efek (Admin panel): hanya visual — partikel (fx) dan/atau kamera sinematik (cam) di target, atau efek besar (big)
-- di map. Tanpa notifikasi, data, papan. Nama divalidasi dari Config (effects, cinematic.modes, tier.big).
local lastFx = {} -- [Player] = os.clock()
testFxFn.OnServerInvoke = function(player, fx, cam, big, targetUserId)
	local okFx = fx == nil or (type(fx) == "string" and Config.effects[fx] ~= nil)
	local okCam = cam == nil or Config.isCamMode(cam)
	local okBig = big == nil or (type(big) == "string" and Config.isBig(big))
	if not (okFx and okCam and okBig) or (fx == nil and cam == nil and big == nil) then
		return false, "invalid"
	end
	local now = os.clock()
	if lastFx[player] and now - lastFx[player] < Config.test.cooldown then
		return false, "cooldown"
	end
	lastFx[player] = now
	if not isAdmin(player) then
		return false, "admin"
	end
	local target = testDonor(player, targetUserId)
	if not target then
		return false, "target"
	end
	if big then
		local robux = 0
		for _, t in Config.tiers do
			if t.big == big then
				robux = t.robux
			end
		end
		bigEvents[big]:FireAllClients(target.Name, Config.bigRecipient, robux, target.UserId)
	end
	if fx or cam then
		effectEvent:FireAllClients(target.UserId, 0, cam, fx)
	end
	local what = {}
	for _, part in { fx or false, cam and ("kamera " .. cam) or false, big or false } do
		if part then
			table.insert(what, part)
		end
	end
	print(("[Donation] TES efek oleh %s: %s di %s"):format(player.Name, table.concat(what, " + "), target.Name))
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastTest[player] = nil
	lastFx[player] = nil
end)

boards:start()
global:start()

local function hasRank(player, minRank)
	RankConfig = RankConfig or require(SSS:WaitForChild("RankConfig"))
	local ok, rank = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
	return ok and type(rank) == "number" and rank >= minRank
end

-- ── Setelan produk dari Admin panel (opsional; gagal → tier bawaan Config) ──
local tierEditFn = ensure(remotes, "RemoteFunction", "TierEdit") -- (op, productId, field, value) → ok, alasan
local tiersModule = script:FindFirstChild("Tiers")
local tierSettings
if tiersModule and Config.tierEdit then
	local okT, errT = pcall(function()
		local Tiers = require(tiersModule)
		local E = Config.tierEdit
		local Market = game:GetService("MarketplaceService")
		tierSettings = Tiers.new({
			cfg = Config,
			store = DataStoreService:GetDataStore(E.store .. suffix),
			messaging = MessagingService,
			jobId = jobId,
			suffix = suffix,
			products = function() -- { [ProductId] = { price, name } } semua Developer Product experience ini
				local map = {}
				local pages = Market:GetDeveloperProductsAsync()
				for _ = 1, 20 do
					for _, p in pages:GetCurrentPage() do
						local id = tonumber(p.ProductId)
						if id then
							map[id] = { price = tonumber(p.PriceInRobux), name = p.Name }
						end
					end
					if pages.IsFinished then
						break
					end
					pages:AdvancePageAsync()
				end
				return map
			end,
			isForeign = function(id)
				local h = ReceiptHandler.ProductHandlers and ReceiptHandler.ProductHandlers[id]
				return h ~= nil and h ~= onReceipt
			end,
			register = function(id)
				ReceiptHandler.RegisterProduct(id, onReceipt)
			end,
			publish = function(list)
				remotes:SetAttribute("Tiers", HttpService:JSONEncode(list))
			end,
			filter = filterPublic,
			isEditor = function(player)
				return hasRank(player, E.rank)
			end,
			clock = os.clock,
			task = task,
			warn = warn,
			print = print,
		})
		tierEditFn.OnServerInvoke = function(player, ...)
			return tierSettings:edit(player, ...)
		end
		Players.PlayerRemoving:Connect(function(player)
			tierSettings.last[player] = nil
		end)
		task.spawn(tierSettings.start, tierSettings)
	end)
	if not okT then
		warn("[Donation] setelan produk tidak aktif: " .. tostring(errT))
	end
end
if not tierSettings then
	tierEditFn.OnServerInvoke = function()
		return false, "notready"
	end
end

-- Baris "You" di papan (src/client/DonationBoards): peringkat dari Boards + total donasi Robux sendiri.
-- DonationEditor = boleh mengubah setelan produk (tab Produk di Admin panel; server tetap mengecek rank lagi).
local function onJoin(player)
	boards:applyRank(player)
	if Config.tierEdit and hasRank(player, Config.tierEdit.rank) and player.Parent then
		pcall(player.SetAttribute, player, "DonationEditor", true)
	end
	local ok, total = pcall(boardOrdered.GetAsync, boardOrdered, tostring(player.UserId))
	if ok and player.Parent then
		pcall(player.SetAttribute, player, "DonationTotal", tonumber(total) or 0)
	end
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(onJoin, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end

-- ── Donasi luar bagibagi (opsional; gagal dipasang → donasi Robux tetap jalan) ──
local bagibagiModule = script:FindFirstChild("Bagibagi")
if bagibagiModule and Config.bagibagi and Config.bagibagi.enabled then
	local okB, errB = pcall(function()
		local Bagibagi = require(bagibagiModule)
		local BB = Config.bagibagi
		local bb = Bagibagi.new({
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
		})
		bb:start()
		boards.goldSource = function()
			return bb:readSummary() -- peringkat Gold (papan TOP & patung Gold)
		end
	end)
	if not okB then
		warn("[Donation] bagibagi tidak aktif: " .. tostring(errB))
	end
end

print(("[Donation] Ready | %d produk | store %s%s"):format(#Config.tiers, Config.store.data, suffix))
