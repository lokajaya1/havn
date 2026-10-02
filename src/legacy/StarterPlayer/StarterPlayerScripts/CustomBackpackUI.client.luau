-- StarterPlayerScripts/CustomBackpackUI (LocalScript) — tas / inventory HAVN (claude/Rencana_Inventory.md).
-- Menggantikan backpack bawaan Roblox (CoreGui Backpack dimatikan). Gaya clean-modern, warna dari ThemeColor (ikut tema):
--   • Hotbar bawah-tengah: slot 1–9, 0 (HP 3–6). Klik / tombol angka = pakai ↔ lepas (seperti Roblox). Slot yang dipakai =
--     garis aksen bergerak. Hover (mouse) = tooltip nama + ToolTip.
--   • Kiri hotbar: ikon TAS (jumlah tool) + tombol ˅ di bawahnya = sembunyikan hotbar (layar bersih, tinggal tas; tombol
--     angka tetap jalan); ˄ = tampilkan lagi.
--   • ` (Backquote, Mac & Windows) / klik tas = jendela INVENTORY: semua tool + kotak cari (nama / ToolTip). Klik kartu =
--     pakai. Seret kartu ke slot hotbar = atur (tukar); seret slot keluar hotbar = lepas dari hotbar (layar sentuh: tahan
--     sebentar lalu seret). ` / tas / X / Esc = tutup. Ikut PanelCoordinator (satu panel terbuka → tidak bertumpuk).
--   • Backspace (buang tool) = perilaku bawaan Roblox (Tool.CanBeDropped), tidak disentuh skrip ini.
--   • Gamepad: LB / RB = tool sebelumnya / berikutnya.
-- Logika murni: ReplicatedStorage.Modules.Inventory · angka: ReplicatedStorage.Config.Inventory.
-- (Dulu skrip ini prototipe hotbar emas yang Disabled; diganti total, nama & tempat dipertahankan.)

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Backpack bawaan dimatikan SECEPATNYA (sebelum menunggu modul) supaya hotbar Roblox tidak sempat muncul.
local function disableDefault()
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
end
disableDefault()
task.spawn(function()
	for _ = 1, 20 do
		task.wait(0.25)
		disableDefault()
	end
end)

local Modules = RS:WaitForChild("Modules")
local ThemeColor = require(Modules:WaitForChild("ThemeColor"))
local Rules = require(Modules:WaitForChild("Inventory"))
local Config = require(RS:WaitForChild("Config"):WaitForChild("Inventory"))
local Responsive = require(RS:WaitForChild("CustomUIModules"):WaitForChild("Responsive"))

local T = ThemeColor.tokens
local FONT = { BOLD = Enum.Font.BuilderSansBold, MEDIUM = Enum.Font.BuilderSansMedium, REGULAR = Enum.Font.BuilderSans }
local PAD = 12 -- padding jendela inventory
local HEAD_H, SEARCH_H, HINT_H = 24, 32, 12

-- ── helper ────────────────────────────────────────────────────────────────────────────────────────────────────────
local function new(class, props)
	local o = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	if props.Parent then
		o.Parent = props.Parent
	end
	return o
end
local function corner(p, r)
	new("UICorner", { CornerRadius = r, Parent = p })
end
local function stroke(p, color, tr, th)
	return new("UIStroke", {
		Color = color, Transparency = tr, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p,
	})
end
local function tw(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- Ikon digambar dari Frame (bukan emoji/aset) → tajam & ikut warna tema.
local function bagIcon(parent)
	local g = new("Frame", { Name = "BagIcon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Parent = parent })
	local handle = new("Frame", { Name = "Handle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Parent = g })
	corner(handle, UDim.new(1, 0))
	local hs = stroke(handle, T.TEXT_STRONG, 0, 2)
	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(1, 6), Size = UDim2.new(1, -2, 1, -6),
		BackgroundColor3 = T.TEXT_STRONG, BorderSizePixel = 0, Parent = g })
	corner(body, UDim.new(0, 5))
	local pocket = new("Frame", { Name = "Pocket", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(8, 2), BackgroundColor3 = T.CARD, BorderSizePixel = 0, Parent = g })
	corner(pocket, UDim.new(1, 0))
	return { body = body, handle = hs, pocket = pocket }
end

local function chevron(parent)
	local c = new("Frame", { Name = "Chevron", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 8), BackgroundTransparency = 1, Parent = parent })
	for _, side in { -1, 1 } do -- "\" kiri + "/" kanan = ˅ (diputar 180° = ˄)
		local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 2.6, 0.5, 0),
			Size = UDim2.fromOffset(7, 2), Rotation = -side * 40, BackgroundColor3 = T.TEXT_DIM, BorderSizePixel = 0, Parent = c })
		corner(bar, UDim.new(1, 0))
	end
	return c
