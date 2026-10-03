-- ═══════════════════════════════════════════════════════════
-- RANK CONFIG — ModuleScript
-- Location: ServerScriptService > RankConfig
-- ═══════════════════════════════════════════════════════════

local ShopConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig"))
local VIP_PASS   = ShopConfig.getGamepassByName("VIP Access")
local VVIP_PASS  = ShopConfig.getGamepassByName("VVIP Access")

local RankConfig = {}

------------------------------------------------------------------------
-- IDs
------------------------------------------------------------------------

RankConfig.GROUP_ID         = 277580244
-- ID dari ShopConfig (satu sumber). Kepemilikan juga mengecek ID lama (ShopConfig.userOwnsPass).
RankConfig.VIP_GAMEPASS_ID  = VIP_PASS.id
RankConfig.VVIP_GAMEPASS_ID = VVIP_PASS.id

------------------------------------------------------------------------
-- ⚠️ UPDATE PENTING (Roblox Communities) ⚠️
-- Roblox sekarang TIDAK otomatis kasih rank 1 ke member baru waktu join
-- community. Member baru bisa "rankless" (GetRankInGroup() == 0) walaupun
-- mereka sudah jadi anggota.
--
-- Jadi status VIP TIDAK lagi ditentukan dari rank == 1, melainkan dari
-- KEANGGOTAAN komunitas itu sendiri.
--
-- Role & status pemain dihitung SATU tempat: UnifiedRankManager (rumus di
-- RankRules) lalu dipasang sebagai atribut (Role, EffectiveRank, IsAdmin,
-- IsVIP, …). Sistem lain membaca ATRIBUT itu, bukan menghitung sendiri.
-- JANGAN pakai GetRoleByRank() sendirian untuk menentukan Role — ia hanya
-- mencocokkan angka rank (member rankless → "Guest").
------------------------------------------------------------------------

------------------------------------------------------------------------
-- TIER THRESHOLDS
-- Rank >= VVIP_MIN_RANK  → collision tier "VVIP" (tembus DoorVIP + DoorVVIP)
-- Member komunitas (isGroupMember) ATAU Rank >= VIP_MIN_RANK → tier "VIP"
-- Bukan member & rank < VIP_MIN_RANK → tier "Normal"
------------------------------------------------------------------------

RankConfig.VVIP_MIN_RANK  = 10   -- VVIP rank dan seterusnya ke atas (manual assign)
RankConfig.VIP_MIN_RANK   = 1    -- VIP rank manual (legacy, masih dipakai kalau ada admin yg assign rank 1 manual)
RankConfig.ADMIN_MIN_RANK = 250
RankConfig.DEV_MIN_RANK   = 251
RankConfig.OWNER_RANK     = 255  -- ⚠️ CEK: komentar lama bilang Owner rank aslinya 254, tapi RANKS.Owner.rank = 255.
-- Pastikan angka ini SAMA PERSIS dengan rank Owner di group Roblox kamu.
RankConfig.PASS_BOOST_RANK = 5   -- pemilik pass VIP/VVIP minimal dianggap rank ini

------------------------------------------------------------------------
-- CEK ULANG GRUP (UnifiedRankManager)
-- *_AT = detik sejak percobaan pertama; sesudah daftar habis → tiap *_EVERY.
-- GROUP_RETRY    : API grup ERROR saat join (rank/keanggotaan belum diketahui)
--                  → dicoba lagi; dulu admin bisa kehilangan akses sepanjang sesi.
-- MEMBER_RECHECK : bukan member → dicek lewat GroupService:GetGroupsAsync
--                  (tidak di-cache) supaya join komunitas di tengah sesi langsung
--                  jadi VIP. IsInGroup di server di-cache sejak panggilan pertama.
------------------------------------------------------------------------

RankConfig.GROUP_RETRY_AT       = { 5, 15, 30, 60 }
RankConfig.GROUP_RETRY_EVERY    = 60
RankConfig.MEMBER_RECHECK_AT    = { 15, 45, 120, 300, 600 }
RankConfig.MEMBER_RECHECK_EVERY = 600

