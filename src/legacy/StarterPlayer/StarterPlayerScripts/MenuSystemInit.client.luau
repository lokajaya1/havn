-- ═══════════════════════════════════════════════════════════
-- MenuSystemInit — StarterPlayer > StarterPlayerScripts
--
-- Membangun PlayerMenuGui: kartu avatar (tombol mata + pill like),
-- teks profil, dan daftar aksi. Baris "Add friend" berubah sendiri jadi
-- "Already friends" kalau sudah berteman.
--
-- Posisi panel: menempel BAWAH layar, tepat di atas hotbar/inventory
-- default Roblox (jarak dari Responsive.BottomInset).
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modules = RS:WaitForChild("CustomUIModules")
local Responsive = require(modules:WaitForChild("Responsive"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))

-- ════════════════════════════════════════════════════════════
-- THEME
-- Warna dari ReplicatedStorage.Modules.ThemeColor (themeColor): THEME.X
-- membaca token tema SEKARANG saat dipakai → hover/refresh ikut tema.
-- SCRIM (overlay gelap di atas foto avatar/community) & LIKE (hati) =
-- warna tetap, tidak ikut tema.
-- ════════════════════════════════════════════════════════════

local THEME = ThemeColor.view({
	BG         = "BG",
	CARD       = "CARD",
	CARD_HOVER = "CARD_HOVER",
	LINE       = "LINE",
	TEXT       = "TEXT",
	TEXT_DIM   = "TEXT_DIM",
	ACCENT     = "ACCENT",
}, {
	SCRIM      = Color3.fromRGB(12, 12, 13),
	LIKE       = Color3.fromRGB(235, 86, 96),
})

-- Scrim: gelap saat avatar tampil (biar avatar kebaca di atas background),
-- hampir bening saat avatar disembunyikan (biar background community bersih).
local SCRIM_WITH_AVATAR = 0.40
local SCRIM_BG_ONLY     = 0.88

-- Set true kalau baris "Hide avatar" di daftar tombol mau ikut
-- mengontrol tampilan avatar di panel ini juga.
local LINK_HIDE_AVATAR_ROW = false

local BUTTONS = {
	{ "Sync",        "Sync dance" },
	{ "AddFriend",   "Add friend" },
	{ "ViewProfile", "View profile" },
	{ "PrivateChat", "Private chat" },
	{ "Carry",       "Request carry" },
	{ "StopCarry",   "Stop carry" },
	{ "HideAvatar",  "Hide avatar" },
}

-- Ukuran frame, tinggi baris, dan ukuran font panel ada di
-- Responsive.Panel() — dipakai bareng dengan panel carry supaya identik.
-- Yang khusus panel ini cuma tinggi kartu avatar.
local AVATAR = {
	mobile  = { portrait = {0.17, 130, 165}, landscape = {0.30, 110, 150} },
	tablet  = { portrait = {0.15, 150, 185}, landscape = {0.20, 140, 180} },
	desktop = { portrait = {0.16, 160, 200}, landscape = {0.16, 160, 200} },
}

local function getConfig()
	local vp = Responsive.Viewport()
	local p  = Responsive.Panel()

	-- avatar selalu proporsional terhadap frame, sama di semua device
	local avatarHeight = math.min(
		Responsive.Resolve(vp.Y, AVATAR[p.device][p.orientation]),
		math.floor(p.height * 0.55)
	)

	return {
		device = p.device, orientation = p.orientation, bottomInset = p.bottomInset,
		frameWidth = p.width, frameHeight = p.height, avatarHeight = avatarHeight,
		rowHeight = p.row, titleSize = p.title, textSize = p.text, statsSize = p.small,
		padding = p.pad, gap = p.gap,
		eyeSize = math.clamp(p.title + 12, 22, 30),
	}
end

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

local function pad(parent, t, b, l, r)
	new("UIPadding", {
		PaddingTop = UDim.new(0, t), PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
		Parent = parent,
	})
end

local function listLayout(parent, gap, align)
	return new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center, Parent = parent,
	})
end

local function findModule(folder, name)
	local direct = folder:FindFirstChild(name)
	if direct then return direct end
	local target = name:lower()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name:lower() == target then
			return child
		end
	end
	return nil
