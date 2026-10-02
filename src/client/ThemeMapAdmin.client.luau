-- StarterPlayerScripts/ThemeMapAdmin (LocalScript) — panel admin tema map (themeMap, claude/Rencana_Tema.md).
-- Dibuka dari Menu › Settings › ADMIN › "Tema map" (SettingsClient memanggil _G.ToggleThemeMap). Hanya untuk IsAdmin;
-- server ThemeMap mengecek rank, jeda & daftar putih lagi — panel ini hanya tampilan.
--   Pilih tema · Mulai (Sekarang / Besok 00:00 WIB) · Selesai (Tanpa batas / 23:59 WIB / 24 jam) → Terapkan (tekan 2×).
-- Membuka panel = PanelCoordinator.NotifyOpen("ThemeMap") → menu tertutup (tidak bertumpuk di HP portrait).
-- State dari atribut ReplicatedStorage.ThemeMapRemotes: Ready, Active, State (JSON), Missing (JSON).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Didaftarkan lebih dulu: SettingsClient bisa memanggil sebelum remote siap.
local isOpen = false
_G.ToggleThemeMap = function() end
_G.ThemeMapMenu = { IsOpen = function() return isOpen end }

local Config = require(RS:WaitForChild("Config"):WaitForChild("ThemeMap"))
local remotes = RS:WaitForChild("ThemeMapRemotes", 60)
local setFn = remotes and remotes:WaitForChild("Set", 30)
if not setFn then
	warn("[ThemeMapAdmin] ThemeMapRemotes.Set tidak ada — server ThemeMap tidak jalan?")
	return
end
local Responsive = require(RS:WaitForChild("CustomUIModules"):WaitForChild("Responsive"))

local waited = 0
while not _G.MenuConfig and waited < 10 do
	task.wait(0.1)
	waited += 0.1
end
local T = (_G.MenuConfig and _G.MenuConfig.theme) or {
	BG = Color3.fromRGB(16, 16, 17),
	CARD = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	LINE = Color3.fromRGB(255, 255, 255),
	TEXT = Color3.fromRGB(238, 238, 240),
	TEXT_DIM = Color3.fromRGB(148, 148, 154),
	ACCENT = Color3.fromRGB(212, 175, 55),
	DANGER = Color3.fromRGB(226, 96, 96),
	SUCCESS = Color3.fromRGB(96, 196, 132),
}
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold,
	MEDIUM = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}
local ON_ACCENT = Color3.fromRGB(18, 18, 20)
local SUCCESS = T.SUCCESS or Color3.fromRGB(96, 196, 132)

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
local function label(parent, text, size, color, font, order, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color, Font = font,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, size + 4), LayoutOrder = order or 0, Parent = parent,
	})
	for k, v in props or {} do l[k] = v end
	return l
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des" }
local function fmt(t)
	if type(t) ~= "number" then return "-" end
	local d = os.date("!*t", math.floor(t + Config.utcOffset * 3600))
	return ("%02d %s %02d:%02d WIB"):format(d.day, MONTHS[d.month], d.hour, d.min)
end
local function decode(attr)
	local raw = remotes:GetAttribute(attr)
	if type(raw) ~= "string" then return nil end
	local ok, v = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok then v else nil
end
local function labelOf(id)
	local t = Config.find(id)
	return t and t.label or tostring(id)
end

