-- ═══════════════════════════════════════════════════════════
-- PlayersPanel — daftar player + setting Primary Community
-- Klik player → MenuBinder.SetMenuPlayer(player)
-- Warna dari ReplicatedStorage.Modules.ThemeColor (themeColor): T.X dibaca saat melukis → ikut tema yang dipilih.
--
-- Dua section: CONNECTIONS (sudah berteman) lalu ALL PLAYERS.
-- Badge jumlah like per baris DISPLAY-ONLY: angkanya dibaca dari Attribute
-- "Likes" milik Player, jadi panel ini nol trafik remote, otomatis sinkron
-- dengan pill hati di menu profil, dan hilang sendiri kalau LikeSystem
-- belum dipasang.
-- ═══════════════════════════════════════════════════════════

repeat task.wait() until _G.MenuUI and _G.InjectPanelUI and _G.MenuConfig

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local modules    = RS:WaitForChild("CustomUIModules")
local Responsive = require(modules:WaitForChild("Responsive"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))

local UI          = _G.MenuUI
local CONFIG      = _G.MenuConfig
local localPlayer = Players.LocalPlayer

local T = ThemeColor.tokens

local FONT = CONFIG.font or {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

-- Warna hati dibikin hex karena dipakai lewat RichText, bukan TextColor3.
local LIKE_HEX = "#EB5660"

local TWEEN   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local INSTANT = TweenInfo.new(0)

-- Header dan baris berbagi satu UIListLayout, jadi urutannya diatur lewat
-- blok angka, bukan lewat parent terpisah.
local ORDER = {
	headerFriends = 1,
	friends       = 10,
	headerAll     = 5000,
	all           = 5010,
	empty         = 9000,
}

local function tween(obj, props, info)
	if obj and obj.Parent then TweenService:Create(obj, info or TWEEN, props):Play() end
end

-- Dibuat sendiri, bukan lewat UI.stroke, supaya tidak bergantung pada versi
-- signature helper di host menu.
local function stroke(parent, transparency, color)
	return UI.new("UIStroke", {
		Color = color or T.LINE, Thickness = 1, Transparency = transparency or 0.94,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local bindHover = UI.bindHover or function(obj, apply)
	obj.MouseEnter:Connect(function() apply(true) end)
	obj.MouseLeave:Connect(function() apply(false) end)
end

local function formatCount(n)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000 then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

-- ── Skala per device ────────────────────────────────────────

local SCALE = {
	mobile  = { item = 40, avatar = 28, name = 12, user = 10, setting = 34, search = 28, gap = 5 },
	tablet  = { item = 42, avatar = 30, name = 12, user = 10, setting = 36, search = 30, gap = 6 },
	desktop = { item = 42, avatar = 30, name = 12, user = 10, setting = 36, search = 30, gap = 6 },
}

local function getScale()
	return SCALE[Responsive.Device()] or SCALE.desktop
end

-- ── Dependensi opsional ────────────────────────────────────

local function findModule(folder, name)
	local direct = folder:FindFirstChild(name)
	if direct then return direct end
	local target = name:lower()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name:lower() == target then return child end
	end
	return nil
end

local CommunityInfo
local AddFriendManager
do
	local mod = findModule(modules, "CommunityInfo")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then
			CommunityInfo = result
		else
			warn("[PlayersPanel] CommunityInfo gagal di-require:", result)
		end
	end

	local friendMod = findModule(modules, "AddFriendManager")
	if friendMod then
		local ok, result = pcall(require, friendMod)
		if ok then
			AddFriendManager = result
		else
			warn("[PlayersPanel] AddFriendManager gagal di-require:", result)
		end
	end
end

local function getMenuBinder()
	if _G.MenuBinder then return _G.MenuBinder end
	local ok, result = pcall(function() return require(modules.MenuBinder) end)
	if ok and result then
		_G.MenuBinder = result
		return result
	end
	return nil
end

local function avatarThumb(userId)
	if userId < 1 then return "rbxasset://textures/ui/GuiImagePlaceholder.png" end
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

-- ── Status pertemanan ──────────────────────────────────────
-- Dipisah dari cache AddFriendManager karena sorting butuh baca sinkron:
-- di sini isinya cuma bool + timestamp, bukan panggilan web.

local FRIEND_TTL = 30

local friendState   = {}   -- [userId] = { value = boolean, time = os.clock() }
local friendPending = {}   -- [userId] = true selagi cek jalan

local queueRefresh -- diisi setelah refreshList

local function friendKnown(plr)
	local entry = friendState[plr.UserId]
	if entry and (os.clock() - entry.time) < FRIEND_TTL then return entry.value end
	return nil
end

local function resolveFriend(plr)
	local userId = plr.UserId
	if plr == localPlayer or userId < 1 then return end
	if friendPending[userId] or friendKnown(plr) ~= nil then return end

	friendPending[userId] = true
	task.spawn(function()
		local value = false
		if AddFriendManager then
			local ok, res = pcall(AddFriendManager.IsFriend, AddFriendManager, plr)
			value = (ok and res) and true or false
		else
			local ok, res = pcall(function() return localPlayer:IsFriendsWith(userId) end)
			value = (ok and res) and true or false
		end

		friendPending[userId] = nil
		friendState[userId] = { value = value, time = os.clock() }
		if queueRefresh then queueRefresh() end
	end)
end

-- ════════════════════════════════════════════════════════════
-- BUILD
-- ════════════════════════════════════════════════════════════

local container = UI.frame({
	Name = "PlayersContainer", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
})

local S = getScale()

-- ── Setting: Primary Community ─────────────────────────────

local settingRow = UI.frame({
	Name = "SettingPrimaryCommunity", Size = UDim2.new(1, 0, 0, S.setting),
	BackgroundColor3 = T.CARD, Parent = container,
})
UI.corner(10).Parent = settingRow
stroke(settingRow)

local settingLabel = UI.text({
	Name = "Label", Position = UDim2.new(0, 11, 0, 0), Size = UDim2.new(1, -74, 1, 0),
	Text = "Primary Community", TextColor3 = T.TEXT, Font = FONT.REGULAR,
	TextSize = S.name, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = settingRow,
})

local TOGGLE_W, TOGGLE_H, TOGGLE_PAD = 38, 20, 3
local knobSize = TOGGLE_H - TOGGLE_PAD * 2

-- Gaya themeColor: hidup = jalur ACCENT + kenop TEXT_STRONG, mati = jalur TRACK + kenop TEXT.
local toggle = UI.button({
	Name = "Toggle", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.new(0, TOGGLE_W, 0, TOGGLE_H), BackgroundColor3 = T.TRACK,
	Text = "", Active = CommunityInfo ~= nil, Parent = settingRow,
})
UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = toggle })

local knob = UI.frame({
	Name = "Knob", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, TOGGLE_PAD, 0.5, 0), Size = UDim2.new(0, knobSize, 0, knobSize),
	BackgroundColor3 = T.TEXT, Parent = toggle,
})
UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })
stroke(knob, 0.7, T.BG)

