--!nonstrict
-- DanceClient — StarterPlayer > StarterPlayerScripts
-- UI dibangun sepenuhnya lewat kode; list dance memakai virtualisasi.
-- Urutan panel: tab → search → list → speed slider (dasar panel).
--
-- Aset animasi dipanaskan lewat AnimationWarmup (LoadAnimation + tunggu
-- Length > 0), bukan ContentProvider:PreloadAsync yang tidak bekerja untuk
-- animasi. Tanpa ini, dance yang diputar server sempat terlihat diam di sisi
-- client karena datanya belum turun.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if _G.DanceClient then return end
_G.DanceClient = true

-- ═══════════════════════════════════════════════════════════
-- KONFIG & TEMA
-- ═══════════════════════════════════════════════════════════

-- Hapus otomatis DanceGUI lama buatan Studio supaya tidak dobel.
local REMOVE_LEGACY_GUI = true

local T = {
	BG         = Color3.fromRGB(16, 16, 17),
	CARD       = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	LINE       = Color3.fromRGB(255, 255, 255),
	TEXT       = Color3.fromRGB(238, 238, 240),
	TEXT_DIM   = Color3.fromRGB(148, 148, 154),
	ACCENT     = Color3.fromRGB(212, 175, 55),
}

local FONT = {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local CFG = {
	SPEED_MIN      = 0.5,
	SPEED_MAX      = 2.0,
	SPEED_STEP     = 0.05,
	SPEED_DEFAULT  = 1.0,
	SPEED_THROTTLE = 0.12,   -- detik; batasi FireServer saat slider digeser

	SEARCH_DEBOUNCE = 0.15,
	EDGE_MARGIN     = 8,
	ROW_BUFFER      = 4,     -- baris ekstra di luar viewport (scroll mulus)
	SPEED_ROW_H     = 18,
	WARMUP_DELAY    = 1.5,   -- mulai panaskan aset setelah UI siap
	SYNC_CARD_H     = 40,

	BTN_SIZE   = 40,
	BTN_ICON   = 21,
	ICON_IMAGE = "rbxassetid://7059328055", -- siluet putih polos, ikut warna tema
	ANIM       = 0.28,
}

-- Preset layout per device/orientasi: {scale, min, max}
local LAYOUT = {
	mobile = {
		portrait  = { w = {0.46, 148, 190}, h = {0.42, 215, 305}, row = 30, text = 11, small = 9,  pad = 8, gap = 5 },
		landscape = { w = {0.24, 136, 178}, h = {0.80, 150, 232}, row = 26, text = 10, small = 9,  pad = 7, gap = 4 },
	},
	tablet = {
		portrait  = { w = {0.21, 160, 205}, h = {0.42, 230, 310}, row = 32, text = 12, small = 10, pad = 9, gap = 5 },
		landscape = { w = {0.17, 158, 200}, h = {0.56, 220, 300}, row = 31, text = 11, small = 10, pad = 8, gap = 5 },
	},
	desktop = {
		portrait  = { w = {0.13, 165, 205}, h = {0.40, 230, 300}, row = 32, text = 12, small = 10, pad = 9, gap = 5 },
		landscape = { w = {0.13, 165, 205}, h = {0.40, 230, 300}, row = 32, text = 12, small = 10, pad = 9, gap = 5 },
	},
}

-- ═══════════════════════════════════════════════════════════
-- HELPER
-- ═══════════════════════════════════════════════════════════

local function new(class, props)
	local obj = Instance.new(class)
	for key, value in pairs(props) do obj[key] = value end
	return obj
end

local function corner(parent, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or T.LINE, Thickness = thickness or 1,
		Transparency = transparency or 0.9,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local TW_FAST  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_SLIDE = TweenInfo.new(CFG.ANIM, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(obj, props, info)
	local t = TweenService:Create(obj, info or TW_FAST, props)
	t:Play()
	return t
end

local function isPointer(input)
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

local function isMove(input)
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch
end

-- Hover untuk mouse sekaligus sentuh (MouseEnter tidak jalan di layar sentuh).
local function bindHover(obj, apply, guard)
	local function set(on)
		if guard and not guard() then return end
		apply(on)
	end
	obj.MouseEnter:Connect(function() set(true) end)
	obj.MouseLeave:Connect(function() set(false) end)
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then set(true) end
	end)
	obj.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then set(false) end
	end)
end

local function fmtSpeed(value)
	local text = string.format("%.2f", value):gsub("0$", ""):gsub("%.$", "")
	return text .. "x"
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ═══════════════════════════════════════════════════════════
-- VIEWPORT / DEVICE
-- ═══════════════════════════════════════════════════════════

local function getViewport()
	local camera = workspace.CurrentCamera
	local size   = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if size.X <= 10 or size.Y <= 10 then return Vector2.new(1280, 720) end
	return size
end

local function getDeviceType()
	local touch    = UserInputService.TouchEnabled
	local keyboard = UserInputService.KeyboardEnabled
	if touch and not keyboard then
		local size = getViewport()
		return (math.max(size.X, size.Y) >= 1000) and "tablet" or "mobile"
	elseif touch and keyboard then
		return "tablet"
	end
	return "desktop"
end

local function resolve(axis, spec)
	return math.floor(math.clamp(axis * spec[1], spec[2], spec[3]))
end

local function getConfig()
	local size   = getViewport()
	local preset = LAYOUT[getDeviceType()][(size.X > size.Y) and "landscape" or "portrait"]

	return {
		width     = math.min(resolve(size.X, preset.w), math.floor(size.X) - 2 * CFG.EDGE_MARGIN),
		height    = math.min(resolve(size.Y, preset.h), math.floor(size.Y) - 2 * CFG.EDGE_MARGIN),
		rowHeight = preset.row,
		textSize  = preset.text,
		smallSize = preset.small,
		padding   = preset.pad,
		gap       = preset.gap,
	}
end

-- ═══════════════════════════════════════════════════════════
-- DATA
-- ═══════════════════════════════════════════════════════════

-- Modul di ReplicatedStorage belum tentu sudah ter-replikasi saat script ini
-- mulai, jadi ditunggu dengan timeout. Satu modul yang salah taruh tidak boleh
-- membuat seluruh UI dance hilang.
local function requireFrom(path, timeout)
	local target = ReplicatedStorage
	for _, name in ipairs(path) do
		target = target:WaitForChild(name, timeout or 10)
		if not target then
			warn("[DanceClient] tidak ditemukan: ReplicatedStorage." .. table.concat(path, "."))
			return nil
		end
	end
	local ok, result = pcall(require, target)
	if not ok then
		warn("[DanceClient] gagal require " .. target.Name .. ":", result)
		return nil
	end
	return result
end

local DanceConfig = requireFrom({ "Config", "DanceConfig" })
local DanceAssets = requireFrom({ "Assets", "Animations", "Dances", "DanceAssets" })

if not (DanceConfig and DanceAssets) then
	warn("[DanceClient] DanceConfig/DanceAssets tidak tersedia — UI dance dibatalkan")
	_G.DanceClient = nil
	return
end

-- Warm-up opsional; tanpa modul ini dance tetap bisa diputar.
local AnimationWarmup = requireFrom({ "Modules", "AnimationWarmup" }, 5)
	or { add = function() end, addByName = function() end }

local danceRemote     = ReplicatedStorage:WaitForChild("DanceRequest")
local favoritesRemote = ReplicatedStorage:FindFirstChild("FavoritesRemote")
local syncRemote      = ReplicatedStorage:FindFirstChild("SyncRemote")

local POSE_KEYWORDS = {
	"pose", "stand", "idle", "sit", "lean", "squat",
	"kneel", "lay", "crouch", "statue", "freeze",
}

local ALL_DANCES, ALL_POSES = {}, {}
local lowerName = {}   -- nama -> lowercase, dipakai filter pencarian

local function lowerOf(name)
	local cached = lowerName[name]
	if not cached then
		cached = name:lower()
		lowerName[name] = cached
	end
	return cached
end

do
	local names = {}
	if type(DanceConfig.getDanceNames) == "function" then
		names = DanceConfig:getDanceNames()
	elseif type(DanceConfig.danceName) == "table" then
		names = DanceConfig.danceName
	else
		for name in pairs(DanceConfig.dances or DanceConfig:getDances()) do
			names[#names + 1] = name
		end
	end

	local customIsPose = type(DanceAssets.isPose) == "function" and DanceAssets.isPose or nil

	local function isPose(name)
		if customIsPose then
			local ok, result = pcall(customIsPose, name)
			if ok then return result end
		end
		local lower = lowerOf(name)
		for _, keyword in ipairs(POSE_KEYWORDS) do
			if lower:find(keyword, 1, true) then return true end
		end
		return false
	end

	-- Nama dari DanceConfig yang tidak punya id di DanceAssets akan ditolak
	-- server, jadi barisnya jangan sampai muncul di list — tap ke baris seperti
	-- itu tidak menghasilkan apa pun dan terlihat seperti dance yang rusak.
	local missing = {}
	for _, name in ipairs(names) do
		if DanceAssets.dances[name] then
			local target = isPose(name) and ALL_POSES or ALL_DANCES
			target[#target + 1] = name
		else
			missing[#missing + 1] = name
		end
	end
	table.sort(ALL_DANCES)
	table.sort(ALL_POSES)

	if #missing > 0 then
		table.sort(missing)
		warn(string.format(
			"[DanceClient] %d nama dari DanceConfig tidak ada di DanceAssets dan disembunyikan: %s%s",
			#missing,
			table.concat(missing, ", ", 1, math.min(#missing, 10)),
			#missing > 10 and " ..." or ""
			))
	end
	print(string.format("[DanceClient] %d dances, %d emotes siap", #ALL_DANCES, #ALL_POSES))
end

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local State = {
	tab        = "DANCES",
	query      = "",
	items      = ALL_DANCES,
	favorites  = {},
	favSet     = {},   -- lookup O(1) untuk ikon bintang
	playing    = nil,
	speed      = CFG.SPEED_DEFAULT,
	open       = false,
	isSyncing  = false,
	syncTarget = "None",
	customPos  = false,
}

local TABS_ORDER = { "DANCES", "EMOTES", "FAVORITES" }
local TABS = {
	DANCES    = { label = "Dances", hint = "Search dances", source = function() return ALL_DANCES end },
	EMOTES    = { label = "Emotes", hint = "Search emotes", source = function() return ALL_POSES  end },
	FAVORITES = { label = "Favs",   hint = "Search favs",   source = function() return State.favorites end },
}

-- ═══════════════════════════════════════════════════════════
-- BUILD UI
-- ═══════════════════════════════════════════════════════════

if REMOVE_LEGACY_GUI then
	local legacy = playerGui:FindFirstChild("DanceGUI")
	if legacy then legacy:Destroy() end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "DanceGUI" then child:Destroy() end
	end)
end

local C = getConfig()

local gui = new("ScreenGui", {
	Name = "DanceHubGui", ResetOnSpawn = false, IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 8, Parent = playerGui,
})

local panel = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, -400, 0.5, 0),
	Size = UDim2.new(0, C.width, 0, C.height),
	BackgroundColor3 = T.BG, BorderSizePixel = 0, Active = true,
	ClipsDescendants = false, Parent = gui,
})
corner(panel, 16)
stroke(panel, T.LINE, 1, 0.88)

-- ── GRIP (mengambang di atas panel, tidak memakan tinggi panel) ──
local gripHit = new("Frame", {
	Name = "Grip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -1),
	Size = UDim2.new(0, 52, 0, 14), BackgroundTransparency = 1, Active = true, Parent = panel,
})

local gripLine = new("Frame", {
	Name = "Line", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 30, 0, 3), BackgroundColor3 = T.ACCENT,
	BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gripHit,
})
corner(gripLine, 2)

-- ── HEADER (isinya cuma tab) ───────────────────────────────
local header = new("Frame", {
	Name = "Header", BackgroundTransparency = 1, Active = true, Parent = panel,
})

local tabBar = new("Frame", { Name = "TabBar", BackgroundTransparency = 1, Parent = header })

local tabButtons = {}
for index, key in ipairs(TABS_ORDER) do
	local button = new("TextButton", {
		Name = "Tab_" .. key, BackgroundColor3 = T.CARD, BorderSizePixel = 0,
		AutoButtonColor = false, Text = TABS[key].label, TextColor3 = T.TEXT_DIM,
		Font = FONT.MEDIUM, TextSize = C.smallSize + 1, LayoutOrder = index,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = tabBar,
	})
	corner(button, 8)
	tabButtons[key] = { button = button, stroke = stroke(button, T.LINE, 1, 0.94) }
end

-- ── SEARCH ─────────────────────────────────────────────────
local searchBar = new("Frame", {
	Name = "SearchBar", BackgroundColor3 = T.CARD, BorderSizePixel = 0, Parent = panel,
})
corner(searchBar, 10)
local searchStroke = stroke(searchBar, T.LINE, 1, 0.92)

-- ClearTextOnFocus: tiap kali box diklik/di-tap, keyword lama langsung hilang.
local searchBox = new("TextBox", {
	Name = "SearchBox", BackgroundTransparency = 1, ClearTextOnFocus = true,
	Text = "", PlaceholderText = TABS.DANCES.hint, PlaceholderColor3 = T.TEXT_DIM,
	TextColor3 = T.TEXT, Font = FONT.REGULAR, TextSize = C.textSize,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = searchBar,
})

local clearBtn = new("TextButton", {
	Name = "ClearSearch", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 20, 0, 20),
	BackgroundTransparency = 1, Text = "×", TextColor3 = T.TEXT_DIM,
	Font = FONT.REGULAR, TextSize = 18, AutoButtonColor = false,
	Visible = false, Parent = searchBar,
})

-- ── LIST ───────────────────────────────────────────────────
local list = new("ScrollingFrame", {
	Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 3,
	ScrollBarImageColor3 = T.TEXT_DIM, ScrollBarImageTransparency = 0.55,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.None, Parent = panel,
})

local emptyLabel = new("TextLabel", {
	Name = "EmptyState", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24),
	Size = UDim2.new(1, -24, 0, 40), BackgroundTransparency = 1, Text = "",
	TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = C.textSize,
	TextWrapped = true, Visible = false, Parent = list,
})

-- ── SPEED SLIDER (dasar panel) ─────────────────────────────
local speedRow = new("Frame", { Name = "SpeedRow", BackgroundTransparency = 1, Parent = panel })

-- Nilai "1x" sekaligus tombol reset, jadi slider cukup satu baris.
local speedValue = new("TextButton", {
	Name = "SpeedValue", BackgroundTransparency = 1, Text = fmtSpeed(CFG.SPEED_DEFAULT),
	TextColor3 = T.ACCENT, Font = FONT.BOLD, TextSize = C.smallSize,
	TextXAlignment = Enum.TextXAlignment.Right, AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0.5), Parent = speedRow,
})

