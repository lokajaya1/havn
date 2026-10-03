-- GraphicsClient
-- StarterPlayer > StarterPlayerScripts

local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local Lighting     = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))
-- "Sembunyikan Efek Pemain" & "Sembunyikan Player Lain" lewat satu sumber dengan "Hide avatar" kartu pemain
-- (ruangan SETTINGS, claude/Rencana_Settings.md): ikut respawn & bagian baru tanpa jeda, efek server tetap benar.
local HideAvatarManager = require(ReplicatedStorage:WaitForChild("CustomUIModules"):WaitForChild("HideAvatarManager"))

local function waitDeps()
	local start = os.clock()
	while not (_G.MenuUI and _G.MenuConfig) do
		if os.clock() - start > 30 then warn("[Graphics] Timeout"); return false end
		task.wait(0.05)
	end
	return true
end
if not waitDeps() then return end

local UI = _G.MenuUI
-- Warna: ThemeColor (themeColor). C = nama lama (ThemeColor.legacy), T = token; tabel bersama → baca saat melukis.
local C  = ThemeColor.legacy
local T  = ThemeColor.tokens
local TW = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function tw(o, p)
	if o and o.Parent then TweenService:Create(o, TW, p):Play() end
end

local DEF = {
	GlobalShadows  = Lighting.GlobalShadows,
	Brightness     = Lighting.Brightness,
	Ambient        = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
}
local defAtm  = Lighting:FindFirstChildOfClass("Atmosphere")
local DEF_ATM = defAtm and { Density = defAtm.Density, Haze = defAtm.Haze, Glare = defAtm.Glare }

local _resetList = {}

-- ── Post-FX cache ─────────────────────────────────────────

local Camera  = workspace.CurrentCamera
local FxCache = {}

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local c = workspace.CurrentCamera
	if c and c ~= Camera then
		Camera = c
		for _, e in pairs(FxCache) do
			if e and e.Parent then e.Parent = Camera end
		end
	end
end)

local function getFx(cls, name)
	local key = cls .. ":" .. name
	if FxCache[key] and FxCache[key].Parent then return FxCache[key] end
	for _, v in Camera:GetChildren() do
		if v:IsA(cls) and v.Name == name then FxCache[key] = v; return v end
	end
	local e = Instance.new(cls)
	e.Name    = name
	e.Enabled = false
	e.Parent  = Camera
	FxCache[key] = e
	return e
end

-- ── Slider drag ───────────────────────────────────────────
-- Satu SDRAG table: hanya satu slider drag aktif sekaligus → tidak ada per-slider UIS connection.
-- FIX: WindowFocusReleased reset SDRAG agar tidak stuck saat window kehilangan fokus
--      (UIS.InputEnded tidak fire saat window minimize/Alt-Tab).

local SDRAG = { active = false, track = nil, cb = nil }

local function resetSDRAG()
	SDRAG.active = false
	SDRAG.track  = nil
	SDRAG.cb     = nil
end

UIS.InputChanged:Connect(function(i)
	if not SDRAG.active or not SDRAG.track then return end
	if i.UserInputType ~= Enum.UserInputType.MouseMovement
		and i.UserInputType ~= Enum.UserInputType.Touch then return end
	local t = SDRAG.track
	SDRAG.cb(math.clamp((i.Position.X - t.AbsolutePosition.X) / t.AbsoluteSize.X, 0, 1))
end)

UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then
		resetSDRAG()
	end
end)

UIS.WindowFocusReleased:Connect(resetSDRAG)

-- ════════════════════════════════════════════════════════════
-- WIDGET FACTORIES
-- Root row pakai Frame bukan TextButton — TextButton sebagai parent
-- memblokir klik pada children-nya di Roblox engine.
-- ════════════════════════════════════════════════════════════

local function SepLabel(parent, lo, text)
	local f = UI.frame({
		Size             = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder      = lo,
		Parent           = parent,
	})
	UI.text({
		Size           = UDim2.new(1, -8, 1, 0),
		Position       = UDim2.new(0, 4, 0, 0),
		Text           = text,
		TextColor3     = C.accent,
		Font           = Enum.Font.GothamBold,
		TextSize       = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent         = f,
	})
	UI.frame({
		Size             = UDim2.new(1, -8, 0, 1),
		Position         = UDim2.new(0, 4, 1, -1),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.7,
		Parent           = f,
	})
end