end

local TWEEN_FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_NONE = TweenInfo.new(0)

-- ════════════════════════════════════════════════════════════
-- ROW
-- ════════════════════════════════════════════════════════════

local rows = {}
local rowByName = {}

local function createRow(parent, name, label, order, cfg)
	local btn = new("TextButton", {
		Name = "Choose_" .. name, Size = UDim2.new(1, 0, 0, cfg.rowHeight),
		BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", LayoutOrder = order, ClipsDescendants = true, Parent = parent,
	})
	corner(btn, 10)
	local st = stroke(btn, THEME.LINE, 1, 0.92)

	local accent = new("Frame", {
		Name = "Accent", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 2, 0, 0),
		BackgroundColor3 = THEME.ACCENT, BorderSizePixel = 0, ZIndex = 2, Parent = btn,
	})
	corner(accent, 2)

	local container = new("Frame", {
		Name = "Container", Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Parent = btn,
	})

	local text = new("TextLabel", {
		Name = "TextLabel", Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -28, 1, 0), BackgroundTransparency = 1,
		Text = label, TextColor3 = THEME.TEXT, Font = Enum.Font.BuilderSansMedium,
		TextSize = cfg.textSize, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = container,
	})

	local function setHover(on)
		TweenService:Create(btn, TWEEN_FAST, { BackgroundColor3 = on and THEME.CARD_HOVER or THEME.CARD }):Play()
		TweenService:Create(accent, TWEEN_FAST, { Size = on and UDim2.new(0, 2, 0.55, 0) or UDim2.new(0, 2, 0, 0) }):Play()
		TweenService:Create(st, TWEEN_FAST, { Transparency = on and 0.78 or 0.92 }):Play()
	end

	btn.MouseEnter:Connect(function() setHover(true) end)
	btn.MouseLeave:Connect(function() setHover(false) end)
	btn.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then setHover(true) end
	end)
	btn.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then setHover(false) end
	end)

	local entry = { button = btn, text = text, key = name }
	table.insert(rows, entry)
	rowByName[name] = entry
	return btn
end

-- ════════════════════════════════════════════════════════════
-- BUILD
-- ════════════════════════════════════════════════════════════

local gui = playerGui:FindFirstChild("PlayerMenuGui")
if not gui then
	gui = new("ScreenGui", {
		Name = "PlayerMenuGui", ResetOnSpawn = false, IgnoreGuiInset = false,
		Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10, Parent = playerGui,
	})
end
ThemeColor.mark(gui)

local oldFrame = gui:FindFirstChild("MenuFrame")
if oldFrame then oldFrame:Destroy() end

local cfg = getConfig()

local frame = new("Frame", {
	Name = "MenuFrame", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -cfg.bottomInset),
	Size = UDim2.new(0, cfg.frameWidth, 0, cfg.frameHeight),
	BackgroundColor3 = THEME.BG, BorderSizePixel = 0, Active = true,
	ClipsDescendants = true, Parent = gui,
})
corner(frame, 16)
ThemeColor.glow(stroke(frame, THEME.LINE, 1, 0.88), "panel") -- garis tepi bergerak (themeColor)

local closeBtn = new("TextButton", {
	Name = "CloseButton", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8), Size = UDim2.new(0, 26, 0, 26),
	BackgroundTransparency = 1, Text = "X", TextColor3 = THEME.TEXT_DIM,
	Font = Enum.Font.BuilderSansBold, TextSize = cfg.titleSize,
	BorderSizePixel = 0, AutoButtonColor = false, ZIndex = 20, Parent = frame,
})
closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeBtn, TWEEN_FAST, { TextColor3 = THEME.TEXT }):Play()
end)
closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeBtn, TWEEN_FAST, { TextColor3 = THEME.TEXT_DIM }):Play()
end)

local scroll = new("ScrollingFrame", {
	Name = "ScrollFrame", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.TEXT_DIM,
	ScrollBarImageTransparency = 0.5, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y, Parent = frame,
})