local KNOB_OFF = UDim2.new(0, TOGGLE_PAD, 0.5, 0)
local KNOB_ON  = UDim2.new(0, TOGGLE_W - knobSize - TOGGLE_PAD, 0.5, 0)

local isOn = (CommunityInfo ~= nil) and CommunityInfo.IsEnabled() or false

local function paintToggle(on, animate)
	local info = animate and TWEEN or INSTANT
	tween(toggle, { BackgroundColor3 = on and T.ACCENT or T.TRACK }, info)
	tween(knob, {
		Position         = on and KNOB_ON or KNOB_OFF,
		BackgroundColor3 = on and T.TEXT_STRONG or T.TEXT,
	}, info)
end

paintToggle(isOn, false)

if not CommunityInfo then
	settingLabel.TextColor3 = T.TEXT_DIM
end

toggle.Activated:Connect(function()
	if not CommunityInfo then return end
	isOn = not isOn
	paintToggle(isOn, true)
	CommunityInfo.SetEnabled(isOn)
end)

if CommunityInfo and CommunityInfo.Changed then
	CommunityInfo.Changed:Connect(function(value)
		if value == isOn then return end
		isOn = value
		paintToggle(isOn, true)
	end)
end

-- ── Search ─────────────────────────────────────────────────

local searchBar = UI.frame({
	Name = "SearchBar", Size = UDim2.new(1, 0, 0, S.search),
	BackgroundColor3 = T.CARD, Parent = container,
})
UI.corner(10).Parent = searchBar
local searchStroke = stroke(searchBar, 0.92)

local searchBox = UI.textbox({
	Name = "SearchInput", Size = UDim2.new(1, -22, 1, 0), Position = UDim2.new(0, 11, 0, 0),
	BackgroundTransparency = 1, Font = FONT.REGULAR, TextSize = S.name,
	TextColor3 = T.TEXT, PlaceholderText = "Cari nama atau username",
	PlaceholderColor3 = T.TEXT_DIM, ClearTextOnFocus = false, Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = searchBar,
})

searchBox.Focused:Connect(function()
	tween(searchStroke, { Transparency = 0.7, Color = T.ACCENT })
end)
searchBox.FocusLost:Connect(function()
	tween(searchStroke, { Transparency = 0.92, Color = T.LINE })
end)