end

local function magnifier(parent)
	local m = new("Frame", { Name = "Magnifier", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(13, 13), BackgroundTransparency = 1, Parent = parent })
	local ring = new("Frame", { Size = UDim2.fromOffset(9, 9), BackgroundTransparency = 1, Parent = m })
	corner(ring, UDim.new(1, 0))
	stroke(ring, T.TEXT_DIM, 0, 1.5)
	local h = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(10.5, 10.5), Size = UDim2.fromOffset(5, 2),
		Rotation = 45, BackgroundColor3 = T.TEXT_DIM, BorderSizePixel = 0, Parent = m })
	corner(h, UDim.new(1, 0))
end

-- ── kerangka ──────────────────────────────────────────────────────────────────────────────────────────────────────
local old = playerGui:FindFirstChild("CustomBackpack")
if old then
	old:Destroy()
end
local gui = new("ScreenGui", { Name = "CustomBackpack", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
ThemeColor.mark(gui)

-- Dock = [tas/˅][slot…], SELALU di tengah layar: AnchorPoint 0.5 + lebar = persis isi yang tampil (Rules.dock) → tengah
-- presisi saat biasa, saat hotbar disembunyikan (tinggal tas), dan saat inventory dibuka (semua slot).
local dock = new("Frame", { Name = "Dock", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -Config.bottom),
	BackgroundTransparency = 1, Parent = gui })
local bagCol = new("Frame", { Name = "BagColumn", BackgroundTransparency = 1, Parent = dock })
local bagBtn = new("TextButton", { Name = "Bag", BackgroundColor3 = T.CARD, BackgroundTransparency = 0.12, AutoButtonColor = false,
	Text = "", Parent = bagCol })
corner(bagBtn, UDim.new(0, 12))
local bagStroke = stroke(bagBtn, T.LINE, 0.9)
local bag = bagIcon(bagBtn)
local badge = new("TextLabel", { Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4),
	Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.ACCENT, TextColor3 = T.ON_ACCENT,
	Font = FONT.BOLD, TextSize = 10, Text = "0", Visible = false, ZIndex = 3, Parent = bagBtn })
corner(badge, UDim.new(1, 0))
new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = badge })
new("UISizeConstraint", { MinSize = Vector2.new(16, 16), Parent = badge })
local hideBtn = new("TextButton", { Name = "Hide", BackgroundColor3 = T.CARD, BackgroundTransparency = 0.25, AutoButtonColor = false,
	Text = "", Parent = bagCol })
corner(hideBtn, UDim.new(0, 7))
local chev = chevron(hideBtn)
local row = new("Frame", { Name = "Slots", BackgroundTransparency = 1, Parent = dock })

-- Jendela inventory (di atas hotbar, tengah layar).
local inv = new("Frame", { Name = "Inventory", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = T.BG, Active = true,
	Visible = false, ZIndex = 5, Parent = gui })
corner(inv, UDim.new(0, 14))
ThemeColor.glow(stroke(inv, T.LINE, 0.88), "panel")
local invScale = new("UIScale", { Parent = inv })
local head = new("Frame", { Name = "Head", Position = UDim2.fromOffset(PAD + 2, PAD), Size = UDim2.new(1, -(PAD * 2 + 30), 0, HEAD_H),
	BackgroundTransparency = 1, Parent = inv })
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = head })
new("TextLabel", { Name = "Title", Size = UDim2.fromOffset(0, HEAD_H), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Text = "INVENTORY", Font = FONT.BOLD, TextSize = 14, TextColor3 = T.TEXT_STRONG, LayoutOrder = 1,
	Parent = head })
local countPill = new("TextLabel", { Name = "Count", Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = T.CHIP, TextColor3 = T.ON_ACCENT, Font = FONT.BOLD, TextSize = 11, Text = "0", LayoutOrder = 2, Parent = head })
corner(countPill, UDim.new(1, 0))
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7), Parent = countPill })
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(PAD - 4), 0, PAD - 1),
	Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "X", Font = FONT.BOLD, TextSize = 13,
	TextColor3 = T.TEXT_DIM, AutoButtonColor = false, Parent = inv })
