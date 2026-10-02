-- DynamicTools — LocalScript → StarterGui
-- Tombol tool muncul di topbar saat tool di-equip; posisinya diatur
-- _G.TopbarLayout (landscape = berbaris kiri dari tombol Menu, portrait =
-- berbaris kiri dari tombol Info), jadi tidak ada offset hardcode dan tidak
-- ada tombol yang saling menimpa.
-- Panel Tool Settings bisa di-drag lewat grip, sama seperti panel Dance.

local Players  = game:GetService("Players")
local TweenSvc = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ID        = "DynamicTools"

if _G[ID] then
	if _G.TopbarGui then
		local old = _G.TopbarGui:FindFirstChild("ToolsBtn")
		if old then old:Destroy() end
	end
	if _G.TopbarLayout then _G.TopbarLayout.unregister("tools") end
	local oldGui = playerGui:FindFirstChild("DynamicToolsGui")
	if oldGui then oldGui:Destroy() end
end
_G[ID] = true

-- ── Tema: ThemeColor.tokens (themeColor) — T.X dibaca saat melukis ─────────────
do
	local waited = 0
	while not _G.MenuConfig and waited < 10 do
		task.wait(0.1)
		waited = waited + 0.1
	end
end

local MenuUI = _G.MenuUI

local T = ThemeColor.tokens