-- ── List ───────────────────────────────────────────────────

local content = UI.scroll({ Name = "PlayersContent", Parent = container })
local layout  = UI.list({ padding = S.gap })
layout.Parent = content

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end)

local emptyLabel = UI.text({
	Name = "EmptyState", Size = UDim2.new(1, 0, 0, 40),
	Text = "", TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = S.name,
	LayoutOrder = ORDER.empty, Visible = false, Parent = content,
})

-- ── Header section ─────────────────────────────────────────
-- Bukan card, cuma label redup. Card di dalam card bikin daftar ramai
-- di layar HP yang sempit.

local function sectionHeader(name, order)
	local lbl = UI.text({
		Name = "Section_" .. name, Size = UDim2.new(1, 0, 0, S.user + 10),
		Text = "", TextColor3 = T.TEXT_DIM, Font = FONT.BOLD, TextSize = S.user,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = order, Visible = false, Parent = content,
	})
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 4), Parent = lbl })
	return lbl
end

local headerFriends = sectionHeader("Connections", ORDER.headerFriends)
local headerAll     = sectionHeader("AllPlayers", ORDER.headerAll)

-- Baris di-recycle: search dan perubahan jumlah player hanya mengubah teks,
-- tidak menghancurkan lalu membangun ulang instance.
local rows = {}

-- Sisi kanan baris dihitung terpisah karena lebarnya berubah: badge "You"
-- hanya ada di baris sendiri, dan badge like hilang kalau LikeSystem belum
-- terpasang.
local function layoutRow(row, scale)
	local iconX   = 8 + scale.avatar + 8
	local reserve = 8

	if row.likes.Visible then
		local likeW = math.max(32, math.floor(scale.name * 3.4))
		row.likes.Size     = UDim2.new(0, likeW, 1, 0)
		row.likes.Position = UDim2.new(1, -8, 0.5, 0)
		row.likes.TextSize = scale.name
		reserve += likeW + 8
	end

	if row.badge.Visible then
		local badgeW = math.floor(scale.name * 2.6)
		row.badge.Size     = UDim2.new(0, badgeW, 0, math.floor(scale.name * 1.5))
		row.badge.Position = UDim2.new(1, -reserve, 0.5, 0)
		row.badge.TextSize = scale.user
		reserve += badgeW + 6
	end

	local textW = -(iconX + reserve + 4)
	row.name.Position = UDim2.new(0, iconX, 0, math.floor(scale.item * 0.16))
	row.name.Size     = UDim2.new(1, textW, 0, scale.name + 3)
	row.name.TextSize = scale.name
	row.user.Position = UDim2.new(0, iconX, 0, math.floor(scale.item * 0.54))
	row.user.Size     = UDim2.new(1, textW, 0, scale.user + 3)
	row.user.TextSize = scale.user
end

local function styleRow(row, scale)
	row.item.Size       = UDim2.new(1, 0, 0, scale.item)
	row.avatar.Size     = UDim2.new(0, scale.avatar, 0, scale.avatar)
	row.avatar.Position = UDim2.new(0, 8, 0.5, 0)
	layoutRow(row, scale)
end

