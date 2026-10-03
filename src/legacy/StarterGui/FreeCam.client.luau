-- FreecamClient v2 (responsive + DRY)
-- StarterPlayer > StarterPlayerScripts

-- PC  : WASD=gerak | Space=naik | LShift=turun | Q/E=FOV | [/]=speed | Arrow/Mouse=rotasi | H=hide UI | F8=toggle
-- MOB : D-Pad=gerak | ▲▼=naik/turun | +/−=speed | F+/F−=FOV | Swipe=rotasi | Pinch=zoom | ⊘=hide UI | X=close

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local UserInputService     = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService         = game:GetService("TweenService")
local StarterGui           = game:GetService("StarterGui")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))

local LP   = Players.LocalPlayer
local Cam  = workspace.CurrentCamera
local PGui = LP:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════════

local CFG = {
	ToggleKey  = Enum.KeyCode.F8,
	HideUIKey  = Enum.KeyCode.H,
	MoveSpeed  = 40,
	SpeedStep  = 8,
	MinSpeed   = 5,
	MaxSpeed   = 250,
	RotSpeed   = 2.5,
	MouseSens  = 0.004,
	TouchSens  = 0.005,
	Smooth     = 9,
	FOV        = 70,
	MinFOV     = 20,
	MaxFOV     = 120,
	FOVStep    = 3,
	HoldRate   = 6,     -- multiplier repeat saat tombol +/− ditahan
	PinchSens  = 0.12,
}

-- Layout base (di-scale otomatis oleh UIScale sesuai ukuran layar)
local LAYOUT = {
	BaseShortSide = 480,  -- referensi sisi pendek layar
	MinScale      = 0.85,
	MaxScale      = 1.6,
	RcBtn         = 34,   -- tombol kolom kanan
	RcGap         = 6,
	RcMargin      = 10,
	RcSpacer      = 14,   -- jarak ekstra antara grup setting dan ▲▼
	Pad           = 46,   -- tombol d-pad
	PadGap        = 4,
	EdgePad       = 16,
}

local IS_TOUCH    = UserInputService.TouchEnabled
local HAS_KEYBOARD = UserInputService.KeyboardEnabled

-- CoreGui yang di-hide saat freecam aktif.
-- Captures SENGAJA tidak dimatikan → tombol screenshot/record tetap bisa dipakai.
local CORE_GUI_TO_HIDE = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.SelfView,
}

-- ══════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════

local Active   = false
local tPos, tYaw, tPitch = Vector3.zero, 0, 0
local sPos, sYaw, sPitch = Vector3.zero, 0, 0
local origType, origSubject, origFOV
local hiddenGuis, savedCoreGuiStates = {}, {}

local camDrag, camLast = false, Vector2.zero
local camTouch, pinchRef = nil, nil
local pinchD0, pinchF0 = 0, CFG.FOV

-- Semua flag "tombol ditahan" disatukan di sini (DRY: satu tabel, satu reset)
local held = {
	fw = false, bk = false, lt = false, rt = false, -- d-pad
	up = false, dn = false,                          -- naik/turun
	spdP = false, spdM = false,                      -- speed repeat
	fovP = false, fovM = false,                      -- fov repeat
}

local uiHidden = false -- hide tombol/HUD freecam sendiri (mode screenshot bersih)
local UI = {}

-- ══════════════════════════════════════════════════════════
-- THEME + UI HELPERS
-- ══════════════════════════════════════════════════════════

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- Warna dari ReplicatedStorage.Modules.ThemeColor (themeColor): THEME.X / T.X membaca token tema SEKARANG saat
-- dipakai. FreecamCtrl & FreecamHUD di-mark → ikut dilukis ulang saat pemain ganti tema.
local T = ThemeColor.tokens
local THEME = ThemeColor.view({
	Dark   = "BG",
	Panel  = "CARD",
	White  = "TEXT",
	Icon   = "TEXT",
	Muted  = "TEXT_DIM",
	Gold   = "ACCENT",
	Red    = "DANGER",
	Grey   = "TEXT_DIM",
})
local TW = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
end

local function stroke(p, col, thick, trans)
	local s = Instance.new("UIStroke")
	s.Color        = col or T.BORDER
	s.Thickness    = thick or 1.5
	s.Transparency = trans or 0.4
	s.Parent       = p
	return s
end

local function isPress(inp)
	local ut = inp.UserInputType
	return ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1
