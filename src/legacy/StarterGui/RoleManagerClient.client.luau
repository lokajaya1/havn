-- ═══════════════════════════════════════════════════════════
-- RoleTitleMenu — StarterPlayer > StarterPlayerScripts
--
-- Panel pengatur title. Mengikuti pola MenuSystemInit: helper new(),
-- THEME yang sama, baris kartu dengan garis accent, dan panel menempel
-- bawah layar di atas hotbar.
--
-- Ukuran panel dihitung sendiri, bukan dari Responsive.Panel(). Angka
-- di sana disetel untuk menu player yang isinya sedikit; dipakai di sini
-- isinya kepotong. Responsive tetap dipakai untuk mendeteksi perubahan
-- layar dan device.
--
-- Semua pilihan memakai UIGridLayout supaya membungkus ke baris baru.
-- Scroll horizontal tersembunyi bikin setengah warna tidak terlihat.
--
-- Toggle: _G.ToggleRoleManager()
-- ═══════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local TextService  = game:GetService("TextService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Didaftarkan lebih dulu supaya SettingsClient tidak mencari fungsi yang
-- belum ada selama script ini masih menunggu modul dan remote.
_G.ToggleRoleManager = function() end

local modules = RS:WaitForChild("CustomUIModules", 15)
if not modules then
	warn("[RoleTitleMenu] Folder 'CustomUIModules' tidak ketemu.")
	return
end

local Responsive = require(modules:WaitForChild("Responsive"))

local function waitForTitleStyle(timeout)
	local deadline = os.clock() + timeout
	repeat
		local module = modules:FindFirstChild("TitleStyle") or RS:FindFirstChild("TitleStyle")
		if module and module:IsA("ModuleScript") then return require(module) end
		task.wait(0.25)
	until os.clock() > deadline
	return nil
end

local TitleStyle = waitForTitleStyle(15)
if not TitleStyle then
	warn("[RoleTitleMenu] ModuleScript 'TitleStyle' tidak ketemu di ReplicatedStorage.")
	return
end

local remotes = RS:WaitForChild("AdminTitles", 20)
if not remotes then
	warn("[RoleTitleMenu] Folder remote 'AdminTitles' tidak ada — cek AdminTitleService.")
	return
end

local checkAccess  = remotes:WaitForChild("CheckAccess")
local getPlayers   = remotes:WaitForChild("GetPlayers")
local setTitle     = remotes:WaitForChild("SetTitle")
local clearTitle   = remotes:WaitForChild("ClearTitle")
local titleUpdated = remotes:WaitForChild("TitleUpdated")

if not checkAccess:InvokeServer() then return end

-- ════════════════════════════════════════════════════════════
-- THEME
-- ════════════════════════════════════════════════════════════

local THEME = {
	BG         = Color3.fromRGB(16, 16, 17),
	CARD       = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	TRACK      = Color3.fromRGB(48, 48, 52),
	LINE       = Color3.fromRGB(255, 255, 255),
	TEXT       = Color3.fromRGB(238, 238, 240),
	TEXT_DIM   = Color3.fromRGB(148, 148, 154),
	ACCENT     = Color3.fromRGB(212, 175, 55),
	DANGER     = Color3.fromRGB(235, 86, 96),
	OK         = Color3.fromRGB(120, 200, 130),
}

local TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_CHARS = 30

local state = {
	list       = {},
	targetId   = nil,
	color      = TitleStyle.WHITE,
	plate      = "Fade",
	plateColor = TitleStyle.INK,
	font       = "Builder",
	effect     = "None",
	outline    = true,
	open       = false,
}

-- ════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════

local function new(class, props)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	return obj
end

local function corner(parent, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thick, trans)
	return new("UIStroke", {
		Name = "Stroke", Color = color, Thickness = thick, Transparency = trans or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local function clampChars(str, max)
	local ok, count = pcall(utf8.len, str)
	if not ok or not count then return str:sub(1, max) end
	if count <= max then return str end
	local offset = utf8.offset(str, max + 1)
	return offset and str:sub(1, offset - 1) or str:sub(1, max)
end

local function getConfig()
	local ok, panel = pcall(Responsive.Panel)
	panel = (ok and type(panel) == "table") and panel or {}

	local viewport = workspace.CurrentCamera.ViewportSize
	local mobile = panel.device == "mobile"

	return {
		bottomInset = panel.bottomInset or 10,
		width  = math.clamp(math.floor(viewport.X * (mobile and 0.92 or 0.33)), 300, 400),
		height = math.clamp(math.floor(viewport.Y * 0.7), 340, 580),
		pad = 14, gap = 8,
		row = 34, chip = 28, swatch = 28, chipWidth = 78,
		titleSize = 15, textSize = 13, smallSize = 10,
		previewHeight = 78, listHeight = 132,
	}
end

local cfg = getConfig()
local order = 0
local function nextOrder()
	order += 1
	return order
end

-- ════════════════════════════════════════════════════════════
-- FRAME
-- ════════════════════════════════════════════════════════════

local existing = playerGui:FindFirstChild("RoleTitleGui")
if existing then existing:Destroy() end

local gui = new("ScreenGui", {
	Name = "RoleTitleGui", ResetOnSpawn = false, IgnoreGuiInset = false,
	Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 12, Parent = playerGui,
})

local frame = new("Frame", {
	Name = "TitleFrame", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -cfg.bottomInset),
	Size = UDim2.new(0, cfg.width, 0, cfg.height),
	BackgroundColor3 = THEME.BG, BorderSizePixel = 0, Active = true,
	ClipsDescendants = true, Parent = gui,
})
corner(frame, 16)
stroke(frame, THEME.LINE, 1, 0.88)

local header = new("Frame", {
	Name = "Header", Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1,
	ZIndex = 5, Parent = frame,
})

new("TextLabel", {
	Position = UDim2.new(0, cfg.pad, 0, 0), Size = UDim2.new(1, -cfg.pad - 44, 1, 0),
	BackgroundTransparency = 1, Text = "Role title", TextColor3 = THEME.TEXT,
	Font = Enum.Font.BuilderSansBold, TextSize = cfg.titleSize,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = header,
})

local closeBtn = new("TextButton", {
	Name = "CloseButton", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 26, 0, 26),
	BackgroundTransparency = 1, Text = "×", TextColor3 = THEME.TEXT_DIM,
	Font = Enum.Font.BuilderSans, TextSize = cfg.titleSize + 8,
	BorderSizePixel = 0, AutoButtonColor = false, ZIndex = 6, Parent = header,
})
closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeBtn, TWEEN, { TextColor3 = THEME.TEXT }):Play()
end)
closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeBtn, TWEEN, { TextColor3 = THEME.TEXT_DIM }):Play()
end)

