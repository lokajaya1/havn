-- ═══════════════════════════════════════════════════════════
-- COMMAND PANEL — StarterGui > CommandPanel (LocalScript)
--
-- Tampilan mengikuti gaya command bar Roblox: kolom "/" di atas + daftar
-- saran dua baris (perintah + argumen di baris atas, deskripsi di bawah).
-- Tema, grip drag, dan slot topbar memakai helper bersama dari UltimateMenu
-- (_G.MenuUI, _G.MenuConfig, _G.TopbarLayout).
--
-- /re, /normal, /rejoin gratis; command lain terkunci sampai punya gamepass.
-- Singleton: instance baru mem-cleanup instance lama.
-- Mobile: keyboard virtual TIDAK dipaksa muncul saat panel dibuka.
-- ═══════════════════════════════════════════════════════════

local Players     = game:GetService("Players")
local TweenSvc    = game:GetService("TweenService")
local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local Lighting    = game:GetService("Lighting")
local RepStorage  = game:GetService("ReplicatedStorage")
local Marketplace = game:GetService("MarketplaceService")
local Stats       = game:GetService("Stats")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ID        = "CommandPanel"

-- ── Singleton ─────────────────────────────────────────────
if type(_G[ID]) == "table" and type(_G[ID].cleanup) == "function" then
	pcall(_G[ID].cleanup)
end

local SELF = {}
_G[ID] = SELF

local _conns = {}
local function track(conn)
	table.insert(_conns, conn)
	return conn
end

local function isAlive()
	return _G[ID] == SELF
end

-- ── Tema (dari UltimateMenu, fallback identik) ─────────────
do
	local waited = 0
	while not _G.MenuConfig and waited < 10 do
		task.wait(0.1)
		waited = waited + 0.1
	end
end

local MenuUI = _G.MenuUI

local T = (_G.MenuConfig and _G.MenuConfig.theme) or {
	BG         = Color3.fromRGB(16, 16, 17),
	CARD       = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	LINE       = Color3.fromRGB(255, 255, 255),
	TEXT       = Color3.fromRGB(238, 238, 240),
	TEXT_DIM   = Color3.fromRGB(148, 148, 154),
	ACCENT     = Color3.fromRGB(212, 175, 55),
	DANGER     = Color3.fromRGB(226, 96, 96),
	SUCCESS    = Color3.fromRGB(96, 196, 132),
}

local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local MONO           = Enum.Font.RobotoMono
local TEXT_ON_ACCENT = Color3.fromRGB(18, 18, 20)

local TF = TweenInfo.new(0.12, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local TS = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ── Konstanta ─────────────────────────────────────────────
local PANEL_TOP_MIN = 54     -- cadangan kalau TopbarLayout belum ada
local SEARCH_H      = 38
local ROW_H         = 42
local PAD           = 9
local BTN_SZ        = 40
local COMMANDS_PASS = require(RepStorage:WaitForChild("ShopConfig")).getGamepassByName("Commands").id
local CommandShared = require(RepStorage:WaitForChild("CommandShared"))
local FILTER_DEBOUNCE = 0.06

local FREE_CMDS = CommandShared.FREE

local IS_CREATOR = game.CreatorType == Enum.CreatorType.User
	and player.UserId == game.CreatorId

local function isMobileDevice()
	return UIS.TouchEnabled and not UIS.KeyboardEnabled and not UIS.MouseEnabled
end

-- ── Helpers ───────────────────────────────────────────────
local function new(class, props)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	return obj
end

local function corner(r, p)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = p })
end

local function stroke(p, transparency, color)
	return new("UIStroke", {
		Color = color or T.LINE, Thickness = 1, Transparency = transparency or 0.92,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p,
	})
end

local function tw(o, i, p)
	if o and o.Parent then TweenSvc:Create(o, i, p):Play() end
end

local bindHover = (MenuUI and MenuUI.bindHover) or function(obj, apply)
	obj.MouseEnter:Connect(function() apply(true) end)
	obj.MouseLeave:Connect(function() apply(false) end)
end

local function getViewport()
	local cam = workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return Vector2.new(1280, 720) end
	return vp
end