-- ── kerangka ──────────────────────────────────────────────────────────────────────────────────────────────────────
local old = playerGui:FindFirstChild("ThemeMapGui")
if old then old:Destroy() end
local gui = new("ScreenGui", { Name = "ThemeMapGui", ResetOnSpawn = false, Enabled = false, DisplayOrder = 12, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
local frame = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = T.BG, BorderSizePixel = 0,
	Active = true, ClipsDescendants = true, Parent = gui, -- Active: klik tidak tembus ke tombol di belakang (DN16c)
})
corner(frame, 16)
stroke(frame, T.LINE, 0.88)
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, Parent = frame })
label(header, "Tema map", 15, T.TEXT, FONT.BOLD, 0, { Position = UDim2.new(0, 14, 0, 12), Size = UDim2.new(1, -60, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
local closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.new(0, 30, 0, 30), BackgroundTransparency = 1,
	Text = "✕", TextColor3 = T.TEXT_DIM, TextSize = 18, Font = FONT.MEDIUM, AutoButtonColor = false, Parent = header,
})
local body = new("ScrollingFrame", {
	Position = UDim2.new(0, 0, 0, 42), Size = UDim2.new(1, 0, 1, -42), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = frame,
})
new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), Parent = body })
local list = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

-- status
local statusCard = new("Frame", { BackgroundColor3 = T.CARD, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = body })
corner(statusCard, 10)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = statusCard })
new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = statusCard })
local activeLbl = label(statusCard, "AKTIF  -", 13, T.ACCENT, FONT.BOLD, 1)
local whoLbl = label(statusCard, "", 11, T.TEXT_DIM, FONT.REGULAR, 2)

-- pilihan tema
label(body, "TEMA", 10, T.TEXT_DIM, FONT.MEDIUM, 2)
local themeBox = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = body })
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = themeBox })

local sel = { id = nil, start = "now", stop = "none" }
local rows = {}
local missing = {}
local state = {}

local function chipRow(order, title, items)
	label(body, title, 10, T.TEXT_DIM, FONT.MEDIUM, order)
	local box = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order + 1, Parent = body })
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 30), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	local chips = {}
	for i, it in items do
		local b = new("TextButton", {
			Text = it.label, TextSize = 12, Font = FONT.MEDIUM, AutoButtonColor = false, BackgroundColor3 = T.CARD,
			TextColor3 = T.TEXT, LayoutOrder = i, Parent = box,
		})
		corner(b, 8)
		chips[it.key] = b
	end
	return chips
end
local startChips = chipRow(4, "MULAI", Config.starts)
local endChips = chipRow(6, "SELESAI", Config.ends)

local applyBtn = new("TextButton", {
	Text = "Terapkan ke semua server", TextSize = 13, Font = FONT.BOLD, AutoButtonColor = false, BackgroundColor3 = T.ACCENT,
	TextColor3 = ON_ACCENT, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 8, Parent = body,
})
corner(applyBtn, 9)
local msgLbl = label(body, "", 11, T.TEXT_DIM, FONT.REGULAR, 9)
label(body, "RIWAYAT", 10, T.TEXT_DIM, FONT.MEDIUM, 10)
local logLbl = label(body, "", 11, T.TEXT_DIM, FONT.REGULAR, 11)

-- ── tampilan ──────────────────────────────────────────────────────────────────────────────────────────────────────
local confirmUntil = 0
local busy = false

local function scheduleText(s)
	if not s or s.id == nil then return "" end
	local a = if s.fromT then "mulai " .. fmt(s.fromT) else "mulai sekarang"
	local b = if s.untilT then "selesai " .. fmt(s.untilT) else "tanpa batas"
	return a .. " · " .. b
end