-- Hit area lebih besar dari track supaya gampang di-tap di HP.
local sliderHit = new("TextButton", {
	Name = "SliderHit", BackgroundTransparency = 1, Text = "",
	AutoButtonColor = false, Parent = speedRow,
})

local sliderTrack = new("Frame", {
	Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = T.CARD_HOVER,
	BorderSizePixel = 0, Parent = sliderHit,
})
corner(sliderTrack, 2)

local sliderFill = new("Frame", {
	Name = "Fill", Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = T.ACCENT,
	BorderSizePixel = 0, Parent = sliderTrack,
})
corner(sliderFill, 2)

local sliderKnob = new("Frame", {
	Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 11, 0, 11), BackgroundColor3 = T.ACCENT,
	BorderSizePixel = 0, ZIndex = 3, Parent = sliderTrack,
})
corner(sliderKnob, 6)
stroke(sliderKnob, T.BG, 2, 0)

-- ── SYNC CARD (mengambang tepat di atas slider) ────────────
local syncCard = new("TextButton", {
	Name = "SyncCard", BackgroundColor3 = T.CARD, BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 1), AutoButtonColor = false,
	Text = "", Visible = false, ZIndex = 6, Parent = panel,
})
corner(syncCard, 12)
stroke(syncCard, T.ACCENT, 1, 0.55)