local scroll = new("ScrollingFrame", {
	Name = "ScrollFrame", Position = UDim2.new(0, 0, 0, 42),
	Size = UDim2.new(1, 0, 1, -42), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.TEXT_DIM,
	ScrollBarImageTransparency = 0.5, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y, Parent = frame,
})

local content = new("Frame", {
	Name = "Content", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll,
})

local contentLayout = new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, cfg.gap),
	Parent = content,
})

local contentPadding = new("UIPadding", {
	PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, cfg.pad + 4),
	PaddingLeft = UDim.new(0, cfg.pad), PaddingRight = UDim.new(0, cfg.pad),
	Parent = content,
})

local captions = {}
local function caption(str)
	local label = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, cfg.smallSize + 6), BackgroundTransparency = 1,
		Text = str, TextColor3 = THEME.TEXT_DIM, Font = Enum.Font.BuilderSans,
		TextSize = cfg.smallSize, TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = nextOrder(), Parent = content,
	})
	table.insert(captions, label)
	return label
end

-- Grid membungkus otomatis ke baris berikutnya, jadi tidak ada pilihan
-- yang tersembunyi di luar layar.
local function gridBox(cellWidth, cellHeight)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = content,
	})
	new("UIGridLayout", {
		CellSize = UDim2.new(0, cellWidth, 0, cellHeight),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder,
	})
	return holder
