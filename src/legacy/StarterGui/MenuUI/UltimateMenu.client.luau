--!nonstrict
-- UltimateMenu — StarterGui > UltimateMenu (LocalScript)
-- Panel geser kanan dengan tema yang sama seperti DanceClient / MenuSystemInit.
-- Header dihapus: tab langsung di atas, konten dapat sisa ruang penuh.
-- API publik (_G.MenuPanel, _G.InjectUI, _G.ToggleMenu, _G.TopbarGui, dst) tidak berubah.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════
-- PANEL COORDINATOR (kontrak lintas script, dipertahankan apa adanya)
-- ═══════════════════════════════════════════════════════════

if not _G.PanelCoordinator then
	local PC = { panels = {}, activePanel = nil, listeners = {} }

	function PC.Register(name, closeFunc)
		PC.panels[name] = closeFunc
	end

	function PC._fire()
		for _, fn in ipairs(PC.listeners) do pcall(fn, PC.activePanel) end
	end

	function PC.OnChange(fn)
		table.insert(PC.listeners, fn)
		pcall(fn, PC.activePanel)
	end

	function PC.CloseAll(except)
		for name, fn in pairs(PC.panels) do
			if name ~= except then pcall(fn) end
		end
		if not except then
			PC.activePanel = nil
			PC._fire()
		end
	end

	function PC.NotifyOpen(name)
		PC.CloseAll(name)
		PC.activePanel = name
		PC._fire()
	end

	function PC.NotifyClose(name)
		if PC.activePanel == name then
			PC.activePanel = nil
			PC._fire()
		end
	end

	_G.PanelCoordinator = PC
	_G.CloseAllPanels   = function() PC.CloseAll() end
end

-- ═══════════════════════════════════════════════════════════
-- TEMA & KONFIG
-- ═══════════════════════════════════════════════════════════

local T = {
	BG         = Color3.fromRGB(16, 16, 17),
	CARD       = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	LINE       = Color3.fromRGB(255, 255, 255),
	TEXT       = Color3.fromRGB(238, 238, 240),
	TEXT_DIM   = Color3.fromRGB(148, 148, 154),
	ACCENT     = Color3.fromRGB(212, 175, 55),
	DANGER     = Color3.fromRGB(226, 96, 96),
	SUCCESS    = Color3.fromRGB(96, 196, 132),
	INFO       = Color3.fromRGB(96, 152, 236),
}

