-- ═══════════════════════════════════════════════════════════
-- GlobalAnnouncement — pengumuman admin (/global, /g, /notif)
-- Path: ServerScriptService (Script)
--
-- Payload ke client: { userId, name, text, duration }
-- userId dikirim supaya client bisa menampilkan avatar pengirim.
--
-- FILTER: teks dilihat SEMUA pemain → TextFilterContext.PublicChat +
-- GetNonChatStringForBroadcastAsync, fail-closed (gagal = tidak dikirim).
-- Pengumuman lintas server difilter SEKALI di server asal, lalu dikirim
-- lewat MessagingService. Server penerima tidak bisa memfilter ulang:
-- FilterStringAsync menolak userId yang tidak ada di server itu
-- ("The sender must be connected to the current server", terbukti A0c).
-- Topik MessagingService hanya bisa diterbitkan oleh server game ini.
-- ═══════════════════════════════════════════════════════════

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local MessagingService    = game:GetService("MessagingService")
local TextChatService     = game:GetService("TextChatService")
local TextService         = game:GetService("TextService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RankConfig = require(ServerScriptService:WaitForChild("RankConfig"))

-- ── Constants ───────────────────────────────────────────────

local MIN_ANNOUNCE_RANK = RankConfig.ADMIN_MIN_RANK -- 250
local TOPIC             = "GlobalAnnouncement"
local DEFAULT_DURATION  = 5

-- Batas MessagingService adalah 1 kB per pesan. 200 karakter cukup untuk
-- sebuah pengumuman dan aman di bawah batas bersama nama + userId.
local MAX_TEXT_LENGTH = 200

-- Jeda per staf. /global memakai kuota MessagingService semua server.
local COOLDOWN = { global = 5, notif = 2 }

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
	return ok and type(rank) == "number" and rank >= MIN_ANNOUNCE_RANK
end

local lastUse = {} -- [userId] = { [jenis] = os.clock() }

local function onCooldown(player: Player, kind: string): boolean
	local uid  = player.UserId
	local mine = lastUse[uid] or {}
	lastUse[uid] = mine
	local now = os.clock()
	if mine[kind] and now - mine[kind] < COOLDOWN[kind] then return true end
	mine[kind] = now
	return false
end

Players.PlayerRemoving:Connect(function(player)
	lastUse[player.UserId] = nil
end)

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

-- Filter untuk teks yang dilihat semua pemain. Pengirim WAJIB ada di server ini.
local function filterBroadcast(text: string, userId: number): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" or result == "" then
		warn("[GlobalAnnouncement] filter gagal, pengumuman tidak dikirim")
		return nil
	end
	return result
end

-- ── Broadcast ───────────────────────────────────────────────

-- Teks di sini SUDAH difilter.
local function show(userId: number, name: string, text: string, duration: number?)
	GlobalAnnouncementEvent:FireAllClients({
		userId   = userId,
		name     = name,
		text     = text,
		duration = duration or DEFAULT_DURATION,
	})
end

local function announceLocal(userId: number, name: string, text: string, duration: number?)
	local filtered = filterBroadcast(text, userId)
	if filtered then show(userId, name, filtered, duration) end
end

-- Server ini ikut menerima pesannya sendiri lewat SubscribeAsync.
local function announceGlobal(userId: number, name: string, text: string, duration: number?)
	local filtered = filterBroadcast(text, userId)
	if not filtered then return end
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, {
		userId   = userId,
		name     = name,
		text     = filtered,
		duration = duration or DEFAULT_DURATION,
	})
	if not ok then
		warn("[GlobalAnnouncement] PublishAsync gagal:", err)
	end
end

-- ── Terima dari server lain (teks sudah difilter di server asal) ──
-- SubscribeAsync bisa melempar error (limit / layanan down) → dibungkus
-- supaya tidak mematikan sisa script.

task.spawn(function()
	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC,
		function(message)
			local data = message.Data
			if type(data) ~= "table" then return end

			local text = sanitize(data.text)
			local name = type(data.name) == "string" and data.name or "Staff"
			if not text then return end

			show(tonumber(data.userId) or 0, name, text, tonumber(data.duration))
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

local function makeCommand(primary: string, secondary: string?, kind: string, handler: (Player, string) -> ())
	local cmd = Instance.new("TextChatCommand")
	cmd.Name           = primary:sub(2) .. "Command"
	cmd.PrimaryAlias   = primary
	cmd.SecondaryAlias = secondary or ""
	cmd.Parent         = TextChatService

	cmd.Triggered:Connect(function(textSource, rawMessage)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player or not canAnnounce(player) then return end

		local text = stripAlias(rawMessage)
		if not text or onCooldown(player, kind) then return end
		handler(player, text)
	end)
end

-- /global & /g → semua server
makeCommand("/global", "/g", "global", function(player, text)
	announceGlobal(player.UserId, player.DisplayName, text)
end)

-- /notif → server ini saja
makeCommand("/notif", nil, "notif", function(player, text)
	announceLocal(player.UserId, player.DisplayName, text)
end)

-- ── Fallback dari tombol GUI ────────────────────────────────

GlobalRequestEvent.OnServerEvent:Connect(function(player, announcementText)
	if not canAnnounce(player) then return end
	local text = sanitize(announcementText)
	if not text or onCooldown(player, "global") then return end
	announceGlobal(player.UserId, player.DisplayName, text)
end)