local scrollContent = new("Frame", {
	Name = "ScrollContent", Size = UDim2.new(1, 0, 0, 0),
	BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll,
})
local contentLayout = listLayout(scrollContent, cfg.gap + 4)
local contentPadding = new("UIPadding", {
	PaddingTop = UDim.new(0, cfg.padding), PaddingBottom = UDim.new(0, cfg.padding + 4),
	PaddingLeft = UDim.new(0, cfg.padding), PaddingRight = UDim.new(0, cfg.padding),
	Parent = scrollContent,
})

-- ── PROFILE ────────────────────────────────────────────────

local profileSection = new("Frame", {
	Name = "ProfileSection", Size = UDim2.new(1, 0, 0, 0),
	BackgroundTransparency = 1, LayoutOrder = 1,
	AutomaticSize = Enum.AutomaticSize.Y, Parent = scrollContent,
})
local profileLayout = listLayout(profileSection, cfg.gap)

local avatarCard = new("Frame", {
	Name = "AvatarCard", Size = UDim2.new(1, 0, 0, cfg.avatarHeight),
	BackgroundColor3 = THEME.CARD, BorderSizePixel = 0,
	ClipsDescendants = true, LayoutOrder = 1, Parent = profileSection,
})
corner(avatarCard, 12)
stroke(avatarCard, THEME.LINE, 1, 0.9)

-- ScaleType Stretch: thumbnail GroupIcon (150px kotak) dipaksa mengisi panel,
-- Crop bikin gambar ke-zoom/terpotong.
local communityBg = new("ImageLabel", {
	Name = "CommunityBackground", Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, Image = "",
	ImageTransparency = 1, ScaleType = Enum.ScaleType.Stretch, ZIndex = 1, Parent = avatarCard,
})

local scrim = new("Frame", {
	Name = "Scrim", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.SCRIM,
	BackgroundTransparency = SCRIM_WITH_AVATAR, BorderSizePixel = 0, ZIndex = 2, Parent = avatarCard,
})

local avatarImage = new("ImageLabel", {
	Name = "CharacterViewport", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.46, 0), Size = UDim2.new(1, -16, 1, -16),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Fit,
	Image = "", ZIndex = 3, Parent = avatarCard,
})

-- Hint kalau avatar disembunyikan tapi background community belum ada
local hiddenHint = new("TextLabel", {
	Name = "HiddenHint", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(1, -20, 0, 18),
	BackgroundTransparency = 1, Text = "Avatar disembunyikan",
	TextColor3 = THEME.TEXT_DIM, Font = Enum.Font.BuilderSans,
	TextSize = cfg.statsSize, TextWrapped = true, Visible = false,
	ZIndex = 4, Parent = avatarCard,
})

-- ── TOMBOL MATA (kiri atas avatar card) ────────────────────

local eyeBtn = new("TextButton", {
	Name = "AvatarToggle", AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(0, cfg.eyeSize, 0, cfg.eyeSize),
	BackgroundColor3 = THEME.SCRIM, BackgroundTransparency = 0.25,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	ZIndex = 10, Parent = avatarCard,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = eyeBtn })
local eyeStroke = stroke(eyeBtn, THEME.LINE, 1, 0.82)

local eyeLabel = new("TextLabel", {
	Name = "Icon", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	Text = "👁", TextColor3 = THEME.TEXT, Font = Enum.Font.BuilderSans,
	TextSize = math.floor(cfg.eyeSize * 0.62), ZIndex = 11, Parent = eyeBtn,
})

local eyeSlash = new("Frame", {
	Name = "Slash", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0.7, 0, 0, 2),
	Rotation = -35, BackgroundColor3 = THEME.TEXT, BorderSizePixel = 0,
	Visible = false, ZIndex = 12, Parent = eyeBtn,
})
corner(eyeSlash, 1)

local avatarShown = true

local function backgroundActive()
	return communityBg.Image ~= "" and communityBg.ImageTransparency < 0.9
end