end

-- Satu factory untuk semua tombol (gaya seragam, hover tween built-in)
local function makeButton(opt)
	local b = Instance.new("TextButton")
	b.Name                   = opt.name or "Btn"
	b.Size                   = opt.size or UDim2.fromOffset(LAYOUT.RcBtn, LAYOUT.RcBtn)
	b.Position               = opt.pos or UDim2.new() -- opsional: tombol dalam UIListLayout tidak butuh pos
	b.AnchorPoint            = opt.anchor or Vector2.zero
	b.BackgroundColor3       = opt.bg or THEME.Panel
	b.BackgroundTransparency = opt.trans or 0.35
	b.BorderSizePixel        = 0
	b.Text                   = opt.text or ""
	b.TextSize               = opt.fs or 13
	b.TextColor3             = opt.fg or THEME.Icon
	b.Font                   = Enum.Font.GothamBold
	b.AutoButtonColor        = false
	b.ZIndex                 = opt.zi or 10
	b.Parent                 = opt.parent
	corner(b, opt.radius or 8)
	if opt.stroke then stroke(b, opt.stroke, opt.strokeThick or 1, opt.strokeTrans or 0.88) end
	if not opt.noHover then
		local base = b.BackgroundTransparency
		b.MouseEnter:Connect(function() TweenService:Create(b, TW, { BackgroundTransparency = 0.05 }):Play() end)
		b.MouseLeave:Connect(function() TweenService:Create(b, TW, { BackgroundTransparency = base }):Play() end)
	end
	return b
end

-- DRY: satu wiring untuk semua tombol tahan (touch + mouse + auto-release)
local function bindHold(btn, flag)
	btn.InputBegan:Connect(function(inp)
		if isPress(inp) then held[flag] = true end
	end)
	btn.InputEnded:Connect(function(inp)
		if isPress(inp) then held[flag] = false end
	end)
	btn.MouseLeave:Connect(function() held[flag] = false end)
end

-- DRY: tombol tap = 1 step, tahan = repeat (dipakai speed & FOV +/-)
local function bindStepHold(btn, flag, stepFn)
	btn.Activated:Connect(stepFn)  -- Activated = klik mouse & tap touch sekaligus
	bindHold(btn, flag)
end

local function setFOV(v)
	CFG.FOV = math.clamp(math.floor(v + 0.5), CFG.MinFOV, CFG.MaxFOV)
	Cam.FieldOfView = CFG.FOV
	if UI.FovLbl then UI.FovLbl.Text = "FOV " .. CFG.FOV end
end

local function setSpeed(v)
	CFG.MoveSpeed = math.clamp(math.floor(v + 0.5), CFG.MinSpeed, CFG.MaxSpeed)
	if UI.SpdLbl then UI.SpdLbl.Text = "SPD " .. CFG.MoveSpeed end
end

-- ══════════════════════════════════════════════════════════
-- HOLD-STATE RESET
-- FIX: UIS.InputEnded tidak fire saat window kehilangan fokus
-- (Alt-Tab / minimize / app switch di HP). Tanpa ini flag bisa
-- stuck true → kamera jalan sendiri.
-- ══════════════════════════════════════════════════════════

local function resetHoldStates()
	camDrag, camTouch, pinchRef = false, nil, nil
	for k in pairs(held) do held[k] = false end
end

UserInputService.WindowFocusReleased:Connect(resetHoldStates)

-- ══════════════════════════════════════════════════════════
-- HIDE / RESTORE GUI GAME LAIN + COREGUI
-- ══════════════════════════════════════════════════════════

local function hideAllUI()
	hiddenGuis, savedCoreGuiStates = {}, {}
	for _, cgType in ipairs(CORE_GUI_TO_HIDE) do
		local ok, wasEnabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, cgType)
		-- Simpan keadaan ASLI (dulu `(ok and wasEnabled) or true` selalu true → keluar freecam menyalakan lagi CoreGui yang
		-- sengaja dimatikan, mis. Backpack bawaan saat inventory HAVN dipakai → hotbar dobel).
		savedCoreGuiStates[cgType] = if ok then wasEnabled else true
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, cgType, false)
	end
	for _, sg in ipairs(PGui:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Name ~= "FreecamCtrl" and sg.Name ~= "FreecamHUD" then
			table.insert(hiddenGuis, { gui = sg, was = sg.Enabled })
			sg.Enabled = false
		end
	end
end

local function restoreAllUI()
	for _, cgType in ipairs(CORE_GUI_TO_HIDE) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, cgType, savedCoreGuiStates[cgType] ~= false)
	end
	savedCoreGuiStates = {}
	for _, entry in ipairs(hiddenGuis) do
		if entry.gui and entry.gui.Parent then
			entry.gui.Enabled = entry.was
		end
	end
	hiddenGuis = {}