corner(new("Frame", {
	Name = "Accent", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.new(0, 2, 0.6, 0), BackgroundColor3 = T.ACCENT,
	BorderSizePixel = 0, ZIndex = 7, Parent = syncCard,
}), 2)

local syncTitle = new("TextLabel", {
	Name = "SyncTitle", Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -34, 0, 13),
	BackgroundTransparency = 1, Text = "Sync", TextColor3 = T.ACCENT,
	Font = FONT.BOLD, TextSize = C.smallSize, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = syncCard,
})

local syncDetail = new("TextLabel", {
	Name = "SyncDetail", Position = UDim2.new(0, 10, 0, 20), Size = UDim2.new(1, -34, 0, 13),
	BackgroundTransparency = 1, Text = "", TextColor3 = T.TEXT_DIM,
	Font = FONT.REGULAR, TextSize = C.smallSize - 1, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = syncCard,
})

local syncStopLabel = new("TextLabel", {
	Name = "SyncStop", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.new(0, 18, 0, 18), BackgroundTransparency = 1, Text = "✕",
	TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = C.smallSize + 3,
	ZIndex = 7, Parent = syncCard,
})

-- ── TOGGLE BUTTON ──────────────────────────────────────────
-- Default mengambang di kiri layar. Kalau panel digeser, tombol menumpang di
-- topbar dan barisannya diatur _G.TopbarLayout.
local buttonGui = new("ScreenGui", {
	Name = "DanceToggleButton", ResetOnSpawn = false, DisplayOrder = -1, Parent = playerGui,
})

