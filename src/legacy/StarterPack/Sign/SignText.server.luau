-- StarterPack > Sign > LocalScript > RemoteEvent > Script
-- Teks papan Sign terlihat SEMUA pemain → wajib lewat filter teks Roblox.
--
-- [FIX 2026-09-26] versi lama: `TextLabel.Text = text` langsung dari client
--   (tanpa filter, tanpa cek tipe, siapa pun bisa mengubah Sign milik orang lain).
-- Sekarang:
--   • hanya pemilik tool (tool ada di Character/Backpack-nya) yang boleh mengubah
--   • teks harus string, dipotong ke MAX_CHARS karakter (aman UTF-8), baris baru dibuang
--   • TextService:FilterStringAsync → GetNonChatStringForBroadcastAsync
--   • fail-closed: kalau filter gagal, teks lama TIDAK diganti
--   • [SOCIAL] teks publik 1× per menit PER PEMAIN (pedoman resmi Roblox, Config/Social PUBLIC_TEXT): waktu
--     terakhir di atribut Player → tidak reset saat respawn / tool baru. Slot dipesan sebelum filter (2 kiriman
--     cepat tidak lolos berdua) dan dikembalikan kalau filter gagal. Teks sama dengan yang terpasang tidak dihitung.

local TextService = game:GetService("TextService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local PUBLIC = require(RS:WaitForChild("Config"):WaitForChild("Social")).PUBLIC_TEXT
local SocialRules = require(RS:WaitForChild("Modules"):WaitForChild("SocialRules"))

local MAX_CHARS = 100
local ATTR = PUBLIC.ATTR.SIGN

local remote = script.Parent
local tool = remote.Parent.Parent
local label = tool:WaitForChild("Handle"):WaitForChild("Part"):WaitForChild("SurfaceGui"):WaitForChild("TextLabel")

local lastText = nil -- teks (sebelum filter) yang terakhir terpasang di Sign ini

local function isOwner(player: Player): boolean
	local parent = tool.Parent
	if parent == nil then
		return false
	end
	if parent == player.Character then
		return true
	end
	return parent == player:FindFirstChildOfClass("Backpack")
end

local function clip(text: string): string
	text = string.gsub(text, "[%c]", " ")
	local ok, len = pcall(utf8.len, text)
	if not ok or len == nil then
		return "" -- bukan UTF-8 valid → tolak
	end
	if len > MAX_CHARS then
		local cut = utf8.offset(text, MAX_CHARS + 1)
		text = string.sub(text, 1, cut - 1)
	end
	return text
end

remote.OnServerEvent:Connect(function(player: Player, text: any)
	if typeof(text) ~= "string" then
		return
	end
	if not isOwner(player) then
		return
	end

	text = clip(text)
	if string.match(text, "^%s*$") or text == lastText then
		return
	end
	local now = workspace:GetServerTimeNow()
	local previous = player:GetAttribute(ATTR)
	if SocialRules.textWait(previous, now, PUBLIC.COOLDOWN) > 0 then
		return
	end
	player:SetAttribute(ATTR, now) -- pesan slot sebelum filter (yield)

	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filtered) ~= "string" then
		warn("[Sign] filter gagal, teks tidak diubah:", filtered)
		player:SetAttribute(ATTR, previous) -- slot dikembalikan
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) or not isOwner(player) then
		player:SetAttribute(ATTR, previous)
		return -- pemain keluar / tool pindah tangan selama filter berjalan
	end
	lastText = text
	label.Text = filtered
end)
