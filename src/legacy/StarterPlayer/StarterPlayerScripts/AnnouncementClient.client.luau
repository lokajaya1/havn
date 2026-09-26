-- ═══════════════════════════════════════════════════════════
-- AnnouncementClient — pengumuman admin (/global, /g, /notif)
-- Path: StarterPlayer > StarterPlayerScripts (LocalScript)
--
-- BENTUK: baris ramping yang MENUMPUK ke bawah. Pesan baru masuk di
-- bawah pesan sebelumnya dan masing-masing hilang sendiri sesuai
-- durasinya — bukan antre satu-satu. Kalau lebih dari MAX_ROWS,
-- yang paling atas (paling lama) langsung dibuang.
--
-- Gaya baris = baris tombol di MenuSystemInit: tinggi Responsive.Panel().row,
-- background CARD, corner 10, stroke putih 0.92, bar aksen emas 2px di kiri.
--
-- POSISI: kanan atas, jarak yang SAMA di semua device. Tumpukan tumbuh ke
-- BAWAH di sisi kanan, sementara kartu donation ada di atas-TENGAH.
--
-- Slot lain: bawah-tengah = PlayerMenu + kartu carry (CarryUI).
-- ═══════════════════════════════════════════════════════════

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Players           = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Responsive = require(ReplicatedStorage:WaitForChild("CustomUIModules")
	:WaitForChild("Responsive"))

local GlobalAnnouncementEvent = ReplicatedStorage:WaitForChild("GlobalAnnouncementEvent")

-- ════════════════════════════════════════════════════════════
-- THEME (sama dengan MenuSystemInit)
-- ════════════════════════════════════════════════════════════

local THEME = {
	CARD   = Color3.fromRGB(26, 26, 28),
	LINE   = Color3.fromRGB(255, 255, 255),
	TEXT   = Color3.fromRGB(238, 238, 240),
	ACCENT = Color3.fromRGB(212, 175, 55),
}

local ACCENT_HEX = "#D4AF37"

local TWEEN_IN  = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad,  Enum.EasingDirection.In)

local DEFAULT_DURATION = 5
local MAX_ROWS         = 4
local ROW_GAP          = 6
local PAD_Y            = 8

-- Batas aman saja supaya satu pesan tidak memenuhi layar. Di bawah angka
-- ini teks TIDAK dipotong — barisnya yang memanjang ke bawah.
local MAX_TEXT = 220

-- Jarak dari tepi atas dan tepi kanan. Nilainya SAMA di semua device
-- (HP, tablet, desktop) supaya tampilannya konsisten.
local TOP_OFFSET  = 52
local SIDE_MARGIN = 14

-- Suara bawaan CLIENT Roblox (skema rbxasset://, bukan rbxassetid://).
-- File ini ikut terpasang bersama aplikasi Roblox, jadi tidak butuh izin
-- aset dan tidak akan pernah melempar "InvalidUser" seperti aset lama
-- (71450094482101) yang diupload akun lain. Ini juga bunyi yang dipakai
-- notifikasi bawaan Roblox, jadi terasa familiar.
-- Alternatif bawaan lain: rbxasset://sounds/switch.wav (klik pendek),
-- rbxasset://sounds/bass.wav (dentum rendah), rbxasset://sounds/snap.mp3.
-- Kosongkan string ini kalau pengumuman tidak perlu suara.
local SOUND_ID    = "rbxasset://sounds/electronicpingshort.wav"
local SOUND_VOLUME = 0.45

-- Empat pengumuman yang datang bersamaan akan membunyikan empat ping yang
-- saling tindih. Jeda minimum ini membuatnya berbunyi sekali saja.
local SOUND_GAP = 0.2

-- ════════════════════════════════════════════════════════════
-- SIZE
-- ════════════════════════════════════════════════════════════

local function getConfig()
	local vp = Responsive.Viewport()
	local p  = Responsive.Panel()

	return {
		width  = math.min(p.width, math.floor(vp.X) - 24),
		height = p.row,
		avatar = p.row - 16,
		text   = p.text,
		top    = TOP_OFFSET,
	}
end

local cfg = getConfig()

-- ════════════════════════════════════════════════════════════
-- ROOT
-- ════════════════════════════════════════════════════════════

local function new(class, props)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	return obj
end

local gui = playerGui:FindFirstChild("AnnouncementGui")
if not gui then
	gui = new("ScreenGui", {
		Name = "AnnouncementGui", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 25,
		Enabled = true, Parent = playerGui,
	})
end

local oldStack = gui:FindFirstChild("Stack")
if oldStack then oldStack:Destroy() end

-- UIListLayout yang mengurus tumpukan: baris yang hilang otomatis membuat
-- sisanya naik, tanpa hitung-hitungan offset manual.
local stack = new("Frame", {
	Name = "Stack", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -SIDE_MARGIN, 0, cfg.top),
	Size = UDim2.new(0, cfg.width, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui,
})

local stackLayout = new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, ROW_GAP),
	HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = stack,
})

-- ════════════════════════════════════════════════════════════
-- ROW
-- ════════════════════════════════════════════════════════════

local rows  = {}
local order = 0

-- Tinggi baris = tinggi teks setelah dibungkus, minimal setinggi baris
-- menu biasa. Label memakai AutomaticSize.Y, jadi Roblox sendiri yang
-- menghitung berapa baris teksnya; kita tinggal ikut.
local function layoutRow(entry)
	entry.avatar.Size = UDim2.new(0, cfg.avatar, 0, cfg.avatar)

	local textX = entry.avatar.Visible and (9 + cfg.avatar + 8) or 12
	entry.label.Position = UDim2.new(0, textX, 0, PAD_Y - 1)
	entry.label.Size     = UDim2.new(0, math.max(cfg.width - textX - 12, 60), 0, 0)
	entry.label.TextSize = cfg.text
	entry.fit()