local function refreshAvatarVisual(animate)
	local info = animate and TWEEN_FAST or TWEEN_NONE
	local bgOn = backgroundActive()

	if avatarShown then avatarImage.Visible = true end
	TweenService:Create(avatarImage, info, { ImageTransparency = avatarShown and 0 or 1 }):Play()
	if not avatarShown then
		task.delay(animate and 0.16 or 0, function()
			if not avatarShown then avatarImage.Visible = false end
		end)
	end

	local scrimTarget = SCRIM_WITH_AVATAR
	if not avatarShown and bgOn then scrimTarget = SCRIM_BG_ONLY end
	TweenService:Create(scrim, info, { BackgroundTransparency = scrimTarget }):Play()

	eyeSlash.Visible = not avatarShown
	TweenService:Create(eyeLabel, info, {
		TextTransparency = avatarShown and 0 or 0.3,
	}):Play()
	TweenService:Create(eyeBtn, info, {
		BackgroundTransparency = avatarShown and 0.25 or 0.1,
	}):Play()
	TweenService:Create(eyeStroke, info, {
		Color = avatarShown and THEME.LINE or THEME.ACCENT,
		Transparency = avatarShown and 0.82 or 0.5,
	}):Play()

	hiddenHint.Visible = (not avatarShown) and (not bgOn)
	gui:SetAttribute("AvatarHidden", not avatarShown)

	if LINK_HIDE_AVATAR_ROW and rowByName.HideAvatar then
		rowByName.HideAvatar.text.Text = avatarShown and "Hide avatar" or "Show avatar"
	end
end

local function setAvatarVisible(on, animate)
	on = (on ~= false)
	if on == avatarShown then
		refreshAvatarVisual(false)
		return
	end
	avatarShown = on
	refreshAvatarVisual(animate ~= false)
end

eyeBtn.Activated:Connect(function()
	setAvatarVisible(not avatarShown, true)
end)

eyeBtn.MouseEnter:Connect(function()
	TweenService:Create(eyeBtn, TWEEN_FAST, { BackgroundTransparency = 0.05 }):Play()
end)
eyeBtn.MouseLeave:Connect(function()
	TweenService:Create(eyeBtn, TWEEN_FAST, {
		BackgroundTransparency = avatarShown and 0.25 or 0.1,
	}):Play()
end)

-- Kalau CommunityInfo mengganti / mematikan background, tampilan ikut disesuaikan
communityBg:GetPropertyChangedSignal("Image"):Connect(function()
	refreshAvatarVisual(false)
end)
communityBg:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
	refreshAvatarVisual(false)
end)

-- ── TOMBOL LIKE (kanan BAWAH avatar card) ──────────────────
-- Pill: hati + jumlah like. Jumlah dibaca dari Attribute "Likes"
-- (di-set server oleh LikeSystem), jadi selalu sinkron dengan leaderboard.
-- Ditaruh di kanan bawah, BUKAN kanan atas: CloseButton (ZIndex 20) ada di
-- pojok kanan atas frame dan area itu bertumpuk dengan pojok avatar card.

local likeBtn = new("TextButton", {
	Name = "LikeButton", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -8, 1, -8),
	Size = UDim2.new(0, math.floor(cfg.eyeSize * 2.15), 0, cfg.eyeSize),
	BackgroundColor3 = THEME.SCRIM, BackgroundTransparency = 0.25,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	ZIndex = 10, Parent = avatarCard,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = likeBtn })
local likeStroke = stroke(likeBtn, THEME.LINE, 1, 0.82)

local heartLabel = new("TextLabel", {
	Name = "Heart", Position = UDim2.new(0, 7, 0, 0),
	Size = UDim2.new(0, math.floor(cfg.eyeSize * 0.62), 1, 0),
	BackgroundTransparency = 1, Text = "♡", TextColor3 = THEME.TEXT,
	Font = Enum.Font.BuilderSans, TextSize = math.floor(cfg.eyeSize * 0.6),
	ZIndex = 11, Parent = likeBtn,
})

local likeCountLabel = new("TextLabel", {
	Name = "Count", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(1, -28, 1, 0),
	BackgroundTransparency = 1, Text = "0", TextColor3 = THEME.TEXT,
	Font = Enum.Font.BuilderSansMedium, TextSize = math.floor(cfg.eyeSize * 0.46),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11, Parent = likeBtn,
})

local likeState = { liked = false, count = 0, locked = false, self = false }
local refreshLikeUI -- diisi di section LIKE, dipakai lebih awal oleh hover