------------------------------------------------------------------------
-- RANKS
-- isVVIP = true → dapat akses DoorVIP + DoorVVIP
-- isVIP  = true → dapat akses DoorVIP saja
-- isRGB  = true → RoleLabel di OverheadTag animasi pelangi
------------------------------------------------------------------------

RankConfig.RANKS = {

	-- ── MANAGEMENT ──────────────────────────────────────────────────

	Owner = {
		rank = 255, displayText = "STAFF", teamName = "STAFF",
		color = Color3.fromRGB(255, 108, 3),
		isRGB = true,
		isOwner = true, isAdmin = true, isDeveloper = true,
		isVVIP = true, isVIP = true,  -- VVIP tier: tembus semua door
		queueLimit = 999,
	},
	CoOwner = {
		rank = 253, displayText = "CO-OWNER", teamName = "CO-OWNER",
		color = Color3.fromRGB(255, 0, 255),
		isRGB = true,
		isAdmin = true, isDeveloper = true,
		isVVIP = true, isVIP = true,
		queueLimit = 999,
	},
	Developer = {
		rank = 251, displayText = "DEVELOPER", teamName = "DEVELOPER",
		color = Color3.fromRGB(0, 255, 150),
		isRGB = true,
		isAdmin = true, isDeveloper = true,
		isVVIP = true, isVIP = true,
		queueLimit = 999,
	},
	Admin = {
		rank = 250, displayText = "STAFF", teamName = "STAFF",
		color = Color3.fromRGB(0, 100, 255),
		isAdmin = true,
		isVVIP = true, isVIP = true,
		queueLimit = 999,
	},

	-- ── PREMIUM DONOR ────────────────────────────────────────────────

	CrazyRich = {
		rank = 241, displayText = "CRAZY RICH", teamName = "CRAZY RICH",
		color = Color3.fromRGB(255, 0, 0),
		isPremium = true,
		isVVIP = true, isVIP = true,  -- rank 241 > VVIP_MIN_RANK(10) → VVIP tier
		queueLimit = 3,
	},
	Donatur = {
		rank = 240, displayText = "DONATUR", teamName = "DONATUR",
		color = Color3.fromRGB(255, 132, 101),
		isPremium = true,
		isVVIP = true, isVIP = true,  -- rank 240 > VVIP_MIN_RANK(10) → VVIP tier
		queueLimit = 3,
	},

	-- ── SPECIAL ROLES (rank > VVIP_MIN_RANK → semua VVIP tier) ──────

	STREAMER = {
		rank = 16, displayText = "STREAMER", teamName = "STREAMER",
		color = Color3.fromRGB(145, 70, 255),
		isVVIP = true, isVIP = true,
		queueLimit = 2,
	},
	QUEENANOMALI = {
		rank = 15, displayText = "QUEENANOMALI", teamName = "QUEEN ANOMALI",
		color = Color3.fromRGB(186, 255, 175),
		isVVIP = true, isVIP = true,
		queueLimit = 2,
	},
	KAMERAMEN = {
		rank = 14, displayText = "KAMERAMEN", teamName = "KAMERAMEN",
		color = Color3.fromRGB(255, 180, 0),
		isVVIP = true, isVIP = true,
		queueLimit = 2,
	},
	DJGANTENG = {
		rank = 13, displayText = "DJ GANTENG", teamName = "DJ GANTENG",
		color = Color3.fromRGB(0, 220, 255),
		isVVIP = true, isVIP = true,
		queueLimit = 2,
	},
	LeadDance = {
		rank = 12, displayText = "LEAD DANCE", teamName = "LEAD DANCE",
		color = Color3.fromRGB(255, 85, 127),
		isVVIP = true, isVIP = true,
		queueLimit = 2,
	},
	PrinceTampan = {
		rank = 11, displayText = "PRINCE TAMPAN", teamName = "PRINCE TAMPAN",
		color = Color3.fromRGB(150, 255, 100),
		isVVIP = true, isVIP = true,
		queueLimit = 2,
	},

	-- ── MEMBER TIERS ─────────────────────────────────────────────────

	VVIP = {
		rank = 10, displayText = "VVIP", teamName = "VVIP",
		color = Color3.fromRGB(255, 50, 255),
		isRGB = true,
		isVVIP = true, isVIP = true,  -- tier tertinggi untuk member biasa
		queueLimit = 2,
	},
	VIP = {
		rank = 1, displayText = "VIP", teamName = "VIP",
		color = Color3.fromRGB(255, 215, 0),
		isVIP = true,                 -- legacy: kalau masih ada yg di-assign manual rank 1
		queueLimit = 1,
	},
	Guest = {
		rank = 0, displayText = "GUEST", teamName = "GUEST",
		color = Color3.fromRGB(130, 130, 130),
		queueLimit = 1,               -- HANYA untuk yang BUKAN member community sama sekali
	},
}