local buttonFrame = new("Frame", {
	Name = "DanceBtn", AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE),
	Position = UDim2.new(0, 15, 0.5, 0), BackgroundTransparency = 1, Parent = buttonGui,
})

local toggleBtn = new("TextButton", {
	Name = "Toggle", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = T.CARD,
	BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = buttonFrame,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = toggleBtn })
local toggleStroke = stroke(toggleBtn, T.ACCENT, 0.5, 0.35)

local toggleIcon = new("ImageLabel", {
	Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, CFG.BTN_ICON, 0, CFG.BTN_ICON), BackgroundTransparency = 1,
	Image = CFG.ICON_IMAGE, ImageColor3 = T.TEXT,
	ScaleType = Enum.ScaleType.Fit, Parent = toggleBtn,
})

-- Dipakai hover maupun buka/tutup, jadi tampilan tombol diatur di satu tempat.
local function paintToggle(hovered)
	local active = State.open or hovered
	tween(toggleBtn,    { BackgroundColor3 = active and T.CARD_HOVER or T.CARD })
	tween(toggleStroke, { Transparency = active and 0.1 or 0.35 })
	tween(toggleIcon,   { ImageColor3 = State.open and T.ACCENT or T.TEXT })
end

-- ═══════════════════════════════════════════════════════════
-- LAYOUT
-- ═══════════════════════════════════════════════════════════

local rowStep    = C.rowHeight + 6
local listPadTop = 4
local listTop, listBottom = 0, 0
local hiddenPos  = UDim2.new(0, -(C.width + 40), 0.5, 0)
local visiblePos = UDim2.new(0, CFG.EDGE_MARGIN, 0.5, 0)

local renderWindow, ensurePool

local function gripWidth()
	return math.clamp(math.floor(C.width * 0.18), 24, 40)
end

local function layoutList()
	local available = listBottom - listTop

	-- Di layar pendek, sync card mengambang di atas list agar list tidak habis.
	local reserve = State.isSyncing and (CFG.SYNC_CARD_H + C.gap) or 0
	if reserve > 0 and (available - reserve) < rowStep * 3 then reserve = 0 end

	list.Size = UDim2.new(1, -2 * C.padding, 0, math.max(available - reserve, 40))
	ensurePool()
	renderWindow(true)
end

local function applyLayout()
	local pad, gap = C.padding, C.gap
	rowStep = C.rowHeight + math.max(gap - 1, 4)

	panel.Size = UDim2.new(0, C.width, 0, C.height)

	local headerH = math.max(C.rowHeight - 9, 22)
	header.Position = UDim2.new(0, pad, 0, pad)
	header.Size     = UDim2.new(1, -2 * pad, 0, headerH)

	gripHit.Position = UDim2.new(0.5, 0, 0, -1)
	gripLine.Size    = UDim2.new(0, gripWidth(), 0, 3)

	tabBar.Position = UDim2.new(0, 0, 0, 0)
	tabBar.Size     = UDim2.new(1, 0, 0, headerH)

	for index, key in ipairs(TABS_ORDER) do
		local button = tabButtons[key].button
		button.Size     = UDim2.new(1 / 3, -4, 1, 0)
		button.Position = UDim2.new((index - 1) / 3, (index - 1) * 2, 0, 0)
		button.TextSize = C.smallSize + 1
	end

	local searchY = pad + headerH + gap
	local searchH = math.max(C.rowHeight - 8, 24)
	searchBar.Position = UDim2.new(0, pad, 0, searchY)
	searchBar.Size     = UDim2.new(1, -2 * pad, 0, searchH)
	searchBox.Position = UDim2.new(0, 10, 0, 0)
	searchBox.Size     = UDim2.new(1, -32, 1, 0)
	searchBox.TextSize = C.textSize

	local valueW = C.smallSize * 3 + 8
	local speedY = C.height - pad - CFG.SPEED_ROW_H
	speedRow.Position = UDim2.new(0, pad, 0, speedY)
	speedRow.Size     = UDim2.new(1, -2 * pad, 0, CFG.SPEED_ROW_H)

	speedValue.Position = UDim2.new(1, 0, 0.5, 0)
	speedValue.Size     = UDim2.new(0, valueW, 1, 0)
	speedValue.TextSize = C.smallSize

	sliderHit.Position = UDim2.new(0, 2, 0, 0)
	sliderHit.Size     = UDim2.new(1, -(valueW + 10), 1, 0)

	listTop       = searchY + searchH + gap
	listBottom    = speedY - gap
	list.Position = UDim2.new(0, pad, 0, listTop)

	syncCard.Position      = UDim2.new(0.5, 0, 0, listBottom)
	syncCard.Size          = UDim2.new(1, -2 * pad, 0, CFG.SYNC_CARD_H)
	syncTitle.TextSize     = C.smallSize
	syncDetail.TextSize    = math.max(C.smallSize - 1, 8)
	syncStopLabel.TextSize = C.smallSize + 3
	emptyLabel.TextSize    = C.smallSize + 1

	hiddenPos = UDim2.new(0, -(C.width + 40), 0.5, 0)
	if not State.customPos then
		visiblePos = UDim2.new(0, CFG.EDGE_MARGIN, 0.5, 0)
	end
	panel.Position = State.open and visiblePos or hiddenPos

	layoutList()