-- Y aman: di bawah baris tombol topbar (di portrait ada dua baris: Menu & Info).
local function panelTop()
	if _G.TopbarLayout and _G.TopbarLayout.contentTop then
		local ok, value = pcall(_G.TopbarLayout.contentTop)
		if ok and type(value) == "number" then return value end
	end
	return PANEL_TOP_MIN
end

local function promptCommandsPurchase()
	pcall(Marketplace.PromptGamePassPurchase, Marketplace, player, COMMANDS_PASS)
end

-- ── Daftar command ────────────────────────────────────────
local CMDS = CommandShared.LIST

local CMD_MAP = {}
for _, c in ipairs(CMDS) do CMD_MAP[c.id] = c end

local function cmdIsFree(c)
	return c.s == "client" or FREE_CMDS[c.id] == true
end

-- ── FPS overlay ───────────────────────────────────────────
local fpsGui, fpsConn = nil, nil

local function destroyFps()
	if fpsConn then fpsConn:Disconnect() fpsConn = nil end
	if fpsGui then fpsGui:Destroy() fpsGui = nil end
end

local function toggleFps()
	if fpsGui then destroyFps() return end

	fpsGui = new("ScreenGui", {
		Name = "DT_FPSOverlay", ResetOnSpawn = false, DisplayOrder = 200,
		IgnoreGuiInset = true, Parent = playerGui,
	})

	local lbl = new("TextLabel", {
		Size = UDim2.new(0, 150, 0, 22), Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = T.BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		TextColor3 = T.TEXT, Font = MONO, TextSize = 11, Text = "FPS --   PING --",
		TextXAlignment = Enum.TextXAlignment.Left, Parent = fpsGui,
	})
	corner(6, lbl)
	stroke(lbl, 0.9)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = lbl })

	-- Akumulasi, tanpa tabel sampel per frame; Heartbeat cukup (bukan render).
	local frames, elapsed = 0, 0
	local pingItem = Stats.Network.ServerStatsItem["Data Ping"]

	fpsConn = RunService.Heartbeat:Connect(function(dt)
		frames  = frames + 1
		elapsed = elapsed + dt
		if elapsed < 1 then return end

		local fps = math.floor(frames / elapsed + 0.5)
		frames, elapsed = 0, 0

		local ping = 0
		pcall(function() ping = math.floor(pingItem:GetValue()) end)

		if lbl.Parent then
			lbl.Text       = string.format("FPS %3d   PING %d ms", fps, ping)
			lbl.TextColor3 = fps >= 55 and T.SUCCESS or (fps >= 30 and T.ACCENT or T.DANGER)
		end
	end)
end

-- ── Toast ─────────────────────────────────────────────────
local toastGui = nil

local function toast(msg, isError)
	if toastGui and toastGui.Parent then toastGui:Destroy() end

	toastGui = new("ScreenGui", {
		Name = "DT_Toast", ResetOnSpawn = false, DisplayOrder = 300,
		IgnoreGuiInset = true, Parent = playerGui,
	})

	local lbl = new("TextLabel", {
		Size = UDim2.new(0, 260, 0, 32), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58), BackgroundColor3 = T.CARD,
		BorderSizePixel = 0, TextColor3 = isError and T.DANGER or T.TEXT,
		Font = FONT.REGULAR, TextSize = 11, Text = msg, TextWrapped = true,
		Parent = toastGui,
	})
	corner(10, lbl)
	stroke(lbl, isError and 0.5 or 0.88, isError and T.DANGER or T.LINE)

	local myGui = toastGui
	task.delay(2.5, function()
		if not lbl.Parent then return end
		tw(lbl, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 })
		task.delay(0.35, function()
			if myGui.Parent then myGui:Destroy() end
			if toastGui == myGui then toastGui = nil end
		end)
	end)
end

-- ── Client-side command handlers ──────────────────────────
local CLIENT = {
	fps = toggleFps,

	cam = function(a)
		local n = tonumber(a[1]); if n ~= n then n = nil end -- tolak NaN ("nan" lolos math.clamp)
		n = math.clamp(n or 16, 5, 128)
		player.CameraMaxZoomDistance = n
		player.CameraMinZoomDistance = math.max(n - 5, 0.5)
		toast("Kamera: " .. n .. " studs")
	end,

	fov = function(a)
		local n = tonumber(a[1]); if n ~= n then n = nil end
		n = math.clamp(n or 70, 30, 120)
		local cam = workspace.CurrentCamera
		if cam then cam.FieldOfView = n end
		toast("FOV: " .. n .. "°")
	end,

	time = function()
		local h  = math.floor(Lighting.ClockTime)
		local m  = math.floor((Lighting.ClockTime - h) * 60)
		local hh = h % 12 == 0 and 12 or h % 12
		toast(string.format("Waktu: %02d:%02d %s", hh, m, h >= 12 and "PM" or "AM"))
	end,
}

