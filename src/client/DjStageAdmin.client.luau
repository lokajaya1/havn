-- StarterPlayerScripts/DjStageAdmin (LocalScript) — panel admin "Layar panggung" (ruangan WORLD, claude/Rencana_World.md).
-- SATU panel untuk semua layar panggung (dulu dua: "Live Screen" buatan Studio + "Layar panggung"). Dibuka dari
-- Menu › Settings › ADMIN › "Layar panggung" (SettingsClient memanggil _G.ToggleDjStage). Hanya untuk IsAdmin; server
-- mengecek lagi — panel ini hanya tampilan.
--   Tab "Live Screen": mode layar samping (📺 Live / 🖼️ Gambar), kamera (Statis / Dinamis), pilih pemain (daftar, cari,
--                      ◀ ▶, Tampilkan, Stop) → ReplicatedStorage.LiveSystem (UpdateScreenEvent / UpdateCameraModeEvent /
--                      UpdateScreenModeEvent). Perilaku sama dengan panel Live Screen lama (StarterGui.LiveScreen).
--   Tab "Media"      : per layar (utama / samping) pilih Gambar / GIF / Video → ReplicatedStorage.DjStageRemotes.SetMedia.
--                      Jenis yang ID-nya belum diisi di Config.DjStage tampil redup "belum diisi".
-- Posisi di TENGAH area layar (di atas hotbar), ukuran ikut layar (Rules.panelSize). Tata letak tanpa AutomaticSize/
-- UIPadding di ScrollingFrame (dua-duanya membuat isi melebar & ketabrak tepi panel di Studio 17:17): isi tiap tab =
-- Frame selebar panel − 2×PAD, tinggi dihitung dari UIListLayout. Membuka panel = PanelCoordinator.NotifyOpen("DjStage")
-- → menu tertutup (tidak bertumpuk di HP portrait).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Didaftarkan lebih dulu: SettingsClient bisa memanggil sebelum remote siap.
local isOpen = false
_G.ToggleDjStage = function() end
_G.DjStageMenu = { IsOpen = function() return isOpen end }

local Config = require(RS:WaitForChild("Config"):WaitForChild("DjStage"))
local Rules = require(RS:WaitForChild("Modules"):WaitForChild("DjStageRules"))
local Responsive = require(RS:WaitForChild("CustomUIModules"):WaitForChild("Responsive"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))

-- Live Screen: folder & nilai buatan Studio, remote dibuat LiveScreenServer (sama dengan panel lama).
local liveSystem = RS:WaitForChild("LiveSystem", 10)
local function liveChild(name)
	return liveSystem and liveSystem:WaitForChild(name, 5) or nil
end
local targetRemote = liveChild("UpdateScreenEvent")
local cameraMode = liveChild("CameraMode")
local cameraModeRemote = liveChild("UpdateCameraModeEvent")
local screenMode = liveChild("ScreenMode")
local screenModeRemote = liveChild("UpdateScreenModeEvent")
local currentTarget = liveChild("CurrentTarget")
local liveReady = targetRemote ~= nil and cameraMode ~= nil
if not liveReady then
	warn("[DjStageAdmin] LiveSystem tidak lengkap — tab Live Screen tidak aktif")
end

-- Media: server DjStage.
local remotes = RS:WaitForChild("DjStageRemotes", 60)
local setFn = remotes and remotes:WaitForChild("SetMedia", 30)
if not setFn then
	warn("[DjStageAdmin] DjStageRemotes.SetMedia tidak ada — server DjStage tidak jalan? Tab Media tidak aktif")
end

local waited = 0
while not _G.MenuConfig and waited < 10 do
	task.wait(0.1)
	waited += 0.1
end
local T = ThemeColor.tokens -- tabel bersama themeColor: T.X dibaca saat melukis → ikut tema pilihan pemain
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold,
	MEDIUM = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}
local HEADER_H, TABS_H, PAD = 44, 34, 14
local TOP_H = HEADER_H + TABS_H + 10 -- isi tab mulai di sini
local ROW_H = 34
local MODE_COOLDOWN = 0.5 -- dtk antar ganti mode Live/Gambar dari panel (sama dengan panel lama & server)