local FONT = {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local CFG = {
	ID = "UltimateMenu",

	-- Nama lama dipertahankan supaya UI yang di-inject script lain tidak rusak.
	colors = {
		bg           = T.BG,
		bgLight      = T.CARD,
		section      = T.CARD,
		hover        = T.CARD_HOVER,
		accent       = T.ACCENT,
		accentDark   = Color3.fromRGB(168, 138, 44),
		white        = T.TEXT,
		gray         = T.TEXT_DIM,
		darkGray     = Color3.fromRGB(104, 104, 110),
		textOnAccent = Color3.fromRGB(18, 18, 20),
		danger       = T.DANGER,
		success      = T.SUCCESS,
		blue         = T.INFO,
		border       = T.LINE,
	},

	tween = {
		instant = TweenInfo.new(0.08, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out),
		fast    = TweenInfo.new(0.14, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out),
		smooth  = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		bounce  = TweenInfo.new(0.30, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
	},

	theme        = T,
	font         = FONT,
	TOGGLE_DEBOUNCE = 0.08,
	HIDE_DELAY      = 0.28,
	RESIZE_DEBOUNCE = 0.12,
	TOPBAR_BOTTOM   = 59,
}

-- Preset ukuran panel: {scale, min, max}
local LAYOUT = {
	mobile = {
		portrait  = { w = {0.84, 250, 320}, h = {0.58, 280, 430}, tab = 28, pad = 9,  gap = 5, title = 13, text = 12 },
		landscape = { w = {0.40, 240, 310}, h = {0.86, 190, 300}, tab = 26, pad = 8,  gap = 4, title = 12, text = 11 },
	},
	tablet = {
		portrait  = { w = {0.42, 290, 370}, h = {0.60, 330, 520}, tab = 32, pad = 11, gap = 6, title = 15, text = 13 },
		landscape = { w = {0.32, 280, 360}, h = {0.74, 300, 480}, tab = 30, pad = 10, gap = 6, title = 14, text = 13 },
	},
	desktop = {
		portrait  = { w = {0.24, 280, 350}, h = {0.62, 320, 500}, tab = 30, pad = 11, gap = 6, title = 15, text = 13 },
		landscape = { w = {0.22, 280, 350}, h = {0.64, 320, 520}, tab = 30, pad = 11, gap = 6, title = 15, text = 13 },
	},
}

-- ═══════════════════════════════════════════════════════════
-- SINGLETON
-- ═══════════════════════════════════════════════════════════

local function destroyGlobal(key)
	pcall(function()
		local obj = _G[key]
		if obj then obj:Destroy() end
	end)
end

if _G[CFG.ID] then
	destroyGlobal("ToolsIcon")
	destroyGlobal("MenuIcon")
	destroyGlobal("PanelContainer")
	task.wait(0.2)
end
_G[CFG.ID] = true

-- Viewport dipakai helper drag & layout, jadi harus terdefinisi lebih awal.
local function getViewport()
	local cam = workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then return Vector2.new(1280, 720) end
	return vp
end

-- ═══════════════════════════════════════════════════════════
-- UI BUILDER (API lama dipertahankan)
-- ═══════════════════════════════════════════════════════════

local UI = {}

-- Weak key: tween yang objeknya sudah di-Destroy ikut hilang, tidak menumpuk.
local activeTweens = setmetatable({}, { __mode = "k" })

function UI.new(class, props)
	local obj = Instance.new(class)
	if props then for k, v in pairs(props) do obj[k] = v end end
	return obj
end

local function make(class, defaults)
	return function(props)
		local obj = Instance.new(class)
		for k, v in pairs(defaults) do obj[k] = v end
		if props then for k, v in pairs(props) do obj[k] = v end end
		return obj
	end
end

UI.frame = make("Frame", {
	BackgroundColor3 = T.CARD, BorderSizePixel = 0,
})

UI.text = make("TextLabel", {
	BackgroundTransparency = 1, Font = FONT.REGULAR,
	TextSize = 14, TextColor3 = T.TEXT,
})

UI.button = make("TextButton", {
	Font = FONT.MEDIUM, TextSize = 14, TextColor3 = T.TEXT,
	BorderSizePixel = 0, BackgroundColor3 = T.CARD, AutoButtonColor = false,
})

UI.textbox = make("TextBox", {
	BackgroundColor3 = T.CARD, BorderSizePixel = 0, Font = FONT.REGULAR,
	TextSize = 14, TextColor3 = T.TEXT, ClearTextOnFocus = false,
})

UI.scroll = make("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
	ScrollBarImageColor3 = T.TEXT_DIM, ScrollBarImageTransparency = 0.55,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.None,
	ScrollingDirection = Enum.ScrollingDirection.Y,
})

function UI.corner(r)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end

function UI.stroke(color, thickness, transparency)
	return UI.new("UIStroke", {
		Color = color or T.LINE, Thickness = thickness or 1,
		Transparency = transparency or 0.9,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.gradient(rotation, c1, c2)
	return UI.new("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(c1, c2) })
end

function UI.padding(t, b, l, r)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or t or 0),
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or l or 0),
	})
end

function UI.list(props)
	local obj = Instance.new("UIListLayout")
	obj.SortOrder = Enum.SortOrder.LayoutOrder
	obj.Padding   = UDim.new(0, (props and props.padding) or 5)
	if props then
		for k, v in pairs(props) do
			if k ~= "padding" then obj[k] = v end
		end
	end
	return obj