end

-- ══════════════════════════════════════════════════════════
-- HIDE / SHOW KONTROL FREECAM SENDIRI (mode screenshot)
-- HideBtn & CamZone tetap hidup supaya bisa di-toggle balik.
-- ══════════════════════════════════════════════════════════

local HIDEABLE = { "CloseBtn", "SpdPlus", "SpdMinus", "FovPlus", "FovMinus", "UpBtn", "DnBtn", "DPadFrame" }

local function applyUIHiddenState()
	local visible = not uiHidden
	for _, key in ipairs(HIDEABLE) do
		if UI[key] then UI[key].Visible = visible end
	end
	if UI.HudSG then UI.HudSG.Enabled = visible end
	if UI.HideBtn then
		UI.HideBtn.Text = uiHidden and "◎" or "⊘"
		UI.HideBtn.BackgroundTransparency = uiHidden and 0.05 or 0.35
	end
end

local function toggleUIHidden()
	if not Active then return end
	uiHidden = not uiHidden
	applyUIHiddenState()
end

-- ══════════════════════════════════════════════════════════
-- RESPONSIVE SCALE
-- Semua ukuran di-layout pakai base px, lalu UIScale menyesuaikan
-- ke ukuran layar. Auto-update saat rotate / resize.
-- ══════════════════════════════════════════════════════════

-- Tinggi total kolom kanan pada base px (8 tombol + gap + spacer ▲▼)
local RC_COLUMN_H = (LAYOUT.RcBtn * 8) + (LAYOUT.RcGap * 7) + LAYOUT.RcSpacer

local function usableSize()
	-- AbsoluteSize ScreenGui = layar dikurangi topbar/notch inset → akurat
	if UI.CtrlSG then return UI.CtrlSG.AbsoluteSize end
	return Cam.ViewportSize
end

local function computeScale()
	local sz    = usableSize()
	local short = math.min(sz.X, sz.Y)
	local s     = math.clamp(short / LAYOUT.BaseShortSide, LAYOUT.MinScale, LAYOUT.MaxScale)

	-- FIX OVERLAP: di layar landscape pendek (mis. iPhone 844x390),
	-- kolom kanan hasil scale bisa lebih tinggi dari layar → tombol
	-- numpuk. Scale WAJIB dibatasi supaya seluruh kolom muat vertikal.
	local maxByHeight = (sz.Y - LAYOUT.EdgePad * 2) / RC_COLUMN_H
	return math.max(math.min(s, maxByHeight), 0.5)
end

local function applyScale()
	local s = computeScale()
	for _, sc in ipairs({ UI.CtrlScale, UI.DPadScale, UI.HudScale }) do
		if sc then sc.Scale = s end
	end
end

-- ══════════════════════════════════════════════════════════
-- BUILD UI
-- ══════════════════════════════════════════════════════════