-- ── helper ────────────────────────────────────────────────────────────────────────────────────────────────────────
local function new(class, props)
	local o = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then o[k] = v end
	end
	o.Parent = props.Parent
	return o
end
local function corner(p, r) new("UICorner", { CornerRadius = UDim.new(0, r), Parent = p }) end
local function stroke(p, c, tr) return new("UIStroke", { Color = c, Thickness = 1, Transparency = tr, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p }) end
-- Label satu baris (tinggi tetap, terpotong "…" kalau kepanjangan). `lines` > 1 = teks dibungkus, tinggi tetap.
local function label(parent, text, size, color, font, order, props, lines)
	local n = lines or 1
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color, Font = font,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = n > 1, TextTruncate = if n > 1 then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, (size + 4) * n), LayoutOrder = order or 0, Parent = parent,
	})
	for k, v in props or {} do l[k] = v end
	return l
end
-- Tombol kartu (teks di tengah). Warna dilukis lewat paintButton.
local function button(parent, text, order, props)
	local b = new("TextButton", {
		Text = text, TextSize = 12, Font = FONT.MEDIUM, TextColor3 = T.TEXT, BackgroundColor3 = T.CARD,
		AutoButtonColor = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = order or 0, Parent = parent,
	})
	for k, v in props or {} do b[k] = v end
	corner(b, 9)
	return { btn = b, stroke = stroke(b, T.LINE, 0.94) }
end
local function paintButton(o, on, dim)
	o.btn.BackgroundColor3 = if on then T.CARD_HOVER else T.CARD
	o.btn.TextColor3 = if dim then T.TEXT_DIM elseif on then T.ACCENT else T.TEXT
	o.stroke.Color = if on then T.ACCENT else T.LINE
	o.stroke.Transparency = if on then 0.2 else 0.94
end
-- Baris n tombol sama lebar (tinggi ROW_H) di dalam `parent` (Frame selebar isi).
local function cells(parent, n)
	new("UIGridLayout", { CellSize = UDim2.new(1 / n, -6 * (n - 1) / n, 0, ROW_H), CellPadding = UDim2.new(0, 6, 0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = parent })
	return parent
end
local function row(parent, n, order)
	return cells(new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = order, Parent = parent }), n)
end
-- Baris pengaturan: judul kiri (LABEL_W) + n tombol sama lebar di kanan.
local LABEL_W = 96
local function settingRow(parent, title, order)
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = order, Parent = parent })
	label(f, title, 12, T.TEXT_DIM, FONT.MEDIUM, 0, { Size = UDim2.new(0, LABEL_W - 6, 1, 0) })
	return cells(new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, LABEL_W, 0, 0), Size = UDim2.new(1, -LABEL_W, 1, 0), Parent = f }), 2)
end
local function say(lbl, text, color) -- pesan kosong = baris disembunyikan (tidak menyisakan celah)
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.Visible = text ~= ""
end
local function labelOf(mediaType)
	return Config.MEDIA_LABEL[mediaType] or tostring(mediaType or "-")
end

-- ── kerangka ──────────────────────────────────────────────────────────────────────────────────────────────────────
local old = playerGui:FindFirstChild("DjStageGui")
if old then old:Destroy() end
local gui = new("ScreenGui", { Name = "DjStageGui", ResetOnSpawn = false, Enabled = false, DisplayOrder = 101, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
ThemeColor.mark(gui)
local frame = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.BG, BorderSizePixel = 0,
	Active = true, ClipsDescendants = true, Parent = gui, -- Active: klik tidak tembus ke tombol di belakang
})
corner(frame, 16)
stroke(frame, T.LINE, 0.88)
local header = new("Frame", { Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundTransparency = 1, Parent = frame })
label(header, "Layar panggung", 15, T.TEXT, FONT.BOLD, 0, { Position = UDim2.new(0, PAD, 0, 0), Size = UDim2.new(1, -PAD - 44, 1, 0) })
local closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 32, 0, 32), BackgroundTransparency = 1,
	Text = "X", TextColor3 = T.TEXT_DIM, TextSize = 15, Font = FONT.BOLD, AutoButtonColor = false, Parent = header,
})
local tabBar = new("Frame", { Position = UDim2.new(0, PAD, 0, HEADER_H), Size = UDim2.new(1, -2 * PAD, 0, TABS_H), BackgroundTransparency = 1, Parent = frame })
new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, TABS_H), CellPadding = UDim2.new(0, 6, 0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabBar })
-- Isi bergulir: lebar isi = lebar panel − 2×PAD (scrollbar di dalam celah kanan), tinggi = isi UIListLayout.
local body = new("ScrollingFrame", {
	Position = UDim2.new(0, 0, 0, TOP_H), Size = UDim2.new(1, 0, 1, -TOP_H), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = T.SCROLL, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarInset = Enum.ScrollBarInset.None, Parent = frame,
})
local tabs = {}
for i, spec in { { "Live", "Live Screen" }, { "Media", "Media" } } do
	local t = button(tabBar, spec[2], i, { Font = FONT.BOLD, TextSize = 13 })
	t.page = new("Frame", { Name = spec[1], BackgroundTransparency = 1, Position = UDim2.new(0, PAD, 0, 0), Size = UDim2.new(1, -2 * PAD, 0, 0), Visible = false, Parent = body })
	t.list = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = t.page })
	tabs[spec[1]] = t