end

-- ── PREVIEW ────────────────────────────────────────────────

local previewCard = new("Frame", {
	Name = "Preview", Size = UDim2.new(1, 0, 0, cfg.previewHeight),
	BackgroundColor3 = Color3.fromRGB(120, 128, 140), BorderSizePixel = 0,
	ClipsDescendants = true, LayoutOrder = nextOrder(), Parent = content,
})
corner(previewCard, 12)
stroke(previewCard, THEME.LINE, 1, 0.9)

new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(146, 152, 163)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB( 92,  98, 108)),
	}),
	Parent = previewCard,
})

-- Plate di atas, nama dummy di bawah, jarak sama seperti di dunia.
local plateHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, 2),
	Size = UDim2.new(1, -16, 0, 22), BackgroundTransparency = 1, Parent = previewCard,
})

local preview = TitleStyle.Build(plateHolder, 14)

local previewName = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 3),
	Size = UDim2.new(1, -16, 0, 16), BackgroundTransparency = 1,
	Text = player.DisplayName, TextColor3 = THEME.LINE,
	Font = Enum.Font.BuilderSansBold, TextSize = 14, Parent = previewCard,
})
new("UIStroke", { Color = Color3.fromRGB(0,0,0), Thickness = 1, Transparency = 0.5, Parent = previewName })

local function currentStyle()
	return {
		text = "", color = state.color, plate = state.plate,
		plateColor = state.plateColor, font = state.font,
		effect = state.effect, outline = state.outline,
	}
end

local repaint

-- ── PLAYER ─────────────────────────────────────────────────

caption("PILIH PLAYER")

local search = new("TextBox", {
	Name = "Search", Size = UDim2.new(1, 0, 0, cfg.row),
	BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, Text = "",
	PlaceholderText = "Cari nama atau @username", TextColor3 = THEME.TEXT,
	PlaceholderColor3 = THEME.TEXT_DIM, Font = Enum.Font.BuilderSans,
	TextSize = cfg.textSize, TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false, LayoutOrder = nextOrder(), Parent = content,
})
corner(search, 10)
stroke(search, THEME.LINE, 1, 0.92)
new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = search })

local playerList = new("ScrollingFrame", {
	Name = "PlayerList", Size = UDim2.new(1, 0, 0, cfg.listHeight),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
	ScrollBarImageColor3 = THEME.TEXT_DIM, ScrollBarImageTransparency = 0.5,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	LayoutOrder = nextOrder(), Parent = content,
})
local playerLayout = new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5), Parent = playerList,
})

-- ── TEKS ───────────────────────────────────────────────────

caption("TEKS TITLE")

local input = new("TextBox", {
	Name = "TitleInput", Size = UDim2.new(1, 0, 0, cfg.row),
	BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, Text = "",
	PlaceholderText = "Tulis title di sini", TextColor3 = THEME.TEXT,
	PlaceholderColor3 = THEME.TEXT_DIM, Font = Enum.Font.BuilderSansMedium,
	TextSize = cfg.textSize, TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false, LayoutOrder = nextOrder(), Parent = content,
})
corner(input, 10)
stroke(input, THEME.LINE, 1, 0.92)
new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 46), Parent = input })

local counter = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.new(0, 34, 1, 0), BackgroundTransparency = 1,
	Text = "0/" .. MAX_CHARS, TextColor3 = THEME.TEXT_DIM,
	Font = Enum.Font.BuilderSans, TextSize = cfg.smallSize,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2, Parent = input,
})

-- ── PILIHAN ────────────────────────────────────────────────

caption("WARNA TEKS")
local colorBox = gridBox(cfg.swatch, cfg.swatch)

caption("PLATE")
local plateBox = gridBox(cfg.chipWidth, cfg.chip)

caption("WARNA PLATE")
local plateColorBox = gridBox(cfg.swatch, cfg.swatch)

caption("FONT")
local fontBox = gridBox(cfg.chipWidth, cfg.chip)