end

-- ═══════════════════════════════════════════════════════════
-- LIST VIRTUALISASI
-- ═══════════════════════════════════════════════════════════

local rowPool    = {}
local firstShown = -1
local pooledRowH = -1

local toggleFavorite, playOrStop

-- Repaint hanya kalau isi baris berubah, jadi scroll tidak menulis properti
-- yang nilainya sama.
local function paintRow(row, name, force)
	local playing = (State.playing == name)
	local favored = State.favSet[name] == true

	if not force and row.lastName == name and row.lastPlaying == playing and row.lastFav == favored then
		return
	end
	row.lastName, row.lastPlaying, row.lastFav = name, playing, favored

	row.button.BackgroundColor3 = playing and T.CARD_HOVER or T.CARD
	row.label.Text              = name
	row.label.TextColor3        = playing and T.ACCENT or T.TEXT
	row.label.Font              = playing and FONT.MEDIUM or FONT.REGULAR
	row.accent.Size             = playing and UDim2.new(0, 2, 0.55, 0) or UDim2.new(0, 2, 0, 0)
	row.stroke.Transparency     = playing and 0.72 or 0.94
	row.favorite.Text           = favored and "★" or "☆"
	row.favorite.TextColor3     = favored and T.ACCENT or T.TEXT_DIM
end

local function createRow()
	-- `: any` supaya Luau tidak menyegel tabel kosong ini; field diisi setelah
	-- dibuat dan row.index sengaja bisa nil.
	local row: any = {}

	local button = new("TextButton", {
		Name = "Row", Size = UDim2.new(1, 0, 0, C.rowHeight),
		BackgroundColor3 = T.CARD, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", ClipsDescendants = true, Visible = false, Parent = list,
	})
	corner(button, 10)

	row.button = button
	row.stroke = stroke(button, T.LINE, 1, 0.94)

	row.accent = new("Frame", {
		Name = "Accent", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0, 0), BackgroundColor3 = T.ACCENT,
		BorderSizePixel = 0, ZIndex = 2, Parent = button,
	})
	corner(row.accent, 2)

	row.label = new("TextLabel", {
		Name = "NameLabel", Position = UDim2.new(0, 11, 0, 0), Size = UDim2.new(1, -42, 1, 0),
		BackgroundTransparency = 1, Text = "", TextColor3 = T.TEXT, Font = FONT.REGULAR,
		TextSize = C.textSize, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
	})

	row.favorite = new("TextButton", {
		Name = "FavoriteBtn", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.new(0, 24, 0, 24), BackgroundTransparency = 1, Text = "☆",
		TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = C.textSize + 3,
		AutoButtonColor = false, ZIndex = 3, Parent = button,
	})

	local function currentName()
		return row.index and State.items[row.index] or nil
	end

	bindHover(button, function(on)
		tween(button, { BackgroundColor3 = on and T.CARD_HOVER or T.CARD })
		tween(row.accent, { Size = on and UDim2.new(0, 2, 0.35, 0) or UDim2.new(0, 2, 0, 0) })
	end, function()
		local name = currentName()
		return name ~= nil and State.playing ~= name
	end)

	button.Activated:Connect(function()
		local name = currentName()
		if name then playOrStop(name) end
	end)
	row.favorite.Activated:Connect(function()
		local name = currentName()
		if name then toggleFavorite(name) end
	end)

	return row
end