end

function UI.tween(obj, props, info)
	if not obj or not obj.Parent then return end
	local running = activeTweens[obj]
	if running then running:Cancel() end
	local t = TweenService:Create(obj, info or CFG.tween.smooth, props)
	activeTweens[obj] = t
	t.Completed:Once(function()
		if activeTweens[obj] == t then activeTweens[obj] = nil end
	end)
	t:Play()
	return t
end

-- Hover untuk mouse sekaligus sentuh (MouseEnter tidak jalan di layar sentuh).
function UI.bindHover(obj, apply, guard)
	local function set(on)
		if guard and not guard() then return end
		apply(on)
	end
	obj.MouseEnter:Connect(function() set(true) end)
	obj.MouseLeave:Connect(function() set(false) end)
	obj.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then set(true) end
	end)
	obj.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then set(false) end
	end)
end

function UI.addHover(button, normalColor, hoverColor, info)
	UI.bindHover(button, function(on)
		UI.tween(button, { BackgroundColor3 = on and hoverColor or normalColor },
		info or (on and CFG.tween.instant or CFG.tween.fast))
	end)
end

-- Drag panel dengan clamp ke dalam layar. Dipakai panel mana pun yang mau
-- dipindah-pindah (Command Panel, Tool Settings, dll) supaya logikanya satu.
function UI.makeDraggable(frame, handles, onMoved)
	handles = handles or frame
	if typeof(handles) == "Instance" then handles = { handles } end

	local dragging, startInput, startPos
	local moved     = false
	local lastMoved = 0

	local function clamp(pos)
		local vp   = getViewport()
		local size = frame.AbsoluteSize
		local a    = frame.AnchorPoint
		local margin = 8

		local left = pos.X.Scale * vp.X + pos.X.Offset - a.X * size.X
		local top  = pos.Y.Scale * vp.Y + pos.Y.Offset - a.Y * size.Y
		local maxL = math.max(vp.X - size.X - margin, margin)
		local maxT = math.max(vp.Y - size.Y - margin, margin)

		local dx = math.clamp(left, margin, maxL) - left
		local dy = math.clamp(top, margin, maxT) - top
		return UDim2.new(pos.X.Scale, pos.X.Offset + dx, pos.Y.Scale, pos.Y.Offset + dy)
	end

	for _, handle in ipairs(handles) do
		handle.Active = true
		handle.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1
				or io.UserInputType == Enum.UserInputType.Touch then
				dragging   = true
				startInput = io.Position
				startPos   = frame.Position
			end
		end)
	end

	UIS.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1
			or io.UserInputType == Enum.UserInputType.Touch then
			if moved then lastMoved = os.clock() end
			dragging = false
			moved    = false
		end
	end)

	UIS.InputChanged:Connect(function(io)
		if not dragging then return end
		if io.UserInputType ~= Enum.UserInputType.MouseMovement
			and io.UserInputType ~= Enum.UserInputType.Touch then return end

		local delta = io.Position - startInput
		if not moved and delta.Magnitude < 3 then return end   -- toleransi getaran tap
		moved     = true
		lastMoved = os.clock()

		frame.Position = clamp(UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
			))
		if onMoved then onMoved(frame.Position) end
	end)

	local function reclamp()
		frame.Position = clamp(frame.Position)
	end

	-- Panel yang sedang/baru saja digeser tidak boleh dianggap "klik" oleh
	-- overlay penutup; pemanggil memakai ini sebagai penjaga.
	local function isDragging()
		return dragging or (os.clock() - lastMoved) < 0.25
	end

	return reclamp, isDragging
end

-- ═══════════════════════════════════════════════════════════
-- LAYOUT
-- ═══════════════════════════════════════════════════════════