caption("EFEK")
local effectBox = gridBox(cfg.chipWidth, cfg.chip)

-- ── OUTLINE ────────────────────────────────────────────────

caption("OUTLINE")

local outlineRow = new("Frame", {
	Name = "OutlineRow", Size = UDim2.new(1, 0, 0, cfg.row),
	BackgroundColor3 = THEME.CARD, BorderSizePixel = 0,
	LayoutOrder = nextOrder(), Parent = content,
})
corner(outlineRow, 10)
stroke(outlineRow, THEME.LINE, 1, 0.92)

local outlineLabel = new("TextLabel", {
	Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -76, 1, 0),
	BackgroundTransparency = 1, Text = "Garis pinggir teks", TextColor3 = THEME.TEXT,
	Font = Enum.Font.BuilderSansMedium, TextSize = cfg.textSize,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = outlineRow,
})

local outlineTrack = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.new(0, 42, 0, 22), BackgroundColor3 = THEME.ACCENT,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = outlineRow,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = outlineTrack })

local outlineKnob = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
	Size = UDim2.new(0, 18, 0, 18), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0, Parent = outlineTrack,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = outlineKnob })

local function paintOutlineToggle()
	TweenService:Create(outlineTrack, TWEEN, {
		BackgroundColor3 = state.outline and THEME.ACCENT or THEME.TRACK,
	}):Play()
	TweenService:Create(outlineKnob, TWEEN, {
		Position = state.outline and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
	}):Play()
end

outlineTrack.Activated:Connect(function()
	state.outline = not state.outline
	paintOutlineToggle()
	repaint()
end)

-- ── AKSI ───────────────────────────────────────────────────

local function actionRow(label, color)
	local button = new("TextButton", {
		Size = UDim2.new(1, 0, 0, cfg.row), BackgroundColor3 = THEME.CARD,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		ClipsDescendants = true, LayoutOrder = nextOrder(), Parent = content,
	})
	corner(button, 10)
	local st = stroke(button, THEME.LINE, 1, 0.92)

	local accent = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0, 0), BackgroundColor3 = color,
		BorderSizePixel = 0, ZIndex = 2, Parent = button,
	})
	corner(accent, 2)

	local text = new("TextLabel", {
		Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -28, 1, 0),
		BackgroundTransparency = 1, Text = label, TextColor3 = color,
		Font = Enum.Font.BuilderSansBold, TextSize = cfg.textSize,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = button,
	})

	local function hover(on)
		TweenService:Create(button, TWEEN, { BackgroundColor3 = on and THEME.CARD_HOVER or THEME.CARD }):Play()
		TweenService:Create(accent, TWEEN, { Size = on and UDim2.new(0, 2, 0.55, 0) or UDim2.new(0, 2, 0, 0) }):Play()
		TweenService:Create(st, TWEEN, { Transparency = on and 0.78 or 0.92 }):Play()
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function() hover(false) end)
	button.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then hover(true) end
	end)
	button.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then hover(false) end
	end)

	return button, text
end

local applyButton, applyText = actionRow("Terapkan title", THEME.ACCENT)
local clearButton, clearText = actionRow("Hapus title", THEME.DANGER)

local feedbackToken = 0
local function feedback(label, message, color, original)
	feedbackToken += 1
	local token = feedbackToken
	label.Text = message
	TweenService:Create(label, TWEEN, { TextColor3 = color }):Play()
	task.delay(2.2, function()
		if token ~= feedbackToken then return end
		label.Text = original
		TweenService:Create(label, TWEEN, {
			TextColor3 = original == "Terapkan title" and THEME.ACCENT or THEME.DANGER,
		}):Play()
	end)
end

-- ════════════════════════════════════════════════════════════
-- PREVIEW
-- ════════════════════════════════════════════════════════════

repaint = function()
	local style = currentStyle()
	style.text = input.Text ~= "" and input.Text or "Label"
	preview.label.TextTransparency = input.Text ~= "" and 0 or 0.35
	TitleStyle.Paint(preview, style)
	TitleStyle.Animate(preview, style, 0)
