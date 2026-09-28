-- ╔══════════════════════════════════════════════════════════════╗
-- ║        INFO TOPBAR — + COMMUNITY (Group & Favorite)          ║
-- ║         StarterPlayer > StarterPlayerScripts (LocalScript)   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- LAYOUT (semua ukuran, posisi, struktur) SAMA seperti versi asli.
-- Yang diubah hanya TEMA: warna + font disamakan dengan DanceClient /
-- UltimateMenu (dibaca dari _G.MenuConfig bila sudah ada), plus tombol Info
-- tidak lagi menimpa panel Menu.

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local UIS                 = game:GetService("UserInputService")
local GuiService          = game:GetService("GuiService")
local GroupService        = game:GetService("GroupService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════════
local INFO_LINK      = "" -- [FIX] link donasi luar Roblox dihapus
local DISCORD_INVITE = "" -- [FIX] pakai Social Links resmi di Creator Dashboard
local GROUP_ID       = 277580244
local PLACE_ID       = game.PlaceId

-- ══════════════════════════════════════════════════════════════
--  CONSTANTS
-- ══════════════════════════════════════════════════════════════
local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
local VP        = workspace.CurrentCamera.ViewportSize
local PW        = math.clamp(math.floor(VP.X * 0.36), 260, 310)
local HEADER_H  = 44
local CARD_H    = 58
local CARD_GAP  = 6
local CARD_N    = 3
local PANEL_H   = HEADER_H + 6 + CARD_N * CARD_H + (CARD_N - 1) * CARD_GAP + 12

local BTN_H     = 42
local BTN_PADX  = 20
local BTN_TEXT  = 15

-- Posisi (desktop / landscape): baris kiri dimulai tepat setelah tombol bawaan Roblox
-- (GuiService.TopbarInset.Min.X) + ROW_GAP. BTN_X = cadangan kalau TopbarInset tidak terbaca.
-- Mobile portrait → baris pindah ke kanan di bawah tombol Menu (updateBtnPosition).
local BTN_X   = 265
local BTN_Y   = 14
local ROW_GAP = 12   -- jarak dari tombol chat Roblox (= jarak antar tombol bawaan)
local ROW_PAD = 8    -- jarak antar tombol di baris kiri (Info, Donate, …)

-- ══════════════════════════════════════════════════════════════
--  TEMA (sama dengan DanceClient / UltimateMenu)
-- ══════════════════════════════════════════════════════════════
do
	local waited = 0
	while not _G.MenuConfig and waited < 5 do
		task.wait(0.1); waited = waited + 0.1
	end
end

local TH = (_G.MenuConfig and _G.MenuConfig.theme) or {
	BG         = Color3.fromRGB(16, 16, 17),
	CARD       = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	LINE       = Color3.fromRGB(255, 255, 255),
	TEXT       = Color3.fromRGB(238, 238, 240),
	TEXT_DIM   = Color3.fromRGB(148, 148, 154),
	ACCENT     = Color3.fromRGB(212, 175, 55),
	SUCCESS    = Color3.fromRGB(96, 196, 132),
}

local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

-- Nama kunci lama dipertahankan supaya seluruh kode di bawah tidak berubah.
local C = {
	Black   = TH.CARD,
	Panel   = TH.BG,
	Header  = TH.BG,
	Card    = TH.CARD,
	Hover   = TH.CARD_HOVER,
	Gold    = TH.ACCENT,
	GoldHov = TH.ACCENT,
	GoldDim = TH.TEXT_DIM,
	Border  = TH.LINE,
	Text    = TH.TEXT,
	Dim     = TH.TEXT_DIM,
	Red     = TH.TEXT_DIM,
	White   = TH.TEXT,
	Discord = TH.ACCENT,
	SWR     = TH.ACCENT,
	Green   = TH.SUCCESS,
}

-- Panel solid seperti panel lain; hanya overlay yang transparan.
local T = {
	Panel  = 0,
	Header = 1,
	Card   = 0,
	Btn    = 0,
	Ov     = 0.45,
}

-- ══════════════════════════════════════════════════════════════
--  TWEEN INFO CACHE
-- ══════════════════════════════════════════════════════════════
local TI = {
	Fast  = TweenInfo.new(0.12, Enum.EasingStyle.Quad),
	Mid   = TweenInfo.new(0.20, Enum.EasingStyle.Quad),
	Open  = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.16, Enum.EasingStyle.Quad),
}