local function getDeviceType()
	local touch, keyboard = UIS.TouchEnabled, UIS.KeyboardEnabled
	if touch and not keyboard then
		local vp = getViewport()
		return (math.max(vp.X, vp.Y) >= 1000) and "tablet" or "mobile"
	elseif touch and keyboard then
		return "tablet"
	end
	return "desktop"
end

local function resolve(axis, spec)
	return math.floor(math.clamp(axis * spec[1], spec[2], spec[3]))
end

local function getLayout()
	local vp     = getViewport()
	local device = getDeviceType()
	local orient = (vp.X > vp.Y) and "landscape" or "portrait"
	local s      = LAYOUT[device][orient]

	local isMobile = (device == "mobile")
	local topPx    = CFG.TOPBAR_BOTTOM + (isMobile and 4 or 6)
	local bottom   = isMobile and 56 or 28

	local width  = math.min(resolve(vp.X, s.w), math.floor(vp.X) - 16)
	local height = math.min(resolve(vp.Y, s.h), math.floor(vp.Y) - topPx - bottom)

	return {
		device       = device,
		isMobile     = isMobile,
		panelWidth   = math.max(240, width),
		panelHeight  = math.max(180, height),
		rightMargin  = isMobile and 6 or 10,
		topPx        = topPx,
		padding      = s.pad,
		gap          = s.gap,
		cornerRadius = 16,
		headerHeight = 0,          -- header dihapus; disimpan untuk kompatibilitas
		tabBarHeight = s.tab,
		fontSize     = { title = s.title, content = s.text },
	}
end

-- ═══════════════════════════════════════════════════════════
-- PANEL
-- ═══════════════════════════════════════════════════════════

local CLOSE_SIZE = 22