end

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	if not state.open or state.effect == "None" then return end
	clock += dt
	TitleStyle.Animate(preview, currentStyle(), clock)
end)

-- ════════════════════════════════════════════════════════════
-- SWATCH & CHIP
-- ════════════════════════════════════════════════════════════

local swatches = { color = {}, plateColor = {} }
local chips = { plate = {}, font = {}, effect = {} }

local function markSwatch(group, color)
	local hex = TitleStyle.ToHex(color)
	for _, item in ipairs(swatches[group]) do
		local on = TitleStyle.ToHex(item.color) == hex
		TweenService:Create(item.stroke, TWEEN, {
			Color = on and THEME.ACCENT or THEME.LINE,
			Thickness = on and 2 or 1,
			Transparency = on and 0 or 0.85,
		}):Play()
	end
end

local function markChip(group, key)
	for chipKey, item in pairs(chips[group]) do
		local on = chipKey == key
		TweenService:Create(item.button, TWEEN, {
			BackgroundColor3 = on and THEME.CARD_HOVER or THEME.CARD,
		}):Play()
		TweenService:Create(item.label, TWEEN, {
			TextColor3 = on and THEME.ACCENT or THEME.TEXT_DIM,
		}):Play()
		TweenService:Create(item.stroke, TWEEN, {
			Color = on and THEME.ACCENT or THEME.LINE,
			Transparency = on and 0.5 or 0.92,
		}):Play()
	end
end

local function addSwatch(parent, group, color, index, onPick)
	local button = new("TextButton", {
		BackgroundColor3 = color, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", LayoutOrder = index, Parent = parent,
	})
	corner(button, 8)
	local st = stroke(button, THEME.LINE, 1, 0.85)
	table.insert(swatches[group], { button = button, stroke = st, color = color })
	button.Activated:Connect(function() onPick(color) end)
end

local function addChip(parent, group, key, label, index, onPick, font)
	local button = new("TextButton", {
		BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", LayoutOrder = index, ClipsDescendants = true, Parent = parent,
	})
	corner(button, 8)
	local st = stroke(button, THEME.LINE, 1, 0.92)

	local text = new("TextLabel", {
		Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0),
		BackgroundTransparency = 1, Text = label, TextColor3 = THEME.TEXT_DIM,
		Font = font or Enum.Font.BuilderSansMedium, TextSize = cfg.smallSize + 1,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
	})

	chips[group][key] = { button = button, label = text, stroke = st }
	button.Activated:Connect(function() onPick(key) end)
end

-- ════════════════════════════════════════════════════════════
-- DAFTAR PLAYER
-- ════════════════════════════════════════════════════════════

local rowByUserId = {}

local function markSelection()
	for userId, row in pairs(rowByUserId) do
		local on = userId == state.targetId
		TweenService:Create(row.button, TWEEN, {
			BackgroundColor3 = on and THEME.CARD_HOVER or THEME.CARD,
		}):Play()
		TweenService:Create(row.accent, TWEEN, {
			Size = on and UDim2.new(0, 2, 0.55, 0) or UDim2.new(0, 2, 0, 0),
		}):Play()
		TweenService:Create(row.stroke, TWEEN, {
			Color = on and THEME.ACCENT or THEME.LINE,
			Transparency = on and 0.6 or 0.92,
		}):Play()
	end
end

local function selectPlayer(data)
	state.targetId = data.UserId
	markSelection()

	if data.HasTitle then
		input.Text       = data.Title
		state.color      = TitleStyle.FromHex(data.Color, TitleStyle.WHITE)
		state.plateColor = TitleStyle.FromHex(data.PlateColor, TitleStyle.INK)
		state.plate      = data.Plate
		state.font       = data.Font
		state.effect     = data.Effect
		state.outline    = data.Outline ~= false
		markSwatch("color", state.color)
		markSwatch("plateColor", state.plateColor)
		markChip("plate", state.plate)
		markChip("font", state.font)
		markChip("effect", state.effect)
		paintOutlineToggle()
	else
		input.Text = ""
	end

	previewName.Text = data.DisplayName
	repaint()