-- ══════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════
local function rnd(r, p)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function pill(p)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = p
end

-- thick sekarang dipakai sebagai TRANSPARANSI stroke (tema baru pakai garis
-- tipis 1px yang nyaris transparan), jadi pemanggilan di bawah tidak berubah.
local function mkStroke(p, color, thick)
	local s = Instance.new("UIStroke")
	s.Color           = color
	s.Thickness       = 1
	s.Transparency    = (thick == 0.5) and 0.94 or 0.88
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = p
	return s
end

local function tw(obj, info, props)
	TweenService:Create(obj, info, props):Play()
end

local function popIn(f, w, h)
	f.Size = UDim2.new(0, 0, 0, 0)
	tw(f, TI.Open, { Size = UDim2.new(0, w, 0, h) })
end

local function popOut(f, cb)
	local t = TweenService:Create(f, TI.Close, { Size = UDim2.new(0, 0, 0, 0) })
	if cb then t.Completed:Once(cb) end
	t:Play()
end

-- ══════════════════════════════════════════════════════════════
--  PANEL COORDINATOR
-- ══════════════════════════════════════════════════════════════
do
	local waited = 0
	while not _G.PanelCoordinator and waited < 5 do
		task.wait(0.1); waited = waited + 0.1
	end
	if not _G.PanelCoordinator then
		_G.PanelCoordinator = { panels = {}, activePanel = nil, listeners = {} }

		function _G.PanelCoordinator.Register(name, closeFn)
			_G.PanelCoordinator.panels[name] = closeFn
		end

		function _G.PanelCoordinator._fire()
			for _, fn in ipairs(_G.PanelCoordinator.listeners) do
				pcall(fn, _G.PanelCoordinator.activePanel)
			end
		end

		function _G.PanelCoordinator.OnChange(fn)
			table.insert(_G.PanelCoordinator.listeners, fn)
			pcall(fn, _G.PanelCoordinator.activePanel)
		end

		function _G.PanelCoordinator.CloseAll(except)
			for name, fn in pairs(_G.PanelCoordinator.panels) do
				if name ~= except then pcall(fn) end
			end
			if not except then
				_G.PanelCoordinator.activePanel = nil
				_G.PanelCoordinator._fire()
			end
		end

		function _G.PanelCoordinator.NotifyOpen(name)
			_G.PanelCoordinator.CloseAll(name)
			_G.PanelCoordinator.activePanel = name
			_G.PanelCoordinator._fire()
		end

		function _G.PanelCoordinator.NotifyClose(name)
			if _G.PanelCoordinator.activePanel == name then
				_G.PanelCoordinator.activePanel = nil
				_G.PanelCoordinator._fire()
			end
		end
	end
end

-- ══════════════════════════════════════════════════════════════
--  SCREEN GUI
--  FIX: DisplayOrder 10 → -1. ScreenGui panel Menu memakai DisplayOrder 0,
--  jadi dengan -1 seluruh lapisan Info selalu berada DI BAWAH panel Menu.
--  Panel Info sendiri tetap tampil normal karena PanelCoordinator menjamin
--  keduanya tidak pernah terbuka bersamaan.
-- ══════════════════════════════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name           = "InfoTopbarGui"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.DisplayOrder   = -1
sg.Parent         = playerGui