local function buildUI()
	-- ── ScreenGuis ────────────────────────────────────────
	local ctrlSG = Instance.new("ScreenGui")
	ctrlSG.Name           = "FreecamCtrl"
	ctrlSG.ResetOnSpawn   = false
	ctrlSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ctrlSG.Enabled        = false
	ctrlSG.Parent         = PGui
	UI.CtrlSG = ctrlSG
	ThemeColor.mark(ctrlSG)

	local hudSG = Instance.new("ScreenGui")
	hudSG.Name           = "FreecamHUD"
	hudSG.ResetOnSpawn   = false
	hudSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	hudSG.Enabled        = false
	hudSG.Parent         = PGui
	UI.HudSG = hudSG
	ThemeColor.mark(hudSG)

	-- ── CamZone: full-screen layer untuk drag/pinch (paling bawah) ──
	UI.CamZone = makeButton({
		name = "CamZone", parent = ctrlSG, zi = 1, noHover = true,
		size = UDim2.fromScale(1, 1), pos = UDim2.new(),
		trans = 1, radius = 0,
	})

	-- ── Kolom kanan: SATU list vertikal (UIListLayout) ────
	-- ROOT CAUSE FIX: sebelumnya tombol atas pakai posisi absolut dari
	-- atas layar, sementara ▲▼ di-anchor ke tengah (0.5 scale) frame
	-- full-height yang ikut ke-scale → dua sistem koordinat tabrakan
	-- di layar landscape pendek (390px) dan tombol saling menumpuk.
	-- Sekarang SEMUA tombol ada di satu UIListLayout: layout engine
	-- yang atur jarak, mustahil overlap di resolusi manapun.
	local rcFrame = Instance.new("Frame")
	rcFrame.Name                   = "RightCol"
	rcFrame.AnchorPoint            = Vector2.new(1, 0.5)
	rcFrame.Position               = UDim2.new(1, -LAYOUT.RcMargin, 0.5, 0)
	rcFrame.AutomaticSize          = Enum.AutomaticSize.XY
	rcFrame.Size                   = UDim2.new()
	rcFrame.BackgroundTransparency = 1
	rcFrame.ZIndex                 = 50
	rcFrame.Parent                 = ctrlSG

	local rcList = Instance.new("UIListLayout")
	rcList.FillDirection       = Enum.FillDirection.Vertical
	rcList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rcList.SortOrder           = Enum.SortOrder.LayoutOrder
	rcList.Padding             = UDim.new(0, LAYOUT.RcGap)
	rcList.Parent              = rcFrame

	local ctrlScale = Instance.new("UIScale")
	ctrlScale.Parent = rcFrame
	UI.CtrlScale = ctrlScale

	local BTN = LAYOUT.RcBtn

	local function makeRC(order, opt)
		opt.parent = rcFrame
		opt.size   = UDim2.fromOffset(BTN, BTN)
		opt.zi     = 50
		opt.stroke = T.LINE -- garis tipis (transparansi 0,88) → LINE
		local b = makeButton(opt)
		b.LayoutOrder = order
		return b
	end

	UI.CloseBtn = makeRC(1, { name = "CloseBtn", text = "X",  fs = 14, fg = THEME.Red })
	UI.HideBtn  = makeRC(2, { name = "HideBtn",  text = "⊘",  fs = 14 })
	UI.SpdPlus  = makeRC(3, { name = "SpdPlus",  text = "+",  fg = THEME.Muted })
	UI.SpdMinus = makeRC(4, { name = "SpdMinus", text = "−",  fg = THEME.Muted })
	UI.FovPlus  = makeRC(5, { name = "FovPlus",  text = "F+", fs = 12, fg = THEME.Muted })
	UI.FovMinus = makeRC(6, { name = "FovMinus", text = "F−", fs = 12, fg = THEME.Muted })

	-- Spacer kecil misahin grup setting vs grup gerak ▲▼
	local spacer = Instance.new("Frame")
	spacer.Name                   = "Spacer"
	spacer.LayoutOrder            = 7
	spacer.Size                   = UDim2.fromOffset(BTN, LAYOUT.RcSpacer)
	spacer.BackgroundTransparency = 1
	spacer.Parent                 = rcFrame

	UI.UpBtn = makeRC(8, { name = "UpBtn", text = "▲", fs = 15 })
	UI.DnBtn = makeRC(9, { name = "DnBtn", text = "▼", fs = 15 })

	-- ── D-Pad kiri bawah (di-scale, anchor bawah-kiri) ────
	local PAD   = LAYOUT.Pad
	local PSTEP = PAD + LAYOUT.PadGap
	local PSIZE = PSTEP * 3 - LAYOUT.PadGap

	local dpadFrame = Instance.new("Frame")
	dpadFrame.Name                   = "DPad"
	dpadFrame.AnchorPoint            = Vector2.new(0, 1)
	dpadFrame.Position               = UDim2.new(0, LAYOUT.EdgePad, 1, -LAYOUT.EdgePad)
	dpadFrame.Size                   = UDim2.fromOffset(PSIZE, PSIZE)
	dpadFrame.BackgroundTransparency = 1
	dpadFrame.ZIndex                 = 10
	dpadFrame.Parent                 = ctrlSG
	dpadFrame.Visible                = IS_TOUCH -- d-pad cuma perlu di device touch
	UI.DPadFrame = dpadFrame

	local dpadScale = Instance.new("UIScale")
	dpadScale.Parent = dpadFrame
	-- ikut scale yang sama (satu sumber kebenaran)
	UI.DPadScale = dpadScale

	local center = Instance.new("Frame")
	center.Size                   = UDim2.fromOffset(PAD, PAD)
	center.Position               = UDim2.fromOffset(PSTEP, PSTEP)
	center.BackgroundColor3       = T.CARD
	center.BackgroundTransparency = 0.5
	center.BorderSizePixel        = 0
	center.ZIndex                 = 9
	center.Parent                 = dpadFrame
	corner(center, 6)

	local function makePad(txt, x, y)
		return makeButton({
			parent = dpadFrame, text = txt, fs = 18, zi = 11,
			size = UDim2.fromOffset(PAD, PAD), pos = UDim2.fromOffset(x, y),
			bg = THEME.Dark, trans = 0.25, stroke = THEME.Gold,
			strokeThick = 1.2, strokeTrans = 0.4, noHover = true,
		})
	end

	UI.DPad_U = makePad("↑", PSTEP,     0)
	UI.DPad_D = makePad("↓", PSTEP,     PSTEP * 2)
	UI.DPad_L = makePad("←", 0,         PSTEP)
	UI.DPad_R = makePad("→", PSTEP * 2, PSTEP)

	-- ── HUD (kiri atas + hint) ────────────────────────────
	local hudFrame = Instance.new("Frame")
	hudFrame.Size                   = UDim2.fromScale(1, 1)
	hudFrame.BackgroundTransparency = 1
	hudFrame.ZIndex                 = 30
	hudFrame.Parent                 = hudSG

	local hudScale = Instance.new("UIScale")
	hudScale.Parent = hudFrame
	UI.HudScale = hudScale

	local function makeHUD(pos, text, color)
		local l = Instance.new("TextLabel")
		l.Size                   = UDim2.fromOffset(76, 18)
		l.Position               = pos
		l.BackgroundColor3       = rgb(0, 0, 0)
		l.BackgroundTransparency = 0.4
		l.BorderSizePixel        = 0
		l.Text                   = text
		l.TextColor3             = color
		l.Font                   = Enum.Font.GothamBold
		l.TextSize               = 10
		l.ZIndex                 = 30
		l.Parent                 = hudFrame
		corner(l, 4)
		return l
	end

	UI.SpdLbl = makeHUD(UDim2.fromOffset(8, 8),  "SPD " .. CFG.MoveSpeed, THEME.Gold)
	UI.FovLbl = makeHUD(UDim2.fromOffset(8, 30), "FOV " .. CFG.FOV,       THEME.White)

	-- Hint sesuai device (jangan spam kontrol keyboard ke user HP)
	local hintText = HAS_KEYBOARD
		and "WASD·Space·LShift·Q/E·[/]·Arrow·H=hide UI·F8"
		or  "D-Pad=gerak · ▲▼=naik/turun · Swipe=rotasi · Pinch=zoom"

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint            = Vector2.new(0.5, 0)
	hint.Size                   = UDim2.new(0.8, 0, 0, 20)
	hint.Position               = UDim2.new(0.5, 0, 0, 8)
	hint.BackgroundColor3       = rgb(0, 0, 0)
	hint.BackgroundTransparency = 0.4
	hint.BorderSizePixel        = 0
	hint.Text                   = hintText
	hint.TextColor3             = THEME.Grey
	hint.Font                   = Enum.Font.Gotham
	hint.TextSize               = 9
	hint.TextScaled             = false
	hint.TextTruncate           = Enum.TextTruncate.AtEnd
	hint.ZIndex                 = 30
	hint.Parent                 = hudFrame
	corner(hint, 4)
	UI.HintLbl = hint

	-- Scale awal + auto-update saat rotate / resize / inset berubah.
	-- Pakai AbsoluteSize ScreenGui (bukan ViewportSize) karena sudah
	-- dikurangi topbar/notch inset → hitungan "muat vertikal" akurat.
	applyScale()
	ctrlSG:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
