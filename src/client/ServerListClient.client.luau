-- StarterPlayerScripts/ServerListClient  (LocalScript)
-- Tombol 🌐 di topbar (kiri tombol "/" lewat _G.TopbarLayout, order 22 baris
-- "info") + panel SERVER LIST responsif: 2 kolom di layar lebar, 1 kolom di HP.
-- Data dari ServerListRemotes (lihat src/server/ServerList.server.luau).

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local UIS      = game:GetService("UserInputService")
local TweenSvc = game:GetService("TweenService")

local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = RS:WaitForChild("ServerListRemotes", 30)
if not remotes then
	warn("[ServerList] ServerListRemotes tidak ditemukan")
	return
end
local getFn    = remotes:WaitForChild("GetServers")
local joinEv   = remotes:WaitForChild("JoinServer")
local noticeEv = remotes:WaitForChild("Notice")

-- ── Tema: ThemeColor.tokens (themeColor) — T.X dibaca saat melukis ─────────
do
	local waited = 0
	while not _G.MenuConfig and waited < 10 do task.wait(0.1); waited += 0.1 end
end
local T = ThemeColor.tokens
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold, MEDIUM = Enum.Font.BuilderSansMedium, REGULAR = Enum.Font.BuilderSans,
}
local TF = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TS = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local BTN_SZ       = 40
local CARD_H       = 92
local GAP          = 8
local MAX_FACES    = 5
local AUTO_REFRESH = 15
local HOTBAR_SPACE = 96   -- ruang di bawah untuk hotbar tool

-- ── helper ─────────────────────────────────────────────────────────────────
local function new(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do if k ~= "Parent" then o[k] = v end end
	if props.Parent then o.Parent = props.Parent end
	return o
end
local function corner(r, p) new("UICorner", { CornerRadius = UDim.new(0, r), Parent = p }) end
local function stroke(p, tr, color)
	return new("UIStroke", { Color = color or T.LINE, Thickness = 1, Transparency = tr or 0.92,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p })
end
local function tw(o, info, props) if o and o.Parent then TweenSvc:Create(o, info, props):Play() end end
local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return Vector2.new(1280, 720) end
	return vp
end
local function panelTop()
	if _G.TopbarLayout and _G.TopbarLayout.contentTop then
		local ok, v = pcall(_G.TopbarLayout.contentTop)
		if ok and type(v) == "number" then return v end
	end
	return 64
end
local function shortId(id)
	local s = tostring(id):gsub("^studio%-", ""):gsub("%-", "")
	return string.upper(string.sub(s, 1, 5))
end
local function fmtUp(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(m)
end

-- Ikon globe digambar (bukan emoji) supaya warnanya mengikuti tema.
local function globe(parent, size, color, pos)
	local g = new("Frame", { Size = UDim2.new(0, size, 0, size), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos or UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, Parent = parent })
	local ring = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Parent = g })
	corner(size, ring)
	new("UIStroke", { Color = color, Thickness = 1.6, Parent = ring })
	local mer = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.45, 0, 1, 0), BackgroundTransparency = 1, Parent = g })
	corner(size, mer)
	new("UIStroke", { Color = color, Thickness = 1.3, Parent = mer })
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 1.4), BackgroundColor3 = color, BorderSizePixel = 0, Parent = g })
	return g
end

-- ── UI dasar ───────────────────────────────────────────────────────────────
local gui = new("ScreenGui", { Name = "ServerListGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
ThemeColor.mark(gui)

local overlay = new("TextButton", { Name = "Overlay", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(),
	BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false, Parent = gui })

local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64),
	BackgroundColor3 = T.BG, Visible = false, Parent = gui })
corner(14, panel); ThemeColor.glow(stroke(panel, 0.85, T.ACCENT), "panel") -- garis tepi bergerak (themeColor)

-- Penanda bisa digeser (garis kecil di tengah atas, di DALAM panel → tidak menimpa tombol topbar).
local grip = new("Frame", { Name = "Grip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.new(0, 28, 0, 3), BackgroundColor3 = T.ACCENT, BackgroundTransparency = 0.35, BorderSizePixel = 0,
	Parent = panel })