------------------------------------------------------------------------
-- PRE-BUILT TIER SETS
-- Dipakai CollisionManager agar tidak hardcode nama role.
-- Otomatis sync dengan RANKS di atas — tidak perlu update manual.
--
-- Format: { ["RoleName"] = true }
-- CollisionManager: if RankConfig.VVIP_ROLE_NAMES[role] then → "VVIP"
------------------------------------------------------------------------

RankConfig.VVIP_ROLE_NAMES = {}  -- semua role dengan isVVIP = true
RankConfig.VIP_ROLE_NAMES  = {}  -- role dengan isVIP = true tapi BUKAN isVVIP

for roleName, data in pairs(RankConfig.RANKS) do
	if data.isVVIP then
		RankConfig.VVIP_ROLE_NAMES[roleName] = true
	elseif data.isVIP then
		RankConfig.VIP_ROLE_NAMES[roleName] = true
	end
end

------------------------------------------------------------------------
-- SORTED CACHE (desc by rank) — internal helper
------------------------------------------------------------------------

local _sortedRanks = nil

local function getSorted()
	if _sortedRanks then return _sortedRanks end
	_sortedRanks = {}
	for name, data in pairs(RankConfig.RANKS) do
		table.insert(_sortedRanks, { name = name, data = data })
	end
	table.sort(_sortedRanks, function(a, b) return a.data.rank > b.data.rank end)
	return _sortedRanks
end

------------------------------------------------------------------------
-- LOOKUP FUNCTIONS
------------------------------------------------------------------------

-- Cari roleData berdasarkan rank number (exact match)
-- ⚠️ JANGAN pakai ini sendirian untuk assign Role attribute — tidak tahu
-- soal gamepass/group membership. Role dipasang UnifiedRankManager.
function RankConfig.GetRoleByRank(rank)
	for _, entry in ipairs(getSorted()) do
		if entry.data.rank == rank then
			return entry.name, entry.data
		end
	end
	return "Guest", RankConfig.RANKS.Guest
end

-- Cari roleName berdasarkan rank + gamepass + status member community
-- isGroupMember: hasil dari player:IsInGroup(RankConfig.GROUP_ID)
function RankConfig.GetRoleName(rank, hasVIPGamepass, hasVVIPGamepass, isGroupMember)
	for _, entry in ipairs(getSorted()) do
		if rank == entry.data.rank then
			-- FIX: kalau ketemu "Guest" (rank 0) TAPI dia member community,
			-- jangan langsung return Guest — lanjut ke fallback VIP di bawah.
			if entry.name == "Guest" and isGroupMember then
				break
			end
			return entry.name
		end
	end
	if hasVVIPGamepass then return "VVIP" end
	if hasVIPGamepass  then return "VIP"  end
	if isGroupMember   then return "VIP"  end -- FIX: join community = langsung VIP
	return "Guest"
end

-- WAJIB kirim isGroupMember supaya member community dapat queueLimit VIP,
-- bukan queueLimit Guest, walaupun rank mereka 0/rankless.
function RankConfig.GetQueueLimit(rank, hasVIPGamepass, hasVVIPGamepass, isGroupMember)
	if rank >= RankConfig.ADMIN_MIN_RANK then return 999 end
	if hasVVIPGamepass then return RankConfig.RANKS.VVIP.queueLimit end
	if hasVIPGamepass  then return RankConfig.RANKS.VIP.queueLimit  end
	local _, data = RankConfig.GetRoleByRank(rank)
	if data.isVVIP or data.isVIP then return data.queueLimit end
	if isGroupMember then return RankConfig.RANKS.VIP.queueLimit end -- FIX: member = limit VIP
	return data.queueLimit or 1
end

return RankConfig