local searchBg = new("Frame", { Name = "Search", Position = UDim2.fromOffset(PAD, PAD + HEAD_H + 8),
	Size = UDim2.new(1, -PAD * 2, 0, SEARCH_H), BackgroundColor3 = T.CARD, BorderSizePixel = 0, Parent = inv })
corner(searchBg, UDim.new(0, 10))
magnifier(searchBg)
local search = new("TextBox", { Name = "Query", Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -40, 1, 0),
	BackgroundTransparency = 1, Text = "", PlaceholderText = "Cari tool…", PlaceholderColor3 = T.TEXT_DIM, TextColor3 = T.TEXT,
	Font = FONT.REGULAR, TextSize = 13, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = searchBg })
local GRID_Y = PAD + HEAD_H + 8 + SEARCH_H + 10
local grid = new("ScrollingFrame", { Name = "Grid", Position = UDim2.fromOffset(PAD, GRID_Y), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = T.SCROLL, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Parent = inv })
new("UIGridLayout", { CellSize = UDim2.fromOffset(Config.cell, Config.cellH), CellPadding = UDim2.fromOffset(Config.cellGap,
	Config.cellGap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2),
	PaddingRight = UDim.new(0, 2), Parent = grid })
local emptyLbl = new("TextLabel", { Name = "Empty", Position = UDim2.fromOffset(PAD, GRID_Y), Size = UDim2.new(1, -PAD * 2, 0, 40),
	BackgroundTransparency = 1, Text = "", Font = FONT.MEDIUM, TextSize = 13, TextColor3 = T.TEXT_DIM, Visible = false, Parent = inv })
local hint = new("TextLabel", { Name = "Hint", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, PAD + 2, 1, -PAD + 2),
	Size = UDim2.new(1, -PAD * 2, 0, HINT_H), BackgroundTransparency = 1, Text = "", Font = FONT.REGULAR, TextSize = 11,
	TextColor3 = T.TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = inv })

-- Tooltip (mouse) di atas slot / tas.
local tip = new("Frame", { Name = "Tip", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = T.BG, Visible = false, ZIndex = 20, Parent = gui })
corner(tip, UDim.new(0, 8))
stroke(tip, T.LINE, 0.85)
new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), PaddingTop = UDim.new(0, 5),
	PaddingBottom = UDim.new(0, 5), Parent = tip })
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = tip })
local tipName = new("TextLabel", { Name = "Name", Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Font = FONT.BOLD, TextSize = 12, TextColor3 = T.TEXT_STRONG, LayoutOrder = 1, ZIndex = 21, Parent = tip })
local tipSub = new("TextLabel", { Name = "Sub", Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Font = FONT.REGULAR, TextSize = 11, TextColor3 = T.TEXT_DIM, LayoutOrder = 2, ZIndex = 21, Parent = tip })

-- Bayangan tool yang sedang diseret.
local ghost = new("Frame", { Name = "DragGhost", BackgroundColor3 = T.CARD_HOVER, Visible = false, ZIndex = 30, Parent = gui })
corner(ghost, UDim.new(0, 12))
local ghostStroke = stroke(ghost, T.ACCENT, 0, 2)
local ghostIcon = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.6, 0.6), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 31, Parent = ghost })
local ghostLabel = new("TextLabel", { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1,
	Font = FONT.BOLD, TextSize = 11, TextColor3 = T.TEXT, TextWrapped = true, ZIndex = 31, Parent = ghost })

-- ── keadaan ───────────────────────────────────────────────────────────────────────────────────────────────────────
local state = Rules.new(Config.slotsMax)
local tools = {} -- nama → Tool (yang ada sekarang)
local names = {} -- nama tool yang ada, urutan datang
local invOpen, hidden = false, false
local L = { phone = false, S = Config.slot, gap = Config.gap, bagW = 42, count = Config.slotsMax }
local slots, cards = {}, {}
local dropTarget = nil -- slot yang sedang disorot sebagai sasaran seret
local press, drag = nil, nil
local suppressClick = 0 -- os.clock() sampai klik diabaikan (ekor seret)

local function humanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function equippedTool()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool")
end

local function scan()
	table.clear(tools)
	table.clear(names)
	local function add(tool)
		if tool:IsA("Tool") and not tools[tool.Name] then
			tools[tool.Name] = tool
			table.insert(names, tool.Name)
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, c in bp:GetChildren() do
			add(c)
		end
	end
	local char = player.Character
	if char then
		for _, c in char:GetChildren() do
			add(c)
		end
	end
