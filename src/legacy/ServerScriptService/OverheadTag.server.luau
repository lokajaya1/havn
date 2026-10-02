-- ═══════════════════════════════════════════════════════════
-- OVERHEAD TAG  (v3)
-- Location : ServerScriptService > OverheadTag  (Script)
--
-- ── Kenapa tag tembus tembok & avatar ──────────────────────
-- AlwaysOnTop = true memaksa billboard digambar paling akhir, tanpa
-- ikut uji kedalaman. Hasilnya tag nempel di depan apa pun: dinding,
-- mobil, avatar orang lain. Bubble chat bawaan Roblox tidak begitu.
-- Sekarang AlwaysOnTop = false, jadi tag ketutup benda yang memang ada
-- di depannya, dan tidak lagi menutupi avatar player lain.
--
-- ── Kenapa posisinya pakai *WorldSpace ─────────────────────
-- StudsOffset biasa menggeser tag di ruang KAMERA. Titik kedalamannya
-- jadi ikut miring saat kamera berputar, dan occlusion-nya meleset.
-- StudsOffsetWorldSpace menggeser lurus ke atas di ruang DUNIA, jadi
-- kedalamannya benar dari sudut mana pun.
--
-- Titik yang digeser = TENGAH tag. Jadi tengahnya dinaikkan ke
-- puncak kepala + CLEARANCE + setengah tinggi tag → TEPI BAWAH tag tepat
-- di atas topi. (Dulu ExtentsOffsetWorldSpace 0.5 dikira "setengah tinggi
-- tag", padahal satuannya ukuran HEAD → separuh bawah tag — nama & role —
-- masuk ke topi dan tertutup kepala. Terbukti screenshot 2026-09-28 07:00.)
--
-- ── Kenapa tag mengecil saat zoom out ──────────────────────
-- Size pakai Scale, yang untuk BillboardGui satuannya STUD. Tag jadi
-- benda dunia: menjauh = ikut mengecil bareng karakternya. Isinya juga
-- Scale semua (TextScaled), jadi tidak ada yang dihitung per frame.
--
-- Layout ditulis dalam "design px" lalu dibagi TAG_PPS jadi stud.
--
-- Lainnya:
--  • Status /afk & /nametag (atribut character DT_Status) juga DI DALAM
--    billboard ini: satu kesatuan title → status → nama → role, tidak lagi
--    billboard terpisah yang menumpuk. Lebar pill status ikut panjang teks.
--  • Susunan rata BAWAH: nama & role tidak pernah bergeser; slot yang
--    kosong tidak meninggalkan celah (title turun kalau tidak ada status).
--  • Bubble chat dinaikkan setinggi tag (VerticalStudsOffset) supaya tidak
--    menutupi nama/status.
--  • Tinggi kepala diukur ulang saat aksesoris selesai dimuat
--    (CharacterAppearanceLoaded / Accessory baru) → role tidak menempel topi.
--  • Title tinggal DI DALAM billboard yang sama dengan nama, jadi
--    jaraknya mustahil meleset dan ikut hilang saat nametag disembunyikan.
--  • Tinggi tag selalu sama, punya title atau tidak — nama tidak lompat.
--  • Animasi title dijalankan client (TitlePlate), bukan server.
--  • Ganti Role cuma menulis ulang label, tidak membangun ulang tag.
--  • Warna NAMA = aksen tema warna pilihan pemain itu (atribut Player
--    "ThemeColor" dari ServerScriptService.ThemeColor, Rules.nameColor),
--    dilihat semua pemain. Tema polos (Default) = putih seperti dulu.
--    Ganti tema cuma mewarnai ulang label, tidak membangun ulang tag.
-- ═══════════════════════════════════════════════════════════

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local SSS         = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")
local TextChat    = game:GetService("TextChatService")

local RankConfig = require(SSS:WaitForChild("RankConfig"))
local ThemeConfig = require(RS:WaitForChild("Config"):WaitForChild("ThemeColor"))
local ThemeRules  = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"):WaitForChild("Rules"))

local TitleStyle
do
	local folder = RS:WaitForChild("CustomUIModules", 10)
	local module = (folder and folder:FindFirstChild("TitleStyle"))
		or RS:FindFirstChild("TitleStyle")
	if module and module:IsA("ModuleScript") then
		TitleStyle = require(module)
	else
		warn("[OverheadTag] TitleStyle tidak ketemu — pakai ukuran cadangan.")
	end
end

-- ═══════════════════════════════════════════════════════════
-- UKURAN — edit di sini saja (design px)
-- ═══════════════════════════════════════════════════════════
local PPS     = TitleStyle and TitleStyle.TAG_PPS  or 36   -- design px per stud
local BILL_W  = TitleStyle and TitleStyle.TAG_W    or 300
local TITLE_H = TitleStyle and TitleStyle.PLATE_H  or 20
local GAP_T_N = TitleStyle and TitleStyle.NAME_GAP or 2

