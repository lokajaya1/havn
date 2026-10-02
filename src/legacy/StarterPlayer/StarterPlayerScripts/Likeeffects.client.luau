-- ═══════════════════════════════════════════════════════════
-- LIKE EFFECTS — LocalScript
-- Location: StarterPlayer > StarterPlayerScripts > LikeEffects
--
-- Tiga efek, semuanya dirender LOKAL (tidak ada instance yang direplikasi):
--   1. Burst  — partikel hati keluar dari tombol like (yang nge-like)
--   2. World  — hati melayang di atas kepala target (yang nge-like)
--   3. Toast  — kartu "X menyukai avatarmu" (yang DI-like)
--
-- Efek 1 & 2 dipanggil langsung oleh MenuSystemInit lewat _G.LikeEffects,
-- jadi tidak butuh trafik jaringan sama sekali.
-- Efek 3 dipicu remote "received" dari LikeSystem — satu paket ke satu
-- pemain, bukan FireAllClients.
-- ═══════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UIS          = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
	-- Jumlah partikel per burst, per device. Mobile dikurangi karena
	-- fill-rate-nya yang jadi bottleneck, bukan jumlah instance-nya.
	Particles = { mobile = 6, tablet = 9, desktop = 12 },

	Enabled         = true,   -- kill switch, bisa dimatikan pemain dari setting
	MaxActiveBursts = 4,      -- burst berikutnya diabaikan, bukan di-queue
	ParticleLife    = 0.85,

	WorldHearts        = true,
	WorldLife          = 1.4,
	MaxWorldBursts     = 6,   -- BillboardGui aktif bersamaan
	MaxRenderDistance  = 120, -- studs; lebih jauh dari ini tidak dirender
	DedupeWindow       = 0.6, -- detik; satu target tidak boleh dobel efek

	ToastSeconds    = 3.5,
	MaxToasts       = 3,

	Sound           = true,
	-- Aset bawaan Roblox. Ganti dengan asset ID sendiri kalau punya.
	SoundId         = "rbxasset://sounds/electronicpingshort.wav",
	SoundVolume     = 0.35,
}

local HEART      = "♥"
local LIKE_COLOR = Color3.fromRGB(235, 86, 96) -- warna hati (konten, tidak ikut tema)

-- Kartu toast: token ReplicatedStorage.Modules.ThemeColor (themeColor), dibaca saat toast dibuat → ikut tema pemain.
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local T = ThemeColor.tokens

-- ── GUI host ────────────────────────────────────────────────
-- IgnoreGuiInset = true supaya sistem koordinatnya SAMA dengan
-- AbsolutePosition yang kita baca dari tombol like. Kalau false, semua
-- partikel akan meleset 36px ke bawah di layar yang punya topbar.

local gui = playerGui:FindFirstChild("LikeEffectsGui")
if gui then gui:Destroy() end

gui = Instance.new("ScreenGui")
gui.Name             = "LikeEffectsGui"
gui.ResetOnSpawn     = false
gui.IgnoreGuiInset   = true
gui.DisplayOrder     = 50            -- di atas PlayerMenuGui (10)
gui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
gui.Parent           = playerGui

-- Partikel tidak boleh menempel di MenuFrame: frame itu ClipsDescendants,
-- jadi hati yang terbang keluar kartu akan terpotong.
local burstLayer = Instance.new("Frame")
burstLayer.Name                   = "BurstLayer"
burstLayer.Size                   = UDim2.fromScale(1, 1)
burstLayer.BackgroundTransparency = 1
burstLayer.ZIndex                 = 1
burstLayer.Parent                 = gui

-- ── Util ────────────────────────────────────────────────────

local function deviceKey()
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then
		local cam = workspace.CurrentCamera
		local vp  = cam and cam.ViewportSize or Vector2.new(1280, 720)
		return (math.max(vp.X, vp.Y) >= 1000) and "tablet" or "mobile"
	end
	return "desktop"
end

local sound
local function playPing()
	if not CONFIG.Sound then return end
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = CONFIG.SoundId
		sound.Volume  = CONFIG.SoundVolume
		sound.Parent  = SoundService
	end
	pcall(function() SoundService:PlayLocalSound(sound) end)
end

-- ── 1. Burst partikel dari sebuah GuiObject ─────────────────

local activeBursts = 0

