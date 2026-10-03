-- ═══════════════════════════════════════════════════════════
-- HideAvatarManager — semua "sembunyikan" pemain di layar SENDIRI (lokal)
-- Path: ReplicatedStorage.CustomUIModules.HideAvatarManager
--
-- Satu sumber untuk:
--   • kartu pemain  "Hide avatar"/"Show avatar"  → HideAvatar / ShowAvatar (per pemain)
--   • Settings      "Sembunyikan Player Lain"    → SetHideAll      (semua pemain lain)
--   •               "Sembunyikan Efek Pemain"    → SetHideEffects  (efek di karakter siapa pun)
--   •               "Sembunyikan nametag"        → SetHideNametags (nametag siapa pun)
-- Keputusan per instance murni di SocialRules.shouldHide (kartu pemain bisa menampilkan
-- satu pemain walau "Sembunyikan Player Lain" aktif, dan sebaliknya).
--
-- Cara per kelas: Config/Social HIDE (SocialRules.hideAction):
--   bagian & decal → LocalTransparencyModifier = 1 (khusus client ini; perintah
--     server /ghost /normal /hat yang menulis Transparency tidak memunculkannya lagi)
--   BillboardGui / SurfaceGui → Enabled = false, nilai asli dipulihkan
--   efek (ParticleEmitter, Beam, Trail, Fire, Smoke, Sparkles, Light, Highlight, SelectionBox)
--     → dilepas sementara (Parent = nil lokal) lalu dikembalikan → efek yang dinyalakan-
--     matikan server (WaterGun, Money Gun, Broom) tetap benar sesudah ditampilkan lagi
-- Karakter baru (respawn) & bagian yang datang belakangan (aksesori, tool, nametag yang
-- dibangun ulang) langsung ikut, tanpa jeda. Transparency, CanCollide, Humanoid TIDAK disentuh.
-- Ruangan SOCIAL + SETTINGS: claude/Rencana_Social.md, claude/Rencana_Settings.md.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RS = game:GetService("ReplicatedStorage")

local HIDE = require(RS:WaitForChild("Config"):WaitForChild("Social")).HIDE
local SocialRules = require(RS:WaitForChild("Modules"):WaitForChild("SocialRules"))

local LocalPlayer = Players.LocalPlayer

local HideAvatarManager = {}

local settings = { all = false, effects = false, nametags = false }
local override = {} -- [userId] = "hide" | "show" (pilihan dari kartu pemain)
local tracked = {} -- [Player] = { conns = {}, charConns = {}, items = {[inst] = item} }
local started = false

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

local function isAvatarHidden(player)
	return SocialRules.avatarHidden(player == LocalPlayer, override[player.UserId], settings.all)
end

-- ── satu instance ──────────────────────────────────────────

local function hideItem(inst, item)
	if item.kind == "ltm" then
		inst.LocalTransparencyModifier = 1
		-- skrip lokal lain tidak boleh memunculkannya selama tersembunyi
		item.guard = inst:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			if item.hidden and inst.LocalTransparencyModifier ~= 1 then
				inst.LocalTransparencyModifier = 1
			end
		end)
	elseif item.kind == "enabled" then
		item.was = inst.Enabled
		inst.Enabled = false
		item.guard = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
			if item.hidden and inst.Enabled then
				item.was = true -- dinyalakan pihak lain selama tersembunyi → itu nilai asli terbaru
				inst.Enabled = false
			end
		end)
	elseif item.kind == "detach" then
		item.parent = inst.Parent
		-- ditunda: mengganti Parent di dalam event penambahan instance ditolak engine
		task.defer(function()
			if item.hidden and inst.Parent ~= nil then
				pcall(function()
					inst.Parent = nil
				end)
			end
		end)
	end
end

local function showItem(inst, item)
	if item.guard then
		item.guard:Disconnect()
		item.guard = nil
	end
	if item.kind == "ltm" then
		if inst.Parent then
			inst.LocalTransparencyModifier = 0
		end
	elseif item.kind == "enabled" then
		if inst.Parent then
			inst.Enabled = item.was
		end
	elseif item.kind == "detach" then
		local parent = item.parent
		item.parent = nil
		if inst.Parent == nil and parent then
			pcall(function()
				inst.Parent = parent -- gagal kalau sudah dihancurkan server → abaikan
			end)
		end
	end
end

local function sync(player, inst, item)
	local want =
		SocialRules.shouldHide(item.kind, item.nametag, player == LocalPlayer, override[player.UserId], settings)
	if want == item.hidden then
		return
	end
	item.hidden = want
	if want then
		hideItem(inst, item)
	else
		showItem(inst, item)
	end
end

local function syncPlayer(player)
	local t = tracked[player]
	if not t then
		return
	end
	for inst, item in pairs(t.items) do
		sync(player, inst, item)
	end
end

local function syncAll()
	for player in pairs(tracked) do
		syncPlayer(player)
	end
end