end

local function createPlayerRow(data, index)
	local button = new("TextButton", {
		Name = "Player_" .. data.UserId, Size = UDim2.new(1, -4, 0, cfg.row),
		BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", ClipsDescendants = true, LayoutOrder = index, Parent = playerList,
	})
	corner(button, 10)
	local st = stroke(button, THEME.LINE, 1, 0.92)

	local accent = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0, 0), BackgroundColor3 = THEME.ACCENT,
		BorderSizePixel = 0, ZIndex = 2, Parent = button,
	})
	corner(accent, 2)

	new("TextLabel", {
		Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(0.6, -14, 1, 0),
		BackgroundTransparency = 1, Text = data.DisplayName,
		TextColor3 = data.HasTitle and THEME.TEXT or THEME.TEXT_DIM,
		Font = Enum.Font.BuilderSansMedium, TextSize = cfg.textSize,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
	})

	new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.4, -14, 1, 0), BackgroundTransparency = 1,
		Text = data.RoleDisplay, TextColor3 = THEME.TEXT_DIM,
		Font = Enum.Font.BuilderSans, TextSize = cfg.smallSize,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
	})

	rowByUserId[data.UserId] = { button = button, accent = accent, stroke = st }
	button.Activated:Connect(function() selectPlayer(data) end)
end

