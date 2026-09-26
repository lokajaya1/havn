-- GlowStick UI | LocalScript → StarterGui
-- Depends on: DynamicTools, GlowStickColorChanged RemoteEvent
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local player           = Players.LocalPlayer

local TOOL_NAME   = "GlowStick"
local ICON_IMAGE  = "rbxassetid://7345154971"
local MAX_RETRIES = 100
local RETRY_DELAY = 0.15

local remoteEvent = ReplicatedStorage:WaitForChild("GlowStickColorChanged", 10)
if not remoteEvent then warn("[GlowStick] GlowStickColorChanged not found") end

local COLORS = {
	{ name = "Red",     color = Color3.fromRGB(255,   0,   0) },
	{ name = "Green",   color = Color3.fromRGB(  0, 255,   0) },
	{ name = "Blue",    color = Color3.fromRGB(  0,   0, 255) },
	{ name = "Yellow",  color = Color3.fromRGB(255, 255,   0) },
	{ name = "Cyan",    color = Color3.fromRGB(  0, 255, 255) },
	{ name = "Magenta", color = Color3.fromRGB(255,   0, 255) },
	{ name = "White",   color = Color3.fromRGB(255, 255, 255) },
	{ name = "Orange",  color = Color3.fromRGB(255, 128,   0) },
	{ name = "Pink",    color = Color3.fromRGB(255, 128, 255) },
	{ name = "Purple",  color = Color3.fromRGB(128,   0, 255) },
}

local State = {
	currentColor = Color3.fromRGB(255, 255, 255),
	activeButtons= {},
	connections  = {},
	sliders      = {},   -- { R, G, B } → { value, valueLabel, fill }
}

local function conn(sig, fn)
	table.insert(State.connections, sig:Connect(fn))
end

local function disconnectAll()
	for _, c in ipairs(State.connections) do pcall(c.Disconnect, c) end
	table.clear(State.connections)
end

local function applyColor(color)
	State.currentColor = color
	if remoteEvent then
		remoteEvent:FireServer(color)
	end
end

local function syncSliders(color)
	local vals = { R = math.floor(color.R * 255), G = math.floor(color.G * 255), B = math.floor(color.B * 255) }
	for ch, v in pairs(vals) do
		local s = State.sliders[ch]
		if s then
			s.value            = v
			s.valueLabel.Text  = tostring(v)
			s.fill.Size        = UDim2.new(v / 255, 0, 1, 0)
		end
	end
end

-- ── Color button ──────────────────────────────────────────
local function makeColorButton(data, order, parent)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = data.color
	btn.BorderSizePixel  = 0
	btn.Text             = ""
	btn.LayoutOrder      = order
	btn.Parent           = parent

	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color       = Color3.fromRGB(255, 255, 255)
	stroke.Thickness   = 0
	stroke.Transparency= 0.7
	stroke.Parent      = btn

	State.activeButtons[data.name] = { btn = btn, stroke = stroke, color = data.color }

	conn(btn.MouseEnter, function()
		stroke.Thickness = 2; btn.Size = UDim2.new(1, 4, 1, 4)
	end)
	conn(btn.MouseLeave, function()
		stroke.Thickness = State.currentColor == data.color and 3 or 0
		btn.Size = UDim2.new(1, 0, 1, 0)
	end)
	conn(btn.Activated, function()
		for _, d in pairs(State.activeButtons) do
			d.stroke.Thickness = 0
			d.stroke.Color     = Color3.fromRGB(255, 255, 255)
			d.btn.Size         = UDim2.new(1, 0, 1, 0)
		end
		stroke.Thickness = 3
		stroke.Color     = Color3.fromRGB(255, 255, 0)
		btn.Size         = UDim2.new(1, 4, 1, 4)
		applyColor(data.color)
		syncSliders(data.color)
	end)
end

-- ── RGB Slider ────────────────────────────────────────────
local FILL_COLOR = { R = Color3.fromRGB(255,0,0), G = Color3.fromRGB(0,255,0), B = Color3.fromRGB(0,0,255) }