likeBtn.MouseEnter:Connect(function()
	if likeState.self then return end
	TweenService:Create(likeBtn, TWEEN_FAST, { BackgroundTransparency = 0.05 }):Play()
end)
likeBtn.MouseLeave:Connect(function()
	TweenService:Create(likeBtn, TWEEN_FAST, { BackgroundTransparency = 0.25 }):Play()
end)

local textContainer = new("Frame", {
	Name = "TextContainer", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = profileSection,
})
listLayout(textContainer, 1, Enum.HorizontalAlignment.Left)
pad(textContainer, 2, 2, 2, 2)

local nameLabel = new("TextLabel", {
	Name = "PlayerName", Size = UDim2.new(1, 0, 0, cfg.titleSize + 6),
	BackgroundTransparency = 1, Text = "Player name", TextColor3 = THEME.ACCENT,
	Font = Enum.Font.BuilderSansBold, TextSize = cfg.titleSize,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	LayoutOrder = 1, Parent = textContainer,
})
-- Warna nama = aksen tema warna pilihan pemain yang dibuka (paintTargetName), bukan lukis ulang tema kita.
ThemeColor.skip(nameLabel)

local usernameLabel = new("TextLabel", {
	Name = "PlayerUsername", Size = UDim2.new(1, 0, 0, cfg.statsSize + 5),
	BackgroundTransparency = 1, Text = "@username", TextColor3 = THEME.TEXT_DIM,
	Font = Enum.Font.BuilderSans, TextSize = cfg.statsSize + 1,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	LayoutOrder = 2, Parent = textContainer,
})

local statsLabel = new("TextLabel", {
	Name = "StatsLabel", Size = UDim2.new(1, 0, 0, cfg.statsSize + 5),
	BackgroundTransparency = 1, Text = "0 connections  0 followers",
	TextColor3 = THEME.TEXT_DIM, Font = Enum.Font.BuilderSans, TextSize = cfg.statsSize,
	TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3, Parent = textContainer,
})

local divider = new("Frame", {
	Name = "Divider", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.LINE,
	BackgroundTransparency = 0.9, BorderSizePixel = 0, LayoutOrder = 3, Parent = profileSection,
})

-- ── ACTIONS ────────────────────────────────────────────────

local buttonsSection = new("Frame", {
	Name = "ButtonsSection", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1,
	LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.Y, Parent = scrollContent,
})

local buttonsFrame = new("Frame", {
	Name = "ButtonsFrame", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y, Parent = buttonsSection,
})
listLayout(buttonsFrame, cfg.gap)

for i, def in ipairs(BUTTONS) do
	createRow(buttonsFrame, def[1], def[2], i, cfg)
end

if LINK_HIDE_AVATAR_ROW and rowByName.HideAvatar then
	rowByName.HideAvatar.button.Activated:Connect(function()
		setAvatarVisible(not avatarShown, true)
	end)
end

refreshAvatarVisual(false)

gui:SetAttribute("SetupComplete", true)

-- ════════════════════════════════════════════════════════════
-- AVATAR + COMMUNITY
-- ════════════════════════════════════════════════════════════

local CommunityInfo
do
	local mod = findModule(modules, "CommunityInfo")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then
			CommunityInfo = result
		else
			warn("[PlayerMenu] CommunityInfo gagal di-require:", result)
		end
	else
		warn("[PlayerMenu] CommunityInfo tidak ada — background community dimatikan.")
	end
end

local currentUserId
local onTargetChangedForLike -- diisi di section LIKE

-- ════════════════════════════════════════════════════════════
-- FRIEND STATE (baris "Add friend")
-- Status dibaca lewat AddFriendManager yang punya cache 30 detik, supaya
-- IsFriendsWith (panggilan web yang yield) tidak diulang tiap menu dibuka.
-- Selalu dijalankan di task.spawn, dan hasil yang datang terlambat dibuang
-- lewat friendToken kalau target sudah berganti.
-- ════════════════════════════════════════════════════════════

local AddFriendManager
do
	local mod = findModule(modules, "AddFriendManager")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then
			AddFriendManager = result
		else
			warn("[PlayerMenu] AddFriendManager gagal di-require:", result)
		end
	end
end

local FRIEND_TEXT = {
	idle    = "Add friend",
	pending = "Checking…",
	friends = "Already friends",
	self    = "This is you",
}