-- ── State ─────────────────────────────────────────────────
local mainGui, panel, overlay, searchBox, searchStroke, topbarBtn, reclampPanel, isDraggingPanel
local vis, sel      = {}, 0
local _showGen      = 0
local commandsOwned = false
local quickEvent    = nil
local customPos     = false
local refreshLocks  = function() end
local panelW, panelH = 0, 0

-- ── Ukuran responsif ──────────────────────────────────────
local function computeSize()
	local vp  = getViewport()
	local top = panelTop()

	panelW = math.floor(math.clamp(vp.X * 0.30, 260, 360))
	panelW = math.min(panelW, math.floor(vp.X) - 20)
	panelH = math.floor(math.clamp(vp.Y * 0.46, 200, 380))
	panelH = math.min(panelH, math.floor(vp.Y) - top - 20)

	if not panel then return end
	panel.Size = UDim2.new(0, panelW, 0, panelH)
	if customPos then
		if reclampPanel then reclampPanel() end
	else
		panel.Position = UDim2.new(0.5, 0, 0, top)
	end
end

-- ── setAccess ─────────────────────────────────────────────
local function setAccess(hasAccess, isPurchase)
	if commandsOwned == hasAccess then return end
	commandsOwned = hasAccess
	refreshLocks()
	if hasAccess and isPurchase then toast("Akses Commands terbuka") end
end

-- ── Open / close ──────────────────────────────────────────
local function pmOpen()
	_showGen = _showGen + 1
	computeSize()

	overlay.Visible                = true
	overlay.BackgroundTransparency = 1
	tw(overlay, TS, { BackgroundTransparency = 0.45 })

	panel.Visible = true
	if not customPos then
		local top = panelTop()
		panel.Position = UDim2.new(0.5, 0, 0, top - 14)
		tw(panel, TS, { Position = UDim2.new(0.5, 0, 0, top) })
	end

	refreshLocks()

	-- Di HP jangan auto-CaptureFocus: keyboard virtual menutupi layar.
	if not isMobileDevice() then
		local gen = _showGen
		task.defer(function()
			if _showGen == gen and panel.Visible and searchBox then
				searchBox:CaptureFocus()
			end
		end)
	end
end

local function pmClose()
	if not (panel and panel.Visible) then return end
	if searchBox then pcall(searchBox.ReleaseFocus, searchBox) end

	-- Panel ditutup DI TEMPAT ia berada (tidak melompat balik dulu). Flag drag
	-- dilepas supaya pembukaan berikutnya memakai posisi default.
	local wasDragged = customPos
	customPos = false

	tw(overlay, TF, { BackgroundTransparency = 1 })
	if not wasDragged then
		tw(panel, TS, { Position = UDim2.new(0.5, 0, 0, panelTop() - 14) })
	end

	local gen = _showGen
	task.delay(0.22, function()
		if _showGen ~= gen then return end
		if panel.Parent   then panel.Visible   = false end
		if overlay.Parent then overlay.Visible = false end
	end)
end

local function pmToggle()
	if panel and panel.Visible then pmClose() else pmOpen() end
end

-- ── Execute ───────────────────────────────────────────────
local function exec(id, args)
	local c = CMD_MAP[id]
	if not c then return end

	if c.s == "client" then
		local handler = CLIENT[id]
		if handler then pcall(handler, args or {}) end
		return
	end

	if not (FREE_CMDS[id] or commandsOwned) then
		toast("Perlu gamepass Commands untuk perintah ini", true)
		promptCommandsPurchase()
		return
	end

	if quickEvent then quickEvent:FireServer(id, args or {}) end
end