local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local TF = TweenInfo.new(0.12, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local TS = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local P_TOP_MIN = 54     -- cadangan kalau TopbarLayout belum ada
local BTN_SZ  = 40
local PAD     = 9
local HEADER_H = 30

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

-- Y aman: di bawah baris tombol topbar.
local function panelTop()
	if _G.TopbarLayout and _G.TopbarLayout.contentTop then
		local ok, value = pcall(_G.TopbarLayout.contentTop)
		if ok and type(value) == "number" then return value end
	end
	return P_TOP_MIN
end

local function getViewport()
	local cam = workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return Vector2.new(1280, 720) end
	return vp
end

-- ── State ─────────────────────────────────────────────────
local S = {
	registry  = {},
	curTool   = nil,
	curUI     = nil,
	toolConn  = nil,
	charConn  = nil,
	panelGui  = nil,
	panel     = nil,
	overlay   = nil,
	scroll    = nil,
	titleLbl  = nil,
	btn       = nil,
	btnStroke = nil,
	btnText   = nil,
	btnImage  = nil,
}

local panelW, panelH     = 0, 0
local customPos          = false
local reclampPanel       = nil
local isDraggingPanel    = nil
local _panelGen       = 0
local _btnGen         = 0

-- Posisi bawaan = TEPAT DI BAWAH tombol Tool di topbar (permintaan user 2 Okt 17:21, screenshot): tengah panel = tengah
-- tombol (diklem EDGE px dari tepi layar); grip pegangan (18 px di atas panel) mulai tepat di bawah baris topbar → tidak
-- menutup tombol mana pun (portrait 2 baris ikut). Tombol belum ada → tengah atas. Digeser → dibuka lagi = kembali ke
-- bawah tombol (customPos dilepas saat tutup). dy = geser animasi buka/tutup.
local EDGE = 8
local function btnRect()
	local btn, gui = S.btn, S.panelGui
	if not (btn and gui and btn.Visible and btn.AbsoluteSize.X > 0) then return nil end
	return btn.AbsolutePosition - gui.AbsolutePosition, btn.AbsoluteSize -- ruang ScreenGui panel (inset apa pun)
end

local function anchorTop()
	local rowsBottom = panelTop() - 10 -- TopbarLayout.contentTop = bawah semua baris topbar + 10
	local pos, size = btnRect()
	if pos then rowsBottom = math.max(rowsBottom, pos.Y + size.Y) end
	return math.floor(rowsBottom + 20)
end

local function defaultPos(dy)
	local vp = getViewport()
	local x = (vp.X - panelW) / 2
	local pos, size = btnRect()
	if pos then x = pos.X + size.X / 2 - panelW / 2 end
	x = math.clamp(x, EDGE, math.max(EDGE, vp.X - panelW - EDGE))
	return UDim2.fromOffset(math.floor(x), anchorTop() + (dy or 0))
end

local function computeSize()
	local vp  = getViewport()
	local top = anchorTop()

	panelW = math.floor(math.clamp(vp.X * 0.26, 250, 330))
	panelW = math.min(panelW, math.floor(vp.X) - 20)
	panelH = math.floor(math.clamp(vp.Y * 0.52, 220, 420))
	panelH = math.min(panelH, math.floor(vp.Y) - top - 20)

	if not S.panel then return end
	S.panel.Size = UDim2.new(0, panelW, 0, panelH)
	if customPos then
		if reclampPanel then reclampPanel() end
	else
		S.panel.Position = defaultPos()
	end
end

-- ── Panel open / close ────────────────────────────────────
local function pmOpen()
	if not S.panel then return end
	_panelGen = _panelGen + 1
	computeSize()

	S.overlay.Visible                = true
	S.overlay.BackgroundTransparency = 1
	tw(S.overlay, TS, { BackgroundTransparency = 0.45 })

	S.panel.Visible = true
	if not customPos then
		S.panel.Position = defaultPos(-8)
		tw(S.panel, TS, { Position = defaultPos() })
	end
end

local function pmClose()
	if not (S.panel and S.panel.Visible) then return end

	-- Panel ditutup DI TEMPAT ia berada (tidak melompat balik dulu). Flag drag
	-- dilepas supaya pembukaan berikutnya memakai posisi default.
	local wasDragged = customPos
	customPos = false

	tw(S.overlay, TF, { BackgroundTransparency = 1 })
	if not wasDragged then
		tw(S.panel, TS, { Position = defaultPos(-8) })
	end

	local gen = _panelGen
	task.delay(0.24, function()
		if _panelGen ~= gen then return end
		if S.panel   then S.panel.Visible   = false end
		if S.overlay then S.overlay.Visible = false end
	end)
end

local function pmToggle()
	if S.panel and S.panel.Visible then pmClose() else pmOpen() end
end

-- ── Visibilitas tombol tool ───────────────────────────────
-- Posisi tidak diatur di sini; cukup ubah Visible lalu minta TopbarLayout
-- menyusun ulang barisan tombol.
local function refreshSlots()
	if _G.TopbarLayout then _G.TopbarLayout.refresh() end
end

local function showBtn(on)
	if not S.btn then return end
	_btnGen = _btnGen + 1

	if on then
		S.btn.Visible = true
		tw(S.btn, TF, { BackgroundTransparency = 0 })
		refreshSlots()
		return
	end

	local gen = _btnGen
	pmClose()
	tw(S.btn, TF, { BackgroundTransparency = 1 })
	task.delay(0.15, function()
		if _btnGen ~= gen then return end
		if S.btn then
			S.btn.Visible = false
			refreshSlots()
		end
	end)
end

-- ── Tool lifecycle ────────────────────────────────────────
local function clearToolConn()
	if S.toolConn then S.toolConn:Disconnect() S.toolConn = nil end
end

local function clearToolUI()
	if S.curUI then pcall(S.curUI.Destroy, S.curUI) S.curUI = nil end
end

local function resetToNoTool()
	clearToolConn()
	clearToolUI()
	S.curTool = nil
	showBtn(false)
end

local function injectTool(tool)
	if not (tool and tool:IsA("Tool") and tool.Parent == player.Character) then return end
	if S.curTool == tool then return end

	local cfg = S.registry[tool.Name]
	if not cfg then
		if S.curTool then resetToNoTool() end
		return
	end

	-- KRITIS: lepas koneksi tool lama SEBELUM state baru di-set, supaya
	-- AncestryChanged tool lama tidak menghapus UI tool baru.
	clearToolConn()
	clearToolUI()

	local ok, frame = pcall(cfg.build)
	if not ok or not frame or not frame:IsA("Frame") then
		warn("[DynamicTools] Build gagal:", tool.Name, frame)
		return
	end

	S.curTool    = tool
	S.curUI      = frame
	frame.Parent = S.scroll

	local meta = cfg.meta or {}
	if meta.iconImage and meta.iconImage ~= "" then
		S.btnImage.Image   = meta.iconImage
		S.btnImage.Visible = true
		S.btnText.Visible  = false
	else
		S.btnText.Text     = (meta.iconText or tool.Name:sub(1, 1)):upper()
		S.btnText.Visible  = true
		S.btnImage.Visible = false
	end

	if S.titleLbl then S.titleLbl.Text = meta.title or "Tool Settings" end
	showBtn(true)

	S.toolConn = tool.AncestryChanged:Connect(function()
		if player.Character and tool:IsDescendantOf(player.Character) then return end
		if S.curTool == tool then resetToNoTool() end
	end)
end

local function hookChar(char)
	if S.charConn then S.charConn:Disconnect() S.charConn = nil end
	resetToNoTool()

	S.charConn = char.ChildAdded:Connect(function(obj)
		if not obj:IsA("Tool") then return end
		task.defer(function() injectTool(obj) end)
	end)

	task.defer(function()
		if not char.Parent then return end
		for _, obj in ipairs(char:GetChildren()) do
			if obj:IsA("Tool") then
				injectTool(obj)
				return
			end
		end
	end)
end

-- ── Build panel ───────────────────────────────────────────
local function buildPanel()
	S.panelGui = new("ScreenGui", {
		Name = "DynamicToolsGui", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
	})
	ThemeColor.mark(S.panelGui)

	S.overlay = new("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		AutoButtonColor = false, Visible = false, ZIndex = 40, Parent = S.panelGui,
	})
	-- Jangan tutup panel kalau ini ekor dari gerakan drag.
	S.overlay.Activated:Connect(function()
		if isDraggingPanel and isDraggingPanel() then return end
		pmClose()
	end)

	S.panel = new("Frame", {
		Name = "Panel", Size = UDim2.new(0, panelW, 0, panelH),
		Position = UDim2.new(1, 50, 0, P_TOP_MIN), BackgroundColor3 = T.BG,
		BorderSizePixel = 0, Visible = false, ClipsDescendants = false,
		ZIndex = 50, Parent = S.panelGui,
	})
	corner(14, S.panel)
	ThemeColor.glow(stroke(S.panel, 0.88), "panel") -- garis tepi bergerak (themeColor)

	-- Grip drag di luar atas panel (sama seperti panel Dance)
	local gripHit = new("Frame", {
		Name = "Grip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Active = true,
		Parent = S.panel,
	})
	local gripLine = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 30, 0, 3), BackgroundColor3 = T.ACCENT,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gripHit,
	})
	corner(2, gripLine)

	if MenuUI and MenuUI.makeDraggable then
		reclampPanel, isDraggingPanel = MenuUI.makeDraggable(S.panel, { gripHit, S.panel }, function()
			customPos = true
		end)
	end

	S.titleLbl = new("TextLabel", {
		Name = "Title", Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -46, 0, 15),
		BackgroundTransparency = 1, Text = "Tool Settings", TextColor3 = T.ACCENT,
		Font = FONT.BOLD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = S.panel,
	})

	local closeBtn = new("TextButton", {
		Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 7),
		Size = UDim2.new(0, 20, 0, 20), BackgroundTransparency = 1, Text = "X",
		TextColor3 = T.TEXT_DIM, Font = FONT.BOLD, TextSize = 12,
		AutoButtonColor = false, ZIndex = 55, Parent = S.panel,
	})
	bindHover(closeBtn, function(on)
		tw(closeBtn, TF, { TextColor3 = on and T.TEXT or T.TEXT_DIM })
	end)
	closeBtn.Activated:Connect(function()
		if isDraggingPanel and isDraggingPanel() then return end
		pmClose()
	end)

	S.scroll = new("ScrollingFrame", {
		Name = "Scroll", Position = UDim2.new(0, PAD, 0, HEADER_H),
		Size = UDim2.new(1, -2 * PAD, 1, -(HEADER_H + PAD)),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.TEXT_DIM, ScrollBarImageTransparency = 0.55,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = S.panel,
	})
	new("UIPadding", { PaddingBottom = UDim.new(0, 8), Parent = S.scroll })