local function spawnParticle(originX, originY, index, total)
	local size = math.random(12, 20)

	local heart = Instance.new("TextLabel")
	heart.Name                   = "Heart"
	heart.AnchorPoint            = Vector2.new(0.5, 0.5)
	heart.Position               = UDim2.fromOffset(originX, originY)
	heart.Size                   = UDim2.fromOffset(size, size)
	heart.BackgroundTransparency = 1
	heart.Text                   = HEART
	heart.TextColor3             = LIKE_COLOR
	heart.Font                   = Enum.Font.BuilderSansBold
	heart.TextSize               = size
	heart.TextTransparency       = 0
	heart.Rotation               = math.random(-25, 25)
	heart.ZIndex                 = 2
	heart.Parent                 = burstLayer

	-- Sebar melengkung ke atas: sudut dibagi rata lalu diberi jitter,
	-- supaya tidak kelihatan seperti garis lurus.
	local spread = math.rad(-90 + (index / total - 0.5) * 110 + math.random(-12, 12))
	local dist   = math.random(55, 105)
	local targetX = originX + math.cos(spread) * dist
	local targetY = originY + math.sin(spread) * dist

	local life = CONFIG.ParticleLife

	TweenService:Create(heart, TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(targetX, targetY),
		Rotation = heart.Rotation + math.random(-60, 60),
	}):Play()

	-- Fade dimulai belakangan supaya hati terlihat dulu sebelum lenyap
	task.delay(life * 0.35, function()
		if not heart.Parent then return end
		TweenService:Create(heart, TweenInfo.new(life * 0.65, Enum.EasingStyle.Linear), {
			TextTransparency = 1,
			Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		}):Play()
	end)

	task.delay(life + 0.1, function()
		if heart then heart:Destroy() end
	end)
end

local function burst(guiObject)
	if typeof(guiObject) ~= "Instance" or not guiObject:IsA("GuiObject") then return end
	if activeBursts >= CONFIG.MaxActiveBursts then return end

	activeBursts += 1
	task.delay(CONFIG.ParticleLife + 0.2, function()
		activeBursts = math.max(0, activeBursts - 1)
	end)

	local abs   = guiObject.AbsolutePosition
	local dim   = guiObject.AbsoluteSize
	local originX = math.floor(abs.X + dim.X * 0.5)
	local originY = math.floor(abs.Y + dim.Y * 0.5)

	local total = CONFIG.Particles[deviceKey()] or 8
	for i = 1, total do
		task.delay((i - 1) * 0.025, function()
			spawnParticle(originX, originY, i, total)
		end)
	end

	playPing()
end

-- ── 2. Hati melayang di atas kepala target ──────────────────
-- BillboardGui di-parent ke PlayerGui (bukan ke karakter), jadi murni lokal
-- dan tidak ikut direplikasi ke pemain lain.

-- Terima Player, Model karakter, atau userId — pemanggilnya banyak
-- (menu, toast, dan pulse dari server), jadi resolusinya disatukan di sini.
local function resolveAdornee(subject)
	local char
	if typeof(subject) == "Instance" then
		if subject:IsA("Player") then
			char = subject.Character
		elseif subject:IsA("Model") then
			char = subject
		end
	elseif typeof(subject) == "number" then
		local plr = Players:GetPlayerByUserId(subject)
		char = plr and plr.Character
	end
	if not char then return nil end
	return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local activeWorld  = 0
local recentBursts = {} -- [adornee] = os.clock() → anti dobel render

