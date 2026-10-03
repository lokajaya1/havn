-- Water Gun UI | LocalScript → StarterGui
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))
-- [TOOLS] rentang stepper Rate/Burst = Config.Tools.WATER_GUN (server memakai angka yang sama).
local W = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools")).WATER_GUN

local MAX_RETRIES = 100
local RETRY_DELAY = 0.15
local TOOL_NAME   = "WaterGun"

-- Warna: ReplicatedStorage.Modules.ThemeColor (themeColor). ThemeColor.view: C.X = token tema SEKARANG
-- (dibaca saat dipakai, juga di setMode/hover/leave) → ikut tema pilihan pemain.
local C = ThemeColor.view({
	accent = "ACCENT",
	white  = "TEXT",
	gray   = "TEXT_DIM",
	dark   = "ON_ACCENT",
	dim    = "CARD_HOVER",
	card   = "CARD",
	title  = "TEXT_STRONG", -- judul panel
	hover  = "TEXT_STRONG", -- hover tombol BURST (latar terang, teks ON_ACCENT)
})

_G.WaterGunMode   = _G.WaterGunMode   or W.DEFAULT_MODE
_G.WaterGunConfig = _G.WaterGunConfig or { rate = W.RATE.DEFAULT, burst = W.BURST.DEFAULT }

-- Tombol Reset Tool Settings: mode, Rate & Burst kembali bawaan Config (dipakai saat semprot berikutnya;
-- panel dibangun ulang DynamicTools).
local function resetDefaults()
	_G.WaterGunMode   = W.DEFAULT_MODE
	_G.WaterGunConfig = { rate = W.RATE.DEFAULT, burst = W.BURST.DEFAULT }
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
	local valLbl = mkLabel({ Size=UDim2.new(0,58,0,28), Text=_G.WaterGunConfig[key]..unit,
		TextColor3=C.accent, TextSize=13, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Center, LayoutOrder=2 }, right)
	local btnPlus = mkButton({ Size=UDim2.new(0,30,0,28), BackgroundColor3=C.dim,
		Text="+", TextColor3=C.white, TextSize=18, LayoutOrder=3 }, right)

	conn(btnMinus.Activated, function()
		_G.WaterGunConfig[key] = math.max(vmin, _G.WaterGunConfig[key] - step)
		valLbl.Text = _G.WaterGunConfig[key] .. unit
	end)
	conn(btnPlus.Activated, function()
		_G.WaterGunConfig[key] = math.min(vmax, _G.WaterGunConfig[key] + step)
		valLbl.Text = _G.WaterGunConfig[key] .. unit
	end)
end

local MODES = {
	{ id="hold",  icon="🔫", label="Hold"  },
	{ id="burst", icon="💦", label="Burst" },
	{ id="auto",  icon="🔁", label="Auto"  },
}

local function mkModeSelector(parent, order)
	local grid = mkFrame({ Size=UDim2.new(1,0,0,56), BackgroundTransparency=1, LayoutOrder=order }, parent)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.333, -3, 1, 0); gl.CellPadding = UDim2.new(0, 4, 0, 0)
	gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gl.Parent = grid

	local refs = {}
	local function setMode(id)
		_G.WaterGunMode = id
		for mid, r in refs do
			local a = mid == id
			r.btn.BackgroundColor3 = a and C.accent or C.dim
			r.icon.TextColor3      = a and C.dark   or C.white
			r.lbl.TextColor3       = a and C.dark   or C.white
		end
	end

	for i, m in ipairs(MODES) do
		local active = m.id == _G.WaterGunMode
		local btn = Instance.new("TextButton")
		btn.Size=UDim2.new(1,0,1,0); btn.BackgroundColor3=active and C.accent or C.dim
		btn.BorderSizePixel=0; btn.Text=""; btn.AutoButtonColor=false
		btn.LayoutOrder=i; btn.Parent=grid
		corner(10, btn)

		local icon = mkLabel({ Size=UDim2.new(1,0,0,22), Position=UDim2.new(0,0,0,6),
			Text=m.icon, TextColor3=active and C.dark or C.white,
			TextSize=16, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center }, btn)
		local lbl = mkLabel({ Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,30),
			Text=m.label, TextColor3=active and C.dark or C.white,
			TextSize=11, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center }, btn)

		refs[m.id] = { btn=btn, icon=icon, lbl=lbl }
		conn(btn.Activated, function() setMode(m.id) end)
	end
end

local function buildUI()
	cleanConns()

	local main = Instance.new("Frame")
	main.Name = "WaterGunSettings"; main.Size = UDim2.new(1,0,0,0)
	main.AutomaticSize = Enum.AutomaticSize.Y; main.BackgroundTransparency = 1
	mkLayout(10, main); mkPad(8, main)

	mkLabel({ Size=UDim2.new(1,0,0,24), LayoutOrder=1, Text="💧  WaterGun",
		TextColor3=C.title, TextSize=16, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Left }, main)
	mkLabel({ Size=UDim2.new(1,0,0,13), LayoutOrder=2, Text="MODE",
		TextColor3=C.gray, TextSize=10, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Left }, main)

	mkModeSelector(main, 3)

	mkLabel({ Size=UDim2.new(1,0,0,13), LayoutOrder=4, Text="SPRAY CONFIG",
		TextColor3=C.gray, TextSize=10, Font=Enum.Font.GothamBold,
		TextXAlignment=Enum.TextXAlignment.Left }, main)

	mkStepper(main, "Rate /detik", "rate",  W.RATE.MIN,  W.RATE.MAX,  W.RATE.STEP,  "/dtk", 5)
	mkStepper(main, "Burst (pcs)", "burst", W.BURST.MIN, W.BURST.MAX, W.BURST.STEP, " pcs", 6)

	local burstBtn = mkButton({ Size=UDim2.new(1,0,0,50), BackgroundColor3=C.accent,
		Text="💦  BURST!", TextColor3=C.dark, TextSize=16, LayoutOrder=7 }, main)
	conn(burstBtn.MouseEnter, function() burstBtn.BackgroundColor3 = C.hover end)
	conn(burstBtn.MouseLeave, function() burstBtn.BackgroundColor3 = C.accent end)
	conn(burstBtn.Activated, function()
		local t = _G.GetCurrentTool and _G.GetCurrentTool()
		-- [TOOLS] burst lewat server (Serverscript WaterGun) → terlihat semua pemain
		local r = t and t:FindFirstChild("RemoteEvent")
		if r then r:FireServer("burst", _G.WaterGunConfig.burst) end
	end)

	return main
end

task.spawn(function()
	for _ = 1, MAX_RETRIES do
		if _G.RegisterDynamicTool then
			_G.RegisterDynamicTool(TOOL_NAME, buildUI, { iconText = "💧", reset = resetDefaults })
			return
		end
		task.wait(RETRY_DELAY)
	end
	warn("[WaterGunUI] DynamicTools tidak ditemukan")
end)