corner(2, grip)
local header = new("Frame", { Size = UDim2.new(1, -24, 0, 36), Position = UDim2.new(0, 12, 0, 10),
	BackgroundTransparency = 1, Active = true, Parent = panel })
globe(header, 16, T.TEXT, UDim2.new(0, 8, 0.5, 0))
local titleLbl = new("TextLabel", { Position = UDim2.new(0, 26, 0, 0), Size = UDim2.new(1, -210, 1, 0), BackgroundTransparency = 1,
	Text = "SERVER LIST", TextColor3 = T.TEXT, Font = FONT.BOLD, TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
local countLbl = new("TextLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -124, 0.5, 0),
	Size = UDim2.new(0, 70, 1, 0), BackgroundTransparency = 1, Text = "", TextColor3 = T.TEXT_DIM,
	Font = FONT.MEDIUM, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = header })
local refreshBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -42, 0.5, 0),
	Size = UDim2.new(0, 74, 0, 32), BackgroundColor3 = T.CARD, Text = "Refresh", TextColor3 = T.TEXT,
	Font = FONT.BOLD, TextSize = 13, AutoButtonColor = false, Parent = header })
corner(10, refreshBtn)
local closeBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.new(0, 32, 0, 32), BackgroundColor3 = T.DANGER, Text = "X", TextColor3 = Color3.new(1, 1, 1),
	Font = FONT.BOLD, TextSize = 16, AutoButtonColor = false, Parent = header })
corner(10, closeBtn)

local search = new("TextBox", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 54),
	BackgroundColor3 = T.CARD, Text = "", PlaceholderText = "Search server ID...", PlaceholderColor3 = T.TEXT_DIM,
	TextColor3 = T.TEXT, Font = FONT.REGULAR, TextSize = 14, ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
corner(10, search)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = search })

local scroll = new("ScrollingFrame", { Position = UDim2.new(0, 12, 0, 98), Size = UDim2.new(1, -24, 1, -110),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = T.ACCENT,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = panel })
new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2),
	PaddingRight = UDim.new(0, 6), Parent = scroll }) -- garis tepi kartu tidak terpotong
local grid = new("UIGridLayout", { CellPadding = UDim2.new(0, GAP, 0, GAP), CellSize = UDim2.new(0.5, -GAP / 2, 0, CARD_H),
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

local emptyLbl = new("TextLabel", { Position = UDim2.new(0, 12, 0, 110), Size = UDim2.new(1, -24, 0, 40),
	BackgroundTransparency = 1, Text = "Loading...", TextColor3 = T.TEXT_DIM, Font = FONT.MEDIUM, TextSize = 14,
	Visible = false, Parent = panel })

local toast = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0, 280, 0, 34), BackgroundColor3 = T.CARD, Text = "", TextColor3 = T.TEXT,
	Font = FONT.MEDIUM, TextSize = 13, TextWrapped = true, Visible = false, ZIndex = 20, Parent = gui })
corner(10, toast); stroke(toast, 0.6, T.ACCENT)
local toastGen = 0
local function showToast(text)
	toastGen += 1
	local g = toastGen
	toast.Text = tostring(text)
	toast.Position = UDim2.new(0.5, 0, 0, panelTop())
	toast.Visible = true
	task.delay(2.5, function() if g == toastGen then toast.Visible = false end end)
end
noticeEv.OnClientEvent:Connect(showToast)

-- Drag & drop lewat judul panel (helper yang sama dengan panel "/").
-- customPos/reclamp dideklarasi DI SINI (sebelum dipakai); dulu di bawah -> jadi global (selene).
-- Posisi bawaan = TENGAH layar (antara topbar & hotbar); setelah digeser, dibuka lagi → kembali ke tengah.
local customPos, reclamp, isDragging = false, nil, nil
if _G.MenuUI and _G.MenuUI.makeDraggable then
	local ok, r, d = pcall(_G.MenuUI.makeDraggable, panel, { header, titleLbl }, function() customPos = true end)
	if ok and type(r) == "function" then reclamp, isDragging = r, d end