end

local function toggleEquip(name)
	local hum, tool = humanoid(), tools[name]
	if not (hum and tool) or hum.Health <= 0 then
		return
	end
	if tool.Parent == player.Character then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

local function useSlot(i)
	local name = state.slots[i]
	if name and tools[name] then
		toggleEquip(name)
	end
end

-- Isi visual sebuah tombol tool (slot / kartu): ikon TextureId, atau nama kalau tool tanpa ikon.
local function texOf(tool)
	local tex = tool and tool.TextureId or ""
	return if tex ~= "" and tex ~= "rbxassetid://0" then tex else nil
end

-- ── slot hotbar ───────────────────────────────────────────────────────────────────────────────────────────────────
local beginPress -- function (di bawah)

local function makeSlot(i)
	local b = new("TextButton", { Name = "Slot" .. Rules.keyLabel(i), BackgroundColor3 = T.CARD, BackgroundTransparency = 0.12,
		AutoButtonColor = false, Text = "", Visible = false, Parent = row })
	corner(b, UDim.new(0, 12))
	local s = {
		index = i, btn = b, stroke = stroke(b, T.LINE, 0.9), glowing = false, name = nil,
		key = new("TextLabel", { Name = "Key", Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1, Text = Rules.keyLabel(i), Font = FONT.BOLD, TextSize = 11, TextColor3 = T.TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = b }),
		icon = new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 2),
			Size = UDim2.fromScale(0.6, 0.6), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Parent = b }),
		label = new("TextLabel", { Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 4),
			Size = UDim2.new(1, -6, 0.6, 0), BackgroundTransparency = 1, Font = FONT.BOLD, TextSize = 11, TextColor3 = T.TEXT,
			TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Parent = b }),
	}
	b.Activated:Connect(function()
		if os.clock() < suppressClick then
			return
		end
		useSlot(i)
	end)
	b.InputBegan:Connect(function(input)
		beginPress(input, s.name, i, b)
	end)
	b.MouseEnter:Connect(function()
		local tool = s.name and tools[s.name]
		if tool and not drag and UIS:GetLastInputType() ~= Enum.UserInputType.Touch then
			tipName.Text = tool.Name
			tipSub.Text = if tool.ToolTip ~= "" then tool.ToolTip else "Klik / tekan " .. Rules.keyLabel(i)
			tipSub.Visible = true
			local p = b.AbsolutePosition - gui.AbsolutePosition
			tip.Position = UDim2.fromOffset(p.X + b.AbsoluteSize.X / 2, p.Y - 8)
			tip.Visible = true
		end
	end)
	b.MouseLeave:Connect(function()
		tip.Visible = false
	end)
	return s
end
for i = 1, Config.slotsMax do
	slots[i] = makeSlot(i)
end

local function paintSlot(s, name, tool, equipped)
	s.name = name
	local tex = texOf(tool)
	s.icon.Image = tex or ""
	s.icon.Visible = tex ~= nil
	s.label.Text = if name and not tex then name else ""
	s.label.Visible = name ~= nil and tex == nil
	s.key.TextColor3 = if equipped then T.ACCENT else T.TEXT_DIM
	s.btn.BackgroundTransparency = if name then 0.12 else 0.55
	local target = dropTarget == s.index
	if equipped then
		if not s.glowing then
			s.stroke.Thickness = 2
			ThemeColor.glow(s.stroke, Config.equipGlow)
			s.glowing = true
		end
	elseif s.glowing then
		ThemeColor.unglow(s.stroke, T.LINE, 0.9)
		s.glowing = false
	end
	if not equipped then
		s.stroke.Thickness = if target then 2 else 1
		s.stroke.Color = if target then T.ACCENT else T.LINE
		s.stroke.Transparency = if target then 0 else 0.9
	end
	s.btn.BackgroundColor3 = if equipped or target then T.CARD_HOVER else T.CARD
end

-- ── kartu inventory ───────────────────────────────────────────────────────────────────────────────────────────────
local function makeCard()
	local b = new("TextButton", { BackgroundColor3 = T.CARD, AutoButtonColor = false, Text = "", Parent = grid })
	corner(b, UDim.new(0, 12))
	local c = {
		btn = b, stroke = stroke(b, T.LINE, 0.9), name = nil,
		key = new("TextLabel", { Name = "Key", Position = UDim2.fromOffset(7, 5), Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1, Font = FONT.BOLD, TextSize = 10, TextColor3 = T.TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = b }),
		icon = new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Parent = b }),
		label = new("TextLabel", { Name = "Label", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -7),
			Size = UDim2.new(1, -10, 0, 26), BackgroundTransparency = 1, Font = FONT.MEDIUM, TextSize = 11, TextColor3 = T.TEXT,
			TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Center, Parent = b }),
	}
	b.Activated:Connect(function()
		if os.clock() < suppressClick or not c.name then
			return
		end
		toggleEquip(c.name)
	end)
	b.InputBegan:Connect(function(input)
		beginPress(input, c.name, nil, b)
	end)
	return c