end

-- ── Build tombol topbar ───────────────────────────────────
local function buildBtn(parent)
	S.btn = new("TextButton", {
		Name = "ToolsBtn", Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 13),
		BackgroundColor3 = T.CARD, BackgroundTransparency = 1, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, Visible = false, Parent = parent,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = S.btn })

	S.btnStroke = stroke(S.btn, 0.35, T.ACCENT)
	S.btnStroke.Thickness = 0.5

	S.btnText = new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "?",
		TextColor3 = T.TEXT, Font = FONT.MEDIUM, TextSize = 15, Parent = S.btn,
	})

	S.btnImage = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, ImageColor3 = T.TEXT, Visible = false, Parent = S.btn,
	})

	bindHover(S.btn, function(on)
		local active = on or (S.panel and S.panel.Visible)
		tw(S.btn, TF, { BackgroundColor3 = active and T.CARD_HOVER or T.CARD })
		tw(S.btnStroke, TF, { Transparency = active and 0.1 or 0.35 })
		tw(S.btnText, TF, { TextColor3 = active and T.ACCENT or T.TEXT })
		tw(S.btnImage, TF, { ImageColor3 = active and T.ACCENT or T.TEXT })
	end)

	S.btn.MouseButton1Down:Connect(function()
		tw(S.btn, TF, { Size = UDim2.new(0, BTN_SZ - 3, 0, BTN_SZ - 3) })
	end)
	S.btn.MouseButton1Up:Connect(function()
		tw(S.btn, TF, { Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ) })
	end)
	S.btn.Activated:Connect(pmToggle)
	-- Barisan topbar disusun ulang (tombol lain muncul/hilang) → panel yang terbuka tetap di bawah tombolnya.
	S.btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if S.panel and S.panel.Visible and not customPos then S.panel.Position = defaultPos() end
	end)

	-- order 10: tombol tool mengambil slot terdekat (persis seperti flow lama
	-- di X=-153), sehingga tombol "/" yang tergeser ke kiri.
	-- Baris "info" (portrait: kiri tombol Info), order 10 → slot terdekat,
	-- sehingga tombol "/" yang tergeser saat tool aktif. Sama seperti flow lama.
	if _G.TopbarLayout then
		_G.TopbarLayout.register("tools", S.btn, 10, "info")
	end