-- ══════════════════════════════════════════════════════════════
--  TOPBAR BUTTON  (dibuat dulu, baru updateBtnPosition dipanggil)
-- ══════════════════════════════════════════════════════════════
-- Baris kiri: Info + tombol lain (mis. Donate lewat _G.TopbarLeft.add) berjajar rapi.
local leftRow = Instance.new("Frame")
leftRow.Name                   = "LeftRow"
leftRow.AutomaticSize          = Enum.AutomaticSize.X
leftRow.Size                   = UDim2.new(0, 0, 0, BTN_H)
leftRow.Position               = UDim2.new(0, BTN_X, 0, BTN_Y)
leftRow.BackgroundTransparency = 1
leftRow.Parent                 = sg

local rowList = Instance.new("UIListLayout")
rowList.FillDirection     = Enum.FillDirection.Horizontal
rowList.VerticalAlignment = Enum.VerticalAlignment.Center
rowList.Padding           = UDim.new(0, ROW_PAD)
rowList.SortOrder         = Enum.SortOrder.LayoutOrder
rowList.Parent            = leftRow

local topBtn = Instance.new("TextButton")
topBtn.Name                   = "InfoTopbarButton"
topBtn.LayoutOrder            = 1
topBtn.AutomaticSize          = Enum.AutomaticSize.X
topBtn.Size                   = UDim2.new(0, 0, 0, BTN_H)
topBtn.BackgroundColor3       = C.Black
topBtn.BackgroundTransparency = T.Btn
topBtn.BorderSizePixel        = 0
topBtn.Text                   = ""
topBtn.AutoButtonColor        = false
topBtn.Parent                 = leftRow
pill(topBtn)

local btnPad = Instance.new("UIPadding")
btnPad.PaddingLeft  = UDim.new(0, BTN_PADX)
btnPad.PaddingRight = UDim.new(0, BTN_PADX)
btnPad.Parent       = topBtn

local btnScale = Instance.new("UIScale")
btnScale.Scale  = 1
btnScale.Parent = topBtn

local btnStroke = Instance.new("UIStroke")
btnStroke.Color           = C.Gold
btnStroke.Thickness       = 1
btnStroke.Transparency    = 0.35
btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
btnStroke.Parent          = topBtn

local btnLabel = Instance.new("TextLabel")
btnLabel.AutomaticSize          = Enum.AutomaticSize.X
btnLabel.Size                   = UDim2.new(0, 0, 1, 0)
btnLabel.BackgroundTransparency = 1
btnLabel.Text                   = "Info"
btnLabel.TextColor3             = C.White
btnLabel.TextSize               = BTN_TEXT
btnLabel.Font                   = FONT.BOLD
btnLabel.Parent                 = topBtn

-- ══════════════════════════════════════════════════════════════
--  POSISI TOMBOL  (dipanggil SETELAH topBtn ada)
--  Mobile portrait → di bawah tombol Menu (UltimateMenu ada di Y=13, H=42)
--  Anchor UltimateMenu btn: Position(1, -92, 0, 13) → kita ikuti X-nya
-- ══════════════════════════════════════════════════════════════
local function rowStartX()
	local ok, inset = pcall(function() return GuiService.TopbarInset end)
	if ok and inset and inset.Min.X > 0 then
		return inset.Min.X + ROW_GAP
	end
	return BTN_X
end

local function updateBtnPosition()
	local vp = workspace.CurrentCamera.ViewportSize
	if vp.Y > vp.X then
		leftRow.AnchorPoint = Vector2.new(1, 0)
		leftRow.Position    = UDim2.new(1, -10, 0, 62)  -- sisi kanan sejajar Menu
	else
		leftRow.AnchorPoint = Vector2.new(0, 0)
		leftRow.Position    = UDim2.new(0, rowStartX(), 0, BTN_Y)
	end
end

-- Panggil sekali saat load
updateBtnPosition()