end

local function paintCard(c, name, order, equipped)
	local tool = tools[name]
	local tex = texOf(tool)
	local slot = Rules.slotOf(state, name)
	c.name = name
	c.btn.LayoutOrder = order
	c.btn.Visible = true
	c.icon.Image = tex or ""
	c.icon.Visible = tex ~= nil
	c.label.Text = name
	-- tanpa ikon: nama di tengah kartu (lebih besar)
	c.label.Size = if tex then UDim2.new(1, -10, 0, 26) else UDim2.new(1, -12, 1, -24)
	c.label.Position = if tex then UDim2.new(0.5, 0, 1, -7) else UDim2.new(0.5, 0, 1, -12)
	c.label.TextSize = if tex then 11 else 13
	c.label.Font = if tex then FONT.MEDIUM else FONT.BOLD
	c.key.Text = if slot and slot <= L.count then Rules.keyLabel(slot) else ""
	c.key.TextColor3 = if equipped then T.ACCENT else T.TEXT_DIM
	c.stroke.Color = if equipped then T.ACCENT else T.LINE
	c.stroke.Transparency = if equipped then 0 else 0.9
	c.stroke.Thickness = if equipped then 1.5 else 1
	c.btn.BackgroundColor3 = if equipped then T.CARD_HOVER else T.CARD
end

-- ── susun & lukis ─────────────────────────────────────────────────────────────────────────────────────────────────
local function layoutDock()
	local vp = Responsive.Viewport()
	local phone = Responsive.Device() == "mobile"
	local S = if phone then Config.slotPhone else Config.slot
	local gap = Config.gap
	local bagW = math.floor(S * 0.82)
	local count
	if phone then
		count = Rules.phoneSlots(vp.X, S, gap, bagW, Config)
	else
		count = math.clamp(math.floor((vp.X - 24 - bagW) / (S + gap)), Config.slotsPhoneMin, Config.slotsMax)
	end
	L = { phone = phone, S = S, gap = gap, bagW = bagW, count = count }
	bagCol.Size = UDim2.fromOffset(bagW, S)
	bagBtn.Size = UDim2.new(1, 0, 1, -(Config.hideH + 4))
	hideBtn.Size = UDim2.new(1, 0, 0, Config.hideH)
	hideBtn.Position = UDim2.new(0, 0, 1, -Config.hideH)
	hint.Text = if UIS.TouchEnabled and not UIS.KeyboardEnabled
		then "Ketuk pakai · tahan & seret ke slot hotbar"
		else "Klik pakai · seret ke slot hotbar · ` tutup"
end

