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
-- ExtentsOffsetWorldSpace.Y = 0.5 menaikkan tag setengah tingginya
-- sendiri, jadi TEPI BAWAH tag persis di titik acuan. Tingginya tidak
-- perlu ikut dihitung manual saat menyetel jarak.
--
-- ── Kenapa tag mengecil saat zoom out ──────────────────────
-- Size pakai Scale, yang untuk BillboardGui satuannya STUD. Tag jadi
-- benda dunia: menjauh = ikut mengecil bareng karakternya. Isinya juga
-- Scale semua (TextScaled), jadi tidak ada yang dihitung per frame.
--
-- Layout ditulis dalam "design px" lalu dibagi TAG_PPS jadi stud.
--
-- Lainnya:
--  • Title tinggal DI DALAM billboard yang sama dengan nama, jadi
--    jaraknya mustahil meleset dan ikut hilang saat nametag disembunyikan.
--  • Tinggi tag selalu sama, punya title atau tidak — nama tidak lompat.
--  • Animasi title dijalankan client (TitlePlate), bukan server.
--  • Ganti Role cuma menulis ulang label, tidak membangun ulang tag.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local SSS     = game:GetService("ServerScriptService")

local RankConfig = require(SSS:WaitForChild("RankConfig"))

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

local NAME_H  = 15
local GAP_N_R = 1
local ROLE_H  = 10

local TOTAL_H = TITLE_H + GAP_T_N + NAME_H + GAP_N_R + ROLE_H   -- 48
local NAME_Y  = TITLE_H + GAP_T_N
local ROLE_Y  = NAME_Y + NAME_H + GAP_N_R

-- Jarak tepi bawah tag ke puncak kepala (stud).
local CLEARANCE    = 0.35
-- Batas atas kalau player pakai topi raksasa; tanpa ini tag bisa
-- terbang jauh sekali di atas kepala.
local MAX_HEAD_TOP = 2.5
local MAX_DISTANCE = 80

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

-- ── Build tag ─────────────────────────────────────────────

local function applyTag(player, character)
	local head     = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (head and humanoid) then return end
	-- Character bisa sudah diganti selama WaitForChild
	if player.Character ~= character then return end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

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
	bill.StudsOffsetWorldSpace   = Vector3.new(0, headTop(character, head) + CLEARANCE, 0)
	-- Naikkan setengah tinggi tag sendiri → tepi bawah pas di titik acuan.
	bill.ExtentsOffsetWorldSpace = Vector3.new(0, 0.5, 0)

	-- Slot title: selalu ada, diisi client. Kosong = tidak kelihatan.
	local slot = Instance.new("Frame")
	slot.Name                   = "TitleSlot"
	slot.BackgroundTransparency = 1
	slot.Position               = UDim2.fromScale(0, 0)
	slot.Size                   = UDim2.fromScale(1, TITLE_H / TOTAL_H)
	slot.Parent                 = bill

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
		player.DisplayName, Color3.fromRGB(238, 238, 238), 0.5)

	makeLabel("RoleLabel", ROLE_Y, ROLE_H,
		roleData.displayText or "GUEST", roleColor, 1)

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

-- ── Player setup ──────────────────────────────────────────

local function setupPlayer(player)
	clearConns(player)

	addConn(player, player:GetAttributeChangedSignal("Role"):Connect(function()
		refreshRole(player)
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