local function createPanel(config)
	local L        = CFG.layout
	local tabs     = config.tabs
	local single   = (#tabs == 1)
	local data     = { contents = {}, tabBtns = {}, activeTab = nil, _showGen = 0 }

	local overlay = UI.button({
		Name = "Overlay", Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Text = "", Visible = false, ZIndex = 40,
	})

	local panel = UI.frame({
		Name = config.name .. "Panel",
		Size = UDim2.new(0, L.panelWidth, 0, L.panelHeight),
		Position = UDim2.new(1, 50, 0, L.topPx),
		BackgroundColor3 = T.BG, ClipsDescendants = true, Visible = false, ZIndex = 50,
	})
	UI.corner(L.cornerRadius).Parent = panel
	UI.stroke(T.LINE, 1, 0.88).Parent = panel

	local tabBar = UI.frame({ Name = "TabBar", BackgroundTransparency = 1, Parent = panel })

	local closeBtn = UI.button({
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.new(0, CLOSE_SIZE, 0, CLOSE_SIZE), BackgroundTransparency = 1,
		Text = "✕", TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 14,
		ZIndex = 55, Parent = panel,
	})
	UI.bindHover(closeBtn, function(on)
		UI.tween(closeBtn, { TextColor3 = on and T.TEXT or T.TEXT_DIM }, CFG.tween.fast)
	end)

	local contentFrame = UI.frame({
		Name = "ContentArea", BackgroundTransparency = 1,
		ClipsDescendants = false, Parent = panel,
	})

	-- Satu fungsi pewarnaan tab untuk state aktif maupun hover.
	local function paintTab(name, hovered)
		local btn    = data.tabBtns[name]
		if not btn then return end
		local active = (data.activeTab == name)
		UI.tween(btn, {
			BackgroundColor3 = (active or hovered) and T.CARD_HOVER or T.CARD,
			TextColor3       = active and T.ACCENT or (hovered and T.TEXT or T.TEXT_DIM),
		}, active and CFG.tween.fast or CFG.tween.instant)
	end

	local function switchTab(name)
		if not data.contents[name] or data.activeTab == name then return end
		local previous = data.activeTab
		data.activeTab = name
		if previous then
			data.contents[previous].Visible = false
			paintTab(previous, false)
		end
		data.contents[name].Visible = true
		paintTab(name, false)
	end

	for i, name in ipairs(tabs) do
		data.contents[name] = UI.frame({
			Name = name .. "Content", Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1, Visible = false,
			ClipsDescendants = false, Parent = contentFrame,
		})

		UI.text({
			Name = "Placeholder", Size = UDim2.new(1, -20, 0, 60),
			Position = UDim2.new(0, 10, 0.5, -30), Text = name .. "\nBelum ada konten.",
			TextColor3 = T.TEXT_DIM, TextSize = L.fontSize.content, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = data.contents[name],
		})

		if not single then
			local btn = UI.button({
				Name = name, Text = name, TextColor3 = T.TEXT_DIM,
				BackgroundColor3 = T.CARD, TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = i, Parent = tabBar,
			})
			UI.corner(8).Parent = btn
			UI.stroke(T.LINE, 1, 0.94).Parent = btn
			data.tabBtns[name] = btn

			btn.Activated:Connect(function() switchTab(name) end)
			UI.bindHover(btn, function(on) paintTab(name, on) end)
		end
	end

	-- Satu sumber kebenaran untuk semua ukuran/posisi panel ini.
	function data.layout(cfg)
		local pad   = cfg.padding
		local gap   = cfg.gap
		local tabH  = single and 0 or cfg.tabBarHeight
		local topY  = single and pad or (pad + tabH + gap)

		panel.Size = UDim2.new(0, cfg.panelWidth, 0, cfg.panelHeight)
		if panel.Visible then
			panel.Position = UDim2.new(1, -(cfg.panelWidth + cfg.rightMargin), 0, cfg.topPx)
		else
			panel.Position = UDim2.new(1, 50, 0, cfg.topPx)
		end

		closeBtn.Position = UDim2.new(1, -pad, 0, pad + (single and 8 or tabH * 0.5))
		closeBtn.Visible  = true

		if not single then
			tabBar.Position = UDim2.new(0, pad, 0, pad)
			tabBar.Size     = UDim2.new(1, -(2 * pad + CLOSE_SIZE + 6), 0, tabH)

			local count = #tabs
			for i, name in ipairs(tabs) do
				local btn = data.tabBtns[name]
				btn.Size     = UDim2.new(1 / count, -4, 1, 0)
				btn.Position = UDim2.new((i - 1) / count, (i - 1) * 2, 0, 0)
				btn.TextSize = cfg.fontSize.content - 1
			end
		end

		contentFrame.Position = UDim2.new(0, pad, 0, topY)
		contentFrame.Size     = UDim2.new(1, -2 * pad, 0, math.max(cfg.panelHeight - topY - pad, 60))

		for _, container in pairs(data.contents) do
			local placeholder = container:FindFirstChild("Placeholder")
			if placeholder then placeholder.TextSize = cfg.fontSize.content end
		end
	end

	data.panel        = panel
	data.overlay      = overlay
	data.closeBtn     = closeBtn
	data.tabBar       = tabBar
	data.contentFrame = contentFrame
	data.switchTab    = switchTab

	data.layout(L)
	switchTab(tabs[1])
	return data
end

-- ═══════════════════════════════════════════════════════════
-- PANEL MANAGER
-- ═══════════════════════════════════════════════════════════

local PM = { container = nil, panels = {}, active = nil }

function PM.init()
	PM.container = UI.new("ScreenGui", {
		Name = "UltimatePanelSystem", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
	})
	return PM.container
end

function PM.register(name, data)
	data.panel.Parent   = PM.container
	data.overlay.Parent = PM.container
	PM.panels[name]     = data

	data.closeBtn.Activated:Connect(function() PM.hide(name) end)
	data.overlay.Activated:Connect(function() PM.hide(name) end)
	_G.PanelCoordinator.Register("Menu_" .. name, function() PM.hide(name) end)
end

function PM.show(name)
	local pd = PM.panels[name]
	if not pd then return end

	_G.PanelCoordinator.NotifyOpen("Menu_" .. name)
	if PM.active and PM.active ~= name then PM.hide(PM.active) end

	-- Generasi baru → callback hide yang masih pending jadi no-op.
	pd._showGen = pd._showGen + 1

	local L = CFG.layout
	pd.overlay.Visible = true
	pd.overlay.BackgroundTransparency = 1
	UI.tween(pd.overlay, { BackgroundTransparency = 0.45 }, CFG.tween.smooth)

	pd.panel.Visible  = true
	pd.panel.Position = UDim2.new(1, 50, 0, L.topPx)
	UI.tween(pd.panel, { Position = UDim2.new(1, -(L.panelWidth + L.rightMargin), 0, L.topPx) }, CFG.tween.smooth)

	PM.active = name
end

function PM.hide(name)
	local pd = PM.panels[name]
	if not pd or not pd.panel.Visible then return end

	_G.PanelCoordinator.NotifyClose("Menu_" .. name)
	UI.tween(pd.overlay, { BackgroundTransparency = 1 }, CFG.tween.fast)
	UI.tween(pd.panel, { Position = UDim2.new(1, 50, 0, CFG.layout.topPx) }, CFG.tween.smooth)

	local gen = pd._showGen
	task.delay(CFG.HIDE_DELAY, function()
		if pd._showGen ~= gen then return end   -- sudah dibuka lagi selama animasi
		if pd.panel.Parent   then pd.panel.Visible   = false end
		if pd.overlay.Parent then pd.overlay.Visible = false end
	end)

	if PM.active == name then PM.active = nil end
end

local toggleCooldown = {}

function PM.toggle(name)
	if toggleCooldown[name] then return end
	toggleCooldown[name] = true
	task.delay(CFG.TOGGLE_DEBOUNCE, function() toggleCooldown[name] = nil end)

	local pd = PM.panels[name]
	if pd and pd.panel.Visible then PM.hide(name) else PM.show(name) end
end

-- ═══════════════════════════════════════════════════════════
-- INJECTION
-- ═══════════════════════════════════════════════════════════

local function inject(panelType, tabName, uiFrame)
	if not uiFrame or not uiFrame:IsA("GuiObject") then return false end
	local panels = (panelType == "Menu") and _G.MenuPanel or _G.ToolPanel
	local target = panels and panels[tabName]
	if not target then return false end
	for _, child in ipairs(target:GetChildren()) do child:Destroy() end
	uiFrame.Parent = target
	return true
end

-- ═══════════════════════════════════════════════════════════
-- TOPBAR BUTTON
-- ═══════════════════════════════════════════════════════════

local function createTopbarButton()
	local topGui = UI.new("ScreenGui", {
		Name = "MenuButtonGui", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
	})

	local btn = UI.button({
		Name = "MenuTopbarButton", Size = UDim2.new(0, 82, 0, 42),
		Position = UDim2.new(1, -92, 0, 13), BackgroundColor3 = T.CARD,
		Text = "", Parent = topGui,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = btn })

	local btnStroke = UI.stroke(T.ACCENT, 0.5, 0.35)
	btnStroke.Parent = btn

	local label = UI.text({
		Size = UDim2.new(1, 0, 1, 0), Text = "Menu", TextColor3 = T.TEXT,
		Font = FONT.MEDIUM, TextSize = 14, Parent = btn,
	})

	-- Satu fungsi tampilan tombol, dipakai hover maupun perubahan state panel.
	local function paintTopbar(hovered)
		local open = (PM.active ~= nil)
		UI.tween(btn, { BackgroundColor3 = (hovered or open) and T.CARD_HOVER or T.CARD }, CFG.tween.fast)
		UI.tween(label, { TextColor3 = open and T.ACCENT or T.TEXT }, CFG.tween.fast)
		UI.tween(btnStroke, { Transparency = (hovered or open) and 0.1 or 0.35 }, CFG.tween.fast)
	end

	UI.bindHover(btn, paintTopbar)

	btn.MouseButton1Down:Connect(function()
		UI.tween(btn, { Size = UDim2.new(0, 78, 0, 42) }, CFG.tween.instant)
	end)
	btn.MouseButton1Up:Connect(function()
		UI.tween(btn, { Size = UDim2.new(0, 82, 0, 42) }, CFG.tween.instant)
	end)
	btn.Activated:Connect(function() PM.toggle("Menu") end)

	-- Ikut berubah kalau panel ditutup lewat overlay atau script lain.
	_G.PanelCoordinator.OnChange(function() paintTopbar(false) end)

	return topGui
end

-- ═══════════════════════════════════════════════════════════
-- TOPBAR SLOTS
-- Satu tempat yang mengatur posisi tombol topbar tambahan (Command "/",
-- Tool, Dance, dll) supaya tidak ada script yang menghitung offset sendiri
-- dan tidak ada tombol yang saling menimpa.
--
-- Dua baris jangkar:
--   row = "menu" → berbaris ke kiri dari tombol Menu (y = 13)
--   row = "info" → berbaris ke kiri dari tombol Info (y = 62)
-- Di landscape hanya ada satu baris (tombol Info berada di kiri layar), jadi
-- semua slot digabung ke baris Menu dan diurutkan memakai `order`.
--
-- contentTop() memberi Y aman untuk panel supaya tidak menabrak tombol topbar.
-- ═══════════════════════════════════════════════════════════

local TOPBAR_GAP = 8

if not _G.TopbarLayout then
	local TL = { slots = {} }

	local function isPortrait()
		local vp = getViewport()
		return vp.Y > vp.X
	end

	local function menuButton()
		local topbar = _G.TopbarGui
		return topbar and topbar:FindFirstChild("MenuTopbarButton")
	end

	local function infoButton()
		local gui = playerGui:FindFirstChild("InfoTopbarGui")
		return gui and gui:FindFirstChild("InfoTopbarButton")
	end

	local function widthOf(obj)
		local w = obj.AbsoluteSize.X
		if w <= 0 then w = obj.Size.X.Offset end
		return w
	end

	-- Titik awal (cursor X, Y) untuk sebuah baris.
	local function anchorFor(row)
		if row == "info" and isPortrait() then
			local info = infoButton()
			if info then
				return info.Position.X.Offset - widthOf(info) - TOPBAR_GAP, info.Position.Y.Offset
			end
			return -10 - TOPBAR_GAP, 62
		end

		local menu = menuButton()
		if menu then
			return menu.Position.X.Offset - TOPBAR_GAP, menu.Position.Y.Offset
		end
		return -100, 13
	end

	function TL.register(name, obj, order, row)
		TL.slots[name] = { obj = obj, order = order or 10, row = row or "info" }
		obj.AnchorPoint = Vector2.new(1, 0)
		TL.refresh()
		-- AbsoluteSize baru terisi setelah frame dirender; susun ulang sesudahnya.
		task.defer(TL.refresh)
		task.delay(0.2, TL.refresh)
	end

	function TL.unregister(name)
		TL.slots[name] = nil
		TL.refresh()
	end

	function TL.refresh()
		local portrait = isPortrait()
		local rows     = { menu = {}, info = {} }

		for name, slot in pairs(TL.slots) do
			local obj = slot.obj
			if obj and obj.Parent and obj.Visible then
				-- Landscape: semua slot masuk satu baris (baris Menu).
				local row = portrait and slot.row or "menu"
				table.insert(rows[row], { name = name, obj = obj, order = slot.order })
			end
		end

		for row, list in pairs(rows) do
			table.sort(list, function(a, b)
				if a.order ~= b.order then return a.order < b.order end
				return a.name < b.name
			end)

			local cursor, y = anchorFor(row)
			for _, slot in ipairs(list) do
				slot.obj.AnchorPoint = Vector2.new(1, 0)
				slot.obj.Position    = UDim2.new(1, cursor, 0, y)
				cursor = cursor - widthOf(slot.obj) - TOPBAR_GAP
			end
		end
	end

	-- Batas bawah seluruh baris topbar; panel sebaiknya mulai di bawah ini.
	function TL.contentTop()
		local bottom = 55   -- baris Menu default (y 13 + tinggi 42)

		local menu = menuButton()
		if menu then
			local h = menu.AbsoluteSize.Y
			if h <= 0 then h = menu.Size.Y.Offset end
			bottom = math.max(bottom, menu.Position.Y.Offset + h)
		end

		local info = infoButton()
		if info and isPortrait() then
			local h = info.AbsoluteSize.Y
			if h <= 0 then h = info.Size.Y.Offset end
			bottom = math.max(bottom, info.Position.Y.Offset + h)
		end

		return math.floor(bottom + 10)
	end

	-- Tombol Info bisa dibuat setelah registry ini ada, dan lebarnya
	-- (AutomaticSize) baru diketahui setelah dirender. Pantau keduanya supaya
	-- barisan portrait selalu menempel di kiri tombol Info.
	local infoConn
	local function watchInfo()
		local btn = infoButton()
		if not btn or infoConn then return end
		infoConn = btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(TL.refresh)
		btn:GetPropertyChangedSignal("Position"):Connect(TL.refresh)
		TL.refresh()
	end

	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "InfoTopbarGui" then task.defer(watchInfo) end
	end)
	watchInfo()

	_G.TopbarLayout = TL