local function worldHearts(subject)
	if not CONFIG.WorldHearts or not CONFIG.Enabled then return end

	local adornee = resolveAdornee(subject)
	if not adornee then return end

	-- Dedupe. Satu like bisa memanggil fungsi ini dari tiga jalur sekaligus:
	-- klik lokal (instan), toast di penerima, dan pulse attribute dari server.
	-- Yang datang pertama menang, sisanya dibuang.
	local now  = os.clock()
	local last = recentBursts[adornee]
	if last and now - last < CONFIG.DedupeWindow then return end
	recentBursts[adornee] = now

	-- Cap: 30 orang saling nge-like tidak boleh jadi 30 BillboardGui sekaligus
	if activeWorld >= CONFIG.MaxWorldBursts then return end

	-- Filter jarak: instance-nya bahkan tidak dibuat kalau jauh dari kamera.
	-- MaxDistance di BillboardGui hanya menyembunyikan, tetap ada biayanya.
	local cam = workspace.CurrentCamera
	if cam then
		local dist = (cam.CFrame.Position - adornee.Position).Magnitude
		if dist > CONFIG.MaxRenderDistance then return end
	end

	activeWorld += 1

	local bb = Instance.new("BillboardGui")
	bb.Name          = "LikeHearts"
	bb.Adornee       = adornee
	bb.Size          = UDim2.fromOffset(140, 140)
	bb.StudsOffset   = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop   = true
	bb.LightInfluence = 0
	bb.MaxDistance   = 80
	bb.Parent        = gui

	for i = 1, 5 do
		task.delay((i - 1) * 0.09, function()
			if not bb.Parent then return end
			local size = math.random(16, 26)

			local heart = Instance.new("TextLabel")
			heart.AnchorPoint            = Vector2.new(0.5, 0.5)
			heart.Position               = UDim2.new(0.5, math.random(-22, 22), 1, 0)
			heart.Size                   = UDim2.fromOffset(size, size)
			heart.BackgroundTransparency = 1
			heart.Text                   = HEART
			heart.TextColor3             = LIKE_COLOR
			heart.Font                   = Enum.Font.BuilderSansBold
			heart.TextSize               = size
			heart.Rotation               = math.random(-20, 20)
			heart.Parent                 = bb

			TweenService:Create(heart, TweenInfo.new(CONFIG.WorldLife, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position         = UDim2.new(0.5, math.random(-40, 40), 0, 0),
				TextTransparency = 1,
				Rotation         = heart.Rotation + math.random(-45, 45),
			}):Play()
		end)
	end

	task.delay(CONFIG.WorldLife + 0.6, function()
		if bb then bb:Destroy() end
		activeWorld = math.max(0, activeWorld - 1)
		if recentBursts[adornee] == now then recentBursts[adornee] = nil end
	end)
end

-- ── 3. Toast untuk yang di-like ─────────────────────────────

local toastHolder = Instance.new("Frame")
toastHolder.Name                   = "ToastHolder"
toastHolder.AnchorPoint            = Vector2.new(0.5, 0)
toastHolder.Position               = UDim2.new(0.5, 0, 0, 46)
toastHolder.Size                   = UDim2.new(0, 260, 0, 0)
toastHolder.BackgroundTransparency = 1
toastHolder.ZIndex                 = 5
toastHolder.Parent                 = gui

local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder          = Enum.SortOrder.LayoutOrder
toastLayout.Padding            = UDim.new(0, 6)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Parent             = toastHolder

local toastCount = 0
local toastOrder = 0