end

-- ══════════════════════════════════════════════════════════
-- KEY SINK
-- ══════════════════════════════════════════════════════════

local function startSink()
	ContextActionService:BindAction("FreecamSink",
		function() return Enum.ContextActionResult.Sink end, false,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.E, Enum.KeyCode.Q,
		Enum.KeyCode.Space, Enum.KeyCode.LeftShift,
		Enum.KeyCode.LeftBracket, Enum.KeyCode.RightBracket
	)
end

local function stopSink()
	ContextActionService:UnbindAction("FreecamSink")
end

local function fireCallback(state)
	if type(_G.OnFreecamStateChanged) == "function" then
		pcall(_G.OnFreecamStateChanged, state)
	end
end

-- ══════════════════════════════════════════════════════════
-- CHARACTER CONTROL LOCK
-- ROOT CAUSE: freecam sebelumnya cuma nge-sink KEYBOARD.
-- Di mobile, gerak karakter datang dari PlayerModule (dynamic
-- thumbstick / touch-to-move) yang baca UserInputService langsung —
-- bukan lewat GUI — jadi swipe kamera ikut menggerakkan karakter.
-- Fix yang benar: matikan ControlModule-nya PlayerModule (cara resmi
-- Roblox), bukan sekadar hide TouchGui. Ini mematikan SEMUA input
-- gerak (thumbstick, keyboard, gamepad) di sumbernya.
-- ══════════════════════════════════════════════════════════