-- ── karakter ───────────────────────────────────────────────

local function addItem(player, t, inst)
	if t.items[inst] then
		return
	end
	local kind = SocialRules.hideAction(function(cls)
		return inst:IsA(cls)
	end, HIDE)
	if not kind then
		return
	end
	local item = { kind = kind, nametag = inst:IsA("BillboardGui"), hidden = false }
	t.items[inst] = item
	sync(player, inst, item)
end

local function dropItems(t)
	disconnectAll(t.charConns)
	for _, item in pairs(t.items) do
		if item.guard then
			item.guard:Disconnect()
		end
	end
	table.clear(t.items)
end

local function setCharacter(player, t, character)
	dropItems(t) -- karakter lama sedang dibuang → tidak perlu dipulihkan
	if not character then
		return
	end
	table.insert(
		t.charConns,
		character.DescendantAdded:Connect(function(d)
			if tracked[player] == t then
				addItem(player, t, d)
			end
		end)
	)
	table.insert(
		t.charConns,
		character.DescendantRemoving:Connect(function(d)
			local item = t.items[d]
			-- efek yang KITA lepas tetap dicatat (dikembalikan saat ditampilkan); selain itu buang catatannya
			if item and not (item.kind == "detach" and item.hidden) then
				if item.guard then
					item.guard:Disconnect()
				end
				t.items[d] = nil
			end
		end)
	)
	for _, d in ipairs(character:GetDescendants()) do
		addItem(player, t, d)
	end
end

local function track(player)
	if tracked[player] then
		return
	end
	local t = { conns = {}, charConns = {}, items = {} }
	tracked[player] = t
	table.insert(
		t.conns,
		player.CharacterAdded:Connect(function(character)
			if tracked[player] == t then
				setCharacter(player, t, character)
			end
		end)
	)
	setCharacter(player, t, player.Character)
end

local function untrack(player)
	local t = tracked[player]
	if not t then
		return
	end
	tracked[player] = nil
	disconnectAll(t.conns)
	dropItems(t)
end

-- Pelacakan dimulai saat fitur sembunyi pertama dipakai (tanpa biaya kalau tidak pernah dipakai).
local function ensureStarted()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	override[player.UserId] = nil
	untrack(player)
end)

-- ── API kartu pemain ───────────────────────────────────────

function HideAvatarManager:IsAvatarHidden(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end
	return isAvatarHidden(targetPlayer)
end

function HideAvatarManager:ShowAvatar(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") or not isAvatarHidden(targetPlayer) then
		return false
	end
	-- "Sembunyikan Player Lain" aktif → pengecualian untuk pemain ini saja
	override[targetPlayer.UserId] = if settings.all then "show" else nil
	syncPlayer(targetPlayer)
	notify("Avatar Shown", nameOf(targetPlayer) .. " is visible again")
	return true
end

-- Dipanggil baris "Hide avatar" di kartu pemain: sudah tersembunyi → tampilkan lagi.
function HideAvatarManager:HideAvatar(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") or targetPlayer == LocalPlayer then
		return false
	end
	if isAvatarHidden(targetPlayer) then
		return self:ShowAvatar(targetPlayer)
	end
	ensureStarted()
	override[targetPlayer.UserId] = if settings.all then nil else "hide"
	track(targetPlayer)
	syncPlayer(targetPlayer)
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
	for _, player in ipairs(Players:GetPlayers()) do
		if isAvatarHidden(player) and self:ShowAvatar(player) then
			count += 1
		end
	end
	return count
end

function HideAvatarManager:GetHiddenPlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if isAvatarHidden(player) then
			table.insert(list, player)
		end
	end
	return list
end

-- ── API Settings ───────────────────────────────────────────

-- "Sembunyikan Player Lain". Pengecualian "tampilkan" dari kartu dibuang tiap sakelar berubah;
-- pemain yang disembunyikan lewat kartu tetap tersembunyi walau sakelar dimatikan.
function HideAvatarManager:SetHideAll(on)
	on = on == true
	if settings.all == on then
		return
	end
	ensureStarted()
	settings.all = on
	for userId, value in pairs(override) do
		if value == "show" then
			override[userId] = nil
		end
	end
	syncAll()
end

-- "Sembunyikan Efek Pemain" (karakter siapa pun, termasuk sendiri — sama dengan dulu).
function HideAvatarManager:SetHideEffects(on)
	on = on == true
	if settings.effects == on then
		return
	end
	ensureStarted()
	settings.effects = on
	syncAll()
end

-- "Sembunyikan nametag" (BillboardGui di karakter siapa pun, termasuk sendiri — sama dengan dulu).
function HideAvatarManager:SetHideNametags(on)
	on = on == true
	if settings.nametags == on then
		return
	end
	ensureStarted()
	settings.nametags = on
	syncAll()
end

function HideAvatarManager:GetSettings()
	return { all = settings.all, effects = settings.effects, nametags = settings.nametags }
end

return HideAvatarManager
