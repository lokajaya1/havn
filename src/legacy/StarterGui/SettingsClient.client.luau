-- SettingsClient — StarterPlayer > StarterPlayerScripts
-- Warna dari ReplicatedStorage.Modules.ThemeColor (themeColor): T.X dibaca saat melukis → ikut tema yang dipilih.

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")
local Stats           = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))

local LocalPlayer = Players.LocalPlayer

local function waitDeps()
	local start = os.clock()
	while not (_G.MenuUI and _G.InjectPanelUI and _G.MenuConfig) do
		if os.clock() - start > 30 then
			warn("[Settings] Timeout: MenuUI tidak ditemukan")
			return false
		end
		task.wait(0.05)
	end
	return true
end
if not waitDeps() then return end

local UI  = _G.MenuUI
local T   = ThemeColor.tokens

local FONT = _G.MenuConfig.font or {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local TW = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function tw(obj, props)
	if obj and obj.Parent then TweenService:Create(obj, TW, props):Play() end
end

-- Hover mouse + sentuh; pakai helper menu kalau tersedia.
local bindHover = UI.bindHover or function(obj, apply)
	obj.MouseEnter:Connect(function() apply(true) end)
	obj.MouseLeave:Connect(function() apply(false) end)
end

-- ── State ─────────────────────────────────────────────────

local HideNametags, HideBubbleChat = false, false
local FreecamEvent = nil
local fcActive, fpsActive, pingActive = false, false, false
local fpsConn, pingThread = nil, nil
local fpsLbl, pingLbl = nil, nil
local fcSet, fpsSet, pingSet, ntSet, bcSet
local setLiveState, setRoleState
local LiveMainFrame
local adminElements = {}

-- ── Nametag ────────────────────────────────────────────────

local function applyBB(enabled)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BillboardGui") then d.Enabled = enabled end
			end
		end
	end
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		if HideNametags then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BillboardGui") then d.Enabled = false end
			end
		end
	end)
end)

-- ── Bubble chat ────────────────────────────────────────────

local BubbleConfig = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
local origMaxDist  = BubbleConfig and BubbleConfig.MaxDistance or 100

local function applyBubbleChat(hide)
	if BubbleConfig then
		BubbleConfig.MaxDistance = hide and 0 or origMaxDist
	end
	if not hide then
		TextChatService.OnBubbleAdded = nil
		return
	end
	TextChatService.OnBubbleAdded = function()
		local props = Instance.new("BubbleChatMessageProperties")
		props.BackgroundTransparency = 1
		props.TextSize = 0
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new(1)
		g.Parent = props
		return props
	end
end

-- ── Hook panel eksternal ───────────────────────────────────

local function hookLiveFrame(frame)
	LiveMainFrame = frame
	frame.Visible = false
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if setLiveState then setLiveState(frame.Visible) end
	end)
end

local function findLiveFrame()
	if LiveMainFrame and LiveMainFrame.Parent then return LiveMainFrame end
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local ls = pg and pg:FindFirstChild("LiveScreenGui")
	if not ls then return nil end
	ls.DisplayOrder = 100
	local frame = ls:FindFirstChild("MainFrame")
	if frame then hookLiveFrame(frame) end
	return LiveMainFrame
end

task.spawn(function()
	local pg = LocalPlayer:WaitForChild("PlayerGui", 60)
	if not pg then return end

	local freecamGui = pg:WaitForChild("UltimateFreecam", 30)
	if freecamGui then
		FreecamEvent = freecamGui:FindFirstChild("Toggle") or freecamGui:WaitForChild("Toggle", 5)
		freecamGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if freecamGui.Enabled == fcActive then return end
			fcActive = freecamGui.Enabled
			if fcSet then fcSet(fcActive) end
		end)
	end

	local ls = pg:WaitForChild("LiveScreenGui", 30)
	if ls then
		ls.DisplayOrder = 100
		local frame = ls:FindFirstChild("MainFrame")
		if frame then hookLiveFrame(frame) end
	end

	local hud = UI.new("ScreenGui", {
		Name = "SettingsHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 200, Parent = pg,
	})
	ThemeColor.mark(hud)

	local function makeHUD(y, text)
		local label = UI.text({
			Size = UDim2.new(0, 76, 0, 20), Position = UDim2.new(0, 8, 0, y),
			BackgroundColor3 = T.BG, BackgroundTransparency = 0.25, BorderSizePixel = 0,
			Text = text, TextColor3 = T.ACCENT, Font = FONT.MEDIUM, TextSize = 11,
			Visible = false, Parent = hud,
		})
		UI.corner(6).Parent = label
		UI.stroke(T.LINE, 1, 0.9).Parent = label
		return label
	end

	fpsLbl  = makeHUD(44, "FPS --")
	pingLbl = makeHUD(68, "Ping --")