local function ToggleRow(parent, lo, label, initState, onToggle)
	local row = Instance.new("Frame")
	row.Size                   = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.BorderSizePixel        = 0
	row.LayoutOrder            = lo
	row.Parent                 = parent

	UI.frame({
		Size             = UDim2.new(1, -8, 0, 1),
		Position         = UDim2.new(0, 4, 1, -1),
		BackgroundColor3 = C.border,
		BackgroundTransparency = 0.5,
		Parent           = row,
	})
	UI.text({
		Size           = UDim2.new(1, -60, 1, 0),
		Position       = UDim2.new(0, 6, 0, 0),
		Text           = label,
		TextColor3     = C.white,
		Font           = Enum.Font.Gotham,
		TextSize       = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent         = row,
	})

	local W, H = 40, 22
	-- Gaya themeColor: hidup = jalur ACCENT + kenop TEXT_STRONG, mati = jalur TRACK + kenop TEXT.
	local pill = UI.button({
		Size             = UDim2.new(0, W, 0, H),
		Position         = UDim2.new(1, -(W + 6), 0.5, -H / 2),
		BackgroundColor3 = initState and T.ACCENT or T.TRACK,
		Text             = "",
		AutoButtonColor  = false,
		Parent           = row,
	})
	UI.corner(H / 2).Parent = pill

	local thumb = UI.frame({
		Size             = UDim2.new(0, H - 6, 0, H - 6),
		Position         = UDim2.new(0, initState and (W - H + 4) or 4, 0.5, -(H - 6) / 2),
		BackgroundColor3 = initState and T.TEXT_STRONG or T.TEXT,
		Parent           = pill,
	})
	UI.corner((H - 6) / 2).Parent = thumb
	UI.stroke(T.BG, 1, 0.7).Parent = thumb

	local on = initState
	local function set(v)
		on = v
		tw(pill,  { BackgroundColor3 = v and T.ACCENT or T.TRACK })
		tw(thumb, {
			Position         = UDim2.new(0, v and (W - H + 4) or 4, 0.5, -(H - 6) / 2),
			BackgroundColor3 = v and T.TEXT_STRONG or T.TEXT,
		})
	end

	pill.MouseButton1Click:Connect(function()
		set(not on)
		if onToggle then onToggle(on) end
	end)

	return row, set, function() return on end
end

local function SliderRow(parent, lo, label, minV, maxV, defV, fmt, onChange)
	local row = Instance.new("Frame")
	row.Size                   = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.BorderSizePixel        = 0
	row.LayoutOrder            = lo
	row.Parent                 = parent

	UI.frame({
		Size             = UDim2.new(1, -8, 0, 1),
		Position         = UDim2.new(0, 4, 1, -1),
		BackgroundColor3 = C.border,
		BackgroundTransparency = 0.5,
		Parent           = row,
	})
	UI.text({
		Size           = UDim2.new(0, 108, 1, 0),
		Position       = UDim2.new(0, 6, 0, 0),
		Text           = label,
		TextColor3     = C.white,
		Font           = Enum.Font.Gotham,
		TextSize       = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent         = row,
	})

	local valLbl = UI.text({
		Size           = UDim2.new(0, 34, 1, 0),
		Position       = UDim2.new(1, -38, 0, 0),
		Text           = "",
		TextColor3     = C.accent,
		Font           = Enum.Font.GothamBold,
		TextSize       = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent         = row,
	})

	-- Gaya themeColor: isi ACCENT, jalur kosong TRACK, kenop TEXT_STRONG.
	local trackBg = UI.button({
		Size             = UDim2.new(1, -150, 0, 6),
		Position         = UDim2.new(0, 116, 0.5, -3),
		BackgroundColor3 = T.TRACK,
		Text             = "",
		AutoButtonColor  = false,
		Parent           = row,
	})
	UI.corner(3).Parent = trackBg

	local fill = UI.frame({
		Size             = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = C.accent,
		Parent           = trackBg,
	})
	UI.corner(3).Parent = fill

	local sthumb = UI.frame({
		Size             = UDim2.new(0, 14, 0, 14),
		Position         = UDim2.new(1, -7, 0.5, -7),
		BackgroundColor3 = T.TEXT_STRONG,
		Parent           = fill,
	})
	UI.corner(7).Parent  = sthumb
	UI.stroke(C.accent, 2).Parent = sthumb

	local function fmtV(v)
		if fmt == "int" then return tostring(math.floor(v + 0.5))
		elseif fmt == "f2" then return string.format("%.2f", v)
		else return string.format("%.1f", v) end
	end

	local function setPct(p)
		p = math.clamp(p, 0, 1)
		fill.Size   = UDim2.new(p, 0, 1, 0)
		valLbl.Text = fmtV(minV + p * (maxV - minV))
		if onChange then onChange(minV + p * (maxV - minV)) end
	end

	setPct(math.clamp((defV - minV) / (maxV - minV), 0, 1))

	trackBg.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1
			and i.UserInputType ~= Enum.UserInputType.Touch then return end
		setPct(math.clamp((i.Position.X - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X, 0, 1))
		SDRAG.active = true
		SDRAG.track  = trackBg
		SDRAG.cb     = setPct
	end)

	return row, function(v) setPct(math.clamp((v - minV) / (maxV - minV), 0, 1)) end