end

-- ── Public API ────────────────────────────────────────────
local function reinjectCurrent()
	if not S.curTool then return false end
	local tool = S.curTool
	S.curTool  = nil
	task.defer(function() injectTool(tool) end)
	return true
end

_G.DynamicToolManager = {
	register = function(name, fn, meta)
		if type(name) ~= "string" or name == "" or type(fn) ~= "function" then return false end
		S.registry[name] = { build = fn, meta = meta or {} }
		if S.curTool and S.curTool.Name == name then reinjectCurrent() end
		return true
	end,
	getCurrent = function() return S.curTool end,
	refresh    = reinjectCurrent,
}
_G.RegisterDynamicTool = _G.DynamicToolManager.register
_G.GetCurrentTool      = _G.DynamicToolManager.getCurrent
_G.RefreshToolUI       = _G.DynamicToolManager.refresh

-- ── Init ──────────────────────────────────────────────────
local camConn

local function init()
	local waited = 0
	while not _G.TopbarGui and waited < 15 do
		task.wait(0.1)
		waited = waited + 0.1
	end
	if not _G.TopbarGui then
		warn("[DynamicTools] TopbarGui tidak ditemukan")
		return
	end

	computeSize()
	buildPanel()
	buildBtn(_G.TopbarGui)

	local resizeQueued = false
	local function queueResize()
		if resizeQueued then return end
		resizeQueued = true
		task.delay(0.12, function()
			resizeQueued = false
			computeSize()
			refreshSlots()
		end)
	end

	local function bindCamera()
		if camConn then camConn:Disconnect() end
		local cam = workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(queueResize)
		end
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		queueResize()
	end)

	if player.Character then hookChar(player.Character) end
	player.CharacterAdded:Connect(hookChar)
end

Players.PlayerRemoving:Connect(function(p)
	if p ~= player then return end
	if S.charConn then S.charConn:Disconnect() end
	if S.toolConn then S.toolConn:Disconnect() end
	if camConn then camConn:Disconnect() end
	clearToolUI()
	if _G.TopbarLayout then _G.TopbarLayout.unregister("tools") end
	pcall(function() if S.btn then S.btn:Destroy() end end)
	pcall(function() if S.panelGui then S.panelGui:Destroy() end end)
	_G.DynamicToolManager, _G.RegisterDynamicTool = nil, nil
	_G.GetCurrentTool, _G.RefreshToolUI, _G[ID] = nil, nil, nil
end)

task.spawn(init)