local friendToken = 0

local function setRowEnabled(entry, enabled)
	entry.button.Active = enabled
	-- Interactable hanya ada di engine baru; Active saja sudah cukup di lama.
	pcall(function() entry.button.Interactable = enabled end)
	TweenService:Create(entry.text, TWEEN_FAST, {
		TextColor3 = enabled and THEME.TEXT or THEME.TEXT_DIM,
	}):Play()
end

local function paintFriendRow(state)
	local entry = rowByName.AddFriend
	if not entry then return end

	entry.text.Text = FRIEND_TEXT[state] or FRIEND_TEXT.idle
	setRowEnabled(entry, state == "idle")

	-- Stroke emas = sudah tersambung. Hover cuma mengubah Transparency, jadi
	-- warna accent ini tetap kelihatan waktu kursor lewat.
	local st = entry.button:FindFirstChild("Stroke")
	if st then
		local isFriend = (state == "friends")
		TweenService:Create(st, TWEEN_FAST, {
			Color = isFriend and THEME.ACCENT or THEME.LINE,
			Transparency = isFriend and 0.6 or 0.92,
		}):Play()
	end
end

local function refreshFriendRow(userId)
	if not rowByName.AddFriend or type(userId) ~= "number" then return end

	friendToken += 1
	local token = friendToken

	if userId == player.UserId then
		paintFriendRow("self")
		return
	end

	paintFriendRow("pending")

	task.spawn(function()
		local isFriend = false
		local target = Players:GetPlayerByUserId(userId)

		if AddFriendManager and target then
			local ok, res = pcall(AddFriendManager.IsFriend, AddFriendManager, target)
			isFriend = (ok and res) and true or false
		else
			local ok, res = pcall(function() return player:IsFriendsWith(userId) end)
			isFriend = (ok and res) and true or false
		end

		if token ~= friendToken then return end
		paintFriendRow(isFriend and "friends" or "idle")
	end)
end

-- Setelah prompt add friend dibuka, pemain butuh beberapa detik untuk menekan
-- Send. Cache dibuang lalu status dicek ulang, termasuk cache PlayersPanel
-- supaya baris itu pindah sendiri ke section CONNECTIONS.
if rowByName.AddFriend then
	rowByName.AddFriend.button.Activated:Connect(function()
		local uid = currentUserId
		if not uid or uid == player.UserId then return end
		task.delay(4, function()
			if uid ~= currentUserId then return end
			if AddFriendManager and AddFriendManager.Invalidate then
				pcall(AddFriendManager.Invalidate, AddFriendManager, uid)
			end
			if _G.PlayersPanel and _G.PlayersPanel.InvalidateFriend then
				pcall(_G.PlayersPanel.InvalidateFriend, uid)
			end
			refreshFriendRow(uid)
		end)
	end)
end

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled and currentUserId then
		refreshFriendRow(currentUserId)
	end
end)

-- ════════════════════════════════════════════════════════════
-- TARGET
-- ════════════════════════════════════════════════════════════

-- Nama di kartu = aksen tema pemain itu (sama dengan nametag di atas kepala); tema polos / bukan di server = ACCENT kita.
local targetThemeConn
local function paintTargetName()
	local plr = currentUserId and Players:GetPlayerByUserId(currentUserId)
	nameLabel.TextColor3 = (plr and ThemeColor.nameColor(plr)) or THEME.ACCENT
end
ThemeColor.onChanged(paintTargetName)

local function setTarget(userId)
	if type(userId) ~= "number" or userId < 1 then return end
	currentUserId = userId
	if targetThemeConn then targetThemeConn:Disconnect() end
	local target = Players:GetPlayerByUserId(userId)
	targetThemeConn = target and target:GetAttributeChangedSignal(ThemeColor.ATTR):Connect(paintTargetName)
	paintTargetName()
	avatarImage.Image = string.format("rbxthumb://type=Avatar&id=%d&w=352&h=352", userId)
	if CommunityInfo then
		CommunityInfo.ApplyTo(gui, userId)
	end
	-- state mata dipertahankan walau target berganti
	refreshAvatarVisual(false)
	refreshFriendRow(userId)
	if onTargetChangedForLike then onTargetChangedForLike(userId) end