local NAME_H   = 15
local GAP_N_R  = 1
local ROLE_H   = 10
local STATUS_H = 16   -- pill /afk & /nametag
local GAP_S    = 2    -- jarak pill → nama dan title → pill
local STATUS_TEXT = 11
local STATUS_PAD  = 8 -- ruang kiri + kanan teks di dalam pill

-- Tersusun dari BAWAH: role, nama, (status), title.
local TOTAL_H  = TITLE_H + GAP_S + STATUS_H + GAP_S + NAME_H + GAP_N_R + ROLE_H   -- 66
local ROLE_Y   = TOTAL_H - ROLE_H
local NAME_Y   = ROLE_Y - GAP_N_R - NAME_H
local STATUS_Y = NAME_Y - GAP_S - STATUS_H
local TITLE_Y_WITH_STATUS = STATUS_Y - GAP_S - TITLE_H           -- 0
local TITLE_Y_NO_STATUS   = NAME_Y - GAP_T_N - TITLE_H           -- title nempel nama

local NAME_COLOR = Color3.fromRGB(238, 238, 238) -- nama tema polos (Default)

local STATUS_STYLE = {
	afk = { text = Color3.fromRGB(255, 195, 40),  bg = Color3.fromRGB(20, 20, 26), bgT = 0.15 },
	tag = { text = Color3.fromRGB(230, 230, 238), bg = Color3.fromRGB(15, 15, 20), bgT = 0.2 },
}

-- Jarak tepi bawah tag ke puncak kepala (stud).
-- (TAG_CENTER dihitung di bawah, setelah TOTAL_H diketahui.)
local CLEARANCE    = 0.45
-- Batas atas kalau player pakai topi raksasa; tanpa ini tag bisa
-- terbang jauh sekali di atas kepala.
local MAX_HEAD_TOP = 2.5
local MAX_DISTANCE = 80

local HALF_TAG = TOTAL_H / PPS / 2
-- Bubble chat bawaan digambar di atas kepala; naikkan setinggi tag supaya
-- tidak menutupi nama/status. Properti instance di TextChatService →
-- ditulis server, tereplikasi ke semua client.
local BUBBLE_OFFSET = CLEARANCE + TOTAL_H / PPS
do
	local cfg = TextChat:FindFirstChildOfClass("BubbleChatConfiguration")
	if cfg then
		pcall(function() cfg.VerticalStudsOffset = BUBBLE_OFFSET end)
	end
end

local paintStatus -- didefinisikan di bawah (dipakai applyTag)

-- ── Connection registry (per player) ──────────────────────
local playerConns = {}

local function clearConns(plr)
	local list = playerConns[plr]
	if not list then return end
	for _, c in ipairs(list) do pcall(c.Disconnect, c) end
	playerConns[plr] = nil
end

local function addConn(plr, c)
	if not playerConns[plr] then playerConns[plr] = {} end
	table.insert(playerConns[plr], c)
end

-- Warna nama: aksen tema warna pilihan pemain (ThemeColor), atau NAME_COLOR.
local function nameColorOf(player)
	return ThemeRules.nameColor(ThemeConfig, player:GetAttribute("ThemeColor")) or NAME_COLOR
end

local function roleOf(player)
	local roleName = player:GetAttribute("Role") or "Guest"
	return RankConfig.RANKS[roleName] or RankConfig.RANKS.Guest
end

-- Puncak kepala diukur dari kepala + aksesoris yang menempel di sana,
-- dihitung sekali saat tag dibangun. Ini yang bikin tag tetap pas walau
-- kepalanya diperbesar (/size) atau pakai topi tinggi.
local function headTop(character, head)
	local top = head.Size.Y * 0.5

	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Accessory") then
			local handle = obj:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				local dy = (handle.Position.Y + handle.Size.Y * 0.5) - head.Position.Y
				if dy > top then top = dy end
			end
		end
	end

	return math.min(top, MAX_HEAD_TOP)
end

local function tagOffset(character, head)
	return Vector3.new(0, headTop(character, head) + CLEARANCE + HALF_TAG, 0)
end

-- ── Status (/afk, /nametag) ───────────────────────────────

local function textWidth(text)
	local ok, size = pcall(TextService.GetTextSize, TextService, text, STATUS_TEXT,
		Enum.Font.GothamBold, Vector2.new(10000, 100))
	if ok and size then return size.X end
	return utf8.len(text) and utf8.len(text) * STATUS_TEXT * 0.62 or #text * 7 -- cadangan
end