local function renderList()
	for _, child in ipairs(playerList:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	table.clear(rowByUserId)

	local query = search.Text:lower()
	for index, data in ipairs(state.list) do
		if query == ""
			or data.Name:lower():find(query, 1, true)
			or data.DisplayName:lower():find(query, 1, true) then
			createPlayerRow(data, index)
		end
	end
	markSelection()
end

local fetching = false
local function fetchPlayers()
	if fetching then return end
	fetching = true
	task.spawn(function()
		local ok, list = pcall(function() return getPlayers:InvokeServer() end)
		fetching = false
		if ok and type(list) == "table" then
			state.list = list
			renderList()
		end
	end)
end

-- ════════════════════════════════════════════════════════════
-- EVENT
-- ════════════════════════════════════════════════════════════

local searchToken = 0
search:GetPropertyChangedSignal("Text"):Connect(function()
	searchToken += 1
	local token = searchToken
	task.delay(0.18, function()
		if token == searchToken then renderList() end
	end)
end)

input:GetPropertyChangedSignal("Text"):Connect(function()
	local clamped = clampChars(input.Text, MAX_CHARS)
	if clamped ~= input.Text then
		input.Text = clamped
		return
	end
	local ok, count = pcall(utf8.len, clamped)
	count = (ok and count) or #clamped
	counter.Text = count .. "/" .. MAX_CHARS
	counter.TextColor3 = count >= MAX_CHARS and THEME.DANGER or THEME.TEXT_DIM
	repaint()
end)

applyButton.Activated:Connect(function()
	if not state.targetId then
		feedback(applyText, "Pilih player dulu", THEME.DANGER, "Terapkan title")
		return
	end
	local text = input.Text:match("^%s*(.-)%s*$")
	if text == "" then
		feedback(applyText, "Teks masih kosong", THEME.DANGER, "Terapkan title")
		return
	end
	setTitle:FireServer(state.targetId, {
		text       = text,
		color      = TitleStyle.ToHex(state.color),
		plate      = state.plate,
		plateColor = TitleStyle.ToHex(state.plateColor),
		font       = state.font,
		effect     = state.effect,
		outline    = state.outline,
	})
	feedback(applyText, "Tersimpan", THEME.OK, "Terapkan title")
	task.delay(0.6, fetchPlayers)
end)

clearButton.Activated:Connect(function()
	if not state.targetId then
		feedback(clearText, "Pilih player dulu", THEME.DANGER, "Hapus title")
		return
	end
	clearTitle:FireServer(state.targetId)
	input.Text = ""
	feedback(clearText, "Title dihapus", THEME.OK, "Hapus title")
	task.delay(0.6, fetchPlayers)
end)

titleUpdated.OnClientEvent:Connect(function()
	if state.open then fetchPlayers() end
end)

closeBtn.Activated:Connect(function() _G.ToggleRoleManager() end)

-- ════════════════════════════════════════════════════════════
-- INIT
-- ════════════════════════════════════════════════════════════

for index, item in ipairs(TitleStyle.COLORS) do
	addSwatch(colorBox, "color", item.color, index, function(color)
		state.color = color
		markSwatch("color", color)
		repaint()
	end)
	addSwatch(plateColorBox, "plateColor", item.color, index, function(color)
		state.plateColor = color
		markSwatch("plateColor", color)
		repaint()
	end)
end

for index, item in ipairs(TitleStyle.PLATES) do
	addChip(plateBox, "plate", item.key, item.name, index, function(key)
		state.plate = key
		markChip("plate", key)
		repaint()
	end)
end

for index, item in ipairs(TitleStyle.FONTS) do
	addChip(fontBox, "font", item.name, item.name, index, function(key)
		state.font = key
		markChip("font", key)
		repaint()
	end, item.font)
end

for index, item in ipairs(TitleStyle.EFFECTS) do
	addChip(effectBox, "effect", item.key, item.name, index, function(key)
		state.effect = key
		markChip("effect", key)
		repaint()
	end)
end

markSwatch("color", state.color)
markSwatch("plateColor", state.plateColor)
markChip("plate", state.plate)
markChip("font", state.font)
markChip("effect", state.effect)
paintOutlineToggle()
repaint()

-- ════════════════════════════════════════════════════════════
-- RESPONSIVE
-- ════════════════════════════════════════════════════════════

local function applyConfig(c)
	frame.Size = UDim2.new(0, c.width, 0, c.height)
	frame.Position = UDim2.new(0.5, 0, 1, -c.bottomInset)

	contentLayout.Padding = UDim.new(0, c.gap)
	contentPadding.PaddingLeft = UDim.new(0, c.pad)
	contentPadding.PaddingRight = UDim.new(0, c.pad)
	contentPadding.PaddingBottom = UDim.new(0, c.pad + 4)

	previewCard.Size = UDim2.new(1, 0, 0, c.previewHeight)
	playerList.Size  = UDim2.new(1, 0, 0, c.listHeight)
	playerLayout.Padding = UDim.new(0, 5)

	search.Size = UDim2.new(1, 0, 0, c.row)
	input.Size  = UDim2.new(1, 0, 0, c.row)
	outlineRow.Size = UDim2.new(1, 0, 0, c.row)
	applyButton.Size = UDim2.new(1, 0, 0, c.row)
	clearButton.Size = UDim2.new(1, 0, 0, c.row)

	search.TextSize = c.textSize
	input.TextSize  = c.textSize
	counter.TextSize = c.smallSize
	outlineLabel.TextSize = c.textSize
	applyText.TextSize = c.textSize
	clearText.TextSize = c.textSize
	closeBtn.TextSize = c.titleSize + 8

	for _, label in ipairs(captions) do
		label.TextSize = c.smallSize
		label.Size = UDim2.new(1, 0, 0, c.smallSize + 6)
	end

	for _, row in pairs(rowByUserId) do
		row.button.Size = UDim2.new(1, -4, 0, c.row)
	end

	cfg = c
end

applyConfig(cfg)
Responsive.OnChange(function()
	if frame.Parent then applyConfig(getConfig()) end
end)

-- ════════════════════════════════════════════════════════════
-- TOGGLE
-- ════════════════════════════════════════════════════════════

_G.ToggleRoleManager = function()
	state.open = not state.open
	gui.Enabled = state.open
	if state.open then
		applyConfig(getConfig())
		fetchPlayers()
	end
end

_G.RoleTitleMenu = {
	Gui = gui,
	Open  = function() if not state.open then _G.ToggleRoleManager() end end,
	Close = function() if state.open then _G.ToggleRoleManager() end end,
}