-- Reaktif saat orientasi berubah.
-- FIX kecil: koneksi lama di-disconnect dulu. Versi sebelumnya menambah
-- koneksi baru tiap kali CurrentCamera berganti tanpa melepas yang lama.
local camConn
local function bindCamera()
	if camConn then camConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateBtnPosition)
	end
end

bindCamera()
-- Lebar tombol bawaan Roblox bisa berubah (chat dimatikan, perangkat lain) → ikut geser.
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateBtnPosition)
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.wait()  -- tunggu kamera baru siap
	bindCamera()
	updateBtnPosition()
end)

-- ══════════════════════════════════════════════════════════════
--  HOVER & PRESS EVENTS (tombol)
-- ══════════════════════════════════════════════════════════════
if not IS_MOBILE then
	topBtn.MouseEnter:Connect(function()
		tw(topBtn,    TI.Mid, { BackgroundColor3 = C.Hover })
		tw(btnLabel,  TI.Mid, { TextColor3 = C.Gold })
		tw(btnStroke, TI.Mid, { Thickness = 1, Transparency = 0.1 })
	end)
	topBtn.MouseLeave:Connect(function()
		tw(topBtn,    TI.Mid, { BackgroundColor3 = C.Black })
		tw(btnLabel,  TI.Mid, { TextColor3 = C.White })
		tw(btnStroke, TI.Mid, { Thickness = 1, Transparency = 0.35 })
	end)
end
topBtn.MouseButton1Down:Connect(function()
	tw(btnScale, TI.Fast, { Scale = 0.92 })
end)
topBtn.MouseButton1Up:Connect(function()
	tw(btnScale, TI.Fast, { Scale = 1 })
end)

-- ══════════════════════════════════════════════════════════════
--  SHARED UI FACTORIES
-- ══════════════════════════════════════════════════════════════
local function makeOverlay()
	local ov = Instance.new("Frame")
	ov.Size                   = UDim2.new(1, 0, 1, 0)
	ov.BackgroundColor3       = C.Black
	ov.BackgroundTransparency = T.Ov
	ov.BorderSizePixel        = 0
	ov.Visible                = false
	ov.Parent                 = sg

	local ob = Instance.new("TextButton")
	ob.Size                   = UDim2.new(1, 0, 1, 0)
	ob.BackgroundTransparency = 1
	ob.Text                   = ""
	ob.Parent                 = ov
	return ov, ob
end

local function makeHeader(parent, titleText, accentColor)
	local hdr = Instance.new("Frame")
	hdr.Size                   = UDim2.new(1, 0, 0, HEADER_H)
	hdr.BackgroundColor3       = C.Header
	hdr.BackgroundTransparency = T.Header
	hdr.BorderSizePixel        = 0
	hdr.Parent                 = parent
	rnd(12, hdr)

	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, 0, 0, 1)
	sep.Position         = UDim2.new(0, 0, 1, -1)
	sep.BackgroundColor3       = C.Border
	sep.BackgroundTransparency = 0.9
	sep.BorderSizePixel        = 0
	sep.Parent           = hdr

	local ttl = Instance.new("TextLabel")
	ttl.Size                   = UDim2.new(1, -50, 1, 0)
	ttl.Position               = UDim2.new(0, 14, 0, 0)
	ttl.BackgroundTransparency = 1
	ttl.Text                   = titleText
	ttl.TextSize               = 13
	ttl.Font                   = FONT.MEDIUM
	ttl.TextColor3             = accentColor
	ttl.TextXAlignment         = Enum.TextXAlignment.Left
	ttl.Parent                 = hdr

	local cl = Instance.new("TextButton")
	cl.Size                   = UDim2.new(0, 26, 0, 26)
	cl.Position               = UDim2.new(1, -34, 0.5, -13)
	cl.BackgroundColor3       = C.Card
	cl.BackgroundTransparency = 0
	cl.BorderSizePixel        = 0
	cl.Text                   = "✕"
	cl.TextSize               = 13
	cl.Font                   = FONT.REGULAR
	cl.TextColor3             = C.Dim
	cl.Parent                 = hdr
	rnd(7, cl)

	if not IS_MOBILE then
		cl.MouseEnter:Connect(function()
			tw(cl, TI.Fast, { BackgroundColor3 = C.Hover, TextColor3 = C.Text })
		end)
		cl.MouseLeave:Connect(function()
			tw(cl, TI.Fast, { BackgroundColor3 = C.Card, TextColor3 = C.Dim })
		end)
	end
	return cl
