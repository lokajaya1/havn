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

-- ═══════════════════════════════════════════════════════════
-- GlobalAnnouncement — pengumuman admin (/global, /g, /notif)
-- Path: ServerScriptService (Script)
--
-- Payload ke client: { userId, name, text, duration }
-- userId dikirim supaya client bisa menampilkan avatar pengirim. Dulu
-- server mengirim satu string "Nama: teks" yang sudah digabung, jadi
-- client tidak punya cara tahu siapa pengirimnya.
-- ═══════════════════════════════════════════════════════════

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local MessagingService    = game:GetService("MessagingService")
local TextChatService     = game:GetService("TextChatService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RankConfig = require(ServerScriptService:WaitForChild("RankConfig"))

-- ── Constants ───────────────────────────────────────────────

local MIN_ANNOUNCE_RANK = 250
local TOPIC             = "GlobalAnnouncement"
local DEFAULT_DURATION  = 5

-- Batas MessagingService adalah 1 kB per pesan. Dulu 1000 karakter, yang
-- artinya payload + nama + userId bisa lewat batas dan PublishAsync gagal
-- tanpa kelihatan. 200 karakter cukup untuk sebuah pengumuman.
local MAX_TEXT_LENGTH = 200

-- ── Remotes ─────────────────────────────────────────────────

local function remote(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end

	local obj = Instance.new("RemoteEvent")
	obj.Name   = name
	obj.Parent = ReplicatedStorage
	return obj
end

local GlobalAnnouncementEvent = remote("GlobalAnnouncementEvent")
local GlobalRequestEvent      = remote("GlobalRequestEvent")

-- ── Helpers ─────────────────────────────────────────────────

local function canAnnounce(player: Player): boolean
	local ok, rank = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
	return ok and rank >= MIN_ANNOUNCE_RANK
end

local function sanitize(text: any): string?
	if type(text) ~= "string" then return nil end
	local clean = text:match("^%s*(.-)%s*$")
	if clean == "" then return nil end
	if #clean > MAX_TEXT_LENGTH then clean = clean:sub(1, MAX_TEXT_LENGTH) end
	return clean
end

-- Ambil teks setelah alias perintah ("/global halo semua" → "halo semua")
local function stripAlias(raw: string): string?
	local text = raw:match("^%S+%s+(.*)")
	return text and sanitize(text) or nil
end

-- ── Broadcast ───────────────────────────────────────────────

local function announceLocal(userId: number, name: string, text: string, duration: number?)
	text = filterBroadcast(text, userId)
	if not text then return end
	GlobalAnnouncementEvent:FireAllClients({
		userId   = userId,
		name     = name,
		text     = text,
		duration = duration or DEFAULT_DURATION,
	})
end

local function announceGlobal(userId: number, name: string, text: string, duration: number?)
	text = filterBroadcast(text, userId)
	if not text then return end
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, {
		userId   = userId,
		name     = name,
		text     = text,
		duration = duration or DEFAULT_DURATION,
	})
	if not ok then
		warn("[GlobalAnnouncement] PublishAsync gagal:", err)
	end
end

-- ── Terima dari server lain ─────────────────────────────────
-- SubscribeAsync bisa melempar error (limit / layanan down); dulu tidak
-- dibungkus, jadi kegagalannya mematikan sisa script di bawahnya.

task.spawn(function()
	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC,
		function(message)
			local data = message.Data
			if type(data) ~= "table" then return end

			local text = sanitize(data.text)
			local name = type(data.name) == "string" and data.name or "Staff"
			if not text then return end

			announceLocal(tonumber(data.userId) or 0, name, text, tonumber(data.duration))
		end)

	if not ok then
		warn("[GlobalAnnouncement] SubscribeAsync gagal:", err)
	end
end)

-- ── Notif saat staff join ───────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	task.wait(2) -- beri jeda supaya rank ter-fetch
	if not player.Parent then return end
	if not canAnnounce(player) then return end

	announceLocal(player.UserId, player.DisplayName, "joined the server.")
end)

-- ── Chat commands ───────────────────────────────────────────

local function makeCommand(primary: string, secondary: string?, handler: (Player, string) -> ())
	local cmd = Instance.new("TextChatCommand")
	cmd.Name           = primary:sub(2) .. "Command"
	cmd.PrimaryAlias   = primary
	cmd.SecondaryAlias = secondary or ""
	cmd.Parent         = TextChatService

	cmd.Triggered:Connect(function(textSource, rawMessage)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player or not canAnnounce(player) then return end

		local text = stripAlias(rawMessage)
		if text then handler(player, text) end
	end)
end

-- /global & /g → semua server
makeCommand("/global", "/g", function(player, text)
	announceGlobal(player.UserId, player.DisplayName, text)
end)

-- /notif → server ini saja
makeCommand("/notif", nil, function(player, text)
	announceLocal(player.UserId, player.DisplayName, text)
end)

-- ── Fallback dari tombol GUI ────────────────────────────────

GlobalRequestEvent.OnServerEvent:Connect(function(player, announcementText)
	if not canAnnounce(player) then return end
	local text = sanitize(announcementText)
	if text then
		announceGlobal(player.UserId, player.DisplayName, text)
	end
end)