end

local function resolveUserId(username)
	local direct = Players:FindFirstChild(username)
	if direct then return direct.UserId end
	local lower = username:lower()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Name:lower() == lower or plr.DisplayName:lower() == lower then
			return plr.UserId
		end
	end
	return nil
end

usernameLabel:GetPropertyChangedSignal("Text"):Connect(function()
	local raw = usernameLabel.Text
	local name = raw:match("^@(.+)$") or raw
	if name == "" or name == "username" then return end
	local uid = resolveUserId(name)
	if uid and uid ~= currentUserId then setTarget(uid) end
end)

-- ════════════════════════════════════════════════════════════
-- LIKE AVATAR
-- Client tidak pernah mengirim angka. Client hanya minta "toggle"
-- dan "query"; jumlah like dibaca dari Attribute "Likes" yang di-set
-- server, jadi UI ini dan leaderboard default selalu satu sumber.
-- ════════════════════════════════════════════════════════════

local likeRemote
do
	local folder = RS:WaitForChild("LikeRemotes", 15)
	likeRemote = folder and folder:WaitForChild("AvatarLike", 10)
	if not likeRemote then
		warn("[PlayerMenu] LikeRemotes.AvatarLike tidak ada — fitur like dimatikan.")
		likeBtn.Visible = false
	end
end

local likeConn -- koneksi ke attribute Likes target sekarang

local function formatCount(n)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000 then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

refreshLikeUI = function(animate)
	local info = animate and TWEEN_FAST or TWEEN_NONE
	local liked = likeState.liked

	heartLabel.Text = liked and "♥" or "♡"
	likeCountLabel.Text = formatCount(likeState.count)

	TweenService:Create(heartLabel, info, {
		TextColor3 = liked and THEME.LIKE or THEME.TEXT,
		TextTransparency = likeState.self and 0.45 or 0,
	}):Play()
	TweenService:Create(likeCountLabel, info, {
		TextColor3 = liked and THEME.LIKE or THEME.TEXT,
		TextTransparency = likeState.self and 0.45 or 0,
	}):Play()
	TweenService:Create(likeStroke, info, {
		Color = liked and THEME.LIKE or THEME.LINE,
		Transparency = liked and 0.5 or 0.82,
	}):Play()

	likeBtn.Active = not likeState.self and not likeState.locked
	likeBtn.AutoButtonColor = false
end

local function readCount(userId)
	local plr = Players:GetPlayerByUserId(userId)
	if not plr then return 0, nil end
	return tonumber(plr:GetAttribute("Likes")) or 0, plr
end

onTargetChangedForLike = function(userId)
	if likeConn then likeConn:Disconnect(); likeConn = nil end

	likeState.self   = (userId == player.UserId)
	likeState.liked  = false
	likeState.locked = false

	local count, plr = readCount(userId)
	likeState.count = count
	refreshLikeUI(false)

	if plr then
		likeConn = plr:GetAttributeChangedSignal("Likes"):Connect(function()
			if currentUserId ~= userId then return end
			likeState.count = tonumber(plr:GetAttribute("Likes")) or 0
			refreshLikeUI(true)
		end)
	end

	if likeRemote and not likeState.self then
		likeRemote:FireServer("query", userId)
	end
end