end
local function centerTop(h)
	local vp, top = viewport(), panelTop()
	return math.max(top, math.min(math.floor((vp.Y - h) / 2), math.floor(vp.Y) - HOTBAR_SPACE - h))
end

-- ── ukuran responsif ──────────────────────────────────────────────────────
local cols, panelW, maxH = 2, 600, 400
local function fitHeight(count)
	local rows = math.max(1, math.ceil(count / cols))
	local want = 110 + rows * CARD_H + (rows - 1) * GAP + 8
	local h = math.clamp(want, math.min(200, maxH), maxH)
	panel.Size = UDim2.new(0, panelW, 0, h)
	if customPos then
		if reclamp then pcall(reclamp) end
	elseif panel.Visible then
		tw(panel, TS, { Position = UDim2.new(0.5, 0, 0, centerTop(h)) }) -- tinggi berubah → tetap di tengah
	end
end
local function layout()
	local vp, top = viewport(), panelTop()
	if vp.X < 520 then
		panelW = math.floor(vp.X) - 24 -- HP portrait: hampir selebar layar
	else
		panelW = math.min(math.floor(math.clamp(vp.X * 0.5, 300, 640)), math.floor(vp.X) - 16)
	end
	maxH = math.max(160, math.floor(math.min(vp.Y * 0.8, vp.Y - top - HOTBAR_SPACE)))
	cols = (panelW >= 520) and 2 or 1
	grid.CellSize = (cols == 2) and UDim2.new(0.5, -GAP / 2, 0, CARD_H) or UDim2.new(1, 0, 0, CARD_H)
	panel.Size = UDim2.new(0, panelW, 0, panel.Size.Y.Offset > 0 and panel.Size.Y.Offset or 200)
	if not customPos then panel.Position = UDim2.new(0.5, 0, 0, centerTop(panel.Size.Y.Offset)) end
end

-- ── kartu server ──────────────────────────────────────────────────────────
local selfId
local function tag(parent, text, color)
	local l = new("TextLabel", { Size = UDim2.new(0, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color, Text = text, TextColor3 = T.ON_ACCENT, Font = FONT.BOLD, TextSize = 11, Parent = parent })
	corner(6, l)
	new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7), Parent = l })
	return l
end

local newestVer = 0
local function card(v, order)
	local isSelf = v.id == selfId
	local n, max = tonumber(v.n) or 0, tonumber(v.max) or 0
	local full = max > 0 and n >= max
	local c = new("Frame", { LayoutOrder = order, BackgroundColor3 = T.CARD, Parent = scroll })
	corner(12, c); stroke(c, isSelf and 0.4 or 0.92, isSelf and T.ACCENT or T.LINE)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = c })

	new("TextLabel", { Size = UDim2.new(1, -80, 0, 22), BackgroundTransparency = 1, Text = "SERVER " .. shortId(v.id),
		TextColor3 = isSelf and T.ACCENT or T.TEXT, Font = FONT.BOLD, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = c })
	new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 80, 0, 22),
		BackgroundTransparency = 1, Text = ("👤 %d/%d"):format(n, max), TextColor3 = full and T.DANGER or T.TEXT,
		Font = FONT.BOLD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = c })

	local tags = new("Frame", { Position = UDim2.new(0, 0, 0, 23), Size = UDim2.new(1, -96, 0, 18),
		BackgroundTransparency = 1, Parent = c })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = tags })
	if isSelf then tag(tags, "THIS SERVER", T.ACCENT) end
	if v.live then tag(tags, "🔴 LIVE", T.DANGER) end
	if newestVer > 0 and (tonumber(v.ver) or 0) > 0 and (tonumber(v.ver) or 0) < newestVer then
		tag(tags, "OLD VERSION", T.TEXT_DIM)
	end

	new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.new(0, 90, 0, 14),
		BackgroundTransparency = 1, Text = "Up " .. fmtUp((tonumber(v.t) or 0) - (tonumber(v.up) or 0)),
		TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Parent = c })

	local faces = new("Frame", { Position = UDim2.new(0, 0, 1, -28), Size = UDim2.new(1, -96, 0, 28),
		BackgroundTransparency = 1, Parent = c })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, -6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = faces })
	local uids = type(v.uids) == "table" and v.uids or {}
	local shown = math.min(#uids, MAX_FACES)
	for i = 1, shown do
		local img = new("ImageLabel", { LayoutOrder = i, Size = UDim2.new(0, 26, 0, 26), BackgroundColor3 = T.BG,
			Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(tonumber(uids[i]) or 0), Parent = faces })
		corner(13, img); stroke(img, 0.2, T.CARD)
	end
	if n > shown then
		local more = new("TextLabel", { LayoutOrder = 99, Size = UDim2.new(0, 34, 0, 26), BackgroundColor3 = T.CARD_HOVER,
			Text = "+" .. (n - shown), TextColor3 = T.TEXT, Font = FONT.BOLD, TextSize = 11, Parent = faces })
		corner(13, more)
	end

	local label, color, txt = "JOIN", T.SUCCESS, T.ON_ACCENT
	if isSelf then label, color = "PLAYING", T.ACCENT elseif full then label, color, txt = "FULL", T.DANGER, Color3.new(1, 1, 1) end
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 88, 0, 30), BackgroundColor3 = color, Text = label, TextColor3 = txt,
		Font = FONT.BOLD, TextSize = 13, AutoButtonColor = false, Parent = c })
	corner(10, btn)
	if not isSelf and not full then
		btn.MouseEnter:Connect(function() tw(btn, TF, { BackgroundTransparency = 0.15 }) end)
		btn.MouseLeave:Connect(function() tw(btn, TF, { BackgroundTransparency = 0 }) end)
		btn.Activated:Connect(function()
			btn.Text = "..."
			joinEv:FireServer(v.id)
			task.delay(3, function() if btn.Parent then btn.Text = "JOIN" end end)
		end)
	end