local function paint()
	local active = remotes:GetAttribute("Active") or Config.default
	local ready = remotes:GetAttribute("Ready") == true
	activeLbl.Text = "AKTIF  " .. labelOf(active) .. (if ready then "" else "  ·  server belum siap")
	local lines = {}
	if state.id and state.id ~= Config.default then
		table.insert(lines, labelOf(state.id) .. ": " .. scheduleText(state))
	end
	if state.byName then
		table.insert(lines, ("diganti %s · %s"):format(state.byName, fmt(state.at)))
	end
	whoLbl.Text = table.concat(lines, "\n")
	whoLbl.Visible = #lines > 0
	for id, r in rows do
		local chosen = sel.id == id
		local bad = missing[id]
		r.btn.BackgroundColor3 = if chosen then T.CARD_HOVER else T.CARD
		r.stroke.Transparency = if chosen then 0.2 else 0.94
		r.stroke.Color = if chosen then T.ACCENT else T.LINE
		r.name.TextColor3 = if bad then T.TEXT_DIM else T.TEXT
		r.desc.Text = if bad then ("aset belum ada di server ini (%s)"):format(bad) else r.theme.desc
		r.tag.Visible = id == active
	end
	local isDefault = sel.id == Config.default
	for key, b in startChips do
		local on = sel.start == key
		local off = isDefault and key ~= "now"
		b.BackgroundColor3 = if on then T.ACCENT else T.CARD
		b.TextColor3 = if on then ON_ACCENT elseif off then T.TEXT_DIM else T.TEXT
		b.AutoButtonColor = false
	end
	for key, b in endChips do
		local on = sel.stop == key
		local off = isDefault and key ~= "none"
		b.BackgroundColor3 = if on then T.ACCENT else T.CARD
		b.TextColor3 = if on then ON_ACCENT elseif off then T.TEXT_DIM else T.TEXT
	end
	local canApply = ready and sel.id ~= nil and not missing[sel.id] and not busy
	applyBtn.BackgroundColor3 = if canApply then T.ACCENT else T.CARD_HOVER
	applyBtn.TextColor3 = if canApply then ON_ACCENT else T.TEXT_DIM
	if busy then
		applyBtn.Text = "Menyimpan…"
	elseif os.clock() < confirmUntil then
		applyBtn.Text = "Tekan lagi untuk konfirmasi"
	else
		applyBtn.Text = "Terapkan ke semua server"
	end
	local log = {}
	for i, e in state.log or {} do
		if i > 3 then break end
		local extra = if e.untilT then " · s/d " .. fmt(e.untilT) else ""
		table.insert(log, ("%s  %s · %s%s"):format(fmt(e.at), labelOf(e.id), tostring(e.byName), extra))
	end
	logLbl.Text = if #log > 0 then table.concat(log, "\n") else "belum ada"
end

local function readState()
	state = decode("State") or {}
	missing = {}
	for _, m in decode("Missing") or {} do -- Roblox mengirim [] untuk daftar kosong
		if type(m) == "table" and type(m.id) == "string" then missing[m.id] = m.why or "aset tidak ada" end
	end
	if sel.id == nil then
		sel.id = remotes:GetAttribute("Active") or Config.default
	end
	paint()
end

