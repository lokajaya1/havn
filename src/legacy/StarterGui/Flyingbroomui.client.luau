-- Flying Broom UI | LocalScript → StarterGui
-- FIXED:
--   1. Color picker sekarang update efek LANGSUNG saat sedang terbang (via _G.BroomApplyEffect)
--   2. Trail toggle juga langsung apply saat terbang
--   3. Tetap compatible dengan DynamicTools system

local MAX_RETRIES = 100
local RETRY_DELAY = 0.15
local TOOL_NAME   = "Flying Broom"

local C = {
	accent = Color3.fromRGB(255, 200, 50),
	white  = Color3.fromRGB(255, 255, 255),
	gray   = Color3.fromRGB(160, 160, 165),
	dark   = Color3.fromRGB(18,  18,  22),
	dim    = Color3.fromRGB(50,  50,  55),
	card   = Color3.fromRGB(28,  28,  33),
	green  = Color3.fromRGB(80,  200, 100),
	red    = Color3.fromRGB(220, 70,  70),
}

_G.BroomConfig = _G.BroomConfig or {
	speed      = 80,
	trailOn    = true,
	trailColor = Color3.fromRGB(255, 200, 50),
}

-- Preset warna trail
local COLORS = {
	{ label="Gold",    color=Color3.fromRGB(255, 200,  50) },
	{ label="Blue",    color=Color3.fromRGB( 80, 180, 255) },
	{ label="Green",   color=Color3.fromRGB( 80, 220, 120) },
	{ label="Red",     color=Color3.fromRGB(255,  80,  80) },
	{ label="Purple",  color=Color3.fromRGB(180,  80, 255) },
	{ label="White",   color=Color3.fromRGB(255, 255, 255) },
	{ label="Cyan",    color=Color3.fromRGB( 40, 230, 220) },
	{ label="Orange",  color=Color3.fromRGB(255, 140,  30) },
}

-- ── Helper: trigger live update ke client script ──────────
-- Dipanggil setiap kali user mengubah warna/trail saat terbang
local function triggerLiveUpdate()
	if _G.BroomApplyEffect then
		_G.BroomApplyEffect()
	end
end

local conns = {}
local function conn(sig, fn) table.insert(conns, sig:Connect(fn)) end
local function cleanConns()
	for _, c in conns do pcall(c.Disconnect, c) end
	table.clear(conns)
end

local function corner(r, p)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p
end
local function mkFrame(props, parent)
	local f = Instance.new("Frame"); f.BorderSizePixel = 0
	for k, v in props do f[k] = v end; f.Parent = parent; return f
end
local function mkLabel(props, parent)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.Font = Enum.Font.Gotham
	for k, v in props do l[k] = v end; l.Parent = parent; return l
end
local function mkButton(props, parent)
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0; b.AutoButtonColor = false; b.Font = Enum.Font.GothamBold
	for k, v in props do b[k] = v end; b.Parent = parent; corner(8, b); return b
end
local function mkLayout(gap, parent)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0, gap); l.Parent = parent
end
local function mkPad(px, parent)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px); p.PaddingRight  = UDim.new(0, px)
	p.PaddingTop  = UDim.new(0, px); p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

-- ── Speed Stepper ─────────────────────────────────────────
local function mkStepper(parent, label, key, vmin, vmax, step, unit, order)
	local wrap = mkFrame({ Size=UDim2.new(1,0,0,40), BackgroundColor3=C.card, LayoutOrder=order }, parent)
	corner(10, wrap); mkPad(10, wrap)

	mkLabel({ Size=UDim2.new(0.5,0,1,0), Text=label,
		TextColor3=C.gray, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left }, wrap)

	local right = mkFrame({ Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0.5,0,0,0), BackgroundTransparency=1 }, wrap)
	local rl = Instance.new("UIListLayout")
	rl.FillDirection       = Enum.FillDirection.Horizontal
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.VerticalAlignment   = Enum.VerticalAlignment.Center
	rl.Padding = UDim.new(0, 6); rl.Parent = right

	local btnMinus = mkButton({ Size=UDim2.new(0,30,0,28), BackgroundColor3=C.dim,
		Text="−", TextColor3=C.white, TextSize=18, LayoutOrder=1 }, right)
	local valLbl = mkLabel({ Size=UDim2.new(0,58,0,28), Text=_G.BroomConfig[key]..unit,
		TextColor3=C.accent, TextSize=13, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Center, LayoutOrder=2 }, right)
	local btnPlus = mkButton({ Size=UDim2.new(0,30,0,28), BackgroundColor3=C.dim,
		Text="+", TextColor3=C.white, TextSize=18, LayoutOrder=3 }, right)

	conn(btnMinus.Activated, function()
		_G.BroomConfig[key] = math.max(vmin, _G.BroomConfig[key] - step)
		valLbl.Text = _G.BroomConfig[key] .. unit
		-- Speed tidak perlu triggerLiveUpdate (dibaca langsung oleh RenderStepped via cfg())
	end)
	conn(btnPlus.Activated, function()
		_G.BroomConfig[key] = math.min(vmax, _G.BroomConfig[key] + step)
		valLbl.Text = _G.BroomConfig[key] .. unit
	end)
end