end

local function makePopup(ov, w, h, accent, title)
	local p = Instance.new("Frame")
	p.Size                   = UDim2.new(0, w, 0, h)
	p.AnchorPoint            = Vector2.new(0.5, 0.5)
	p.Position               = UDim2.new(0.5, 0, 0.5, 0)
	p.BackgroundColor3       = C.Panel
	p.BackgroundTransparency = T.Panel
	p.BorderSizePixel        = 0
	p.Parent                 = ov
	rnd(12, p)
	mkStroke(p, C.Border, 0.8)

	local closeBtn = makeHeader(p, title, accent)
	return p, closeBtn
end

local function makeLinkBox(parent, url, accentColor, yPos)
	local bg = Instance.new("Frame")
	bg.Size                   = UDim2.new(1, -18, 0, 42)
	bg.Position               = UDim2.new(0, 9, 0, yPos)
	bg.BackgroundColor3       = C.Card
	bg.BackgroundTransparency = 0
	bg.BorderSizePixel        = 0
	bg.Parent                 = parent
	rnd(8, bg)
	mkStroke(bg, accentColor, 0.5)

	local box = Instance.new("TextBox")
	box.Size                   = UDim2.new(1, -10, 1, 0)
	box.Position               = UDim2.new(0, 5, 0, 0)
	box.BackgroundTransparency = 1
	box.Text                   = url
	box.TextSize               = 11
	box.Font                   = FONT.REGULAR
	box.TextColor3             = accentColor
	box.TextXAlignment         = Enum.TextXAlignment.Center
	box.TextEditable           = false
	box.ClearTextOnFocus       = false
	box.Parent                 = bg

	box.Focused:Connect(function()
		box.SelectionStart = 1
		box.CursorPosition = #url + 1
	end)
	return bg
end

local function mkNote(parent, text, color, yPos)
	local l = Instance.new("TextLabel")
	l.Size                   = UDim2.new(1, -18, 0, 15)
	l.Position               = UDim2.new(0, 9, 0, yPos)
	l.BackgroundTransparency = 1
	l.Text                   = text
	l.TextSize               = 9
	l.Font                   = FONT.REGULAR
	l.TextColor3             = color or C.Dim
	l.TextXAlignment         = Enum.TextXAlignment.Center
	l.Parent                 = parent
	return l
end

local function makeActionBtn(parent, text, accentColor, yPos, onClick)
	local btn = Instance.new("TextButton")
	btn.Size                   = UDim2.new(1, -18, 0, 40)
	btn.Position               = UDim2.new(0, 9, 0, yPos)
	btn.BackgroundColor3       = C.Card
	btn.BackgroundTransparency = T.Card
	btn.BorderSizePixel        = 0
	btn.Text                   = text
	btn.TextSize               = 13
	btn.Font                   = FONT.MEDIUM
	btn.TextColor3             = accentColor
	btn.AutoButtonColor        = false
	btn.Parent                 = parent
	rnd(8, btn)
	mkStroke(btn, accentColor, 0.5)

	if not IS_MOBILE then
		btn.MouseEnter:Connect(function()
			tw(btn, TI.Fast, { BackgroundColor3 = C.Hover, BackgroundTransparency = 0 })
		end)
		btn.MouseLeave:Connect(function()
			tw(btn, TI.Fast, { BackgroundColor3 = C.Card, BackgroundTransparency = T.Card })
		end)
	end
	btn.MouseButton1Click:Connect(function()
		tw(btn, TI.Fast, { BackgroundColor3 = accentColor })
		task.delay(0.12, function()
			tw(btn, TI.Fast, { BackgroundColor3 = C.Card, BackgroundTransparency = T.Card })
		end)
		if onClick then onClick() end
	end)
	return btn