local ctrlModule -- cache: false = gagal require (fallback dipakai)

local function getControls()
	if ctrlModule ~= nil then return ctrlModule end
	local ok, controls = pcall(function()
		local pm = LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		return require(pm):GetControls()
	end)
	ctrlModule = (ok and controls) or false
	return ctrlModule
end

local savedHum -- { hum, walkSpeed, jumpPower, jumpHeight }

local function setCharacterFrozen(frozen)
	local controls = getControls()
	if controls then
		pcall(function()
			if frozen then controls:Disable() else controls:Enable() end
		end)
	end

	-- Hardening layer: nolkan gerak di Humanoid juga, jaga-jaga kalau
	-- game pakai control script custom yang bukan PlayerModule standar.
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if frozen and hum then
		savedHum = { hum = hum, walkSpeed = hum.WalkSpeed, jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight }
		hum:Move(Vector3.zero)
		hum.WalkSpeed  = 0
		hum.JumpPower  = 0
		hum.JumpHeight = 0
	elseif not frozen and savedHum then
		-- restore hanya ke humanoid yang sama (kalau respawn, humanoid
		-- baru sudah punya nilai default sendiri — jangan ditimpa)
		if savedHum.hum and savedHum.hum.Parent then
			savedHum.hum.WalkSpeed  = savedHum.walkSpeed
			savedHum.hum.JumpPower  = savedHum.jumpPower
			savedHum.hum.JumpHeight = savedHum.jumpHeight
		end
		savedHum = nil
	end
end

-- ══════════════════════════════════════════════════════════
-- ENABLE / DISABLE
-- ══════════════════════════════════════════════════════════