end)

-- ── Admin sync ─────────────────────────────────────────────

local function syncAdmin()
	local isAdmin = LocalPlayer:GetAttribute("IsAdmin") == true
	for _, el in ipairs(adminElements) do
		if el and el.Parent then el.Visible = isAdmin end
	end
end

task.delay(1.5, syncAdmin)
LocalPlayer:GetAttributeChangedSignal("IsAdmin"):Connect(syncAdmin)

-- ════════════════════════════════════════════════════════════
-- WIDGET
-- Row memakai Frame, bukan TextButton — TextButton sebagai parent
-- memblokir klik pada children-nya.
-- ════════════════════════════════════════════════════════════

local ROW_H = 40

local function Cat(parent, order, text)
	local frame = UI.frame({
		Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
		LayoutOrder = order, Parent = parent,
	})
	UI.text({
		Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0),
		Text = text, TextColor3 = T.TEXT_DIM, Font = FONT.MEDIUM, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
	})
	return frame
end

local function Row(parent, order, label)
	local row = UI.frame({
		Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = T.CARD,
		LayoutOrder = order, Parent = parent,
	})
	UI.corner(10).Parent = row
	UI.stroke(T.LINE, 1, 0.94).Parent = row

	UI.text({
		Size = UDim2.new(1, -80, 1, 0), Position = UDim2.new(0, 11, 0, 0),
		Text = label, TextColor3 = T.TEXT, Font = FONT.REGULAR, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	return row
end

local function Switch(parent, initState)
	local W, H, PAD = 38, 20, 3
	local thumbSize  = H - PAD * 2

	-- Gaya themeColor: hidup = jalur ACCENT + kenop TEXT_STRONG, mati = jalur TRACK + kenop TEXT.
	local pill = UI.button({
		Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundColor3 = initState and T.ACCENT or T.TRACK,
		Text = "", Parent = parent,
	})
	UI.corner(H / 2).Parent = pill

	local thumb = UI.frame({
		Size = UDim2.new(0, thumbSize, 0, thumbSize), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, initState and (W - thumbSize - PAD) or PAD, 0.5, 0),
		BackgroundColor3 = initState and T.TEXT_STRONG or T.TEXT, Parent = pill,
	})
	UI.corner(thumbSize / 2).Parent = thumb
	UI.stroke(T.BG, 1, 0.7).Parent = thumb

	local function set(on)
		tw(pill, { BackgroundColor3 = on and T.ACCENT or T.TRACK })
		tw(thumb, {
			Position         = UDim2.new(0, on and (W - thumbSize - PAD) or PAD, 0.5, 0),
			BackgroundColor3 = on and T.TEXT_STRONG or T.TEXT,
		})
	end

	return pill, set
end

-- Tombol aksi buka/tutup; dipakai Live Screen dan Role Manager.
local function ActionButton(parent, labelClosed, labelOpen)
	local W, H = 62, 24
	local btn = UI.button({
		Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = T.ACCENT,
		Text = labelClosed, TextColor3 = T.ON_ACCENT,
		Font = FONT.MEDIUM, TextSize = 11, Parent = parent,
	})
	UI.corner(8).Parent = btn
	local btnStroke = UI.stroke(T.ACCENT, 1, 1)
	btnStroke.Parent = btn

	local isOpen = false

	local function paint(hovered)
		if isOpen then
			tw(btn, {
				BackgroundColor3 = hovered and T.CARD_HOVER or T.CARD,
				TextColor3       = T.ACCENT,
			})
			tw(btnStroke, { Transparency = 0.35 })
		else
			tw(btn, {
				BackgroundColor3 = hovered and T.TEXT or T.ACCENT,
				TextColor3       = T.ON_ACCENT,
			})
			tw(btnStroke, { Transparency = 1 })
		end
	end

	local function setOpen(open)
		isOpen   = open and true or false
		btn.Text = isOpen and labelOpen or labelClosed
		paint(false)
	end

	bindHover(btn, paint)
	return btn, setOpen
end

-- ════════════════════════════════════════════════════════════
-- BUILD
-- ════════════════════════════════════════════════════════════

local function build()
	local scroll = UI.scroll({
		Size = UDim2.new(1, 0, 1, 0), ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never, ScrollBarThickness = 3,
	})

	local content = UI.frame({
		Size = UDim2.new(1, -6, 0, 0), Position = UDim2.new(0, 3, 0, 2),
		BackgroundTransparency = 1, Parent = scroll,
	})

	local listLayout = UI.list({ padding = 6 })
	listLayout.Parent = content

	local function updateCanvas()
		if not scroll.Parent then return end
		scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 16)
	end
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

	-- Tab bisa diinject saat masih tersembunyi; hitung ulang saat pertama terlihat.
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if scroll.AbsoluteSize.Y > 0 then task.defer(updateCanvas) end
	end)

	local order = 0
	local function L() order = order + 1; return order end
	local resetFns = {}

	-- ── ADMIN ──────────────────────────────────────────────

	local admHeader = Cat(content, L(), "ADMIN")
	admHeader.Visible = false
	table.insert(adminElements, admHeader)

	local liveRow = Row(content, L(), "Live Screen")
	liveRow.Visible = false
	table.insert(adminElements, liveRow)

	local liveBtn
	liveBtn, setLiveState = ActionButton(liveRow, "Buka", "Tutup")
	liveBtn.Activated:Connect(function()
		local frame = findLiveFrame()
		if not frame then return end
		frame.Visible = not frame.Visible   -- setLiveState dipanggil lewat listener
	end)

	local roleRow = Row(content, L(), "Role Manager")
	roleRow.Visible = false
	table.insert(adminElements, roleRow)

	local roleBtn
	roleBtn, setRoleState = ActionButton(roleRow, "Buka", "Tutup")
	roleBtn.Activated:Connect(function()
		if type(_G.ToggleRoleManager) ~= "function" then
			warn("[Settings] _G.ToggleRoleManager belum tersedia")
			return
		end
		_G.ToggleRoleManager()
		task.delay(0.05, function()
			setRoleState(_G.RoleManagerPanel and _G.RoleManagerPanel.Visible)
		end)
	end)

	task.spawn(function()
		local start = os.clock()
		while not _G.RoleManagerPanel do
			if os.clock() - start > 30 then return end
			task.wait(0.2)
		end
		setRoleState(_G.RoleManagerPanel.Visible)
		_G.RoleManagerPanel:GetPropertyChangedSignal("Visible"):Connect(function()
			setRoleState(_G.RoleManagerPanel.Visible)
		end)
	end)

	-- Tema map (themeMap): panel ThemeMapAdmin (StarterPlayerScripts) — _G.ToggleThemeMap / _G.ThemeMapMenu.
	local themeRow = Row(content, L(), "Tema map")
	themeRow.Visible = false
	table.insert(adminElements, themeRow)

	local themeBtn, setThemeState = ActionButton(themeRow, "Buka", "Tutup")
	themeBtn.Activated:Connect(function()
		if type(_G.ToggleThemeMap) ~= "function" then
			warn("[Settings] _G.ToggleThemeMap belum tersedia")
			return
		end
		_G.ToggleThemeMap()
	end)

	task.spawn(function()
		local start = os.clock()
		while not (_G.ThemeMapMenu and _G.ThemeMapMenu.IsOpen) do
			if os.clock() - start > 30 then return end
			task.wait(0.2)
		end
		setThemeState(_G.ThemeMapMenu.IsOpen())
		_G.ThemeMapMenu.OnChanged = function(open)
			if themeBtn.Parent then setThemeState(open) end
		end
	end)

	-- ── TAMPILAN ───────────────────────────────────────────
	-- Tema warna (themeColor): panel pemilih ThemeColorClient (StarterPlayerScripts) — _G.ToggleThemeColor.

	Cat(content, L(), "TAMPILAN")

	local tcRow = Row(content, L(), "Themes (game pass)")
	local tcChip = UI.button({
		Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = T.CHIP,
		Text = ThemeColor.label(ThemeColor.current), TextColor3 = T.ON_ACCENT,
		Font = FONT.BOLD, TextSize = 11, Parent = tcRow,
	})
	UI.corner(7).Parent = tcChip
	UI.padding(0, 0, 10, 10).Parent = tcChip
	-- Label baris memberi ruang selebar chip (nama tema beda panjang) → tidak bertumpuk di HP sempit.
	local tcLabel = tcRow:FindFirstChildOfClass("TextLabel")
	local function fitLabel()
		if tcLabel and tcChip.AbsoluteSize.X > 0 then
			tcLabel.Size = UDim2.new(1, -(tcChip.AbsoluteSize.X + 24), 1, 0)
		end
	end
	tcChip:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLabel)
	fitLabel()
	bindHover(tcChip, function(on)
		tw(tcChip, { BackgroundColor3 = on and T.ACCENT or T.CHIP })
	end)
	tcChip.Activated:Connect(function()
		if type(_G.ToggleThemeColor) ~= "function" then
			warn("[Settings] _G.ToggleThemeColor belum tersedia")
			return
		end
		_G.ToggleThemeColor()
	end)
	local stopTheme = ThemeColor.onChanged(function(id)
		if tcChip.Parent then tcChip.Text = ThemeColor.label(id) end
	end)
	tcChip.Destroying:Connect(stopTheme)

	-- ── GENERAL ────────────────────────────────────────────

	Cat(content, L(), "GENERAL")

	local fcRow = Row(content, L(), "Freecam  ·  F8")
	local fcPill
	fcPill, fcSet = Switch(fcRow, false)

	_G.OnFreecamStateChanged = function(active)
		fcActive = active
		fcSet(active)
	end

	fcPill.Activated:Connect(function()
		if type(_G.ToggleFreecam) == "function" then
			_G.ToggleFreecam()
			return
		end
		if not FreecamEvent then
			local pg  = LocalPlayer:FindFirstChild("PlayerGui")
			local gui = pg and pg:FindFirstChild("UltimateFreecam")
			FreecamEvent = gui and gui:FindFirstChild("Toggle")
		end
		if FreecamEvent then
			fcActive = not fcActive
			fcSet(fcActive)
			FreecamEvent:Fire(fcActive)
		end
	end)

	table.insert(resetFns, function()
		if fcActive then
			if type(_G.ToggleFreecam) == "function" then
				_G.ToggleFreecam()
			elseif FreecamEvent then
				FreecamEvent:Fire(false)
			end
		end
		fcActive = false
		fcSet(false)
	end)

	local ntRow = Row(content, L(), "Sembunyikan nametag")
	local ntPill
	ntPill, ntSet = Switch(ntRow, false)
	ntPill.Activated:Connect(function()
		HideNametags = not HideNametags
		ntSet(HideNametags)
		applyBB(not HideNametags)
	end)
	table.insert(resetFns, function()
		HideNametags = false
		ntSet(false)
		applyBB(true)
	end)

	local bcRow = Row(content, L(), "Sembunyikan bubble chat")
	local bcPill
	bcPill, bcSet = Switch(bcRow, false)
	bcPill.Activated:Connect(function()
		HideBubbleChat = not HideBubbleChat
		bcSet(HideBubbleChat)
		applyBubbleChat(HideBubbleChat)
	end)
	table.insert(resetFns, function()
		HideBubbleChat = false
		bcSet(false)
		applyBubbleChat(false)
	end)

	-- ── GRAFIS ─────────────────────────────────────────────

	Cat(content, L(), "GRAFIS")
	local gfxSlot = L()

	task.spawn(function()
		local start = os.clock()
		while not _G.GraphicsPanel do
			if os.clock() - start > 30 then
				warn("[Settings] GraphicsPanel timeout")
				return
			end
			task.wait(0.1)
		end
		_G.GraphicsPanel.LayoutOrder = gfxSlot
		_G.GraphicsPanel.Parent      = content
	end)

	-- ── PERFORMA ───────────────────────────────────────────

	Cat(content, L(), "PERFORMA")

	local function hudColor(value, goodMax, warnMax, lowerIsBetter)
		if lowerIsBetter then
			return value <= goodMax and T.SUCCESS or (value <= warnMax and T.ACCENT or T.DANGER)
		end
		return value >= goodMax and T.SUCCESS or (value >= warnMax and T.ACCENT or T.DANGER)
	end

	local fpsRow = Row(content, L(), "Tampilkan FPS")
	local fpsPill
	fpsPill, fpsSet = Switch(fpsRow, false)
	fpsPill.Activated:Connect(function()
		fpsActive = not fpsActive
		fpsSet(fpsActive)
		if fpsLbl then fpsLbl.Visible = fpsActive end

		if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
		if not fpsActive then
			if fpsLbl then fpsLbl.Text = "FPS --" end
			return
		end

		-- Rata-rata dari akumulasi, tanpa tabel sampel per frame.
		local frames, elapsed = 0, 0
		fpsConn = RunService.Heartbeat:Connect(function(dt)
			frames  = frames + 1
			elapsed = elapsed + dt
			if elapsed < 0.4 then return end
			local fps = math.floor(frames / elapsed + 0.5)
			frames, elapsed = 0, 0
			if fpsLbl and fpsLbl.Parent then
				fpsLbl.Text       = "FPS " .. fps
				fpsLbl.TextColor3 = hudColor(fps, 55, 30, false)
			end
		end)
	end)
	table.insert(resetFns, function()
		fpsActive = false
		fpsSet(false)
		if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
		if fpsLbl then fpsLbl.Visible = false; fpsLbl.Text = "FPS --" end
	end)

	local pingRow = Row(content, L(), "Tampilkan ping")
	local pingPill
	pingPill, pingSet = Switch(pingRow, false)
	pingPill.Activated:Connect(function()
		pingActive = not pingActive
		pingSet(pingActive)
		if pingLbl then pingLbl.Visible = pingActive end

		if pingThread then
			pcall(task.cancel, pingThread)
			pingThread = nil
		end
		if not pingActive then
			if pingLbl then pingLbl.Text = "Ping --" end
			return
		end

		-- Loop 1 detik; tidak perlu ikut Heartbeat tiap frame.
		pingThread = task.spawn(function()
			local item = Stats.Network.ServerStatsItem["Data Ping"]
			while true do
				local ok, ms = pcall(function() return math.floor(item:GetValue()) end)
				if ok and pingLbl and pingLbl.Parent then
					pingLbl.Text       = "Ping " .. ms .. "ms"
					pingLbl.TextColor3 = hudColor(ms, 80, 150, true)
				end
				task.wait(1)
			end
		end)
	end)
	table.insert(resetFns, function()
		pingActive = false
		pingSet(false)
		if pingThread then pcall(task.cancel, pingThread); pingThread = nil end
		if pingLbl then pingLbl.Visible = false; pingLbl.Text = "Ping --" end
	end)

	-- ── RESET ──────────────────────────────────────────────

	local resetWrap = UI.frame({
		Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1,
		LayoutOrder = L(), Parent = content,
	})

	local resetBtn = UI.button({
		Size = UDim2.new(0, 148, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = T.CARD,
		Text = "Reset setting", TextColor3 = T.DANGER,
		Font = FONT.MEDIUM, TextSize = 12, Parent = resetWrap,
	})
	UI.corner(9).Parent = resetBtn
	local resetStroke = UI.stroke(T.DANGER, 1, 0.6)
	resetStroke.Parent = resetBtn

	local function paintReset(hovered)
		tw(resetBtn, {
			BackgroundColor3 = hovered and T.DANGER or T.CARD,
			TextColor3       = hovered and T.TEXT or T.DANGER,
		})
		tw(resetStroke, { Transparency = hovered and 0.2 or 0.6 })
	end
	bindHover(resetBtn, paintReset)

	resetBtn.Activated:Connect(function()
		for _, fn in ipairs(resetFns) do pcall(fn) end
		if type(_G.GfxReset) == "function" then pcall(_G.GfxReset) end
		if _G.RoleManagerPanel and _G.RoleManagerPanel.Visible
			and type(_G.ToggleRoleManager) == "function" then
			_G.ToggleRoleManager()
		end
		if _G.ThemeMapMenu and type(_G.ThemeMapMenu.Close) == "function" then
			pcall(_G.ThemeMapMenu.Close)
		end
		if _G.ThemeColorMenu and type(_G.ThemeColorMenu.Close) == "function" then
			pcall(_G.ThemeColorMenu.Close)
		end

		resetBtn.Text = "Tersetel ulang"
		tw(resetBtn, { BackgroundColor3 = T.ACCENT, TextColor3 = T.ON_ACCENT })
		task.delay(0.9, function()
			if not resetBtn.Parent then return end
			resetBtn.Text = "Reset setting"
			paintReset(false)
		end)
	end)

	return scroll
end

-- ════════════════════════════════════════════════════════════
-- INJECT
-- ════════════════════════════════════════════════════════════

local container = UI.frame({
	Name = "SettingsContainer", Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
})

local ok, err = pcall(function() build().Parent = container end)
if not ok then warn("[Settings] build error:", err) end

task.spawn(function()
	local start = os.clock()
	while not (_G.MenuPanel and _G.MenuPanel.Settings) do
		if os.clock() - start > 30 then
			warn("[Settings] inject timeout")
			return
		end
		task.wait(0.1)
	end
	local injected, injectErr = pcall(_G.InjectPanelUI, "Settings", container)
	if not injected then warn("[Settings] inject error:", injectErr) end
end)