end

-- ══════════════════════════════════════════════════════════════
--  MAIN PANEL
-- ══════════════════════════════════════════════════════════════
local mainOv, mainOvBtn = makeOverlay()

local mainPanel = Instance.new("Frame")
mainPanel.Size                   = UDim2.new(0, PW, 0, 0)
mainPanel.AnchorPoint            = Vector2.new(0.5, 0.5)
mainPanel.Position               = UDim2.new(0.5, 0, 0.5, 0)
mainPanel.BackgroundColor3       = C.Panel
mainPanel.BackgroundTransparency = T.Panel
mainPanel.BorderSizePixel        = 0
mainPanel.Parent                 = mainOv
rnd(12, mainPanel)
mkStroke(mainPanel, C.Border, 0.8)

local pClose = makeHeader(mainPanel, "Info", C.Gold)

local cCon = Instance.new("Frame")
cCon.Size                   = UDim2.new(1, -16, 0, CARD_N * CARD_H + (CARD_N - 1) * CARD_GAP)
cCon.Position               = UDim2.new(0, 8, 0, HEADER_H + 6)
cCon.BackgroundTransparency = 1
cCon.Parent                 = mainPanel

local cList = Instance.new("UIListLayout")
cList.Padding   = UDim.new(0, CARD_GAP)
cList.SortOrder = Enum.SortOrder.LayoutOrder
cList.Parent    = cCon

local function makeCard(order, icon, title, sub, accent)
	local card = Instance.new("TextButton")
	card.LayoutOrder            = order
	card.Size                   = UDim2.new(1, 0, 0, CARD_H)
	card.BackgroundColor3       = C.Card
	card.BackgroundTransparency = T.Card
	card.BorderSizePixel        = 0
	card.Text                   = ""
	card.AutoButtonColor        = false
	card.Parent                 = cCon
	rnd(8, card)
	mkStroke(card, C.Border, 0.5)

	local bar = Instance.new("Frame")
	bar.Size                   = UDim2.new(0, 2, 0.44, 0)
	bar.Position               = UDim2.new(0, 0, 0.28, 0)
	bar.BackgroundColor3       = accent
	bar.BackgroundTransparency = 0.35
	bar.BorderSizePixel        = 0
	bar.Parent                 = card
	rnd(2, bar)

	local ico = Instance.new("TextLabel")
	ico.Size                   = UDim2.new(0, 30, 1, 0)
	ico.Position               = UDim2.new(0, 11, 0, 0)
	ico.BackgroundTransparency = 1
	ico.Text                   = icon
	ico.TextSize               = 18
	ico.Font                   = FONT.REGULAR
	ico.TextColor3             = accent
	ico.Parent                 = card

	local t1 = Instance.new("TextLabel")
	t1.Size                   = UDim2.new(1, -54, 0, 20)
	t1.Position               = UDim2.new(0, 46, 0, 9)
	t1.BackgroundTransparency = 1
	t1.Text                   = title
	t1.TextSize               = 12
	t1.Font                   = FONT.MEDIUM
	t1.TextColor3             = C.Text
	t1.TextXAlignment         = Enum.TextXAlignment.Left
	t1.Parent                 = card

	local t2 = Instance.new("TextLabel")
	t2.Size                   = UDim2.new(1, -54, 0, 15)
	t2.Position               = UDim2.new(0, 46, 0, 29)
	t2.BackgroundTransparency = 1
	t2.Text                   = sub
	t2.TextSize               = 10
	t2.Font                   = FONT.REGULAR
	t2.TextColor3             = C.Dim
	t2.TextXAlignment         = Enum.TextXAlignment.Left
	t2.Parent                 = card

	local arr = Instance.new("TextLabel")
	arr.Size                   = UDim2.new(0, 16, 1, 0)
	arr.Position               = UDim2.new(1, -20, 0, 0)
	arr.BackgroundTransparency = 1
	arr.Text                   = "›"
	arr.TextSize               = 18
	arr.Font                   = FONT.MEDIUM
	arr.TextColor3             = C.GoldDim
	arr.Parent                 = card

	if not IS_MOBILE then
		card.MouseEnter:Connect(function()
			tw(card, TI.Fast, { BackgroundColor3 = C.Hover, BackgroundTransparency = 0 })
			tw(arr,  TI.Fast, { TextColor3 = C.Gold })
		end)
		card.MouseLeave:Connect(function()
			tw(card, TI.Fast, { BackgroundColor3 = C.Card, BackgroundTransparency = T.Card })
			tw(arr,  TI.Fast, { TextColor3 = C.GoldDim })
		end)
	end
	return card