-- ── Trail Toggle ──────────────────────────────────────────
local function mkTrailToggle(parent, order)
	local wrap = mkFrame({ Size=UDim2.new(1,0,0,40), BackgroundColor3=C.card, LayoutOrder=order }, parent)
	corner(10, wrap); mkPad(10, wrap)

	mkLabel({ Size=UDim2.new(0.5,0,1,0), Text="Trail Effect",
		TextColor3=C.gray, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left }, wrap)

	local toggleBtn = mkButton({
		Size=UDim2.new(0,80,0,28), Position=UDim2.new(1,-80,0.5,-14),
		BackgroundColor3=_G.BroomConfig.trailOn and C.green or C.red,
		Text=_G.BroomConfig.trailOn and "ON" or "OFF",
		TextColor3=C.white, TextSize=13,
	}, wrap)

	conn(toggleBtn.Activated, function()
		_G.BroomConfig.trailOn = not _G.BroomConfig.trailOn
		toggleBtn.BackgroundColor3 = _G.BroomConfig.trailOn and C.green or C.red
		toggleBtn.Text             = _G.BroomConfig.trailOn and "ON"    or "OFF"
		-- FIXED: langsung update efek saat sedang terbang
		triggerLiveUpdate()
	end)
end

-- ── Color Picker (Preset Grid) ────────────────────────────
local function mkColorPicker(parent, order)
	local wrap = mkFrame({ Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y,
		BackgroundTransparency=1, LayoutOrder=order }, parent)
	mkLayout(6, wrap)

	mkLabel({ Size=UDim2.new(1,0,0,13), LayoutOrder=1, Text="TRAIL COLOR",
		TextColor3=C.gray, TextSize=10, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Left }, wrap)

	-- Grid: 4 kolom × 2 baris untuk 8 warna
	local grid = mkFrame({ Size=UDim2.new(1,0,0,60), BackgroundTransparency=1, LayoutOrder=2 }, wrap)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize      = UDim2.new(0, 40, 0, 24)
	gl.CellPadding   = UDim2.new(0, 4, 0, 4)
	gl.SortOrder     = Enum.SortOrder.LayoutOrder
	gl.Parent        = grid

	local refs = {}

	local function selectColor(idx)
		_G.BroomConfig.trailColor = COLORS[idx].color
		for i, r in refs do
			local sel = i == idx
			r.stroke.Thickness    = sel and 2.5 or 0
			r.stroke.Transparency = sel and 0   or 1
		end
		-- FIXED: langsung update warna partikel saat sedang terbang
		triggerLiveUpdate()
	end

	-- Cari index warna yang sedang aktif
	local function findActiveIndex()
		for i, preset in ipairs(COLORS) do
			if preset.color == _G.BroomConfig.trailColor then return i end
		end
		return 1
	end

	for i, preset in ipairs(COLORS) do
		local isActive = (i == findActiveIndex())

		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1,0,1,0)
		btn.BackgroundColor3 = preset.color
		btn.Text             = ""
		btn.AutoButtonColor  = false
		btn.BorderSizePixel  = 0
		btn.LayoutOrder      = i
		btn.Parent           = grid
		corner(6, btn)

		local stroke = Instance.new("UIStroke")
		stroke.Color        = C.white
		stroke.Thickness    = isActive and 2.5 or 0
		stroke.Transparency = isActive and 0   or 1
		stroke.Parent       = btn

		refs[i] = { btn=btn, stroke=stroke }
		conn(btn.Activated, function() selectColor(i) end)
	end
end

-- ── Build UI ──────────────────────────────────────────────
local function buildUI()
	cleanConns()

	local main = Instance.new("Frame")
	main.Name              = "BroomSettings"
	main.Size              = UDim2.new(1,0,0,0)
	main.AutomaticSize     = Enum.AutomaticSize.Y
	main.BackgroundTransparency = 1
	mkLayout(10, main); mkPad(8, main)

	-- Judul
	mkLabel({ Size=UDim2.new(1,0,0,24), LayoutOrder=1, Text="🧹  Flying Broom",
		TextColor3=C.white, TextSize=16, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Left }, main)

	mkLabel({ Size=UDim2.new(1,0,0,13), LayoutOrder=2, Text="FLIGHT CONFIG",
		TextColor3=C.gray, TextSize=10, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Left }, main)

	-- Setting controls
	mkStepper(main, "Speed", "speed", 20, 200, 10, " stud/s", 3)
	mkTrailToggle(main, 4)
	mkColorPicker(main, 5)

	-- Hint
	mkLabel({ Size=UDim2.new(1,0,0,26), LayoutOrder=6,
		Text="Double-tap to toggle fly",
		TextColor3=C.gray, TextSize=11, Font=Enum.Font.Gotham,
		TextXAlignment=Enum.TextXAlignment.Center }, main)

	return main
end

-- ── Register ke DynamicTools ──────────────────────────────
task.spawn(function()
	for _ = 1, MAX_RETRIES do
		if _G.RegisterDynamicTool then
			_G.RegisterDynamicTool(TOOL_NAME, buildUI, { iconText = "🧹" })
			return
		end
		task.wait(RETRY_DELAY)
	end
	warn("[FlyingBroomUI] DynamicTools tidak ditemukan")
end)