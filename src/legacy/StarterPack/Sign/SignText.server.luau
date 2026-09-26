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
--   • cooldown per Sign supaya tidak bisa di-spam (filter punya batas panggilan)

local TextService = game:GetService("TextService")
local Players = game:GetService("Players")

local MAX_CHARS = 100
local COOLDOWN = 1 -- detik

local remote = script.Parent
local tool = remote.Parent.Parent
local label = tool:WaitForChild("Handle"):WaitForChild("Part"):WaitForChild("SurfaceGui"):WaitForChild("TextLabel")

local lastChange = 0

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
	local now = os.clock()
	if now - lastChange < COOLDOWN then
		return
	end
	lastChange = now

	text = clip(text)
	if string.match(text, "^%s*$") then
		return
	end

	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filtered) ~= "string" then
		warn("[Sign] filter gagal, teks tidak diubah:", filtered)
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) or not isOwner(player) then
		return -- pemain keluar / tool pindah tangan selama filter berjalan
	end
	label.Text = filtered
end)