end

-- ════════════════════════════════════════════════════════════
-- BUILD CONTAINER
-- FIX BUG CANVAS: Ganti AutomaticSize.Y dengan explicit size dari
-- layout.AbsoluteContentSize. AutomaticSize.Y tidak update saat frame
-- hidden (Roblox bug resmi) → CanvasSize SettingsClient = 0 →
-- tombol di bawah canvas tidak bisa diklik.
-- Explicit size lewat AbsoluteContentSize update meskipun hidden
-- karena children punya fixed height.
-- ════════════════════════════════════════════════════════════

local container = Instance.new("Frame")
container.Name                   = "GraphicsPanel"
container.Size                   = UDim2.new(1, 0, 0, 0)
container.BackgroundTransparency = 1
container.BorderSizePixel        = 0

local layout = UI.list({ padding = 0 })
layout.Parent = container

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	container.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y)
end)

local lo = 0
local function L() lo += 1; return lo end

-- ════════════════════════════════════════════════════════════
-- PENCAHAYAAN
-- ════════════════════════════════════════════════════════════

SepLabel(container, L(), "PENCAHAYAAN")

local _, shadowSet = ToggleRow(container, L(), "Bayangan Global", Lighting.GlobalShadows, function(v)
	Lighting.GlobalShadows = v
end)
table.insert(_resetList, function()
	shadowSet(DEF.GlobalShadows)
	Lighting.GlobalShadows = DEF.GlobalShadows
end)

local _, brightnessSet = SliderRow(container, L(), "Kecerahan", 0, 5, Lighting.Brightness, "f1",
	function(v) Lighting.Brightness = v end)
table.insert(_resetList, function() brightnessSet(DEF.Brightness) end)

do
	local av = (Lighting.Ambient.R + Lighting.Ambient.G + Lighting.Ambient.B) / 3
	local _, ambientSet = SliderRow(container, L(), "Cahaya Ambient", 0, 1, av, "f2", function(v)
		Lighting.Ambient        = Color3.new(v, v, v)
		Lighting.OutdoorAmbient = Color3.new(math.min(v * 1.3, 1), math.min(v * 1.3, 1), math.min(v * 1.3, 1))
	end)
	table.insert(_resetList, function()
		ambientSet(av)
		Lighting.Ambient        = DEF.Ambient
		Lighting.OutdoorAmbient = DEF.OutdoorAmbient
	end)
end

-- ════════════════════════════════════════════════════════════
-- POST-PROCESSING
-- ════════════════════════════════════════════════════════════

SepLabel(container, L(), "POST-PROCESSING")

local _, bloomSet = ToggleRow(container, L(), "Bloom  (Cahaya Menyebar)", false, function(v)
	local e = getFx("BloomEffect", "GFX_Bloom")
	e.Intensity = 0.9; e.Threshold = 0.95; e.Size = 24; e.Enabled = v
end)
local _, sunSet = ToggleRow(container, L(), "Sun Rays  (Sinar Matahari)", false, function(v)
	local e = getFx("SunRaysEffect", "GFX_Sun")
	e.Intensity = 0.25; e.Spread = 0.5; e.Enabled = v
end)
local _, dofSet = ToggleRow(container, L(), "Depth of Field  (Blur Jauh)", false, function(v)
	local e = getFx("DepthOfFieldEffect", "GFX_DOF")
	e.FocusDistance = 55; e.InFocusRadius = 35; e.FarIntensity = 0.4; e.NearIntensity = 0.05; e.Enabled = v
end)
local _, blurSet = ToggleRow(container, L(), "Gaussian Blur  (Kabur)", false, function(v)
	local e = getFx("BlurEffect", "GFX_Blur")
	e.Size = 8; e.Enabled = v
end)