for i, theme in Config.list do
	local btn = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = T.CARD, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, Parent = themeBox,
	})
	corner(btn, 10)
	local st = stroke(btn, T.LINE, 0.94)
	local name = label(btn, theme.label, 13, T.TEXT, FONT.MEDIUM, 0, { Position = UDim2.new(0, 10, 0, 5), Size = UDim2.new(1, -80, 0, 16), AutomaticSize = Enum.AutomaticSize.None })
	local desc = label(btn, theme.desc, 11, T.TEXT_DIM, FONT.REGULAR, 0, { Position = UDim2.new(0, 10, 0, 23), Size = UDim2.new(1, -20, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
	local tag = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.new(0, 52, 0, 16), BackgroundColor3 = SUCCESS,
		Text = "AKTIF", TextSize = 10, Font = FONT.BOLD, TextColor3 = ON_ACCENT, Visible = false, Parent = btn,
	})
	corner(tag, 6)
	rows[theme.id] = { btn = btn, stroke = st, name = name, desc = desc, tag = tag, theme = theme }
	btn.Activated:Connect(function()
		sel.id = theme.id
		if theme.id == Config.default then
			sel.start, sel.stop = "now", "none"
		end
		confirmUntil = 0
		paint()
	end)
end
for key, b in startChips do
	b.Activated:Connect(function()
		if sel.id == Config.default and key ~= "now" then return end
		sel.start = key
		confirmUntil = 0
		paint()
	end)
end
for key, b in endChips do
	b.Activated:Connect(function()
		if sel.id == Config.default and key ~= "none" then return end
		sel.stop = key
		confirmUntil = 0
		paint()
	end)
end

local REASON = {
	invalid = "pilihan tidak sah",
	rank = "hanya admin (rank ≥ 250)",
	notready = "server belum membaca DataStore, coba lagi sebentar",
	missing = "aset tema belum ada di server ini",
	busy = "sedang menyimpan, tunggu",
	save = "gagal menyimpan, tidak ada yang berubah — coba lagi",
}
applyBtn.Activated:Connect(function()
	if busy or not sel.id or missing[sel.id] or remotes:GetAttribute("Ready") ~= true then return end
	if os.clock() >= confirmUntil then
		confirmUntil = os.clock() + 3
		msgLbl.Text = ("%s · %s"):format(labelOf(sel.id), if sel.id == Config.default then "lepas dekor sekarang" else ("%s / %s"):format(sel.start == "now" and "sekarang" or "besok 00:00 WIB", sel.stop))
		msgLbl.TextColor3 = T.TEXT_DIM
		paint()
		task.delay(3.05, paint)
		return
	end
	confirmUntil = 0
	busy = true
	paint()
	local ok, r = pcall(setFn.InvokeServer, setFn, sel.id, sel.start, sel.stop)
	busy = false
	if ok and type(r) == "table" and r.ok then
		msgLbl.Text = "✓ tersimpan · semua server ikut dalam beberapa detik"
		msgLbl.TextColor3 = SUCCESS
	else
		local why = ok and type(r) == "table" and r.reason or "tidak ada jawaban server"
		msgLbl.Text = "✕ " .. (if why == "cooldown" then ("tunggu %s dtk"):format(tostring(r.wait or "")) else (REASON[why] or tostring(why)))
		msgLbl.TextColor3 = T.DANGER
	end
	readState()
end)

-- ── buka / tutup ──────────────────────────────────────────────────────────────────────────────────────────────────
local function layout()
	local ok, p = pcall(Responsive.Panel)
	p = if ok and type(p) == "table" then p else {}
	local vp = workspace.CurrentCamera.ViewportSize
	local mobile = p.device == "mobile"
	local w = math.clamp(math.floor(vp.X * (if mobile then 0.92 else 0.33)), 300, 400)
	local h = math.clamp(math.floor(vp.Y * 0.7), 300, 520)
	frame.Size = UDim2.new(0, math.min(w, vp.X - 16), 0, math.min(h, list.AbsoluteContentSize.Y + 42 + 16))
	frame.Position = UDim2.new(0.5, 0, 1, -(p.bottomInset or 10))
end
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	if isOpen then layout() end
end)
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
		sel.id = remotes:GetAttribute("Active") or Config.default
		sel.start, sel.stop = "now", "none"
		msgLbl.Text = ""
		readState()
		layout()
		if pc and pc.NotifyOpen then pcall(pc.NotifyOpen, "ThemeMap") end
	elseif pc and pc.NotifyClose then
		pcall(pc.NotifyClose, "ThemeMap")
	end
	if _G.ThemeMapMenu.OnChanged then pcall(_G.ThemeMapMenu.OnChanged, open) end
end
task.spawn(function()
	local t0 = os.clock()
	while not (coordinator() and coordinator().Register) and os.clock() - t0 < 30 do task.wait(0.2) end
	local pc = coordinator()
	if pc and pc.Register then pc.Register("ThemeMap", function() setOpen(false) end) end
end)

_G.ToggleThemeMap = function() setOpen(not isOpen) end
_G.ThemeMapMenu.Open = function() setOpen(true) end
_G.ThemeMapMenu.Close = function() setOpen(false) end
_G.ThemeMapMenu.Gui = gui

closeBtn.Activated:Connect(function() setOpen(false) end)
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)
player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
	if player:GetAttribute("IsAdmin") ~= true then setOpen(false) end
end)
for _, a in { "State", "Missing", "Active", "Ready" } do
	remotes:GetAttributeChangedSignal(a):Connect(function()
		if isOpen then readState() end
	end)
end