local function enable()
	if Active then return end
	-- Kamera 360 (StarterPlayerScripts/360) juga mengendalikan kamera tiap frame → tidak bersamaan.
	if type(_G.Is360Active) == "function" and _G.Is360Active() then return end
	Active = true

	origType, origSubject, origFOV = Cam.CameraType, Cam.CameraSubject, Cam.FieldOfView

	local cf = Cam.CFrame
	tPos, sPos = cf.Position, cf.Position
	local rx, ry = cf:ToEulerAnglesYXZ()
	tYaw, sYaw, tPitch, sPitch = ry, ry, rx, rx

	resetHoldStates()
	Cam.CameraType    = Enum.CameraType.Scriptable
	Cam.CameraSubject = nil
	Cam.FieldOfView   = CFG.FOV

	startSink()
	setCharacterFrozen(true)
	hideAllUI()

	applyScale()
	UI.CtrlSG.Enabled = true
	uiHidden = false
	applyUIHiddenState()

	if UI.HintLbl then
		UI.HintLbl.TextTransparency       = 0
		UI.HintLbl.BackgroundTransparency = 0.4
		task.delay(4, function()
			if not Active then return end
			TweenService:Create(UI.HintLbl, TweenInfo.new(1.5),
				{ TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end)
	end

	fireCallback(true)
end

local function disable()
	if not Active then return end
	Active = false

	stopSink()
	resetHoldStates()
	setCharacterFrozen(false)

	local char = LP.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	Cam.CameraType    = origType or Enum.CameraType.Custom
	Cam.CameraSubject = origSubject or hum or (char and char.PrimaryPart)
	Cam.FieldOfView   = origFOV or 70

	UI.CtrlSG.Enabled = false
	UI.HudSG.Enabled  = false
	uiHidden = false

	restoreAllUI()
	fireCallback(false)
end

local function toggle()
	if Active then disable() else enable() end
end

_G.ToggleFreecam   = toggle
_G.IsFreecamActive = function() return Active end

-- ══════════════════════════════════════════════════════════
-- RENDER LOOP (satu loop untuk gerak + repeat tombol)
-- ══════════════════════════════════════════════════════════

local function keyDown(k) return UserInputService:IsKeyDown(k) end

RunService.RenderStepped:Connect(function(dt)
	if not Active then return end

	if Cam.CameraType ~= Enum.CameraType.Scriptable then
		Cam.CameraType = Enum.CameraType.Scriptable
	end
	if Cam.CameraSubject ~= nil then
		Cam.CameraSubject = nil
	end

	-- Rotasi arrow keys
	local rs = CFG.RotSpeed * dt
	if keyDown(Enum.KeyCode.Left)  then tYaw = tYaw + rs end
	if keyDown(Enum.KeyCode.Right) then tYaw = tYaw - rs end
	if keyDown(Enum.KeyCode.Up)    then tPitch = tPitch + rs end
	if keyDown(Enum.KeyCode.Down)  then tPitch = tPitch - rs end
	tPitch = math.clamp(tPitch, -math.pi / 2 + 0.05, math.pi / 2 - 0.05)

	-- FOV & speed: keyboard + tombol tahan (satu tempat, ga dobel loop)
	local hold = CFG.HoldRate * dt
	if keyDown(Enum.KeyCode.Q)            then setFOV(CFG.FOV + CFG.FOVStep) end
	if keyDown(Enum.KeyCode.E)            then setFOV(CFG.FOV - CFG.FOVStep) end
	if held.fovP then setFOV(CFG.FOV + CFG.FOVStep * hold) end
	if held.fovM then setFOV(CFG.FOV - CFG.FOVStep * hold) end
	if keyDown(Enum.KeyCode.RightBracket) then setSpeed(CFG.MoveSpeed + CFG.SpeedStep * dt * 10) end
	if keyDown(Enum.KeyCode.LeftBracket)  then setSpeed(CFG.MoveSpeed - CFG.SpeedStep * dt * 10) end
	if held.spdP then setSpeed(CFG.MoveSpeed + CFG.SpeedStep * hold) end
	if held.spdM then setSpeed(CFG.MoveSpeed - CFG.SpeedStep * hold) end

	-- Gerak: keyboard + tombol layar digabung
	local fw = (keyDown(Enum.KeyCode.W) and 1 or 0) - (keyDown(Enum.KeyCode.S) and 1 or 0)
		+ (held.fw and 1 or 0) - (held.bk and 1 or 0)
	local rt = (keyDown(Enum.KeyCode.D) and 1 or 0) - (keyDown(Enum.KeyCode.A) and 1 or 0)
		+ (held.rt and 1 or 0) - (held.lt and 1 or 0)
	local up = (keyDown(Enum.KeyCode.Space) and 1 or 0) - (keyDown(Enum.KeyCode.LeftShift) and 1 or 0)
		+ (held.up and 1 or 0) - (held.dn and 1 or 0)

	local ms = CFG.MoveSpeed * dt
	local xz = Vector3.new(rt, 0, -fw)
	if xz.Magnitude > 1 then xz = xz.Unit end

	tPos = tPos
		+ CFrame.Angles(0, tYaw, 0):VectorToWorldSpace(xz) * ms
		+ Vector3.new(0, up * ms, 0)

	local k = math.min(dt * CFG.Smooth, 1)
	sPos   = sPos:Lerp(tPos, k)
	sYaw   = sYaw   + (tYaw   - sYaw)   * k
	sPitch = sPitch + (tPitch - sPitch) * k

	Cam.CFrame = CFrame.new(sPos)
		* CFrame.Angles(0, sYaw, 0)
		* CFrame.Angles(sPitch, 0, 0)
end)

-- ══════════════════════════════════════════════════════════
-- WIRE INPUT
-- ══════════════════════════════════════════════════════════

local function wireInput()
	-- Tombol aksi tunggal (Activated = mouse click + touch tap)
	UI.CloseBtn.Activated:Connect(disable)
	UI.HideBtn.Activated:Connect(toggleUIHidden)

	-- Tap = 1 step, tahan = repeat
	bindStepHold(UI.SpdPlus,  "spdP", function() setSpeed(CFG.MoveSpeed + CFG.SpeedStep) end)
	bindStepHold(UI.SpdMinus, "spdM", function() setSpeed(CFG.MoveSpeed - CFG.SpeedStep) end)
	bindStepHold(UI.FovPlus,  "fovP", function() setFOV(CFG.FOV + CFG.FOVStep) end)
	bindStepHold(UI.FovMinus, "fovM", function() setFOV(CFG.FOV - CFG.FOVStep) end)

	-- Tombol gerak tahan
	bindHold(UI.DPad_U, "fw")
	bindHold(UI.DPad_D, "bk")
	bindHold(UI.DPad_L, "lt")
	bindHold(UI.DPad_R, "rt")
	bindHold(UI.UpBtn,  "up")
	bindHold(UI.DnBtn,  "dn")

	-- ── CamZone: drag mouse / swipe / pinch ───────────────
	UI.CamZone.InputBegan:Connect(function(inp)
		if not Active then return end
		local ut = inp.UserInputType

		if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.MouseButton2 then
			camDrag = true
			camLast = Vector2.new(inp.Position.X, inp.Position.Y)

		elseif ut == Enum.UserInputType.Touch then
			if camTouch and not pinchRef then
				pinchRef = inp
				local p1 = Vector2.new(camTouch.Position.X, camTouch.Position.Y)
				local p2 = Vector2.new(inp.Position.X, inp.Position.Y)
				pinchD0  = (p2 - p1).Magnitude
				pinchF0  = CFG.FOV
			elseif not camTouch then
				camTouch = inp
				camLast  = Vector2.new(inp.Position.X, inp.Position.Y)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(inp)
		if not Active then return end

		-- Pinch zoom
		if pinchRef and (inp == camTouch or inp == pinchRef) then
			if inp.UserInputType ~= Enum.UserInputType.Touch then return end
			local p1 = Vector2.new(camTouch.Position.X, camTouch.Position.Y)
			local p2 = Vector2.new(pinchRef.Position.X, pinchRef.Position.Y)
			setFOV(pinchF0 + (pinchD0 - (p2 - p1).Magnitude) * CFG.PinchSens)
			return
		end

		-- Drag mouse
		if camDrag and inp.UserInputType == Enum.UserInputType.MouseMovement then
			local pos = Vector2.new(inp.Position.X, inp.Position.Y)
			local d   = pos - camLast
			tYaw   = tYaw - d.X * CFG.MouseSens
			tPitch = math.clamp(tPitch - d.Y * CFG.MouseSens, -math.pi / 2 + 0.05, math.pi / 2 - 0.05)
			camLast = pos
			return
		end

		-- Swipe touch
		if inp == camTouch and not pinchRef then
			if inp.UserInputType ~= Enum.UserInputType.Touch then return end
			local pos = Vector2.new(inp.Position.X, inp.Position.Y)
			local d   = pos - camLast
			tYaw   = tYaw - d.X * CFG.TouchSens
			tPitch = math.clamp(tPitch - d.Y * CFG.TouchSens, -math.pi / 2 + 0.05, math.pi / 2 - 0.05)
			camLast = pos
		end
	end)

	UserInputService.InputEnded:Connect(function(inp)
		local ut = inp.UserInputType
		if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.MouseButton2 then
			camDrag = false
		end
		if not Active then return end

		if inp == pinchRef then
			pinchRef = nil
			if camTouch then camLast = Vector2.new(camTouch.Position.X, camTouch.Position.Y) end
			return
		end
		if inp == camTouch then
			camTouch = nil
			if pinchRef then
				camTouch = pinchRef
				pinchRef = nil
				camLast  = Vector2.new(camTouch.Position.X, camTouch.Position.Y)
			end
		end
	end)

	-- Hotkeys
	UserInputService.InputBegan:Connect(function(inp, gp)
		if gp then return end
		if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if inp.KeyCode == CFG.ToggleKey then
			toggle()
		elseif inp.KeyCode == CFG.HideUIKey then
			toggleUIHidden()
		end
	end)

	-- Respawn: matikan freecam & balikin kamera ke karakter baru
	LP.CharacterAdded:Connect(function()
		if Active then disable() end
		task.wait(0.5)
		if not Active and LP.Character then
			local hum = LP.Character:FindFirstChildOfClass("Humanoid")
			Cam.CameraSubject = hum or LP.Character.PrimaryPart
		end
	end)
end

-- ══════════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════════

buildUI()
wireInput()