local function renderDock()
	local eq = equippedTool()
	tip.Visible = false -- isi / posisi slot bisa berubah → tooltip lama tidak boleh tertinggal
	local lay = Rules.dock(state, tools, L.count, invOpen, hidden, L.S, L.gap, L.bagW)
	for i = 1, Config.slotsMax do
		local s = slots[i]
		local name = state.slots[i]
		local tool = name and tools[name]
		local x = lay.x[i]
		s.btn.Visible = x ~= nil
		if x then
			s.btn.Size = UDim2.fromOffset(L.S, L.S)
			s.btn.Position = UDim2.fromOffset(x, 0)
			paintSlot(s, if tool then name else nil, tool, tool ~= nil and tool == eq)
		elseif s.glowing then
			ThemeColor.unglow(s.stroke, T.LINE, 0.9)
			s.glowing = false
		end
	end
	row.Visible = lay.showRow
	row.Position = UDim2.fromOffset(lay.rowX, 0)
	row.Size = UDim2.fromOffset(lay.rowW, L.S)
	-- lebar dock = persis isi yang tampil; AnchorPoint 0.5 di tengah layar → tengah presisi di semua keadaan
	dock.Size = UDim2.fromOffset(lay.width, L.S)
	-- tas: aktif (inventory terbuka) = chip terang seperti tab aktif
	bagBtn.BackgroundColor3 = if invOpen then T.CHIP else T.CARD
	bagBtn.BackgroundTransparency = if invOpen then 0 else 0.12
	bag.body.BackgroundColor3 = if invOpen then T.ON_ACCENT else T.TEXT_STRONG
	bag.handle.Color = if invOpen then T.ON_ACCENT else T.TEXT_STRONG
	bag.pocket.BackgroundColor3 = if invOpen then T.CHIP else T.CARD
	bagStroke.Transparency = if invOpen then 1 else 0.9
	badge.Text = tostring(#names)
	badge.Visible = #names > 0 and not invOpen
	chev.Rotation = if hidden then 180 else 0
end

local function renderInventory()
	if not invOpen then
		return
	end
	local eq = equippedTool()
	local items = {}
	for _, n in Rules.order(state, names) do
		local tool = tools[n]
		table.insert(items, { name = n, tip = if tool and tool.ToolTip ~= "" then tool.ToolTip else nil })
	end
	local shown = Rules.filter(items, search.Text)
	for i, it in shown do
		local c = cards[i] or makeCard()
		cards[i] = c
		paintCard(c, it.name, i, tools[it.name] ~= nil and tools[it.name] == eq)
	end
	for i = #shown + 1, #cards do
		cards[i].btn.Visible = false
		cards[i].name = nil
	end
	countPill.Text = tostring(#names)
	emptyLbl.Visible = #shown == 0
	emptyLbl.Text = if #names == 0 then "Belum ada tool" else "Tidak ada yang cocok"
end

local function topLimit()
	local tl = _G.TopbarLayout
	if tl and tl.contentTop then
		local ok, v = pcall(tl.contentTop)
		if ok and type(v) == "number" then
			return v
		end
	end
	return 64
end

local function layoutInventory()
	local vp = Responsive.Viewport()
	local dockTop = Config.bottom + L.S
	local roomX = vp.X - 24 - PAD * 2 - 4
	local roomY = vp.Y - dockTop - 12 - topLimit() - (GRID_Y + 8 + HINT_H + PAD) - 4
	local cols, rows = Rules.grid(#names, roomX, roomY, Config, L.phone)
	cols = math.min(cols, math.max(3, #names)) -- sedikit tool → jendela selebar isinya
	local gridW = cols * Config.cell + (cols - 1) * Config.cellGap + 4 + 4 -- + padding + ruang scrollbar
	local gridH = rows * Config.cellH + (rows - 1) * Config.cellGap + 4
	inv.Size = UDim2.fromOffset(gridW + PAD * 2, GRID_Y + gridH + 8 + HINT_H + PAD)
	inv.Position = UDim2.new(0.5, 0, 1, -(dockTop + 12))
	grid.Size = UDim2.fromOffset(gridW, gridH)
end

local refreshQueued = false
local function refresh()
	scan()
	Rules.sync(state, names, os.clock(), Config.respawnHold)
	renderDock()
	if invOpen then
		renderInventory()
		layoutInventory()
	end
end
local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refresh()
	end)
end

-- ── buka / tutup / sembunyikan ────────────────────────────────────────────────────────────────────────────────────
local setOpen -- function(open)

local function coordinator()
	return _G.PanelCoordinator
end

function setOpen(open)
	if open == invOpen then
		return
	end
	invOpen = open
	tip.Visible = false
	if open then
		disableDefault()
		local pc = coordinator()
		if pc and pc.NotifyOpen then
			pcall(pc.NotifyOpen, "Inventory")
		end
		search.Text = ""
		refresh()
		inv.Visible = true
		invScale.Scale = 0.96
		tw(invScale, 0.14, { Scale = 1 })
		layoutInventory()
	else
		pcall(search.ReleaseFocus, search)
		inv.Visible = false
		dropTarget = nil
		press = nil -- seret yang sedang berjalan dibatalkan
		if drag then
			drag = nil
			ghost.Visible = false
			grid.ScrollingEnabled = true
			suppressClick = os.clock() + 0.2
		end
		local pc = coordinator()
		if pc and pc.NotifyClose then
			pcall(pc.NotifyClose, "Inventory")
		end
		renderDock()
	end
end

local function setHidden(on)
	hidden = on
	tip.Visible = false
	renderDock()
end

bagBtn.Activated:Connect(function()
	setOpen(not invOpen)
end)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)
hideBtn.Activated:Connect(function()
	setHidden(not hidden)
end)
bagBtn.MouseEnter:Connect(function()
	if UIS:GetLastInputType() == Enum.UserInputType.Touch or invOpen then
		return
	end
	tipName.Text = "Inventory"
	tipSub.Text = if UIS.KeyboardEnabled then "Tekan ` untuk buka / tutup" else "Ketuk untuk buka"
	tipSub.Visible = true
	local p = bagBtn.AbsolutePosition - gui.AbsolutePosition
	tip.Position = UDim2.fromOffset(p.X + bagBtn.AbsoluteSize.X / 2, p.Y - 8)
	tip.Visible = true
end)
bagBtn.MouseLeave:Connect(function()
	tip.Visible = false
end)
closeBtn.MouseEnter:Connect(function()
	tw(closeBtn, 0.1, { TextColor3 = T.TEXT })
end)
closeBtn.MouseLeave:Connect(function()
	tw(closeBtn, 0.1, { TextColor3 = T.TEXT_DIM })
end)

local searchGen = 0
search:GetPropertyChangedSignal("Text"):Connect(function()
	searchGen += 1
	local g = searchGen
	task.delay(0.08, function()
		if g == searchGen and invOpen then
			renderInventory()
		end
	end)
end)

-- ── seret (inventory terbuka): kartu → slot = atur / tukar · slot → luar hotbar = lepas ─────────────────────────────
local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Pusat bayangan di ruang AbsolutePosition: posisi awal tombol + geser jari/mouse (tanpa asumsi inset layar).
local function ghostCenter(input)
	local d = input.Position - press.start
	return press.originPos + press.originSize / 2 + Vector2.new(d.X, d.Y)
end

local function slotAt(p)
	for i = 1, L.count do
		local b = slots[i].btn
		if b.Visible then
			local a, s = b.AbsolutePosition, b.AbsoluteSize
			local half = L.gap / 2
			if p.X >= a.X - half and p.X <= a.X + s.X + half and p.Y >= a.Y - half and p.Y <= a.Y + s.Y + half then
				return i
			end
		end
	end
	return nil
end

local function inside(obj, p)
	local a, s = obj.AbsolutePosition, obj.AbsoluteSize
	return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

local function startDrag()
	if not press or drag or not press.name then
		return
	end
	drag = { name = press.name, fromSlot = press.fromSlot }
	local tool = tools[press.name]
	local tex = texOf(tool)
	ghost.Size = UDim2.fromOffset(L.S, L.S)
	ghostIcon.Image = tex or ""
	ghostIcon.Visible = tex ~= nil
	ghostLabel.Text = if tex then "" else press.name
	ghostStroke.Color = T.ACCENT
	ghost.BackgroundColor3 = T.CARD_HOVER
	grid.ScrollingEnabled = false
	tip.Visible = false
	suppressClick = math.huge -- klik pelepasan seret diabaikan, urutan Activated vs InputEnded tidak penting
end

local function moveDrag(input)
	if not drag then
		return
	end
	local c = ghostCenter(input)
	local origin = gui.AbsolutePosition
	ghost.Position = UDim2.fromOffset(c.X - origin.X - L.S / 2, c.Y - origin.Y - L.S / 2)
	ghost.Visible = true
	local t = slotAt(c)
	if t ~= dropTarget then
		dropTarget = t
		renderDock()
	end
end

local function endPress(input)
	if not press then
		return
	end
	local p = press
	press = nil
	if not drag then
		return
	end
	local d = drag
	drag = nil
	ghost.Visible = false
	grid.ScrollingEnabled = true
	suppressClick = os.clock() + 0.2
	local c = p.originPos + p.originSize / 2 + Vector2.new(input.Position.X - p.start.X, input.Position.Y - p.start.Y)
	local target = slotAt(c)
	dropTarget = nil
	if target then
		Rules.move(state, d.name, target)
	elseif d.fromSlot and not inside(dock, c) then
		Rules.unassign(state, d.name)
	end
	refresh()
end

function beginPress(input, name, fromSlot, origin)
	if not isPointer(input) or not invOpen or not name or press then
		return
	end
	press = {
		input = input, name = name, fromSlot = fromSlot, start = input.Position, t0 = os.clock(),
		touch = input.UserInputType == Enum.UserInputType.Touch,
		originPos = origin.AbsolutePosition, originSize = origin.AbsoluteSize,
	}
	if press.touch then
		local mine = press
		task.delay(Config.touchHoldDrag, function()
			if press == mine and not drag then
				startDrag() -- tahan tanpa digulir → mulai seret
				moveDrag(mine.input)
			end
		end)
	end
end

UIS.InputChanged:Connect(function(input)
	if not press then
		return
	end
	if press.touch then
		if input ~= press.input then
			return
		end
		local moved = (input.Position - press.start).Magnitude
		if not drag and moved > 10 then
			press = nil -- bergerak sebelum tahan selesai = menggulir daftar, bukan seret
			return
		end
		moveDrag(input)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement then
		local moved = (input.Position - press.start).Magnitude
		if not drag and moved >= Config.dragThreshold then
			startDrag()
		end
		moveDrag(input)
	end
end)

UIS.InputEnded:Connect(function(input)
	if not press then
		return
	end
	if (press.touch and input == press.input) or (not press.touch and input.UserInputType == Enum.UserInputType.MouseButton1) then
		endPress(input)
	end
end)

-- ── tombol keyboard & gamepad ─────────────────────────────────────────────────────────────────────────────────────
local toggleKeys = {}
for _, k in Config.toggleKeys do
	local ok, code = pcall(function()
		return Enum.KeyCode[k]
	end)
	if ok and code then
		toggleKeys[code] = true
	end
end

local function currentSlot()
	local eq = equippedTool()
	return eq and Rules.slotOf(state, eq.Name) or nil
end

-- Sedang mengetik? (TextBox kita / skrip lain, atau bar chat TextChatService yang ada di CoreGui)
local function typing()
	if UIS:GetFocusedTextBox() then
		return true
	end
	local ok, focused = pcall(function()
		local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		return bar and bar.IsFocused
	end)
	return ok and focused == true
end

UIS.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		-- Seperti backpack Roblox: diabaikan saat mengetik (chat / kotak cari) atau menu Roblox terbuka. ` sengaja tidak
		-- memakai `processed` (di Studio tombol ini bisa ditandai processed walau tidak sedang mengetik).
		if typing() or GuiService.MenuIsOpen then
			return
		end
		local key = input.KeyCode
		if toggleKeys[key] then
			setOpen(not invOpen)
			return
		end
		if key == Enum.KeyCode.Escape then
			if invOpen and not processed then
				setOpen(false)
			end
			return
		end
		local i = Rules.keyToSlot(key.Name)
		if i and i <= L.count and not processed then -- hanya slot yang tampil (layar sempit = slot lebih sedikit)
			useSlot(i)
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1 then
		if processed then
			return
		end
		local present = {}
		for _, n in names do
			present[n] = true
		end
		local i = Rules.cycle(state, present, currentSlot(), if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1, L.count)
		if i then
			useSlot(i)
		end
	end
end)

-- ── pantau tool, karakter, layar, tema ────────────────────────────────────────────────────────────────────────────
local bpConns, charConns = {}, {}
local function watch(list, parent)
	for _, c in list do
		c:Disconnect()
	end
	table.clear(list)
	if parent then
		table.insert(list, parent.ChildAdded:Connect(queueRefresh))
		table.insert(list, parent.ChildRemoved:Connect(queueRefresh))
	end
end
local function bindBackpack()
	watch(bpConns, player:FindFirstChildOfClass("Backpack"))
	queueRefresh()
end
local function bindCharacter(char)
	watch(charConns, char)
	queueRefresh()
	task.delay(1, disableDefault)
end
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then
		bindBackpack() -- Backpack dibuat ulang setiap respawn
	end
end)
player.CharacterAdded:Connect(bindCharacter)
bindBackpack()
if player.Character then
	bindCharacter(player.Character)
end

Responsive.OnChange(function()
	layoutDock()
	renderDock()
	if invOpen then
		layoutInventory()
	end
end)
ThemeColor.onChanged(function()
	renderDock()
	renderInventory()
end)

task.spawn(function()
	local t0 = os.clock()
	while not (_G.PanelCoordinator and _G.PanelCoordinator.Register) and os.clock() - t0 < 30 do
		task.wait(0.2)
	end
	local pc = _G.PanelCoordinator
	if pc and pc.Register then
		pc.Register("Inventory", function()
			setOpen(false)
		end)
	end
end)

_G.Inventory = {
	Open = function()
		setOpen(true)
	end,
	Close = function()
		setOpen(false)
	end,
	Toggle = function()
		setOpen(not invOpen)
	end,
	IsOpen = function()
		return invOpen
	end,
	SetHidden = setHidden,
}

layoutDock()
refresh()
print(("[Inventory] siap | %d slot | ` = inventory"):format(L.count))