end

local cardSWR     = makeCard(1, "🌟", "Support",   "Dukungan Bagi",           C.SWR)
local cardDiscord = makeCard(2, "💬", "Discord",   "Join komunitas",           C.Discord)
local cardCommun  = makeCard(3, "👥", "Community", "Gabung group & favorite",  C.Gold)
cardSWR.Visible = false     -- [FIX]
cardDiscord.Visible = false -- [FIX]

-- ══════════════════════════════════════════════════════════════
--  POPUP: SWR
-- ══════════════════════════════════════════════════════════════
local swrOv, swrOvBtn    = makeOverlay()
local swrPopup, swrClose = makePopup(swrOv, PW, 130, C.SWR, "Support")

makeLinkBox(swrPopup, INFO_LINK, C.SWR, HEADER_H + 6)
mkNote(swrPopup, "Klik link → Ctrl+C untuk salin",             C.GoldDim, 98)
mkNote(swrPopup, "Isi kolom DARI dengan username Roblox kamu", C.Dim,     113)

-- ══════════════════════════════════════════════════════════════
--  POPUP: DISCORD
-- ══════════════════════════════════════════════════════════════
local dcOv, dcOvBtn    = makeOverlay()
local dcPopup, dcClose = makePopup(dcOv, PW, 116, C.Discord, "Discord Server")

makeLinkBox(dcPopup, DISCORD_INVITE, C.Discord, HEADER_H + 6)
mkNote(dcPopup, "Klik link → Ctrl+C → paste di browser", C.Dim, 98)

-- ══════════════════════════════════════════════════════════════
--  POPUP: COMMUNITY
-- ══════════════════════════════════════════════════════════════
local commOv, commOvBtn    = makeOverlay()
local commPopup, commClose = makePopup(commOv, PW, 156, C.Gold, "Community")

local groupBtn = makeActionBtn(commPopup, "👥  Gabung Group", C.Gold, HEADER_H + 8, function()
	pcall(function()
		GroupService:PromptJoinAsync(GROUP_ID)
	end)
end)

makeActionBtn(commPopup, "⭐  Favorite Game", C.SWR, HEADER_H + 8 + 48, function()
	pcall(function()
		AvatarEditorService:PromptSetFavorite(PLACE_ID, Enum.AvatarItemType.Asset, true)
	end)
end)

mkNote(commPopup, "Dukung game ini — join & favorite ⭐", C.Dim, 140)

local function refreshGroupStatus()
	local ok, inGroup = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if ok and inGroup then
		groupBtn.Text       = "👥  Sudah Gabung ✓"
		groupBtn.TextColor3 = C.Green
	else
		groupBtn.Text       = "👥  Gabung Group"
		groupBtn.TextColor3 = C.Gold
	end
end