table.insert(_resetList, function()
	bloomSet(false); sunSet(false); dofSet(false); blurSet(false)
	for _, e in Camera:GetChildren() do
		if e:IsA("BloomEffect") or e:IsA("SunRaysEffect")
			or e:IsA("DepthOfFieldEffect") or e:IsA("BlurEffect") then
			e.Enabled = false
		end
	end
end)

-- ════════════════════════════════════════════════════════════
-- COLOR GRADING
-- ════════════════════════════════════════════════════════════

SepLabel(container, L(), "COLOR GRADING")

do
	local function getCG() return getFx("ColorCorrectionEffect", "GFX_CG") end
	local cgBrightSet, cgContrastSet, cgSatSet

	local _, _b = SliderRow(container, L(), "Brightness", -1, 1, 0, "f2", function(v)
		local e = getCG(); e.Brightness = v; e.Enabled = true
	end)
	cgBrightSet = _b

	local _, _c = SliderRow(container, L(), "Contrast", -1, 1, 0, "f2", function(v)
		local e = getCG(); e.Contrast = v; e.Enabled = true
	end)
	cgContrastSet = _c

	local _, _s = SliderRow(container, L(), "Saturation", -1, 1, 0, "f2", function(v)
		local e = getCG(); e.Saturation = v; e.Enabled = true
	end)
	cgSatSet = _s

	local pLabel = UI.frame({
		Size             = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder      = L(),
		Parent           = container,
	})
	UI.text({
		Size           = UDim2.new(1, -8, 1, 0),
		Position       = UDim2.new(0, 6, 0, 0),
		Text           = "Preset",
		TextColor3     = T.TEXT_DIM,
		Font           = Enum.Font.Gotham,
		TextSize       = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent         = pLabel,
	})

	local PRESETS = {
		{ name = "Normal",    brightness = 0,     contrast = 0,    saturation = 0,    tint = Color3.new(1, 1, 1) },
		{ name = "Cinematic", brightness = -0.05, contrast = 0.25, saturation = -0.1, tint = Color3.fromRGB(255, 240, 210) },
		{ name = "Malam",     brightness = -0.3,  contrast = 0.3,  saturation = -0.3, tint = Color3.fromRGB(180, 200, 255) },
		{ name = "Vintage",   brightness = 0.05,  contrast = 0.15, saturation = -0.4, tint = Color3.fromRGB(255, 230, 180) },
		{ name = "Vibrant",   brightness = 0.05,  contrast = 0.1,  saturation = 0.5,  tint = Color3.new(1, 1, 1) },
		{ name = "Noir",      brightness = -0.1,  contrast = 0.4,  saturation = -1,   tint = Color3.new(1, 1, 1) },
	}

	local presetGrid = UI.frame({
		Size             = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		LayoutOrder      = L(),
		Parent           = container,
	})

	local gridLayout                   = Instance.new("UIGridLayout")
	gridLayout.CellSize                = UDim2.new(0, 68, 0, 26)
	gridLayout.CellPadding             = UDim2.new(0, 4, 0, 4)
	gridLayout.HorizontalAlignment     = Enum.HorizontalAlignment.Left
	gridLayout.Parent                  = presetGrid

	local uipad           = Instance.new("UIPadding")
	uipad.PaddingLeft     = UDim.new(0, 6)
	uipad.PaddingTop      = UDim.new(0, 4)
	uipad.Parent          = presetGrid

	local activePreset = "Normal"
	local presetBtns   = {}

	local function refreshPresetBtns()
		for _, d in ipairs(presetBtns) do
			local isActive = (d.name == activePreset)
			tw(d.btn, {
				BackgroundColor3 = isActive and T.ACCENT or T.CARD,
				TextColor3       = isActive and T.ON_ACCENT or T.TEXT,
			})
		end
	end

	local function applyPreset(p)
		activePreset = p.name
		local e = getCG()
		e.Brightness = p.brightness
		e.Contrast   = p.contrast
		e.Saturation = p.saturation
		e.TintColor  = p.tint
		e.Enabled    = p.name ~= "Normal"
		cgBrightSet(p.brightness)
		cgContrastSet(p.contrast)
		cgSatSet(p.saturation)
		refreshPresetBtns()
	end

	for _, p in ipairs(PRESETS) do
		local btn = UI.button({
			Size             = UDim2.new(0, 1, 0, 1),
			BackgroundColor3 = T.CARD,
			Text             = p.name,
			TextColor3       = T.TEXT,
			Font             = Enum.Font.GothamBold,
			TextSize         = 9,
			AutoButtonColor  = false,
			Parent           = presetGrid,
		})
		UI.corner(6).Parent = btn

		local pCopy = p
		btn.MouseEnter:Connect(function()
			if pCopy.name ~= activePreset then
				tw(btn, { BackgroundColor3 = T.CARD_HOVER })
			end
		end)
		btn.MouseLeave:Connect(refreshPresetBtns)
		btn.MouseButton1Click:Connect(function() applyPreset(pCopy) end)
		table.insert(presetBtns, { btn = btn, name = p.name })
	end

	applyPreset(PRESETS[1])
	getCG().Enabled = false

	table.insert(_resetList, function()
		applyPreset(PRESETS[1])
		getCG().Enabled = false
	end)