local function showToast(likerUserId, likerName)
	if toastCount >= CONFIG.MaxToasts then return end
	toastCount += 1
	toastOrder += 1

	local card = Instance.new("Frame")
	card.Name             = "LikeToast"
	card.Size             = UDim2.new(1, 0, 0, 44)
	card.BackgroundColor3  = T.CARD
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel  = 0
	card.LayoutOrder      = toastOrder
	card.Parent           = toastHolder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent       = card

	local stroke = Instance.new("UIStroke")
	stroke.Color            = LIKE_COLOR
	stroke.Thickness        = 1
	stroke.Transparency     = 0.55
	stroke.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
	stroke.Parent           = card

	local avatar = Instance.new("ImageLabel")
	avatar.AnchorPoint            = Vector2.new(0, 0.5)
	avatar.Position               = UDim2.new(0, 7, 0.5, 0)
	avatar.Size                   = UDim2.fromOffset(30, 30)
	avatar.BackgroundColor3       = T.CARD_HOVER
	avatar.BorderSizePixel        = 0
	avatar.ScaleType              = Enum.ScaleType.Fit
	avatar.Image = (likerUserId and likerUserId > 0)
		and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", likerUserId)
		or ""
	avatar.Parent = card

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent       = avatar

	local heart = Instance.new("TextLabel")
	heart.AnchorPoint            = Vector2.new(1, 0.5)
	heart.Position               = UDim2.new(1, -10, 0.5, 0)
	heart.Size                   = UDim2.fromOffset(20, 20)
	heart.BackgroundTransparency = 1
	heart.Text                   = HEART
	heart.TextColor3             = LIKE_COLOR
	heart.Font                   = Enum.Font.BuilderSansBold
	heart.TextSize               = 18
	heart.Parent                 = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position               = UDim2.new(0, 44, 0, 6)
	nameLabel.Size                   = UDim2.new(1, -78, 0, 15)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = likerName or "Seseorang"
	nameLabel.TextColor3             = T.TEXT
	nameLabel.Font                   = Enum.Font.BuilderSansBold
	nameLabel.TextSize               = 13
	nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
	nameLabel.TextTruncate           = Enum.TextTruncate.AtEnd
	nameLabel.Parent                 = card

	local subLabel = Instance.new("TextLabel")
	subLabel.Position               = UDim2.new(0, 44, 0, 22)
	subLabel.Size                   = UDim2.new(1, -78, 0, 14)
	subLabel.BackgroundTransparency = 1
	subLabel.Text                   = "menyukai avatarmu"
	subLabel.TextColor3             = T.TEXT_DIM
	subLabel.Font                   = Enum.Font.BuilderSans
	subLabel.TextSize               = 11
	subLabel.TextXAlignment         = Enum.TextXAlignment.Left
	subLabel.TextTruncate           = Enum.TextTruncate.AtEnd
	subLabel.Parent                 = card

	-- Masuk: turun sedikit + fade in
	card.Position = UDim2.new(0, 0, 0, -10)
	for _, obj in ipairs({ nameLabel, subLabel, heart }) do
		obj.TextTransparency = 1
		TweenService:Create(obj, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	end
	card.BackgroundTransparency = 1
	TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.05,
	}):Play()

	-- Hati di toast ikut berdenyut sekali
	TweenService:Create(heart, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 24,
	}):Play()
	task.delay(0.16, function()
		if heart.Parent then
			TweenService:Create(heart, TweenInfo.new(0.16), { TextSize = 18 }):Play()
		end
	end)

	-- Keluar
	task.delay(CONFIG.ToastSeconds, function()
		if not card.Parent then
			toastCount = math.max(0, toastCount - 1)
			return
		end
		TweenService:Create(card, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		for _, obj in ipairs({ nameLabel, subLabel, heart }) do
			TweenService:Create(obj, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		end
		TweenService:Create(avatar, TweenInfo.new(0.25), { ImageTransparency = 1 }):Play()
		task.delay(0.3, function()
			card:Destroy()
			toastCount = math.max(0, toastCount - 1)
		end)
	end)

	-- Hati juga meletup di atas kepala kita sendiri, jadi terasa "kena"
	worldHearts(player.UserId)
	playPing()
end

-- ── API + remote ────────────────────────────────────────────

_G.LikeEffects = {
	Burst       = burst,
	WorldHearts = worldHearts,
	Toast       = showToast,
	Config      = CONFIG,
	SetEnabled  = function(on) CONFIG.Enabled = (on ~= false) end,
	IsEnabled   = function() return CONFIG.Enabled end,
}

-- ── Pulse: efek yang dilihat SEMUA pemain ───────────────────
-- Server menaikkan Attribute "LikePulse" di Player yang di-like. Attribute
-- Player direplikasi otomatis ke semua client, jadi tidak perlu
-- FireAllClients: satu perubahan properti, bukan N paket remote buatan.
-- Setiap client memutuskan sendiri apakah efeknya dirender (jarak, cap,
-- dedupe), jadi beban render tidak dipaksakan dari server.

local pulseConns = {}

local function bindPulse(plr)
	if pulseConns[plr] then return end
	pulseConns[plr] = plr:GetAttributeChangedSignal("LikePulse"):Connect(function()
		-- Nilai pulse-nya tidak dipakai; yang penting perubahannya.
		-- Karakter bisa belum ada (baru respawn) — worldHearts pulang sendiri.
		worldHearts(plr)
	end)
end

local function unbindPulse(plr)
	local conn = pulseConns[plr]
	if conn then
		conn:Disconnect()
		pulseConns[plr] = nil
	end
end

for _, plr in ipairs(Players:GetPlayers()) do
	bindPulse(plr)
end
Players.PlayerAdded:Connect(bindPulse)
Players.PlayerRemoving:Connect(unbindPulse)

task.spawn(function()
	local folder = RS:WaitForChild("LikeRemotes", 20)
	local remote = folder and folder:WaitForChild("AvatarLike", 10)
	if not remote then
		warn("[LikeEffects] LikeRemotes.AvatarLike tidak ada — toast dimatikan.")
		return
	end

	remote.OnClientEvent:Connect(function(kind, likerUserId, likerName)
		if kind ~= "received" then return end
		showToast(tonumber(likerUserId) or 0, likerName)
	end)
end)

print("[LikeEffects] Ready |", deviceKey())