end

-- ── data ──────────────────────────────────────────────────────────────────
local servers, loading = {}, false

local function render()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
	local q = string.upper((search.Text or ""):gsub("%s", ""))
	local list = {}
	for _, v in ipairs(servers) do
		if q == "" or string.find(shortId(v.id), q, 1, true) or string.find(string.upper(tostring(v.id)), q, 1, true) then
			table.insert(list, v)
		end
	end
	table.sort(list, function(a, b)
		if (a.id == selfId) ~= (b.id == selfId) then return a.id == selfId end
		if (tonumber(a.n) or 0) ~= (tonumber(b.n) or 0) then return (tonumber(a.n) or 0) > (tonumber(b.n) or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	newestVer = 0
	for _, v in ipairs(servers) do newestVer = math.max(newestVer, tonumber(v.ver) or 0) end
	for i, v in ipairs(list) do card(v, i) end
	fitHeight(#list)
	countLbl.Text = ("%d server%s"):format(#servers, #servers == 1 and "" or "s")
	emptyLbl.Text = (#servers == 0) and "Loading..." or "No server found"
	emptyLbl.Visible = #list == 0
end

local function refresh()
	if loading then return end
	loading = true
	tw(refreshBtn, TF, { TextColor3 = T.ACCENT })
	local ok, res = pcall(getFn.InvokeServer, getFn)
	loading = false
	tw(refreshBtn, TF, { TextColor3 = T.TEXT })
	if not ok or type(res) ~= "table" then return showToast("Failed to load the server list") end
	if res.wait then return end
	selfId = res.self
	-- Server lain dengan 0 pemain sedang/akan mati dan tidak bisa dimasuki.
	servers = {}
	for _, v in ipairs(type(res.list) == "table" and res.list or {}) do
		if v.id == selfId or (tonumber(v.n) or 0) > 0 then table.insert(servers, v) end
	end
	if panel.Visible then render() end
end

-- ── buka / tutup ──────────────────────────────────────────────────────────
local openGen = 0
local function open()
	openGen += 1
	local g = openGen
	customPos = false -- selalu dibuka di tengah
	layout()
	overlay.Visible, panel.Visible = true, true
	overlay.BackgroundTransparency = 1
	tw(overlay, TS, { BackgroundTransparency = 0.45 })
	local top = centerTop(panel.Size.Y.Offset)
	panel.Position = UDim2.new(0.5, 0, 0, top - 14)
	tw(panel, TS, { Position = UDim2.new(0.5, 0, 0, top) })
	render()
	task.spawn(refresh)
	task.spawn(function()
		while openGen == g and panel.Visible do
			task.wait(AUTO_REFRESH)
			if openGen == g and panel.Visible then refresh() end
		end
	end)
end
local function close()
	if not panel.Visible then return end
	openGen += 1
	local g = openGen
	pcall(search.ReleaseFocus, search)
	tw(overlay, TF, { BackgroundTransparency = 1 })
	-- Seperti panel "/": ditutup di tempat, posisi default lagi saat dibuka berikutnya.
	if not customPos then tw(panel, TS, { Position = UDim2.new(0.5, 0, 0, centerTop(panel.Size.Y.Offset) - 14) }) end
	customPos = false
	task.delay(0.22, function()
		if openGen ~= g then return end
		panel.Visible, overlay.Visible = false, false
	end)
end
local function toggle() if panel.Visible then close() else open() end end

overlay.Activated:Connect(function()
	if isDragging and isDragging() then return end -- ekor gerakan drag, bukan klik di luar panel
	close()
end)
closeBtn.Activated:Connect(close)
refreshBtn.Activated:Connect(refresh)
local filterGen = 0
search:GetPropertyChangedSignal("Text"):Connect(function()
	filterGen += 1
	local g = filterGen
	task.delay(0.15, function() if g == filterGen and panel.Visible then render() end end)
end)

local resizeGen = 0
local function onResize()
	resizeGen += 1
	local g = resizeGen
	task.delay(0.12, function() if g == resizeGen and panel.Visible then layout(); render() end end)
end
local camConn
local function bindCam()
	if camConn then camConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onResize) end
end
bindCam()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() bindCam(); onResize() end)

UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and panel.Visible then close() end
end)

-- ── tombol topbar (kiri tombol "/") ───────────────────────────────────────
task.spawn(function()
	local waited = 0
	repeat task.wait(0.1); waited += 0.1 until _G.TopbarGui or waited >= 15
	if not _G.TopbarGui then
		warn("[ServerList] TopbarGui tidak ditemukan, tombol tidak dibuat")
		return
	end
	local old = _G.TopbarGui:FindFirstChild("ServerListBtn")
	if old then old:Destroy() end
	-- Gaya themeColor tombol topbar: latar TOPBAR, hover CARD_HOVER, ikon TEXT_STRONG (_G.TopbarGui di-mark UltimateMenu).
	local btn = new("TextButton", { Name = "ServerListBtn", Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 13), BackgroundColor3 = T.TOPBAR,
		BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = _G.TopbarGui })
	globe(btn, 14, T.TEXT_STRONG)
	corner(BTN_SZ / 2, btn)
	local st = stroke(btn, 0.35, T.ACCENT)
	st.Thickness = 0.5
	btn.MouseEnter:Connect(function() tw(btn, TF, { BackgroundColor3 = T.CARD_HOVER }); tw(st, TF, { Transparency = 0.1 }) end)
	btn.MouseLeave:Connect(function() tw(btn, TF, { BackgroundColor3 = T.TOPBAR }); tw(st, TF, { Transparency = 0.35 }) end)
	btn.MouseButton1Down:Connect(function() tw(btn, TF, { Size = UDim2.new(0, BTN_SZ - 3, 0, BTN_SZ - 3) }) end)
	btn.MouseButton1Up:Connect(function() tw(btn, TF, { Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ) }) end)
	btn.Activated:Connect(toggle)
	-- order 22 di baris "info": selalu tepat di kiri tombol "/" (order 20).
	if _G.TopbarLayout then _G.TopbarLayout.register("serverlist", btn, 22, "info") end
	-- disembunyikan sementara selama tertutup panel lain (mis. panel Menu di portrait)
	local okC, Cover = pcall(require, RS:WaitForChild("TopbarCover", 10))
	if okC and Cover then Cover.watch(btn) end
end)

print("[ServerList] UI siap")