end

-- ═══════════════════════════════════════════════════════════
-- RESIZE (debounced: ViewportSize bisa fire puluhan kali per detik)
-- ═══════════════════════════════════════════════════════════

local resizeToken = 0

local function applyResize()
	CFG.layout = getLayout()
	for _, pd in pairs(PM.panels) do
		pd.layout(CFG.layout)
	end
	if _G.TopbarLayout then _G.TopbarLayout.refresh() end
end

local cameraConn
local function bindCamera()
	if cameraConn then cameraConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if not cam then return end
	cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		resizeToken = resizeToken + 1
		local token = resizeToken
		task.delay(CFG.RESIZE_DEBOUNCE, function()
			if token == resizeToken then applyResize() end
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

CFG.layout = getLayout()
PM.init()

local menuPanel = createPanel({
	name = "Menu", title = "Menu",
	tabs = { "Settings", "Shop", "Music", "Players" },
})
PM.register("Menu", menuPanel)

local topbarGui = createTopbarButton()

bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera()
	applyResize()
end)

_G.PanelContainer = PM.container
_G.PanelManager   = PM
_G.MenuPanel      = menuPanel.contents
_G.MenuConfig     = CFG
_G.MenuUI         = UI
_G.MenuIcon       = topbarGui
_G.TopbarGui      = topbarGui

_G.InjectUI      = inject
_G.InjectMusicUI = function(frame)      return inject("Menu", "Music", frame) end
_G.InjectPanelUI = function(tab, frame) return inject("Menu", tab, frame)     end
_G.ToggleMenu    = function() PM.toggle("Menu") end
_G.OpenMenu      = function() PM.show("Menu")   end
_G.CloseMenu     = function() PM.hide("Menu")   end

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(plr)
	if plr ~= player then return end

	for _, t in pairs(activeTweens) do pcall(function() t:Cancel() end) end
	if cameraConn then cameraConn:Disconnect() end

	destroyGlobal("ToolsIcon")
	destroyGlobal("MenuIcon")
	destroyGlobal("PanelContainer")

	for _, key in ipairs({
		CFG.ID, "PanelManager", "PanelContainer", "MenuPanel", "MenuConfig", "MenuUI",
		"MenuIcon", "TopbarGui", "InjectUI", "InjectMusicUI", "InjectPanelUI",
		"ToggleMenu", "OpenMenu", "CloseMenu",
		}) do
		_G[key] = nil
	end
end)