local function makeSlider(ch, defaultVal, order, parent)
	local frame = Instance.new("Frame")
	frame.Size               = UDim2.new(1, 0, 0, 40)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder        = order
	frame.Parent             = parent

	local label = Instance.new("TextLabel")
	label.Size               = UDim2.new(0, 30, 1, 0)
	label.BackgroundTransparency = 1
	label.Text               = ch
	label.TextColor3         = Color3.fromRGB(255, 255, 255)
	label.TextSize           = 16
	label.Font               = Enum.Font.GothamBold
	label.Parent             = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size               = UDim2.new(0, 40, 1, 0)
	valueLabel.Position           = UDim2.new(1, -40, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text               = tostring(defaultVal)
	valueLabel.TextColor3         = Color3.fromRGB(200, 200, 200)
	valueLabel.TextSize           = 14
	valueLabel.Font               = Enum.Font.Gotham
	valueLabel.Parent             = frame

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, -80, 0, 6)
	bg.Position         = UDim2.new(0, 35, 0.5, -3)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	bg.BorderSizePixel  = 0
	bg.Parent           = frame

	local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(1, 0); bgc.Parent = bg

	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(defaultVal / 255, 0, 1, 0)
	fill.BackgroundColor3 = FILL_COLOR[ch]
	fill.BorderSizePixel  = 0
	fill.Parent           = bg

	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill

	State.sliders[ch] = { value = defaultVal, valueLabel = valueLabel, fill = fill }

	local dragging = false

	local function onMove(input)
		local rel = math.clamp(input.Position.X - bg.AbsolutePosition.X, 0, bg.AbsoluteSize.X)
		local pct = rel / bg.AbsoluteSize.X
		local val = math.floor(pct * 255)
		State.sliders[ch].value = val
		valueLabel.Text         = tostring(val)
		fill.Size               = UDim2.new(pct, 0, 1, 0)
		applyColor(Color3.fromRGB(State.sliders.R.value, State.sliders.G.value, State.sliders.B.value))
		-- Reset preset highlights (custom color)
		for _, d in pairs(State.activeButtons) do
			d.stroke.Thickness = 0
			d.stroke.Color     = Color3.fromRGB(255, 255, 255)
			d.btn.Size         = UDim2.new(1, 0, 1, 0)
		end
	end

	conn(bg.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true; onMove(input)
		end
	end)
	conn(bg.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	conn(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			onMove(input)
		end
	end)
end

-- ── Build UI ──────────────────────────────────────────────
local function buildUI()
	disconnectAll()
	State.sliders       = {}
	State.activeButtons = {}

	local main = Instance.new("Frame")
	main.Name            = "GlowStickSettings"
	main.Size            = UDim2.new(1, 0, 0, 0)
	main.AutomaticSize   = Enum.AutomaticSize.Y
	main.BackgroundTransparency = 1

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 8)
	layout.Parent    = main

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 10); pad.PaddingRight  = UDim.new(0, 10)
	pad.PaddingTop    = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent        = main

	-- Title
	local title = Instance.new("TextLabel")
	title.Size               = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Text               = "🌟 GlowStick Color"
	title.TextColor3         = Color3.fromRGB(255, 255, 255)
	title.TextSize           = 18
	title.Font               = Enum.Font.GothamBold
	title.TextXAlignment     = Enum.TextXAlignment.Left
	title.LayoutOrder        = 1
	title.Parent             = main

	-- Color grid container
	local gridContainer = Instance.new("Frame")
	gridContainer.Size            = UDim2.new(1, 0, 0, 0)
	gridContainer.AutomaticSize  = Enum.AutomaticSize.Y
	gridContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	gridContainer.BorderSizePixel = 0
	gridContainer.LayoutOrder     = 2
	gridContainer.Parent          = main

	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 8); gc.Parent = gridContainer

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize           = UDim2.new(0, 45, 0, 45)
	gridLayout.CellPadding        = UDim2.new(0, 6, 0, 6)
	gridLayout.SortOrder          = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment= Enum.HorizontalAlignment.Center
	gridLayout.Parent             = gridContainer

	local gp = Instance.new("UIPadding")
	gp.PaddingLeft   = UDim.new(0, 8); gp.PaddingRight  = UDim.new(0, 8)
	gp.PaddingTop    = UDim.new(0, 8); gp.PaddingBottom = UDim.new(0, 8)
	gp.Parent        = gridContainer

	for i, data in ipairs(COLORS) do
		makeColorButton(data, i, gridContainer)
	end

	-- RGB section
	local rgbSection = Instance.new("Frame")
	rgbSection.Size            = UDim2.new(1, 0, 0, 0)
	rgbSection.AutomaticSize  = Enum.AutomaticSize.Y
	rgbSection.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	rgbSection.BorderSizePixel = 0
	rgbSection.LayoutOrder     = 3
	rgbSection.Parent          = main

	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = rgbSection

	local rgbLayout = Instance.new("UIListLayout")
	rgbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rgbLayout.Padding   = UDim.new(0, 10)
	rgbLayout.Parent    = rgbSection

	local rp = Instance.new("UIPadding")
	rp.PaddingLeft   = UDim.new(0, 12); rp.PaddingRight  = UDim.new(0, 12)
	rp.PaddingTop    = UDim.new(0, 12); rp.PaddingBottom = UDim.new(0, 12)
	rp.Parent        = rgbSection

	makeSlider("R", math.floor(State.currentColor.R * 255), 1, rgbSection)
	makeSlider("G", math.floor(State.currentColor.G * 255), 2, rgbSection)
	makeSlider("B", math.floor(State.currentColor.B * 255), 3, rgbSection)

	return main
end

-- ── Init ──────────────────────────────────────────────────
task.spawn(function()
	for _ = 1, MAX_RETRIES do
		if _G.RegisterDynamicTool then
			_G.RegisterDynamicTool(TOOL_NAME, buildUI, { iconImage = ICON_IMAGE })
			print("[GlowStick UI] Registered")
			return
		end
		task.wait(RETRY_DELAY)
	end
	warn("[GlowStick UI] DynamicTools not found")
end)