-- CATATAN DESAIN — kenapa di sini tidak ada tombol like / add friend:
--  1. Seluruh permukaan baris sudah jadi tombol "buka profil". Menaruh
--     tombol hati di dalamnya = hitbox bersarang; di HP baris cuma 40px,
--     salah tap bakal sering.
--  2. Protokol remote LikeSystem bersifat satu target: satu balasan "state"
--     untuk satu userId. Menampilkan status liked/belum untuk 20 baris
--     sekaligus butuh aksi batch baru di server, bukan cuma UI.
--  3. Angka like di bawah dibaca dari Attribute, jadi panel ini sama sekali
--     tidak menyentuh jaringan. Aksi like tetap satu pintu: pill hati di
--     menu profil, yang sudah punya cooldown, lock, dan feedback optimistik.
--  4. Aksi add friend juga satu pintu: baris "Add friend" di menu profil.
local function createRow()
	local row = {}

	local item = UI.button({
		Name = "PlayerRow", BackgroundColor3 = T.CARD, Text = "",
		Visible = false, Parent = content,
	})
	UI.corner(10).Parent = item
	row.item   = item
	row.stroke = stroke(item)

	row.avatar = UI.new("ImageLabel", {
		Name = "Avatar", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = T.CARD_HOVER,
		BorderSizePixel = 0, ScaleType = Enum.ScaleType.Fit, Image = "", Parent = item,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = row.avatar })

	row.name = UI.text({
		Name = "DisplayName", Text = "", TextColor3 = T.TEXT, Font = FONT.MEDIUM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = item,
	})
	-- Warna nama diatur paintName (tema pemain itu), bukan lukis ulang tema kita.
	ThemeColor.skip(row.name)

	row.user = UI.text({
		Name = "Username", Text = "", TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = item,
	})

	row.likes = UI.text({
		Name = "LikeCount", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0), Text = "", TextColor3 = T.TEXT_DIM,
		Font = FONT.MEDIUM, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false, Parent = item,
	})

	row.badge = UI.text({
		Name = "YouBadge", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundColor3 = T.ACCENT, BackgroundTransparency = 0, BorderSizePixel = 0,
		Text = "You", TextColor3 = T.ON_ACCENT, Font = FONT.BOLD,
		Visible = false, Parent = item,
	})
	UI.corner(6).Parent = row.badge

	bindHover(item, function(on)
		tween(item, { BackgroundColor3 = on and T.CARD_HOVER or T.CARD })
		tween(row.stroke, { Transparency = on and 0.85 or (row.isFriend and 0.72 or 0.94) })
	end)

	item.Activated:Connect(function()
		local plr = row.player
		if not plr or not plr.Parent then return end
		local binder = getMenuBinder()
		if binder then pcall(binder.SetMenuPlayer, plr) end
		if _G.MenuVisuals then pcall(_G.MenuVisuals.SetTarget, plr.UserId) end
	end)

	styleRow(row, S)
	table.insert(rows, row)
	return row
end

-- ── Badge like: baca Attribute, nol remote ─────────────────

local function paintLikes(row, plr)
	local raw = plr:GetAttribute("Likes")
	if raw == nil then
		-- LikeSystem belum dipasang / belum sempat set attribute
		row.likes.Visible = false
		return false
	end
	local n = tonumber(raw) or 0
	row.likes.Text    = string.format('<font color="%s">♥</font> %s', LIKE_HEX, formatCount(n))
	row.likes.Visible = true
	return true
end

local function releaseRow(row)
	if row.likeConn then
		row.likeConn:Disconnect()
		row.likeConn = nil
	end
	if row.themeConn then
		row.themeConn:Disconnect()
		row.themeConn = nil
	end
	row.player = nil
end

-- Warna nama = aksen tema warna pilihan pemain ITU (sama dengan nametag di atas kepala; ThemeColor.nameColor).
-- Tema polos (Default) → seperti dulu: diri sendiri ACCENT tema kita, pemain lain TEXT.
local function paintName(row, plr)
	row.name.TextColor3 = ThemeColor.nameColor(plr) or ((plr == localPlayer) and T.ACCENT or T.TEXT)
end

local function watchTheme(row, plr)
	if row.themeConn then
		row.themeConn:Disconnect()
		row.themeConn = nil
	end
	paintName(row, plr)
	row.themeConn = plr:GetAttributeChangedSignal(ThemeColor.ATTR):Connect(function()
		if row.player == plr then paintName(row, plr) end
	end)
end

local function watchLikes(row, plr)
	if row.likeConn then
		row.likeConn:Disconnect()
		row.likeConn = nil
	end

	local had = paintLikes(row, plr)

	-- Attribute bisa muncul belakangan (LikeSystem masih GetAsync saat join),
	-- jadi sinyalnya tetap dipasang walau saat ini nil.
	row.likeConn = plr:GetAttributeChangedSignal("Likes"):Connect(function()
		if row.player ~= plr then return end
		local nowHas = paintLikes(row, plr)
		-- Kalau badge baru muncul/hilang, lebar kolom nama harus dihitung ulang
		if nowHas ~= had then
			had = nowHas
			layoutRow(row, S)
		end
	end)

	return had
end

local function assignRow(row, plr, order, isFriend)
	if row.player ~= plr then
		releaseRow(row)
		row.player = plr
	end

	row.item.Name        = "Player_" .. plr.Name
	row.item.LayoutOrder = order
	row.item.Visible     = true
	row.item.BackgroundColor3 = T.CARD

	local thumb = avatarThumb(plr.UserId)
	if row.avatar.Image ~= thumb then row.avatar.Image = thumb end

	row.name.Text = plr.DisplayName
	row.user.Text = "@" .. plr.Name

	local isSelf = (plr == localPlayer)
	watchTheme(row, plr)
	row.badge.Visible   = isSelf

	-- Connection ditandai stroke agak terang, bukan warna nama: warna nama
	-- sudah dipakai untuk menandai diri sendiri.
	row.isFriend = isFriend and true or false
	row.stroke.Transparency = row.isFriend and 0.72 or 0.94

	watchLikes(row, plr)
	layoutRow(row, S)