end
local function pageHeight(t)
	return t.list.AbsoluteContentSize.Y + PAD
end
local activeTab = "Live"

-- ══ TAB LIVE ══════════════════════════════════════════════════════════════════════════════════════════════════════
local LP = tabs.Live.page
-- status + Stop (satu klik dari mana pun di daftar)
local statusCard = new("Frame", { BackgroundColor3 = T.CARD, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 1, Parent = LP })
corner(statusCard, 10)
local statusLbl = label(statusCard, "", 13, T.ACCENT, FONT.BOLD, 0, { Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -112, 0, 18) })
local statusSub = label(statusCard, "", 11, T.TEXT_DIM, FONT.REGULAR, 0, { Position = UDim2.new(0, 12, 0, 28), Size = UDim2.new(1, -112, 0, 15) })
local stopB = button(statusCard, "■ Stop", 0, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0), Size = UDim2.new(0, 86, 0, ROW_H) })

-- pengaturan layar samping
local modeRow = settingRow(LP, "Layar samping", 2)
local modeBtn = { Live = button(modeRow, "📺 Live", 1), Gambar = button(modeRow, "🖼️ Gambar", 2) }
local camRow = settingRow(LP, "Kamera", 3)
local camBtn = { Static = button(camRow, "Statis", 1), Dynamic = button(camRow, "Dinamis", 2) }

-- pilih pemain
label(LP, "PILIH PEMAIN", 10, T.TEXT_DIM, FONT.MEDIUM, 4, { Size = UDim2.new(1, 0, 0, 20), TextYAlignment = Enum.TextYAlignment.Bottom })
local searchRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = 5, Parent = LP })
local searchBox = new("TextBox", {
	Size = UDim2.new(1, -98, 1, 0), BackgroundColor3 = T.CARD, Text = "", PlaceholderText = "Cari / ketik nama pemain",
	PlaceholderColor3 = T.TEXT_DIM, TextColor3 = T.TEXT, TextSize = 12, Font = FONT.REGULAR, ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = searchRow,
})
corner(searchBox, 9)
stroke(searchBox, T.LINE, 0.9)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), Parent = searchBox })
local showB = button(searchRow, "Tampilkan", 0, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 92, 1, 0) })
local navRow = row(LP, 2, 6)
local prevB = button(navRow, "◀ Sebelumnya", 1)
local nextB = button(navRow, "Berikutnya ▶", 2)
local liveMsg = label(LP, "", 11, T.TEXT_DIM, FONT.REGULAR, 7, { Visible = false }, 2)
local listBox = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 8, Parent = LP })
local listLayout = new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listBox })
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	listBox.Size = UDim2.new(1, 0, 0, listLayout.AbsoluteContentSize.Y)
end)
local emptyLbl = label(LP, "", 11, T.TEXT_DIM, FONT.REGULAR, 9, { Visible = false })
if not liveReady then
	say(liveMsg, "LiveSystem tidak ditemukan — Live Screen tidak bisa dipakai.", T.DANGER)
end

