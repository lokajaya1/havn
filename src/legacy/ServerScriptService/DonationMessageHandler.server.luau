--!strict
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

-- DonationMessageHandler | ServerScriptService (Script)
-- Prompt donor untuk kirim pesan, broadcast ke notification panel
-- TIDAK kirim ke chat display (DonationServer handle chat)
-- ═══════════════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- ── Config ──────────────────────────────────────────────
local CONFIG = {
	MinRobuxForMessage = 100,
	MaxMessageLength   = 100,
	PromptCleanupTime  = 300,
	CleanupInterval    = 60,
}

-- ── Remote Events ───────────────────────────────────────
local RemoteFolder = ReplicatedStorage:FindFirstChild("DonationMessageSystem")
if not RemoteFolder then
	RemoteFolder = Instance.new("Folder")
	RemoteFolder.Name = "DonationMessageSystem"
	RemoteFolder.Parent = ReplicatedStorage
end

local function GetOrCreateRemote(name: string): RemoteEvent
	local existing = RemoteFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name = name; event.Parent = RemoteFolder
	return event
end

local PromptMessageEvent = GetOrCreateRemote("PromptMessage")
local SubmitMessageEvent = GetOrCreateRemote("SubmitMessage")
local ShowMessageEvent   = GetOrCreateRemote("ShowMessage")

-- ── Storage ─────────────────────────────────────────────
local pendingPrompts: {[number]: {productId: number, robuxAmount: number, timestamp: number}} = {}

-- ── Util ────────────────────────────────────────────────
local function SanitizeMessage(message: string?): string?
	if not message or type(message) ~= "string" then return nil end
	message = message:gsub("^%s+", ""):gsub("%s+$", "")
	if #message > CONFIG.MaxMessageLength then message = message:sub(1, CONFIG.MaxMessageLength) end
	return #message > 0 and message or nil
end

local function GetProductInfo(productId: number): {Name: string, PriceInRobux: number}?
	local success, productInfo = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	return success and productInfo or nil
end

-- ── Message Submission ──────────────────────────────────
SubmitMessageEvent.OnServerEvent:Connect(function(player: Player, productId: number, message: string?)
	if not player or not productId then return end
	message = SanitizeMessage(message)
	message = message and filterBroadcast(message, player.UserId)

	local promptData = pendingPrompts[player.UserId]
	if not promptData then return end

	local robuxAmount = promptData.robuxAmount
	pendingPrompts[player.UserId] = nil

	if message then
		task.spawn(function()
			task.wait(0.3)
			ShowMessageEvent:FireAllClients(player.DisplayName, player.Name, robuxAmount, message)
		end)
	end
end)

-- ── Purchase Listener (SIGNAL, no conflict) ─────────────
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
	if not isPurchased then return end

	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	local productInfo = GetProductInfo(productId)
	if not productInfo or productInfo.PriceInRobux < CONFIG.MinRobuxForMessage then return end

	pendingPrompts[userId] = {
		productId = productId,
		robuxAmount = productInfo.PriceInRobux,
		timestamp = tick()
	}

	task.wait(0.3)
	PromptMessageEvent:FireClient(player, productId, productInfo.PriceInRobux)
end)

-- ── Cleanup ─────────────────────────────────────────────
task.spawn(function()
	while true do
		task.wait(CONFIG.CleanupInterval)
		local currentTime = tick()
		for userId, data in pairs(pendingPrompts) do
			if currentTime - data.timestamp > CONFIG.PromptCleanupTime then
				pendingPrompts[userId] = nil
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player) pendingPrompts[player.UserId] = nil end)