function ensurePool()
	local viewHeight = list.AbsoluteSize.Y
	if viewHeight <= 0 then viewHeight = C.height end

	local needed = math.ceil(viewHeight / rowStep) + CFG.ROW_BUFFER
	while #rowPool < needed do
		rowPool[#rowPool + 1] = createRow()
	end

	-- Ukuran baris hanya ditulis ulang saat benar-benar berubah.
	if pooledRowH ~= C.rowHeight then
		pooledRowH = C.rowHeight
		for _, row in ipairs(rowPool) do
			row.button.Size     = UDim2.new(1, 0, 0, C.rowHeight)
			row.label.TextSize  = C.textSize
			row.favorite.TextSize = C.textSize + 3
		end
	end
end

-- Panaskan aset baris yang sedang terlihat, jadi saat di-tap sudah siap.
local lastWarm = 0
local warmIds  = {}

local function warmVisible()
	local now = os.clock()
	if now - lastWarm < 0.2 then return end
	lastWarm = now

	table.clear(warmIds)
	for _, row in ipairs(rowPool) do
		local name = row.index and State.items[row.index]
		local assetId = name and DanceAssets.dances[name]
		if assetId then warmIds[#warmIds + 1] = assetId end
	end
	if #warmIds > 0 then AnimationWarmup.add(warmIds) end
end

function renderWindow(force)
	local items = State.items
	local count = #items
	local first = math.max(1, math.floor(list.CanvasPosition.Y / rowStep) - 1)

	if not force and first == firstShown then return end
	firstShown = first

	for offset, row in ipairs(rowPool) do
		local index = first + offset - 1
		if index <= count then
			row.index           = index
			row.button.Position = UDim2.new(0, 0, 0, listPadTop + (index - 1) * rowStep)
			row.button.Visible  = true
			paintRow(row, items[index], force)
		else
			row.index          = nil
			row.button.Visible = false
		end
	end

	warmVisible()
end

local function refreshRows()
	for _, row in ipairs(rowPool) do
		if row.index and row.button.Visible then
			local name = State.items[row.index]
			if name then paintRow(row, name, false) end
		end
	end
end

local function updateEmptyState()
	if #State.items > 0 then
		emptyLabel.Visible = false
		return
	end
	emptyLabel.Visible = true
	if State.query ~= "" then
		emptyLabel.Text = "No results for \"" .. State.query .. "\"."
	elseif State.tab == "FAVORITES" then
		emptyLabel.Text = "No favorites yet. Tap ☆ on any dance to save it."
	else
		emptyLabel.Text = "Nothing here yet."
	end
end

local filtered = {}   -- dipakai ulang tiap pencarian, tanpa alokasi baru

local function applyFilter(keepScroll)
	local source = TABS[State.tab].source()

	if State.query == "" then
		State.items = source
	else
		table.clear(filtered)
		local query = State.query:lower()
		for _, name in ipairs(source) do
			if lowerOf(name):find(query, 1, true) then
				filtered[#filtered + 1] = name
			end
		end
		State.items = filtered
	end

	list.CanvasSize = UDim2.new(0, 0, 0, math.max(#State.items * rowStep + listPadTop + 6, 0))
	if not keepScroll then list.CanvasPosition = Vector2.new(0, 0) end

	searchBox.PlaceholderText = TABS[State.tab].hint
	updateEmptyState()
	ensurePool()
	renderWindow(true)
end

-- ═══════════════════════════════════════════════════════════
-- FAVORIT
-- ═══════════════════════════════════════════════════════════

local function refreshFavorites(names)
	State.favorites = names
	local set = {}
	for _, name in ipairs(names) do set[name] = true end
	State.favSet = set

	if State.tab == "FAVORITES" then applyFilter(true) else refreshRows() end
end

-- Cadangan lokal kalau remote favorit belum ada di tempat.
local function persistLocal()
	pcall(function()
		player:SetAttribute("DanceFavorites_v2", HttpService:JSONEncode(State.favorites))
	end)
end

function toggleFavorite(name)
	local index = table.find(State.favorites, name)
	if index then
		table.remove(State.favorites, index)
	else
		table.insert(State.favorites, name)
	end

	if favoritesRemote then
		favoritesRemote:FireServer(index and "remove" or "add", name)
	else
		persistLocal()
	end
	refreshFavorites(State.favorites)
end

if favoritesRemote then
	favoritesRemote.OnClientEvent:Connect(function(action, data)
		if (action == "loaded" or action == "updated") and type(data) == "table" then
			refreshFavorites(data)
		end
	end)
end

local function loadFavorites()
	if favoritesRemote then
		favoritesRemote:FireServer("load")
		return
	end
	local ok, data = pcall(function()
		local raw = player:GetAttribute("DanceFavorites_v2")
		return raw and HttpService:JSONDecode(raw) or {}
	end)
	if ok and type(data) == "table" then refreshFavorites(data) end
end

-- ═══════════════════════════════════════════════════════════
-- DANCE PLAY / SPEED
-- ═══════════════════════════════════════════════════════════

function playOrStop(name)
	if State.isSyncing then return end

	-- Kalau dance ini belum dipanaskan, dorong ke depan antrean.
	local assetId = DanceAssets.dances[name]
	if assetId then AnimationWarmup.add({ assetId }, true) end

	if State.playing == name then
		State.playing = nil
		danceRemote:FireServer("", State.speed)
	else
		State.playing = name
		danceRemote:FireServer(name, State.speed)
	end
	refreshRows()
end

local lastSpeedFire = 0

local function pushSpeed(force)
	if State.isSyncing or not State.playing then return end
	local now = os.clock()
	if not force and (now - lastSpeedFire) < CFG.SPEED_THROTTLE then return end
	lastSpeedFire = now
	danceRemote:FireServer(State.playing, State.speed)
end

local function setSpeed(value, commit)
	value = math.clamp(value, CFG.SPEED_MIN, CFG.SPEED_MAX)
	value = math.floor(value / CFG.SPEED_STEP + 0.5) * CFG.SPEED_STEP
	value = math.clamp(value, CFG.SPEED_MIN, CFG.SPEED_MAX)

	local changed = math.abs(value - State.speed) > 1e-4
	State.speed = value

	local alpha = (value - CFG.SPEED_MIN) / (CFG.SPEED_MAX - CFG.SPEED_MIN)
	sliderFill.Size     = UDim2.new(alpha, 0, 1, 0)
	sliderKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
	if not State.isSyncing then speedValue.Text = fmtSpeed(value) end

	if changed or commit then pushSpeed(commit) end
end

-- Sumbu X tidak terpengaruh GUI inset, jadi AbsolutePosition.X aman dipakai.
local function speedFromX(x)
	local left  = sliderTrack.AbsolutePosition.X
	local width = math.max(sliderTrack.AbsoluteSize.X, 1)
	return CFG.SPEED_MIN + math.clamp((x - left) / width, 0, 1) * (CFG.SPEED_MAX - CFG.SPEED_MIN)
end

local dragging, dragSlider = false, false
local captureInput -- diisi di bagian DRAG (butuh clampPanel & helper topbar)

sliderHit.InputBegan:Connect(function(input)
	if State.isSyncing or not isPointer(input) then return end
	dragSlider = true
	tween(sliderKnob, { Size = UDim2.new(0, 15, 0, 15) })
	setSpeed(speedFromX(input.Position.X), false)
	captureInput()
end)

speedValue.Activated:Connect(function()
	if State.isSyncing then return end
	setSpeed(CFG.SPEED_DEFAULT, true)
end)
bindHover(speedValue, function(on)
	tween(speedValue, { TextColor3 = on and T.TEXT or T.ACCENT })
end, function() return not State.isSyncing end)

-- ═══════════════════════════════════════════════════════════
-- SYNC UI
-- ═══════════════════════════════════════════════════════════

local function updateSyncDetail(danceName)
	syncDetail.Text = (danceName and danceName ~= "") and danceName or "Waiting for the lead"
end

local function updateSyncUI(isSyncing, target, currentDance)
	State.isSyncing  = isSyncing and true or false
	State.syncTarget = target or "None"

	syncCard.Visible = State.isSyncing
	syncTitle.Text   = State.isSyncing and ("Sync · " .. State.syncTarget) or "Sync"
	updateSyncDetail(currentDance)

	local enabled = not State.isSyncing
	sliderHit.Active            = enabled
	sliderFill.BackgroundColor3 = enabled and T.ACCENT or T.TEXT_DIM
	sliderKnob.BackgroundColor3 = enabled and T.ACCENT or T.TEXT_DIM
	speedValue.TextColor3       = enabled and T.ACCENT or T.TEXT_DIM
	speedValue.Text             = enabled and fmtSpeed(State.speed) or "SYNC"

	player:SetAttribute("IsSyncing",  State.isSyncing)
	player:SetAttribute("SyncTarget", State.syncTarget)

	layoutList()
end

local function clearPlaying()
	State.playing = nil
	refreshRows()
end

syncCard.Activated:Connect(function()
	if syncRemote then syncRemote:FireServer("stop") end
	danceRemote:FireServer("", State.speed)
	updateSyncUI(false, "None", nil)
	clearPlaying()
end)

bindHover(syncCard, function(on)
	tween(syncCard, { BackgroundColor3 = on and T.CARD_HOVER or T.CARD })
	tween(syncStopLabel, { TextColor3 = on and T.TEXT or T.TEXT_DIM })
end)

if syncRemote then
	syncRemote.OnClientEvent:Connect(function(action, data)
		if action == "syncStatus" and type(data) == "table" then
			if data.reason == "carriedDropped" or data.reason == "leadPaused" then
				updateSyncDetail(nil)
			else
				updateSyncUI(data.isSyncing, data.target, data.currentDance)
				if not data.isSyncing then clearPlaying() end
			end
		elseif action == "leadDisconnected" then
			updateSyncUI(false, "None", nil)
			clearPlaying()
		end
	end)

	task.delay(0.1, function() syncRemote:FireServer("getSyncStatus") end)
end

-- ═══════════════════════════════════════════════════════════
-- TAB & SEARCH
-- ═══════════════════════════════════════════════════════════

-- Dipakai state aktif maupun hover, jadi warna tab diatur di satu tempat.
local function paintTab(key, hovered)
	local ref    = tabButtons[key]
	local active = (State.tab == key)
	tween(ref.button, {
		BackgroundColor3 = (active or hovered) and T.CARD_HOVER or T.CARD,
		TextColor3       = active and T.ACCENT or (hovered and T.TEXT or T.TEXT_DIM),
	})
	tween(ref.stroke, { Transparency = active and 0.6 or 0.94 })
end

local function refreshTabVisual()
	for key in pairs(tabButtons) do paintTab(key, false) end
end

for key, ref in pairs(tabButtons) do
	ref.button.Activated:Connect(function()
		if State.tab == key then return end
		State.tab = key
		refreshTabVisual()
		applyFilter(false)  -- keyword pencarian tetap dipakai untuk tab baru
	end)
	bindHover(ref.button, function(on) paintTab(key, on) end)
end

local searchThread
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	clearBtn.Visible = searchBox.Text ~= ""

	if searchThread then
		task.cancel(searchThread)
		searchThread = nil
	end

	if trim(searchBox.Text) == "" then
		if State.query ~= "" then
			State.query = ""
			applyFilter(false)
		end
		return
	end

	searchThread = task.delay(CFG.SEARCH_DEBOUNCE, function()
		searchThread = nil
		State.query  = trim(searchBox.Text)
		applyFilter(false)
	end)
end)

searchBox.Focused:Connect(function() tween(searchStroke, { Transparency = 0.7, Color = T.ACCENT }) end)
searchBox.FocusLost:Connect(function() tween(searchStroke, { Transparency = 0.92, Color = T.LINE }) end)
clearBtn.Activated:Connect(function() searchBox.Text = "" end)

-- ═══════════════════════════════════════════════════════════
-- TOGGLE / DRAG / TOPBAR
-- ═══════════════════════════════════════════════════════════

local inTopbar = false

local function buttonClosedPos()
	return UDim2.new(0, 15, 0.5, 0)
end

local function buttonOpenPos()
	local width = panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.X or C.width
	return UDim2.new(0, CFG.EDGE_MARGIN + width + 8, 0.5, 0)
end

-- Saat panel digeser, tombol menumpang di topbar. Offsetnya tidak dihitung di
-- sini — cukup daftar ke _G.TopbarLayout (order 30, baris "menu").
local function moveButtonToTopbar()
	if inTopbar or not _G.TopbarGui then return end
	inTopbar = true
	buttonFrame.AnchorPoint = Vector2.new(1, 0)
	buttonFrame.Parent      = _G.TopbarGui
	if _G.TopbarLayout then
		_G.TopbarLayout.register("dance", buttonFrame, 30, "menu")
	end
end

local function moveButtonToLeft()
	if not inTopbar then return end
	inTopbar = false
	if _G.TopbarLayout then _G.TopbarLayout.unregister("dance") end
	buttonFrame.AnchorPoint = Vector2.new(0, 0.5)
	buttonFrame.Parent      = buttonGui
	buttonFrame.Position    = buttonClosedPos()
end

local function setOpen(open)
	if State.open == open then return end
	State.open = open

	if not open and State.customPos then
		State.customPos = false
		visiblePos = UDim2.new(0, CFG.EDGE_MARGIN, 0.5, 0)
		moveButtonToLeft()
	end

	tween(panel, { Position = open and visiblePos or hiddenPos }, TW_SLIDE)
	if not inTopbar then
		tween(buttonFrame, { Position = open and buttonOpenPos() or buttonClosedPos() }, TW_SLIDE)
	end
	paintToggle(false)

	if open then
		ensurePool()
		renderWindow(true)
	end
end

local function toggleSidebar()
	setOpen(not State.open)
end

toggleBtn.Activated:Connect(function()
	local press = TweenService:Create(toggleBtn, TweenInfo.new(0.08), { Size = UDim2.new(0.9, 0, 0.9, 0) })
	press:Play()
	press.Completed:Once(function()
		TweenService:Create(toggleBtn, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end)
	toggleSidebar()
end)

bindHover(toggleBtn, paintToggle)

-- ── DRAG PANEL & SLIDER ────────────────────────────────────
-- InputChanged/InputEnded hanya tersambung selama drag berlangsung, jadi saat
-- idle tidak ada handler yang jalan tiap gerakan mouse.
local dragStart, panelStart
local moveConn, endConn

local function clampPanel(position)
	local viewport = getViewport()
	local x = math.clamp(
		position.X.Offset,
		CFG.EDGE_MARGIN,
		math.max(viewport.X - C.width - CFG.EDGE_MARGIN, CFG.EDGE_MARGIN)
	)
	local centerY = viewport.Y * position.Y.Scale + position.Y.Offset
	local minY    = C.height * 0.5 + CFG.EDGE_MARGIN
	local maxY    = viewport.Y - C.height * 0.5 - CFG.EDGE_MARGIN
	centerY = math.clamp(centerY, minY, math.max(maxY, minY))
	return UDim2.new(0, x, position.Y.Scale, centerY - viewport.Y * position.Y.Scale)
end

local function releaseInput()
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end
	if endConn then
		endConn:Disconnect()
		endConn = nil
	end

	if dragging then
		dragging = false
		tween(gripLine, { BackgroundTransparency = 0.25, Size = UDim2.new(0, gripWidth(), 0, 3) })
	end
	if dragSlider then
		dragSlider = false
		tween(sliderKnob, { Size = UDim2.new(0, 11, 0, 11) })
		pushSpeed(true)
	end
end

local function onMove(input)
	if not isMove(input) then return end

	if dragSlider then
		setSpeed(speedFromX(input.Position.X), false)
		return
	end
	if not dragging then return end

	local delta = input.Position - dragStart
	panel.Position = clampPanel(UDim2.new(
		panelStart.X.Scale, panelStart.X.Offset + delta.X,
		panelStart.Y.Scale, panelStart.Y.Offset + delta.Y
		))
	State.customPos = true
	visiblePos      = panel.Position

	moveButtonToTopbar()
end

function captureInput()
	if moveConn then return end
	moveConn = UserInputService.InputChanged:Connect(onMove)
	endConn  = UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then releaseInput() end
	end)
end

local function beginDrag(input)
	if not isPointer(input) then return end
	dragging   = true
	dragStart  = input.Position
	panelStart = panel.Position
	tween(gripLine, { BackgroundTransparency = 0, Size = UDim2.new(0, gripWidth() + 6, 0, 3) })
	captureInput()
end

gripHit.InputBegan:Connect(beginDrag)
header.InputBegan:Connect(beginDrag)   -- area kosong di sekitar tab

-- ═══════════════════════════════════════════════════════════
-- RESPONSIVE
-- ═══════════════════════════════════════════════════════════

local resizeQueued = false
local function onViewportChanged()
	if resizeQueued then return end
	resizeQueued = true
	task.delay(0.08, function()
		resizeQueued = false
		if not panel.Parent then return end

		C = getConfig()
		applyLayout()
		applyFilter(true)

		if inTopbar then
			if _G.TopbarLayout then _G.TopbarLayout.refresh() end
		else
			buttonFrame.Position = State.open and buttonOpenPos() or buttonClosedPos()
		end
	end)
end

local cameraConn
local function bindCamera()
	if cameraConn then cameraConn:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
	end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera()
	onViewportChanged()
end)
bindCamera()

list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() renderWindow(false) end)
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	ensurePool()
	renderWindow(true)
end)
panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if not inTopbar and State.open then
		buttonFrame.Position = buttonOpenPos()
	end
end)