-- ── state Live (sama dengan panel lama) ──
local selectedPlayerName = ""
local currentScreenModeLocal = if screenMode and screenMode.Value ~= "" then screenMode.Value else "Gambar"
local camModeLocal = if cameraMode and cameraMode.Value ~= "" then cameraMode.Value else "Static"
local lastModeSwitchTime = 0
local sortedPlayerList = {} -- { {Name, DisplayName} } urut nama tampilan
local visiblePlayerList = {} -- Name yang lolos kotak cari (urutan daftar)
local playerButtons = {} -- [Name] = { btn, stroke, name }

local function displayOf(name)
	local p = Players:FindFirstChild(name)
	return if p and p:IsA("Player") then p.DisplayName else name
end

local function paintLive()
	local target = if currentTarget then currentTarget.Value else ""
	if currentScreenModeLocal == "Live" then
		statusLbl.Text = "📺 LIVE · " .. (if target ~= "" then displayOf(target) else "belum ada pemain")
	else
		statusLbl.Text = "🖼️ GAMBAR · layar samping menampilkan media"
	end
	statusSub.Text = ("Kamera %s · %d pemain"):format(if camModeLocal == "Dynamic" then "Dinamis" else "Statis", #sortedPlayerList)
	for mode, o in modeBtn do
		paintButton(o, mode == currentScreenModeLocal, not liveReady)
	end
	for mode, o in camBtn do
		paintButton(o, mode == camModeLocal, not liveReady)
	end
	for _, o in { showB, prevB, stopB, nextB } do
		paintButton(o, false, not liveReady)
	end
	for name, pb in playerButtons do
		local on = name == selectedPlayerName
		paintButton(pb, on, false)
		pb.name.TextColor3 = if on then T.ACCENT else T.TEXT
	end
end

local function updateButtonHighlight(targetName)
	selectedPlayerName = targetName
	paintLive()
end

local function setCameraMode(mode)
	if not liveReady or cameraMode.Value == mode then return end
	camModeLocal = mode
	paintLive()
	if cameraModeRemote then
		cameraModeRemote:FireServer(mode)
	end
end

local function setScreenMode(mode)
	if not liveReady or currentScreenModeLocal == mode then return end
	local now = os.clock()
	if now - lastModeSwitchTime < MODE_COOLDOWN then return end
	lastModeSwitchTime = now
	currentScreenModeLocal = mode
	paintLive()
	if screenModeRemote then
		screenModeRemote:FireServer(mode)
	end
end

local function broadcastPlayerByName(targetName)
	if not liveReady or not targetName or targetName == "" then return end
	local targetPlayer = Players:FindFirstChild(targetName)
	if not targetPlayer then
		warn("[LiveScreen] Player not found:", targetName)
		say(liveMsg, "❌ pemain tidak ada: " .. targetName, T.DANGER)
		return
	end
	targetRemote:FireServer(targetName)
	say(liveMsg, "✅ tampil di layar: " .. targetPlayer.DisplayName, T.SUCCESS)
end

local function broadcastPlayerFromInput()
	local searchText = searchBox.Text
	if searchText == "" then return end
	local found = Rules.findPlayer(sortedPlayerList, searchText)
	if found then
		updateButtonHighlight(found.Name)
		broadcastPlayerByName(found.Name)
	else
		warn("[LiveScreen] No match:", searchText)
		say(liveMsg, "❌ tidak ada pemain cocok: " .. searchText, T.DANGER)
	end
end

local function stopBroadcast()
	if not liveReady then return end
	targetRemote:FireServer("")
	updateButtonHighlight("")
	setScreenMode("Gambar")
	say(liveMsg, "■ Live dihentikan", T.TEXT_DIM)
end

-- Pilih pemain (klik daftar / ◀ ▶) = mode Live + kamera Statis + tampilkan — urutan sama dengan panel lama.
local function pickPlayer(name)
	updateButtonHighlight(name)
	setScreenMode("Live")
	setCameraMode("Static")
	broadcastPlayerByName(name)
end

local function filterPlayerList()
	local text = searchBox.Text
	table.clear(visiblePlayerList)
	for _, p in sortedPlayerList do
		local match = Rules.matches(p, text)
		local pb = playerButtons[p.Name]
		if pb then pb.btn.Visible = match end
		if match then table.insert(visiblePlayerList, p.Name) end
	end
	emptyLbl.Visible = #visiblePlayerList == 0
	emptyLbl.Text = if #sortedPlayerList == 0 then "Belum ada pemain." else ("Tidak ada pemain cocok dengan \"%s\"."):format(text)
end

local function refreshPlayerList()
	for _, pb in playerButtons do pb.btn:Destroy() end
	table.clear(playerButtons)
	local list = {}
	for _, p in Players:GetPlayers() do
		table.insert(list, { Name = p.Name, DisplayName = p.DisplayName })
	end
	sortedPlayerList = Rules.sortPlayers(list)
	for i, p in sortedPlayerList do
		local pb = button(listBox, "", i, { Name = p.Name, Size = UDim2.new(1, 0, 0, 40) })
		pb.name = label(pb.btn, p.DisplayName, 13, T.TEXT, FONT.MEDIUM, 0, { Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(1, -24, 0, 17) })
		label(pb.btn, "@" .. p.Name, 10, T.TEXT_DIM, FONT.REGULAR, 0, { Position = UDim2.new(0, 12, 0, 21), Size = UDim2.new(1, -24, 0, 14) })
		playerButtons[p.Name] = pb
		pb.btn.Activated:Connect(function()
			pickPlayer(p.Name)
		end)
	end
	filterPlayerList()
	paintLive()
end

local function navigatePlayer(direction)
	local name = Rules.navigate(visiblePlayerList, selectedPlayerName, direction)
	if name then pickPlayer(name) end
end

-- Tampilkan = tombol "Show" lama (mode Live + Statis, lalu pemain dari kotak cari); Enter di kotak = tombol "Enter" lama.
showB.btn.Activated:Connect(function()
	setScreenMode("Live")
	setCameraMode("Static")
	broadcastPlayerFromInput()
end)
searchBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and searchBox.Text ~= "" then
		setScreenMode("Live")
		setCameraMode("Static")
		broadcastPlayerFromInput()
	end
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(filterPlayerList)
stopB.btn.Activated:Connect(stopBroadcast)
prevB.btn.Activated:Connect(function() navigatePlayer("prev") end)
nextB.btn.Activated:Connect(function() navigatePlayer("next") end)
for mode, o in modeBtn do
	o.btn.Activated:Connect(function() setScreenMode(mode) end)
end
for mode, o in camBtn do
	o.btn.Activated:Connect(function() setCameraMode(mode) end)
end

-- ══ TAB MEDIA ═════════════════════════════════════════════════════════════════════════════════════════════════════
local MP = tabs.Media.page
local layars = {}
local order = 0
local function nextOrder()
	order += 1
	return order
end
for _, layarId in Config.LAYAR_URUTAN do
	local layar = Config.LAYAR[layarId]
	label(MP, string.upper(layar.label), 10, T.TEXT_DIM, FONT.MEDIUM, nextOrder())
	local nowLbl = label(MP, "", 13, T.ACCENT, FONT.BOLD, nextOrder())
	local box = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = nextOrder(), Parent = MP })
	new("UIGridLayout", { CellSize = UDim2.new(1 / #Config.MEDIA_TYPES, -6, 0, 40), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	local chips = {}
	for i, mediaType in Config.MEDIA_TYPES do
		local c = button(box, "", i)
		c.name = label(c.btn, labelOf(mediaType), 12, T.TEXT, FONT.MEDIUM, 0, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -16, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
		c.note = label(c.btn, "", 10, T.TEXT_DIM, FONT.REGULAR, 0, { Position = UDim2.new(0, 8, 0, 21), Size = UDim2.new(1, -16, 0, 14), TextXAlignment = Enum.TextXAlignment.Center })
		local filled, why = Rules.mediaOf(layar, mediaType)
		c.filled, c.why = filled ~= nil, why
		chips[mediaType] = c
	end
	layars[layarId] = { layar = layar, now = nowLbl, chips = chips }
end
local liveNote = label(MP, "Layar samping sedang LIVE — media samping tampil lagi saat mode 🖼️ Gambar (tab Live Screen).", 11, T.TEXT_DIM, FONT.REGULAR, nextOrder(), nil, 2)
local msgLbl = label(MP, "", 11, T.TEXT_DIM, FONT.REGULAR, nextOrder(), { Visible = false }, 2)
label(MP, "Berlaku di server ini saja; server baru kembali ke MEDIA_TYPE di Config. Video hanya boleh di satu layar.", 10, T.TEXT_DIM, FONT.REGULAR, nextOrder(), nil, 2)

local busy = false
local function mediaAttr(layarId)
	return if remotes then remotes:GetAttribute(layarId) else nil
end
local function videoElsewhere(layarId)
	for _, id in Config.LAYAR_URUTAN do
		if id ~= layarId and mediaAttr(id) == "VIDEO" then
			return true
		end
	end
	return false
end

local function paintMedia()
	for layarId, ly in layars do
		local active = mediaAttr(layarId)
		ly.now.Text = "Sekarang: " .. labelOf(active)
		local blockVideo = videoElsewhere(layarId)
		for mediaType, c in ly.chips do
			local on = mediaType == active
			local off = busy or not setFn or not c.filled or (mediaType == "VIDEO" and blockVideo and not on)
			paintButton(c, on, false)
			c.name.TextColor3 = if off then T.TEXT_DIM elseif on then T.ACCENT else T.TEXT
			c.note.Text = if on then "tampil" elseif not c.filled then "belum diisi" elseif mediaType == "VIDEO" and blockVideo then "dipakai layar lain" else ""
		end
	end
	liveNote.Visible = screenMode ~= nil and screenMode.Value ~= Config.LAYAR_SAMPING.ACTIVE_ON_MODE
	if not setFn then
		say(msgLbl, "Server DjStage tidak jalan — media tidak bisa diganti.", T.DANGER)
		return
	end
	local by = remotes:GetAttribute("ChangedBy")
	if msgLbl.Text == "" and type(by) == "string" then
		say(msgLbl, "Terakhir diganti: " .. by, T.TEXT_DIM)
	end
end

local REASON = {
	admin = "hanya admin",
	invalid = "pilihan tidak sah",
	empty = "belum diisi di Config.DjStage",
	video = "video sudah dipakai layar lain (maks 1 layar)",
}
for layarId, ly in layars do
	for mediaType, c in ly.chips do
		c.btn.Activated:Connect(function()
			if busy or not setFn then return end
			if not c.filled then
				say(msgLbl, ("❌ %s: %s"):format(ly.layar.label, tostring(c.why)), T.DANGER)
				return
			end
			if mediaAttr(layarId) == mediaType then -- sudah tampil: tidak perlu tanya server
				say(msgLbl, ("✅ %s sudah menampilkan %s"):format(ly.layar.label, labelOf(mediaType)), T.SUCCESS)
				return
			end
			if mediaType == "VIDEO" and videoElsewhere(layarId) then
				say(msgLbl, "❌ " .. REASON.video, T.DANGER)
				return
			end
			busy = true
			paintMedia()
			local ok, r = pcall(setFn.InvokeServer, setFn, layarId, mediaType)
			busy = false
			if ok and type(r) == "table" and r.ok then
				say(msgLbl, ("✅ %s → %s"):format(ly.layar.label, labelOf(mediaType)), T.SUCCESS)
			else
				local why = ok and type(r) == "table" and r.reason or "tidak ada jawaban server"
				say(msgLbl, "❌ " .. (if why == "cooldown" then ("tunggu %s dtk"):format(tostring(r.wait or "")) else (REASON[why] or tostring(why))), T.DANGER)
			end
			paintMedia()
		end)
	end
end

-- ── tab, ukuran & buka/tutup ──────────────────────────────────────────────────────────────────────────────────────
-- Ukuran dihitung saat panel dibuka, tab diganti, atau layar berubah (diputar / jendela diubah). Sesudah itu TETAP:
-- pemain masuk/keluar hanya mengubah isi daftar (digulir), panel tidak bergeser sendiri.
local SIZING_TIME = 0.5 -- dtk sesudah buka / ganti tab: ukuran isi baru boleh dihitung ulang (tata letak Roblox menyusul)
local sizingUntil = 0
local function layout()
	local ok, p = pcall(Responsive.Panel)
	p = if ok and type(p) == "table" then p else {}
	local vp = workspace.CurrentCamera.ViewportSize
	local topInset = GuiService:GetGuiInset()
	local bottom = p.bottomInset or 10
	local guiH = vp.Y - topInset.Y
	local w, h = Rules.panelSize(vp.X, guiH, p.device == "mobile", bottom, pageHeight(tabs[activeTab]) + TOP_H)
	frame.Size = UDim2.new(0, w, 0, h)
	-- tengah area antara tepi atas (+8) dan hotbar
	frame.Position = UDim2.new(0.5, 0, 0, math.floor((guiH - bottom + 8) / 2))
end
-- Tinggi isi tab & kanvas gulir selalu mengikuti isi (pemain masuk → daftar memanjang, digulir).
local function fitPage(t)
	local hgt = pageHeight(t)
	t.page.Size = UDim2.new(1, -2 * PAD, 0, hgt)
	if t.page.Visible then
		body.CanvasSize = UDim2.new(0, 0, 0, hgt)
	end
end

local function showTab(id)
	activeTab = id
	for name, t in tabs do
		t.page.Visible = name == id
		paintButton(t, name == id, false)
	end
	fitPage(tabs[id])
	body.CanvasPosition = Vector2.new(0, 0)
	sizingUntil = os.clock() + SIZING_TIME
	if isOpen then layout() end
end
for id, t in tabs do
	t.btn.Activated:Connect(function() showTab(id) end)
	t.list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		fitPage(t)
		if isOpen and activeTab == id and os.clock() < sizingUntil then layout() end
	end)
end
Responsive.OnChange(function()
	if isOpen then layout() end
end)

local function coordinator()
	return _G.PanelCoordinator
end
local function setOpen(open)
	if open and player:GetAttribute("IsAdmin") ~= true then open = false end
	if open == isOpen then return end
	isOpen = open
	gui.Enabled = open
	local pc = coordinator()
	if open then
		say(msgLbl, "", T.TEXT_DIM)
		refreshPlayerList()
		paintMedia()
		showTab(activeTab)
		if pc and pc.NotifyOpen then pcall(pc.NotifyOpen, "DjStage") end
	elseif pc and pc.NotifyClose then
		pcall(pc.NotifyClose, "DjStage")
	end
	if _G.DjStageMenu.OnChanged then pcall(_G.DjStageMenu.OnChanged, open) end
end
task.spawn(function()
	local t0 = os.clock()
	while not (coordinator() and coordinator().Register) and os.clock() - t0 < 30 do task.wait(0.2) end
	local pc = coordinator()
	if pc and pc.Register then pc.Register("DjStage", function() setOpen(false) end) end
end)

_G.ToggleDjStage = function() setOpen(not isOpen) end
_G.DjStageMenu.Open = function() setOpen(true) end
_G.DjStageMenu.Close = function() setOpen(false) end
_G.DjStageMenu.Gui = gui

closeBtn.Activated:Connect(function() setOpen(false) end)
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)
player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
	if player:GetAttribute("IsAdmin") ~= true then setOpen(false) end
end)

-- ── sinkron dari server ───────────────────────────────────────────────────────────────────────────────────────────
if screenMode then
	screenMode.Changed:Connect(function(v)
		currentScreenModeLocal = v
		if isOpen then
			paintLive()
			paintMedia()
		end
	end)
end
if cameraMode then
	cameraMode.Changed:Connect(function(v)
		camModeLocal = v
		if isOpen then paintLive() end
	end)
end
if currentTarget then
	currentTarget.Changed:Connect(function()
		if isOpen then paintLive() end
	end)
end
if remotes then
	local watched = { "ChangedBy" }
	for _, layarId in Config.LAYAR_URUTAN do
		table.insert(watched, layarId)
	end
	for _, a in watched do
		remotes:GetAttributeChangedSignal(a):Connect(function()
			if isOpen then paintMedia() end
		end)
	end
end
local refreshQueued = false
local function queueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	task.delay(0.3, function()
		refreshQueued = false
		if isOpen then refreshPlayerList() end
	end)
end
Players.PlayerAdded:Connect(queueRefresh)
Players.PlayerRemoving:Connect(queueRefresh)