-- ── Build UI ──────────────────────────────────────────────
local function build()
	mainGui = new("ScreenGui", {
		Name = "CmdPanelGui", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
	})

	overlay = new("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		AutoButtonColor = false, Visible = false, ZIndex = 40, Parent = mainGui,
	})
	-- Jangan tutup panel kalau ini ekor dari gerakan drag.
	overlay.Activated:Connect(function()
		if isDraggingPanel and isDraggingPanel() then return end
		pmClose()
	end)

	panel = new("Frame", {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, PANEL_TOP_MIN),
		Size = UDim2.new(0, panelW, 0, panelH), BackgroundColor3 = T.BG,
		BorderSizePixel = 0, Visible = false, ClipsDescendants = false,
		ZIndex = 50, Parent = mainGui,
	})
	corner(14, panel)
	stroke(panel, 0.88)

	-- Grip drag di luar atas panel (gaya sama dengan panel Dance)
	-- Area pegangan dibuat selebar panel (bukan cuma 52px) supaya gampang
	-- di-drag di HP; garis kecilnya hanya penanda visual.
	local gripHit = new("Frame", {
		Name = "Grip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Active = true,
		Parent = panel,
	})
	local gripLine = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 30, 0, 3), BackgroundColor3 = T.ACCENT,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gripHit,
	})
	corner(2, gripLine)

	-- Bisa digeser dari grip MAUPUN dari area kosong panel (baris & textbox
	-- menyerap input sendiri, jadi tidak bentrok).
	if MenuUI and MenuUI.makeDraggable then
		reclampPanel, isDraggingPanel = MenuUI.makeDraggable(panel, { gripHit, panel }, function()
			customPos = true
		end)
	end

	-- Kolom "/" (mengikuti gaya command bar di screenshot)
	local searchRow = new("Frame", {
		Name = "SearchRow", Position = UDim2.new(0, PAD, 0, PAD),
		Size = UDim2.new(1, -2 * PAD, 0, SEARCH_H), BackgroundColor3 = T.CARD,
		BorderSizePixel = 0, Parent = panel,
	})
	corner(10, searchRow)
	searchStroke = stroke(searchRow, 0.9)

	new("TextLabel", {
		Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1, Text = "/", TextColor3 = T.ACCENT,
		Font = MONO, TextSize = 14, Parent = searchRow,
	})

	searchBox = new("TextBox", {
		Position = UDim2.new(0, 26, 0, 0), Size = UDim2.new(1, -66, 1, 0),
		BackgroundTransparency = 1, Text = "", TextColor3 = T.TEXT,
		PlaceholderText = isMobileDevice() and "ketuk untuk mengetik perintah"
			or "cari atau ketik perintah",
		PlaceholderColor3 = T.TEXT_DIM, Font = MONO, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = searchRow,
	})

	new("Frame", {
		Name = "Divider", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -34, 0.5, 0), Size = UDim2.new(0, 1, 0, 18),
		BackgroundColor3 = T.LINE, BackgroundTransparency = 0.88,
		BorderSizePixel = 0, Parent = searchRow,
	})

	local filterBtn = new("TextButton", {
		Name = "Filter", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -9, 0.5, 0), Size = UDim2.new(0, 22, 0, 22),
		BackgroundTransparency = 1, Text = "⌕", TextColor3 = T.ACCENT,
		Font = FONT.REGULAR, TextSize = 16, AutoButtonColor = false, Parent = searchRow,
	})
	bindHover(filterBtn, function(on)
		tw(filterBtn, TF, { TextColor3 = on and T.TEXT or T.ACCENT })
	end)

	-- Daftar saran
	local listY = PAD + SEARCH_H + 6
	local scroll = new("ScrollingFrame", {
		Name = "List", Position = UDim2.new(0, PAD, 0, listY),
		Size = UDim2.new(1, -2 * PAD, 1, -(listY + PAD)),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.TEXT_DIM, ScrollBarImageTransparency = 0.55,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = panel,
	})

	new("UIListLayout", {
		Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll,
	})
	new("UIPadding", { PaddingBottom = UDim.new(0, 6), Parent = scroll })

	-- Banner beli (hanya saat belum punya akses)
	local banner = new("Frame", {
		Name = "Banner", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.CARD,
		BorderSizePixel = 0, LayoutOrder = 0, Visible = false, Parent = scroll,
	})
	corner(10, banner)
	stroke(banner, 0.5, T.ACCENT)

	new("TextLabel", {
		Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 11, 0, 0),
		BackgroundTransparency = 1, TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR,
		TextSize = 10, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Perintah premium terkunci\n/re, /normal, /rejoin tetap gratis",
		Parent = banner,
	})

	local buyBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 64, 0, 26), BackgroundColor3 = T.ACCENT,
		Text = "Beli", TextColor3 = TEXT_ON_ACCENT, Font = FONT.MEDIUM,
		TextSize = 11, BorderSizePixel = 0, AutoButtonColor = false, Parent = banner,
	})
	corner(8, buyBtn)
	bindHover(buyBtn, function(on)
		tw(buyBtn, TF, { BackgroundColor3 = on and T.TEXT or T.ACCENT })
	end)
	buyBtn.Activated:Connect(promptCommandsPurchase)

	-- Baris command: dua baris seperti di screenshot
	local allRows = {}

	for i, cmd in ipairs(CMDS) do
		local free = cmdIsFree(cmd)

		local row = new("TextButton", {
			Name = "Row_" .. cmd.id, Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundColor3 = T.CARD, BorderSizePixel = 0, AutoButtonColor = false,
			Text = "", LayoutOrder = i, ClipsDescendants = true, Parent = scroll,
		})
		corner(10, row)
		local rowStroke = stroke(row, 0.94)

		local bar = new("Frame", {
			Size = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = T.ACCENT,
			BorderSizePixel = 0, Visible = false, Parent = row,
		})
		corner(2, bar)

		local cmdLbl = new("TextLabel", {
			Position = UDim2.new(0, 11, 0, 7), Size = UDim2.new(0, 88, 0, 14),
			BackgroundTransparency = 1, Text = cmd.cmd, TextColor3 = T.ACCENT,
			Font = MONO, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})

		local argsLbl = new("TextLabel", {
			Position = UDim2.new(0, 100, 0, 8), Size = UDim2.new(1, -134, 0, 13),
			BackgroundTransparency = 1, Text = cmd.args, TextColor3 = T.TEXT_DIM,
			Font = MONO, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})

		local descLbl = new("TextLabel", {
			Position = UDim2.new(0, 11, 0, 23), Size = UDim2.new(1, -34, 0, 13),
			BackgroundTransparency = 1, Text = cmd.desc, TextColor3 = T.TEXT_DIM,
			Font = FONT.REGULAR, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})

		local lockLbl
		if not free then
			lockLbl = new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -9, 0, 7),
				Size = UDim2.new(0, 14, 0, 14), BackgroundTransparency = 1,
				Text = "🔒", TextSize = 10, TextColor3 = T.TEXT_DIM,
				Visible = false, Parent = row,
			})
		end

		allRows[i] = {
			row = row, bar = bar, stroke = rowStroke, cmd = cmd, free = free,
			cmdLbl = cmdLbl, argsLbl = argsLbl, descLbl = descLbl, lock = lockLbl,
		}
	end

	local foot = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
		TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 9,
		TextWrapped = true, LayoutOrder = #CMDS + 1, Parent = scroll,
		Text = isMobileDevice()
			and "Ketuk perintah untuk menjalankan · ketuk kolom untuk mengetik"
			or  "Enter jalankan · ↑/↓ navigasi · Tab autocomplete · Esc tutup",
	})
	foot.Name = "Footer"

	-- refreshLocks: satu-satunya sumber tampilan lock
	refreshLocks = function()
		local locked = not commandsOwned
		for _, r in ipairs(allRows) do
			if not r.free then
				local a = locked and 0.45 or 0
				r.cmdLbl.TextTransparency  = a
				r.argsLbl.TextTransparency = a
				r.descLbl.TextTransparency = a
				if r.lock then r.lock.Visible = locked end
			end
		end
		banner.Visible = locked
	end

	-- Seleksi: hanya baris lama & baru yang di-repaint (bukan seluruh daftar)
	local function paintRow(r, selected)
		r.bar.Visible = selected
		tw(r.row, TF, { BackgroundColor3 = selected and T.CARD_HOVER or T.CARD })
		tw(r.stroke, TF, { Transparency = selected and 0.7 or 0.94 })
	end

	local function setSel(idx)
		idx = math.clamp(idx, 0, #vis)
		if idx == sel then return end
		local prev = vis[sel]
		if prev then paintRow(prev, false) end
		sel = idx
		local cur = vis[sel]
		if cur then
			paintRow(cur, true)
			local top = (sel - 1) * (ROW_H + 5)
			if top < scroll.CanvasPosition.Y then
				scroll.CanvasPosition = Vector2.new(0, top)
			elseif top + ROW_H > scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y then
				scroll.CanvasPosition = Vector2.new(0, top + ROW_H - scroll.AbsoluteSize.Y)
			end
		end
	end

	local function filter(raw)
		local word = raw:gsub("^/", ""):lower():split(" ")[1] or ""
		local prev = vis[sel]
		if prev then paintRow(prev, false) end

		vis = {}
		for _, r in ipairs(allRows) do
			local ok = word == ""
				or r.cmd.id:find(word, 1, true) ~= nil
				or r.cmd.desc:lower():find(word, 1, true) ~= nil
			r.row.Visible = ok
			if ok then vis[#vis + 1] = r end
		end

		sel = 0
		if #vis > 0 then setSel(1) end
	end

	local filterThread
	local function queueFilter()
		if filterThread then task.cancel(filterThread) end
		filterThread = task.delay(FILTER_DEBOUNCE, function()
			filterThread = nil
			filter(searchBox.Text)
		end)
	end

	local function parseArgs()
		local parts = searchBox.Text:gsub("^/", ""):split(" ")
		local args  = {}
		for i = 2, #parts do
			if parts[i] ~= "" then args[#args + 1] = parts[i] end
		end
		return args
	end

	local function runSelected(target)
		local t = target or vis[sel] or vis[1]
		if not t then return end
		exec(t.cmd.id, parseArgs())
		searchBox.Text = ""
		pmClose()
	end

	for _, r in ipairs(allRows) do
		local rr = r
		bindHover(rr.row, function(on)
			if vis[sel] == rr then return end
			tw(rr.row, TF, { BackgroundColor3 = on and T.CARD_HOVER or T.CARD })
			tw(rr.stroke, TF, { Transparency = on and 0.85 or 0.94 })
		end)
		rr.row.Activated:Connect(function() runSelected(rr) end)
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(queueFilter)

	searchBox.Focused:Connect(function()
		tw(searchStroke, TF, { Transparency = 0.6, Color = T.ACCENT })
		if sel == 0 and #vis > 0 then setSel(1) end
	end)

	searchBox.FocusLost:Connect(function(enterPressed)
		tw(searchStroke, TF, { Transparency = 0.9, Color = T.LINE })
		if enterPressed then runSelected() end
	end)

	filterBtn.Activated:Connect(function()
		if searchBox.Text ~= "" then
			searchBox.Text = ""
		elseif not isMobileDevice() then
			searchBox:CaptureFocus()
		end
	end)

	track(UIS.InputBegan:Connect(function(inp)
		if not isAlive() or not panel.Visible then return end
		if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end

		if inp.KeyCode == Enum.KeyCode.Down then
			setSel(math.min(sel + 1, #vis))
		elseif inp.KeyCode == Enum.KeyCode.Up then
			setSel(math.max(sel - 1, 1))
		elseif inp.KeyCode == Enum.KeyCode.Tab then
			local ref = vis[sel] or vis[1]
			if ref then
				local fill = ref.cmd.id .. (ref.cmd.args ~= "" and " " or "")
				searchBox.Text           = fill
				searchBox.CursorPosition = #fill + 1
			end
		elseif inp.KeyCode == Enum.KeyCode.Escape then
			pmClose()
		end
	end))

	filter("")
	refreshLocks()
	computeSize()
end

-- ── Cleanup ───────────────────────────────────────────────
function SELF.cleanup()
	for _, c in ipairs(_conns) do pcall(c.Disconnect, c) end
	table.clear(_conns)
	destroyFps()
	if toastGui and toastGui.Parent then toastGui:Destroy() end
	if mainGui and mainGui.Parent then mainGui:Destroy() end
	if topbarBtn and topbarBtn.Parent then topbarBtn:Destroy() end
	if _G.TopbarLayout then _G.TopbarLayout.unregister("command") end
	if _G[ID] == SELF then _G[ID] = nil end
end

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════
local function init()
	local waited = 0
	repeat task.wait(0.1) waited = waited + 0.1 until _G.TopbarGui or waited >= 15
	if not isAlive() then return end
	if not _G.TopbarGui then
		warn("[CommandPanel] TopbarGui tidak ditemukan. Panel dibuat tanpa tombol topbar.")
	end

	quickEvent = RepStorage:WaitForChild("QuickCommandExec", 10)
	if not quickEvent then
		warn("[CommandPanel] QuickCommandExec tidak ditemukan.")
	end
	local accessEvent = RepStorage:WaitForChild("CommandAccessUpdated", 10)
	if not isAlive() then return end

	build()

	-- Responsif (debounced): satu handler, rebind saat kamera berganti.
	local resizeQueued = false
	local function queueResize()
		if resizeQueued or not isAlive() then return end
		resizeQueued = true
		task.delay(0.12, function()
			resizeQueued = false
			if isAlive() then computeSize() end
		end)
	end

	local camConn
	local function bindCamera()
		if camConn then camConn:Disconnect() end
		local cam = workspace.CurrentCamera
		if cam then
			camConn = track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(queueResize))
		end
	end
	bindCamera()
	track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if not isAlive() then return end
		bindCamera()
		queueResize()
	end))

	if IS_CREATOR then setAccess(true, false) end

	if accessEvent then
		track(accessEvent.OnClientEvent:Connect(function(hasAccess, isPurchase)
			if isAlive() then setAccess(hasAccess == true, isPurchase == true) end
		end))
	end

	local shopRemotes = RepStorage:FindFirstChild("ShopRemotes")
	local ownUpdated  = shopRemotes and shopRemotes:FindFirstChild("OwnershipUpdated")
	if ownUpdated then
		track(ownUpdated.OnClientEvent:Connect(function(passName, owned)
			if isAlive() and passName == "Commands" and owned then setAccess(true, true) end
		end))
	end

	track(Marketplace.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
		if not isAlive() then return end
		if plr ~= player or passId ~= COMMANDS_PASS or not purchased then return end
		setAccess(true, true)
	end))

	-- Tombol topbar: posisinya diatur _G.TopbarLayout (landscape = kiri tombol
	-- Menu, portrait = kiri tombol Info), jadi tidak ada offset hardcode.
	if _G.TopbarGui then
		local old = _G.TopbarGui:FindFirstChild("CmdPanelBtn")
		if old then old:Destroy() end

		local btn = new("TextButton", {
			Name = "CmdPanelBtn", Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ),
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -100, 0, 13),
			BackgroundColor3 = T.CARD, BorderSizePixel = 0, Text = "/",
			TextColor3 = T.TEXT, Font = MONO, TextSize = 16,
			AutoButtonColor = false, Parent = _G.TopbarGui,
		})
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = btn })
		local btnStroke = stroke(btn, 0.35, T.ACCENT)
		btnStroke.Thickness = 0.5
		topbarBtn = btn

		bindHover(btn, function(on)
			local active = on or (panel and panel.Visible)
			tw(btn, TF, { BackgroundColor3 = active and T.CARD_HOVER or T.CARD })
			tw(btn, TF, { TextColor3 = active and T.ACCENT or T.TEXT })
			tw(btnStroke, TF, { Transparency = active and 0.1 or 0.35 })
		end)

		btn.MouseButton1Down:Connect(function()
			tw(btn, TF, { Size = UDim2.new(0, BTN_SZ - 3, 0, BTN_SZ - 3) })
		end)
		btn.MouseButton1Up:Connect(function()
			tw(btn, TF, { Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ) })
		end)
		btn.Activated:Connect(pmToggle)

		-- order 20: tombol "/" berada SETELAH tombol tool, jadi saat player
		-- memegang tool, "/" yang bergeser menjauh — sama seperti sebelumnya.
		-- Baris "info": di portrait berbaris kiri dari tombol Info; di landscape
		-- ikut baris tombol Menu. order 20 → setelah tombol tool, jadi saat
		-- player memegang tool, "/" yang bergeser.
		if _G.TopbarLayout then
			_G.TopbarLayout.register("command", btn, 20, "info")
		end
	end
end

task.spawn(init)