-- ══════════════════════════════════════════════════════════════
--  POPUP CONTROLLER FACTORY
-- ══════════════════════════════════════════════════════════════
local function makePopupCtrl(ov, popup, w, h)
	local function open()
		ov.Visible = true
		popIn(popup, w, h)
	end
	local function close()
		popOut(popup, function() ov.Visible = false end)
	end
	return open, close
end

local openSWR,  closeSWR  = makePopupCtrl(swrOv,  swrPopup,  PW, 130)
local openDC,   closeDC   = makePopupCtrl(dcOv,   dcPopup,   PW, 116)
local openComm, closeComm = makePopupCtrl(commOv, commPopup, PW, 156)

-- ══════════════════════════════════════════════════════════════
--  MAIN PANEL LOGIC
-- ══════════════════════════════════════════════════════════════
local isPanelOpen = false

local function closeMain()
	if not isPanelOpen then return end
	isPanelOpen = false
	_G.PanelCoordinator.NotifyClose("Info")
	popOut(mainPanel, function() mainOv.Visible = false end)
end

local function openMain()
	if isPanelOpen then closeMain(); return end
	isPanelOpen = true
	_G.PanelCoordinator.NotifyOpen("Info")
	mainOv.Visible = true
	popIn(mainPanel, PW, PANEL_H)
end

_G.PanelCoordinator.Register("Info", closeMain)

-- ══════════════════════════════════════════════════════════════
--  FIX ANTI-TIMPA
--  Tombol Info disembunyikan selama panel LAIN terbuka (mis. panel Menu),
--  lalu muncul lagi setelah panel itu ditutup. Posisi, ukuran, dan gaya
--  tombol tidak diubah sama sekali — hanya properti Visible.
-- ══════════════════════════════════════════════════════════════
local function setBtnHidden(hidden)
	leftRow.Visible = not hidden
end

if type(_G.PanelCoordinator.OnChange) == "function" then
	_G.PanelCoordinator.OnChange(function(activePanel)
		setBtnHidden(activePanel ~= nil and activePanel ~= "Info")
	end)
else
	-- Coordinator versi lama tanpa OnChange: pantau langsung panel Menu.
	task.spawn(function()
		for _ = 1, 60 do
			local pm = _G.PanelManager
			local pd = pm and pm.panels and pm.panels.Menu
			if pd and pd.panel then
				pd.panel:GetPropertyChangedSignal("Visible"):Connect(function()
					setBtnHidden(pd.panel.Visible)
				end)
				setBtnHidden(pd.panel.Visible)
				return
			end
			task.wait(0.5)
		end
	end)
end

-- ══════════════════════════════════════════════════════════════
--  EVENTS
-- ══════════════════════════════════════════════════════════════
topBtn.MouseButton1Click:Connect(openMain)
pClose.MouseButton1Click:Connect(closeMain)
mainOvBtn.MouseButton1Click:Connect(closeMain)

cardSWR.MouseButton1Click:Connect(function()
	closeMain()
	task.wait(0.18)
	openSWR()
end)
cardDiscord.MouseButton1Click:Connect(function()
	closeMain()
	task.wait(0.18)
	openDC()
end)
cardCommun.MouseButton1Click:Connect(function()
	closeMain()
	task.wait(0.18)
	refreshGroupStatus()
	openComm()
end)

swrClose.MouseButton1Click:Connect(closeSWR)
swrOvBtn.MouseButton1Click:Connect(closeSWR)

dcClose.MouseButton1Click:Connect(closeDC)
dcOvBtn.MouseButton1Click:Connect(closeDC)

commClose.MouseButton1Click:Connect(closeComm)
commOvBtn.MouseButton1Click:Connect(closeComm)

-- API baris kiri untuk skrip lain (mis. DonationClient): tombol diberi tinggi BTN_H.
_G.TopbarLeft = {
	height = BTN_H,
	add = function(btn, order)
		btn.LayoutOrder = order or 10
		btn.Parent      = leftRow
	end,
}

print("[InfoTopbar] Ready ✓ (+ Community)")