if likeRemote then
	likeRemote.OnClientEvent:Connect(function(kind, targetUserId, payload)
		if targetUserId ~= currentUserId then return end

		if kind == "state" then
			likeState.liked  = payload and true or false
			likeState.locked = false
			likeState.count  = (readCount(targetUserId))
			refreshLikeUI(true)

		elseif kind == "reject" then
			likeState.locked = false
			refreshLikeUI(true)
			-- payload = "cooldown" | "self" | "offline" | "already" | "loading"
			if payload == "offline" then
				warn("[PlayerMenu] Like gagal: target sudah keluar server.")
			end
		end
	end)

	likeBtn.Activated:Connect(function()
		if not currentUserId or likeState.self or likeState.locked then return end
		likeState.locked = true

		-- Feedback optimistik: hati langsung berubah, angka dikoreksi
		-- oleh attribute dari server beberapa milidetik kemudian.
		likeState.liked = not likeState.liked
		refreshLikeUI(true)

		TweenService:Create(heartLabel, TweenInfo.new(0.1, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { TextSize = math.floor(cfg.eyeSize * 0.78) }):Play()
		task.delay(0.12, function()
			TweenService:Create(heartLabel, TWEEN_FAST,
				{ TextSize = math.floor(cfg.eyeSize * 0.6) }):Play()
		end)

		-- Efek hanya saat MENYALAKAN like, bukan saat membatalkan.
		-- Dijalankan optimistik supaya terasa instan; kalau server menolak,
		-- yang salah cuma efek visual sekali, bukan angkanya.
		if likeState.liked and _G.LikeEffects then
			pcall(_G.LikeEffects.Burst, likeBtn)
			pcall(_G.LikeEffects.WorldHearts, currentUserId)
		end

		likeRemote:FireServer("toggle", currentUserId)

		-- Kalau server tidak menjawab (rate limit / putus), buka lagi kuncinya
		task.delay(3, function() likeState.locked = false end)
	end)
end

refreshLikeUI(false)

_G.MenuVisuals = {
	SetTarget = setTarget,
	GetTarget = function() return currentUserId end,
	SetAvatarVisible = function(on, animate) setAvatarVisible(on, animate) end,
	IsAvatarVisible = function() return avatarShown end,
	ToggleAvatar = function() setAvatarVisible(not avatarShown, true) end,
	GetLikeState = function() return likeState.liked, likeState.count end,
	RefreshFriendState = function()
		if currentUserId then refreshFriendRow(currentUserId) end
	end,
	Gui = gui,
}

-- ════════════════════════════════════════════════════════════
-- RESPONSIVE
-- ════════════════════════════════════════════════════════════

local function applyConfig(c)
	frame.Size = UDim2.new(0, c.frameWidth, 0, c.frameHeight)
	frame.Position = UDim2.new(0.5, 0, 1, -c.bottomInset)

	contentLayout.Padding = UDim.new(0, c.gap + 4)
	contentPadding.PaddingTop = UDim.new(0, c.padding)
	contentPadding.PaddingBottom = UDim.new(0, c.padding + 4)
	contentPadding.PaddingLeft = UDim.new(0, c.padding)
	contentPadding.PaddingRight = UDim.new(0, c.padding)

	-- profile: satu susunan untuk semua device (avatar di atas, teks di bawah)
	profileLayout.FillDirection = Enum.FillDirection.Vertical
	profileLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	profileLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	profileLayout.Padding = UDim.new(0, c.gap)
	avatarCard.Size = UDim2.new(1, 0, 0, c.avatarHeight)
	textContainer.Size = UDim2.new(1, 0, 0, 0)
	divider.Visible = true

	nameLabel.Size = UDim2.new(1, 0, 0, c.titleSize + 6)
	nameLabel.TextSize = c.titleSize
	usernameLabel.Size = UDim2.new(1, 0, 0, c.statsSize + 5)
	usernameLabel.TextSize = c.statsSize + 1
	statsLabel.Size = UDim2.new(1, 0, 0, c.statsSize + 5)
	statsLabel.TextSize = c.statsSize
	closeBtn.TextSize = c.titleSize

	eyeBtn.Size = UDim2.new(0, c.eyeSize, 0, c.eyeSize)
	eyeLabel.TextSize = math.floor(c.eyeSize * 0.62)
	hiddenHint.TextSize = c.statsSize

	likeBtn.Size        = UDim2.new(0, math.floor(c.eyeSize * 2.15), 0, c.eyeSize)
	heartLabel.Size     = UDim2.new(0, math.floor(c.eyeSize * 0.62), 1, 0)
	heartLabel.TextSize = math.floor(c.eyeSize * 0.6)
	likeCountLabel.TextSize = math.floor(c.eyeSize * 0.46)

	-- cfg dipakai lagi oleh animasi "pop" hati, jadi harus ikut ter-update
	cfg = c

	for _, row in ipairs(rows) do
		row.button.Size = UDim2.new(1, 0, 0, c.rowHeight)
		row.text.TextSize = c.textSize
	end
end

applyConfig(cfg)

Responsive.OnChange(function()
	if frame.Parent then applyConfig(getConfig()) end
end)