-- Teks status SUDAH difilter CommandServer sebelum ditulis ke atribut.
paintStatus = function(character, bill)
	local pill = bill:FindFirstChild("StatusPill")
	local slot = bill:FindFirstChild("TitleSlot")
	if not (pill and slot) then return end
	local text  = character:GetAttribute("DT_Status")
	local style = STATUS_STYLE[character:GetAttribute("DT_StatusKind")] or STATUS_STYLE.tag
	local on    = type(text) == "string" and text ~= ""

	pill.Visible = on
	slot.Position = UDim2.fromScale(0, (on and TITLE_Y_WITH_STATUS or TITLE_Y_NO_STATUS) / TOTAL_H)
	if not on then return end

	local label = pill:FindFirstChild("StatusText")
	local w = math.min(textWidth(text) + STATUS_PAD * 2, BILL_W)
	pill.Size = UDim2.fromScale(w / BILL_W, STATUS_H / TOTAL_H)
	pill.BackgroundColor3       = style.bg
	pill.BackgroundTransparency = style.bgT
	if label then
		label.Text       = text
		label.TextColor3 = style.text
	end
end

local function tagOf(character)
	local head = character:FindFirstChild("Head")
	return head and head:FindFirstChild("OverheadTag")
end

-- Ukur ulang tinggi kepala TANPA membangun ulang tag (plate title tetap).
local function remeasure(character)
	local head = character:FindFirstChild("Head")
	local bill = tagOf(character)
	if head and bill then
		bill.StudsOffsetWorldSpace = tagOffset(character, head)
	end
end

-- Sekali per character: status & aksesoris yang datang belakangan.
local watched = setmetatable({}, { __mode = "k" })
local function watchCharacter(player, character)
	if watched[character] then return end
	watched[character] = true

	local function onStatus()
		local bill = tagOf(character)
		if bill then paintStatus(character, bill) end
	end
	character:GetAttributeChangedSignal("DT_Status"):Connect(onStatus)
	character:GetAttributeChangedSignal("DT_StatusKind"):Connect(onStatus)

	local pending = false
	character.ChildAdded:Connect(function(child)
		if not child:IsA("Accessory") or pending then return end
		pending = true
		task.delay(0.3, function()
			pending = false
			if character.Parent and player.Character == character then remeasure(character) end
		end)
	end)
end

-- ── Build tag ─────────────────────────────────────────────

local function applyTag(player, character)
	local head     = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (head and humanoid) then return end
	-- Character bisa sudah diganti selama WaitForChild
	if player.Character ~= character then return end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	watchCharacter(player, character)

	local old = head:FindFirstChild("OverheadTag")
	if old then old:Destroy() end

	local roleData  = roleOf(player)
	local roleColor = roleData.color or Color3.fromRGB(255, 255, 255)

	local bill = Instance.new("BillboardGui")
	bill.Name    = "OverheadTag"
	bill.Adornee = head

	-- Scale, bukan Offset: satuannya stud, jadi ikut skala dunia.
	bill.Size = UDim2.fromScale(BILL_W / PPS, TOTAL_H / PPS)

	-- Ikut uji kedalaman — ketutup dinding dan avatar di depannya.
	bill.AlwaysOnTop = false
	-- Tetap terang walau lokasinya gelap, biar nama masih kebaca.
	bill.LightInfluence = 0
	bill.MaxDistance    = MAX_DISTANCE

	-- Naik lurus di ruang dunia, bukan ruang kamera → occlusion akurat.
	-- Tengah tag = puncak kepala + jarak + setengah tinggi tag.
	bill.StudsOffsetWorldSpace = tagOffset(character, head)

	-- Slot title: selalu ada, diisi client. Kosong = tidak kelihatan.
	local slot = Instance.new("Frame")
	slot.Name                   = "TitleSlot"
	slot.BackgroundTransparency = 1
	slot.Position               = UDim2.fromScale(0, TITLE_Y_NO_STATUS / TOTAL_H)
	slot.Size                   = UDim2.fromScale(1, TITLE_H / TOTAL_H)
	slot.Parent                 = bill

	-- Pill status: lebar diatur paintStatus() sesuai teks.
	local pill = Instance.new("Frame")
	pill.Name             = "StatusPill"
	pill.AnchorPoint      = Vector2.new(0.5, 0)
	pill.Position         = UDim2.fromScale(0.5, STATUS_Y / TOTAL_H)
	pill.Size             = UDim2.fromScale(0, STATUS_H / TOTAL_H)
	pill.BorderSizePixel  = 0
	pill.Visible          = false
	pill.Parent           = bill
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent       = pill
	local pillText = Instance.new("TextLabel")
	pillText.Name                   = "StatusText"
	pillText.AnchorPoint            = Vector2.new(0.5, 0.5)
	pillText.Position               = UDim2.fromScale(0.5, 0.5)
	pillText.Size                   = UDim2.fromScale(1, STATUS_TEXT / STATUS_H)
	pillText.BackgroundTransparency = 1
	pillText.Font                   = Enum.Font.GothamBold
	pillText.TextScaled             = true
	pillText.Text                   = ""
	pillText.Parent                 = pill

	local function makeLabel(name, posY, h, text, color, strokeTrans)
		local l = Instance.new("TextLabel")
		l.Name                   = name
		l.Position               = UDim2.fromScale(0, posY / TOTAL_H)
		l.Size                   = UDim2.fromScale(1, h / TOTAL_H)
		l.BackgroundTransparency = 1
		l.Text                   = text
		l.TextColor3             = color
		l.Font                   = Enum.Font.GothamBold
		l.TextScaled             = true   -- ikut tinggi kotak → ikut stud
		l.TextStrokeTransparency = strokeTrans
		l.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
		l.TextXAlignment         = Enum.TextXAlignment.Center
		l.Parent                 = bill
		return l
	end

	makeLabel("NameLabel", NAME_Y, NAME_H,
		player.DisplayName, nameColorOf(player), 0.5)

	makeLabel("RoleLabel", ROLE_Y, ROLE_H,
		roleData.displayText or "GUEST", roleColor, 1)

	paintStatus(character, bill)

	-- Parent terakhir: billboard sampai ke client sudah lengkap isinya.
	bill.Parent = head