-- ═══════════════════════════════════════════════════════════
-- INPUT & API
-- ═══════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if UserInputService:GetFocusedTextBox() then return end

	if input.KeyCode == Enum.KeyCode.M then
		toggleSidebar()
	elseif input.KeyCode == Enum.KeyCode.Escape and State.open then
		setOpen(false)
	end
end)

_G.ToggleDanceGUI = toggleSidebar
_G.OpenDanceGUI   = function() setOpen(true) end
_G.CloseDanceGUI  = function() setOpen(false) end
_G.IsDanceGUIOpen = function() return State.open end

-- ═══════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════

applyLayout()
refreshTabVisual()
setSpeed(CFG.SPEED_DEFAULT, false)
applyFilter(false)
buttonFrame.Position = buttonClosedPos()

-- Viewport kadang belum final di frame pertama; sinkron ulang sekali.
task.defer(onViewportChanged)

task.spawn(function()
	if not player.Character then player.CharacterAdded:Wait() end
	loadFavorites()
end)

-- Panaskan beberapa nama teratas saat mulai; sisanya menyusul otomatis
-- lewat warmVisible() begitu list digulir.
task.delay(CFG.WARMUP_DELAY, function()
	local first = {}
	for index = 1, math.min(#State.items, 8) do
		first[index] = State.items[index]
	end
	AnimationWarmup.addByName(DanceAssets.dances, first)
end)