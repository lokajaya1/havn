-- ═══════════════════════════════════════════════════════════
-- HideAvatarManager — sembunyikan avatar pemain lain (HANYA di layar sendiri)
-- Path: ReplicatedStorage.CustomUIModules.HideAvatarManager
--
-- Cara per kelas: Config/Social HIDE (aturan SocialRules.hideAction):
--   bagian & decal → LocalTransparencyModifier = 1 (khusus client ini; perintah
--     server /ghost /normal /hat yang menulis Transparency tidak memunculkannya lagi)
--   BillboardGui / SurfaceGui → Enabled = false, nilai asli dipulihkan saat Show
--   efek yang dinyalakan-matikan server (WaterGun, Money Gun, Broom) → dilepas
--     sementara (Parent = nil lokal) lalu dikembalikan → status dari server tetap benar
-- Bagian yang datang belakangan (aksesori, tool, nametag baru) & karakter baru
-- sesudah respawn ikut disembunyikan. Transparency, CanCollide, Humanoid TIDAK
-- disentuh. Satu set koneksi per pemain, dilepas saat Show / keluar.
-- Ruangan SOCIAL: claude/Rencana_Social.md.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RS = game:GetService("ReplicatedStorage")

local HIDE = require(RS:WaitForChild("Config"):WaitForChild("Social")).HIDE
local SocialRules = require(RS:WaitForChild("Modules"):WaitForChild("SocialRules"))

local HideAvatarManager = {}

-- [userId] = { player, conns = {}, charConns = {}, parts = {[inst]=true}, enabled = {[inst]=asli}, detached = {[inst]=parent} }
local hidden = {}

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 3 })
	end)
end

local function nameOf(player)
	return player.DisplayName ~= "" and player.DisplayName or player.Name
end

local function disconnectAll(list)
	for _, c in ipairs(list) do
		c:Disconnect()
	end
	table.clear(list)
end

-- ── sembunyikan satu instance ──────────────────────────────

local function hideOne(state, d)
	if state.parts[d] or state.enabled[d] ~= nil or state.detached[d] then
		return
	end
	local action = SocialRules.hideAction(function(cls)
		return d:IsA(cls)
	end, HIDE)

	if action == "ltm" then
		state.parts[d] = true
		d.LocalTransparencyModifier = 1
		-- skrip lokal lain (mis. "Sembunyikan Player Lain") tidak boleh memunculkannya selama tersembunyi
		table.insert(state.charConns, d:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			if state.parts[d] and d.LocalTransparencyModifier ~= 1 then
				d.LocalTransparencyModifier = 1
			end
		end))
	elseif action == "enabled" then
		state.enabled[d] = d.Enabled
		d.Enabled = false
		table.insert(state.charConns, d:GetPropertyChangedSignal("Enabled"):Connect(function()
			if state.enabled[d] ~= nil and d.Enabled then
				state.enabled[d] = true -- dinyalakan pihak lain selama tersembunyi → itu nilai asli terbaru
				d.Enabled = false
			end
		end))
	elseif action == "detach" then
		state.detached[d] = d.Parent
		-- ditunda: mengganti Parent di dalam event penambahan instance ditolak engine
		task.defer(function()
			if state.detached[d] and d.Parent ~= nil then
				pcall(function()
					d.Parent = nil
				end)
			end
		end)
	end
end

-- kembalikan semua yang disembunyikan dari karakter saat ini (Show / ganti karakter)
local function restoreAll(state)
	disconnectAll(state.charConns)
	for part in pairs(state.parts) do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	for gui, was in pairs(state.enabled) do
		if gui.Parent then
			gui.Enabled = was
		end
	end
	for inst, parent in pairs(state.detached) do
		if inst.Parent == nil and parent then
			pcall(function()
				inst.Parent = parent -- gagal kalau sudah dihancurkan server → abaikan
			end)
		end
	end
	table.clear(state.parts)
	table.clear(state.enabled)
	table.clear(state.detached)
end

local function hideCharacter(state, character)
	restoreAll(state)
	if not character then return end
	table.insert(state.charConns, character.DescendantAdded:Connect(function(d)
		if hidden[state.player.UserId] == state then
			hideOne(state, d)
		end
	end))
	for _, d in ipairs(character:GetDescendants()) do
		hideOne(state, d)
	end
end

-- ── API ────────────────────────────────────────────────────

function HideAvatarManager:IsAvatarHidden(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end
	return hidden[targetPlayer.UserId] ~= nil
end

function HideAvatarManager:ShowAvatar(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end
	local state = hidden[targetPlayer.UserId]
	if not state then
		return false
	end
	hidden[targetPlayer.UserId] = nil
	disconnectAll(state.conns)
	restoreAll(state)
	notify("Avatar Shown", nameOf(targetPlayer) .. " is visible again")
	return true
end

-- Dipanggil baris "Hide avatar" di kartu pemain: sudah tersembunyi → tampilkan lagi.
function HideAvatarManager:HideAvatar(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") or targetPlayer == Players.LocalPlayer then
		return false
	end
	if hidden[targetPlayer.UserId] then
		return self:ShowAvatar(targetPlayer)
	end

	local state = {
		player = targetPlayer,
		conns = {},
		charConns = {},
		parts = {},
		enabled = {},
		detached = {},
	}
	hidden[targetPlayer.UserId] = state

	table.insert(state.conns, targetPlayer.CharacterAdded:Connect(function(character)
		if hidden[targetPlayer.UserId] == state then
			hideCharacter(state, character)
		end
	end))
	hideCharacter(state, targetPlayer.Character)

	notify("Avatar Hidden", nameOf(targetPlayer) .. " is hidden for you only. Open their card again to show.")
	return true
end

function HideAvatarManager:ToggleAvatar(targetPlayer)
	if self:IsAvatarHidden(targetPlayer) then
		return self:ShowAvatar(targetPlayer)
	end
	return self:HideAvatar(targetPlayer)
end

function HideAvatarManager:ShowAllAvatars()
	local count = 0
	for _, state in pairs(hidden) do
		if self:ShowAvatar(state.player) then
			count += 1
		end
	end
	return count
end

function HideAvatarManager:GetHiddenPlayers()
	local list = {}
	for _, state in pairs(hidden) do
		if state.player.Parent then
			table.insert(list, state.player)
		end
	end
	return list
end

Players.PlayerRemoving:Connect(function(player)
	local state = hidden[player.UserId]
	if state then
		hidden[player.UserId] = nil
		disconnectAll(state.conns)
		disconnectAll(state.charConns)
	end
end)

return HideAvatarManager