end

-- Ganti role cukup tulis ulang labelnya. Membangun ulang tag akan
-- menghapus plate title yang sudah dipasang client.
local function refreshRole(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local bill = head and head:FindFirstChild("OverheadTag")
	local lbl  = bill and bill:FindFirstChild("RoleLabel")

	if not lbl then
		if char then applyTag(player, char) end
		return
	end

	local roleData = roleOf(player)
	lbl.Text       = roleData.displayText or "GUEST"
	lbl.TextColor3 = roleData.color or Color3.fromRGB(255, 255, 255)
end

-- Ganti tema warna cukup mewarnai ulang nama (tag tidak dibangun ulang).
local function refreshName(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local bill = head and head:FindFirstChild("OverheadTag")
	local lbl  = bill and bill:FindFirstChild("NameLabel")
	if lbl then lbl.TextColor3 = nameColorOf(player) end
end

-- ── Player setup ──────────────────────────────────────────

local function setupPlayer(player)
	clearConns(player)

	addConn(player, player:GetAttributeChangedSignal("Role"):Connect(function()
		refreshRole(player)
	end))

	addConn(player, player:GetAttributeChangedSignal("ThemeColor"):Connect(function()
		refreshName(player)
	end))

	-- Aksesoris sering selesai dimuat SETELAH tag dibangun → ukur ulang.
	addConn(player, player.CharacterAppearanceLoaded:Connect(function(ch)
		if player.Character == ch then remeasure(ch) end
	end))

	addConn(player, player.CharacterAdded:Connect(function(ch)
		-- Beri waktu aksesoris terpasang, biar headTop() terukur benar.
		task.wait(0.4)
		applyTag(player, ch)
	end))

	if player.Character then applyTag(player, player.Character) end
end

-- ── Event: attribute siap (dari sistem rank) ──────────────
task.spawn(function()
	local ev = SSS:WaitForChild("PlayerAttributesReady", 30)
	if not (ev and ev:IsA("BindableEvent")) then
		warn("[OverheadTag] PlayerAttributesReady tidak ditemukan.")
		return
	end
	ev.Event:Connect(function(player)
		if player and player.Character then
			refreshRole(player)
		end
	end)
end)

-- ── Re-apply setelah ApplyDescription (/headless, /size, dll) ──
-- Head bisa jadi instance baru dan tingginya berubah, jadi tag lama
-- sudah hancur dan jaraknya perlu diukur ulang.
task.spawn(function()
	local ev = SSS:WaitForChild("PlayerAppearanceApplied", 30)
	if not (ev and ev:IsA("BindableEvent")) then
		warn("[OverheadTag] PlayerAppearanceApplied tidak ditemukan — "
			.. "tag tidak akan re-apply setelah /headless dkk.")
		return
	end
	ev.Event:Connect(function(player)
		local char = player and player.Character
		if not char then return end
		task.wait(0.25)   -- beri waktu Roblox selesai menukar part
		if char.Parent and player.Character == char then
			applyTag(player, char)
		end
	end)
end)

-- ── Lifecycle ─────────────────────────────────────────────
Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(clearConns)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(setupPlayer, p) end

print("[OverheadTag] Ready")