end

local function makeRow(data)
	order += 1

	local root = new("CanvasGroup", {
		Name = "Row", Size = UDim2.new(1, 0, 0, cfg.height),
		BackgroundColor3 = THEME.CARD, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, GroupTransparency = 1, ClipsDescendants = true,
		LayoutOrder = order, Parent = stack,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = root })
	new("UIStroke", {
		Color = THEME.LINE, Thickness = 1, Transparency = 0.92,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = root,
	})
	local scale = new("UIScale", { Scale = 0.97, Parent = root })

	-- Bar aksen kiri: penanda yang sama dipakai baris menu saat hover
	new("Frame", {
		Name = "Accent", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 2, 0.55, 0),
		BackgroundColor3 = THEME.ACCENT, BorderSizePixel = 0, Parent = root,
	})

	-- AnchorPoint Y 0 + offset PAD_Y: saat teks jadi beberapa baris, avatar
	-- tetap sejajar baris PERTAMA, tidak melayang di tengah.
	local avatar = new("ImageLabel", {
		Name = "Avatar", AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 9, 0, PAD_Y),
		Size = UDim2.new(0, cfg.avatar, 0, cfg.avatar),
		BackgroundColor3 = THEME.CARD, BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Fit, Visible = data.userId > 0,
		Image = (data.userId > 0)
			and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", data.userId)
			or "",
		Parent = root,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = avatar })

	-- Satu label RichText: nama emas + pesan. TextWrapped + AutomaticSize.Y
	-- membuatnya turun ke baris berikutnya, bukan dipotong jadi "...".
	local label = new("TextLabel", {
		Name = "Line", AnchorPoint = Vector2.new(0, 0),
		BackgroundTransparency = 1, RichText = true, TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y, Text = data.rich,
		TextColor3 = THEME.TEXT, Font = Enum.Font.BuilderSansMedium,
		TextSize = cfg.text, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Parent = root,
	})

	local entry = { root = root, scale = scale, avatar = avatar, label = label }

	function entry.fit()
		root.Size = UDim2.new(1, 0, 0, math.max(cfg.height, label.AbsoluteSize.Y + PAD_Y * 2))
	end

	-- Tinggi teks baru diketahui setelah Roblox membungkusnya, dan bisa
	-- berubah lagi saat lebar layar berubah. Ikuti sinyalnya, jangan tebak.
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(entry.fit)

	layoutRow(entry)
	return entry
end

local function removeRow(entry, instant)
	local index = table.find(rows, entry)
	if index then table.remove(rows, index) end

	if instant then
		entry.root:Destroy()
		return
	end

	local fade = TweenService:Create(entry.root, TWEEN_OUT, { GroupTransparency = 1 })
	TweenService:Create(entry.scale, TWEEN_OUT, { Scale = 0.97 }):Play()
	fade.Completed:Once(function() entry.root:Destroy() end)
	fade:Play()
end

-- ════════════════════════════════════════════════════════════
-- SOUND (dibuat sekali di SoundService)
-- ════════════════════════════════════════════════════════════

local chime
if SOUND_ID ~= "" then
	chime = new("Sound", {
		Name = "AnnouncementChime", SoundId = SOUND_ID, Volume = SOUND_VOLUME,
		Parent = SoundService,
	})
end

local lastSound = 0

local function playChime()
	if not chime then return end

	local now = os.clock()
	if now - lastSound < SOUND_GAP then return end
	lastSound = now

	-- Sound yang sama diputar ulang dari awal, bukan bikin instance baru
	chime.TimePosition = 0
	chime:Play()
end

-- ════════════════════════════════════════════════════════════
-- MASUK
-- ════════════════════════════════════════════════════════════

-- RichText harus di-escape, kalau tidak pesan yang berisi "<" bikin
-- seluruh label gagal di-parse dan tampil kosong.
local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function trim(text: string): string
	if #text <= MAX_TEXT then return text end
	return text:sub(1, MAX_TEXT - 1) .. "…"
end

GlobalAnnouncementEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.text) ~= "string" or data.text == "" then return end

	local name = (type(data.name) == "string" and data.name ~= "") and data.name or "Staff"

	-- Penuh: yang paling atas (paling lama) dibuang supaya yang baru muat
	while #rows >= MAX_ROWS do
		removeRow(rows[1], true)
	end

	local entry = makeRow({
		userId = tonumber(data.userId) or 0,
		rich   = string.format('<font color="%s"><b>%s</b></font>  %s',
			ACCENT_HEX, escape(name), escape(trim(data.text))),
	})
	table.insert(rows, entry)

	TweenService:Create(entry.root,  TWEEN_IN, { GroupTransparency = 0 }):Play()
	TweenService:Create(entry.scale, TWEEN_IN, { Scale = 1 }):Play()

	playChime()

	task.delay(tonumber(data.duration) or DEFAULT_DURATION, function()
		if entry.root.Parent then removeRow(entry, false) end
	end)
end)

-- ════════════════════════════════════════════════════════════
-- RESPONSIVE
-- ════════════════════════════════════════════════════════════

Responsive.OnChange(function()
	if not stack.Parent then return end

	cfg = getConfig()
	stack.Size          = UDim2.new(0, cfg.width, 0, 0)
	stack.Position      = UDim2.new(1, -SIDE_MARGIN, 0, cfg.top)
	stackLayout.Padding = UDim.new(0, ROW_GAP)

	for _, entry in ipairs(rows) do
		layoutRow(entry)
	end
end)