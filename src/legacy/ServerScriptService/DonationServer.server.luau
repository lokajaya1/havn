-- [FIX] Filter teks wajib untuk semua teks pemain yang disiarkan
local TextService = game:GetService("TextService")
local function filterBroadcast(text, userId)
	if type(text) ~= "string" or text == "" then return nil end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId)
	end)
	if not ok then return nil end
	local ok2, clean = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	return ok2 and clean or nil
end

-- DONATION SERVER v2 — dengan Message System
-- ServerScriptService > Script
-- Ganti DonationServer lama dengan ini

local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Market  = game:GetService("MarketplaceService")

local DEFAULT_RECIPIENT = "SICK HAVN"
local COOLDOWN = 5
local MIN_ROBUX_FOR_MESSAGE = 20   -- ⬅ tambahkan ini di dekat DEFAULT_RECIPIENT
local recentKeys = {}
local processedReceipts = {}

local function ensureFolder(parent, name)
	local f=parent:FindFirstChild(name)
	if not f then f=Instance.new("Folder"); f.Name=name; f.Parent=parent end
	return f
end
local function ensureInstance(className, name, parent)
	local i=parent:FindFirstChild(name)
	if not i then i=Instance.new(className); i.Name=name; i.Parent=parent end
	return i
end

local RemoteFolder = ensureFolder(RS, "DonationRemotes")

local PRICE_TIERS = {
	{price=10,    remoteName="FireLevel1"   },
	{price=50,    remoteName="FireLevel2"   },
	{price=100,   remoteName="FireLevel3"   },
	{price=200,   remoteName="FireLevel4"   },
	{price=500,   remoteName="FireLevel5"   },
	{price=1000,  remoteName="FireNuke"     },
	{price=2000,  remoteName="FireLevel6"   },
	{price=3000,  remoteName="FireLevel7"   },
	{price=5000,  remoteName="FireHammer"   },
	{price=10000, remoteName="FireBlackHole"},
}
for _, tier in ipairs(PRICE_TIERS) do
	tier.remote = ensureInstance("RemoteEvent", tier.remoteName, RemoteFolder)
end

-- LiveSystem signal
local liveSystem = RS:FindFirstChild("LiveSystem")
local donationScreenSignal = nil
if liveSystem then
	donationScreenSignal = liveSystem:FindFirstChild("DonationScreenSignal")
	if not donationScreenSignal then
		donationScreenSignal = Instance.new("BindableEvent")
		donationScreenSignal.Name = "DonationScreenSignal"
		donationScreenSignal.Parent = liveSystem
	end
end

-- ══ DONATION MESSAGE SYSTEM ══════════════════════════════
-- Folder dibuat di sini — shared dengan LeaderboardServer
local msgFolder = ensureFolder(RS, "DonationMessageSystem")
local promptMessageEvent = ensureInstance("RemoteEvent", "PromptMessage", msgFolder)
local submitMessageEvent = ensureInstance("RemoteEvent", "SubmitMessage", msgFolder)
local showMessageEvent   = ensureInstance("RemoteEvent", "ShowMessage",   msgFolder)

-- Pending prompts: userId → {productId, price, timer}
local pendingPrompts = {}
local PROMPT_TIMEOUT = 30 -- detik sebelum auto-skip

-- ═════════════════════════════════════════════════════════

local function getTier(amount)
	local matched
	for _, tier in ipairs(PRICE_TIERS) do
		if amount >= tier.price then matched = tier end
	end
	return matched
end

local function getPrice(productId)
	local ok, info = pcall(Market.GetProductInfo, Market, productId, Enum.InfoType.Product)
	return (ok and info and info.PriceInRobux) or 0
end

local function getPlayerName(userId)
	local p=Players:GetPlayerByUserId(userId)
	if p then return p.Name, p.DisplayName end
	local ok, name=pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local n=ok and name or ("Player"..userId)
	return n, n
end

local function isOnCooldown(userId, productId)
	local key=userId.."_"..productId
	if recentKeys[key] and (tick()-recentKeys[key])<COOLDOWN then return true end
	recentKeys[key]=tick()
	task.delay(COOLDOWN+1, function() recentKeys[key]=nil end)
	return false
end

local function fireDonationVFX(username, displayName, price, userId)
	local tier=getTier(price)
	if not tier then return end
	tier.remote:FireAllClients(username, DEFAULT_RECIPIENT, price, userId)
	if donationScreenSignal then
		donationScreenSignal:Fire(displayName ~= "" and displayName or username, price)
	end
end

local function processPurchase(userId, productId, price)
	if not price or price<=0 then price=getPrice(productId) end
	local tier=getTier(price)
	if not tier then return false end
	if isOnCooldown(userId, productId) then return false end

	local username, displayName = getPlayerName(userId)

	-- Fire VFX (selalu jalan untuk semua donasi, berapapun jumlahnya)
	fireDonationVFX(username, displayName, price, userId)

	-- Cek apakah donasi ini eligible untuk prompt message
	if price >= MIN_ROBUX_FOR_MESSAGE then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			promptMessageEvent:FireClient(player, productId, price)
			pendingPrompts[userId] = {productId=productId, price=price, username=username, displayName=displayName}
			task.delay(PROMPT_TIMEOUT, function()
				if pendingPrompts[userId] and pendingPrompts[userId].productId == productId then
					pendingPrompts[userId] = nil
					showMessageEvent:FireAllClients(displayName, username, price, "")
				end
			end)
		else
			showMessageEvent:FireAllClients(username, username, price, "")
		end
	else
		-- Di bawah 100 Robux: langsung show notifikasi donasi tanpa prompt pesan
		showMessageEvent:FireAllClients(displayName, username, price, "")
	end

	return true
end

-- Terima submit message dari client
submitMessageEvent.OnServerEvent:Connect(function(player, productId, message)
	local userId = player.UserId
	local pending = pendingPrompts[userId]
	if not pending then return end

	-- Clear pending
	pendingPrompts[userId] = nil

	local username  = pending.username or player.Name
	local dispName  = pending.displayName or player.DisplayName
	local price     = pending.price or 0
	local cleanMsg  = filterBroadcast(message and tostring(message):sub(1, 100), userId) or ""

	-- Fire ShowMessage ke semua client
	showMessageEvent:FireAllClients(dispName, username, price, cleanMsg)
	print(string.format("[DonationServer] Message dari %s: \"%s\"", username, cleanMsg))
end)

-- ProcessReceipt
Market.ProcessReceipt = function(receipt)
	if not (receipt and receipt.PlayerId and receipt.ProductId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key=receipt.PlayerId.."_"..(receipt.PurchaseId or os.time())
	if processedReceipts[key] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	processedReceipts[key]=true
	task.delay(60, function() processedReceipts[key]=nil end)
	processPurchase(receipt.PlayerId, receipt.ProductId, receipt.CurrencySpent)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

Market.PromptProductPurchaseFinished:Connect(function(playerOrId, productId, purchased)
	if not purchased then return end
	local userId = type(playerOrId)=="number" and playerOrId
		or (typeof(playerOrId)=="Instance" and playerOrId:IsA("Player") and playerOrId.UserId)
	if not userId then return end
	task.wait(1)
	processPurchase(userId, productId, getPrice(productId))
end)

print("✅ [DonationServer v2] Loaded — VFX + Message System aktif!")