end

-- ════════════════════════════════════════════════════════════
-- ATMOSFER
-- ════════════════════════════════════════════════════════════

do
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if a then
		SepLabel(container, L(), "ATMOSFER")

		local _, densSet = SliderRow(container, L(), "Kepadatan", 0, 1, a.Density, "f2", function(v)
			local x = Lighting:FindFirstChildOfClass("Atmosphere")
			if x then x.Density = v end
		end)
		local _, hazeSet = SliderRow(container, L(), "Kabut (Haze)", 0, 2.3, a.Haze, "f1", function(v)
			local x = Lighting:FindFirstChildOfClass("Atmosphere")
			if x then x.Haze = v end
		end)
		local _, glareSet = SliderRow(container, L(), "Kilau (Glare)", 0, 1, a.Glare, "f2", function(v)
			local x = Lighting:FindFirstChildOfClass("Atmosphere")
			if x then x.Glare = v end
		end)

		if DEF_ATM then
			table.insert(_resetList, function()
				densSet(DEF_ATM.Density); hazeSet(DEF_ATM.Haze); glareSet(DEF_ATM.Glare)
				local x = Lighting:FindFirstChildOfClass("Atmosphere")
				if x then
					x.Density = DEF_ATM.Density
					x.Haze    = DEF_ATM.Haze
					x.Glare   = DEF_ATM.Glare
				end
			end)
		end
	end
end

-- ════════════════════════════════════════════════════════════
-- EFEK PEMAIN
-- ════════════════════════════════════════════════════════════

SepLabel(container, L(), "EFEK PEMAIN")

do
	local _, fxSet = ToggleRow(container, L(), "Sembunyikan Efek Pemain", false, function(v)
		HideAvatarManager:SetHideEffects(v)
	end)
	table.insert(_resetList, function() fxSet(false); HideAvatarManager:SetHideEffects(false) end)
end

-- ════════════════════════════════════════════════════════════
-- PEMAIN
-- ════════════════════════════════════════════════════════════

SepLabel(container, L(), "PEMAIN")

do
	local _, playerSet = ToggleRow(container, L(), "Sembunyikan Player Lain", false, function(v)
		HideAvatarManager:SetHideAll(v)
	end)
	table.insert(_resetList, function() playerSet(false); HideAvatarManager:SetHideAll(false) end)
end

UI.frame({ Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = L(), Parent = container })

-- ── Export ────────────────────────────────────────────────

_G.GraphicsPanel = container

_G.GfxReset = function()
	for _, fn in ipairs(_resetList) do pcall(fn) end
	Lighting.GlobalShadows  = DEF.GlobalShadows
	Lighting.Brightness     = DEF.Brightness
	Lighting.Ambient        = DEF.Ambient
	Lighting.OutdoorAmbient = DEF.OutdoorAmbient
	if DEF_ATM then
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		if a then
			a.Density = DEF_ATM.Density
			a.Haze    = DEF_ATM.Haze
			a.Glare   = DEF_ATM.Glare
		end
	end
	for _, e in Camera:GetChildren() do
		if e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect")
			or e:IsA("DepthOfFieldEffect") or e:IsA("BlurEffect") then
			e.Enabled = false
		end
	end
end