end

local query = ""

local function matches(plr, lower)
	if lower == "" then return true end
	return plr.Name:lower():find(lower, 1, true) ~= nil
		or plr.DisplayName:lower():find(lower, 1, true) ~= nil
end

local function byName(a, b)
	return a.Name:lower() < b.Name:lower()
end

local function refreshList()
	local lower = query:lower()

	local friends, others, total = {}, {}, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if matches(plr, lower) then
			total += 1
			resolveFriend(plr)
			if plr ~= localPlayer and friendKnown(plr) == true then
				table.insert(friends, plr)
			else
				table.insert(others, plr)
			end
		end
	end

	table.sort(friends, byName)
	table.sort(others, function(a, b)
		if a == localPlayer then return true end
		if b == localPlayer then return false end
		return byName(a, b)
	end)

	local used = 0
	local function place(plr, order, isFriend)
		used += 1
		assignRow(rows[used] or createRow(), plr, order, isFriend)
	end

	for i, plr in ipairs(friends) do place(plr, ORDER.friends + i, true) end
	for i, plr in ipairs(others) do place(plr, ORDER.all + i, false) end

	for i = used + 1, #rows do
		rows[i].item.Visible = false
		releaseRow(rows[i])
	end

	headerFriends.Visible = #friends > 0
	headerFriends.Text    = string.format("CONNECTIONS  %d", #friends)

	-- Header ALL PLAYERS disembunyikan kalau tidak ada section di atasnya,
	-- supaya daftar biasa tidak kelihatan punya satu judul menggantung.
	headerAll.Visible = (#others > 0) and (#friends > 0)
	headerAll.Text    = string.format("ALL PLAYERS  %d", #others)

	emptyLabel.Visible = (total == 0)
	if total == 0 then
		emptyLabel.Text = (lower ~= "") and "Tidak ada hasil." or "Tidak ada pemain."
	end
end

-- Debounce: ketikan cepat, gelombang join/leave, dan hasil cek pertemanan
-- yang datang menyusul hanya memicu satu refresh.
local refreshQueued = false
queueRefresh = function()
	if refreshQueued then return end
	refreshQueued = true
	task.delay(0.12, function()
		refreshQueued = false
		if container.Parent then refreshList() end
	end)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	query = searchBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	queueRefresh()
end)

-- Tema kita diganti → nama ber-warna-bawaan (T.ACCENT / T.TEXT) ikut; dilepas saat panel ini diganti (respawn).
local stopTheme = ThemeColor.onChanged(function()
	for _, row in ipairs(rows) do
		if row.player then paintName(row, row.player) end
	end
end)
container.Destroying:Connect(stopTheme)

Players.PlayerAdded:Connect(queueRefresh)
Players.PlayerRemoving:Connect(function(plr)
	friendState[plr.UserId] = nil
	queueRefresh()
end)

-- Dipanggil MenuSystemInit setelah pemain mengirim friend request, supaya
-- barisnya pindah ke CONNECTIONS tanpa menunggu TTL habis.
_G.PlayersPanel = _G.PlayersPanel or {}
_G.PlayersPanel.InvalidateFriend = function(userId)
	if type(userId) ~= "number" then return end
	friendState[userId] = nil
	if AddFriendManager and AddFriendManager.Invalidate then
		pcall(AddFriendManager.Invalidate, AddFriendManager, userId)
	end
	queueRefresh()
end

-- ── Layout (satu sumber, dipakai saat build & resize) ───────

local function applyScale()
	S = getScale()

	settingRow.Size       = UDim2.new(1, 0, 0, S.setting)
	settingLabel.TextSize = S.name

	local searchY = S.setting + S.gap
	searchBar.Position = UDim2.new(0, 0, 0, searchY)
	searchBar.Size     = UDim2.new(1, 0, 0, S.search)
	searchBox.TextSize = S.name

	local listY = searchY + S.search + S.gap
	content.Position = UDim2.new(0, 0, 0, listY)
	content.Size     = UDim2.new(1, 0, 1, -listY)

	layout.Padding      = UDim.new(0, S.gap)
	emptyLabel.TextSize = S.name

	for _, header in ipairs({ headerFriends, headerAll }) do
		header.Size     = UDim2.new(1, 0, 0, S.user + 10)
		header.TextSize = S.user
	end

	for _, row in ipairs(rows) do styleRow(row, S) end
end

applyScale()

Responsive.OnChange(function()
	if container.Parent then applyScale() end
end, 0.12)

refreshList()
_G.InjectPanelUI("Players", container)