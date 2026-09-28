-- ServerScriptService.DonationServer — donasi Robux (Developer Product).
-- Struk HANYA lewat ReceiptHandler.RegisterProduct (satu ProcessReceipt per game; tidak memakai
-- PromptProductPurchaseFinished — itu bukan bukti bayar dan ikut menyala untuk gift Shop).
-- Alur: pemain (opsional) kirim pesan → server filter PublicChat → pemain beli produk →
-- struk: total disimpan tepat sekali (Store) → antrean pengumuman: notifikasi + efek semua pemain + LiveScreen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

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

-- ── Remote (folder & nama lama dipertahankan: DonationMessageNotification mendengar ShowMessage) ──
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

local function announce(item)
	showMessage:FireAllClients(item.displayName, item.name, item.robux, item.message, item.userId)
	effectEvent:FireAllClients(item.userId, item.robux)
	local okBoard, errBoard = pcall(boards.onDonation, boards, item)
	if not okBoard then
		warn("[Donation] papan gagal: " .. tostring(errBoard))
	end
	local big = item.big and bigEvents[item.big]
	if big then
		big:FireAllClients(item.name, Config.bigRecipient, item.robux, item.userId)
	end
	local sig = screenSignal()
	if sig then
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
		enqueue({
			displayName = player.DisplayName,
			name = player.Name,
			userId = player.UserId,
			robux = robux,
			message = takeMessage(player),
			gap = tier.gap,
			big = tier.big,
		})
	end
	return true
end

for _, tier in Config.tiers do
	ReceiptHandler.RegisterProduct(tier.productId, onReceipt)
end

boards:start()

print(("[Donation] Ready | %d produk | store %s%s"):format(#Config.tiers, Config.store.data, suffix))
