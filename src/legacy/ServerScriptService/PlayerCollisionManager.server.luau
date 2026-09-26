local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")

------------------------------------------------------------------------
-- COLLISION GROUPS
-- Daftarkan semua group di sini. Tambah di list ini jika perlu group baru.
------------------------------------------------------------------------

local COLLISION_GROUPS = {
	"DoorVIP",
	"DoorVVIP",
	"PlayerVVIP",
	"PlayerVIP",
	"PlayerNormal",
	"CarrySystem_Carrier",
	"CarrySystem_Carried",
}

for _, group in ipairs(COLLISION_GROUPS) do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
end

------------------------------------------------------------------------
-- COLLISION RULES
-- Format: { groupA, groupB, collidable }
-- false = tembus/no collision | true = nabrak/blocked
--
-- LOGIKA TIER:
--   DoorVIP  → VVIP & VIP tembus, Normal blocked
--   DoorVVIP → VVIP tembus SAJA, VIP & Normal blocked
------------------------------------------------------------------------

local COLLISION_RULES = {

	-- ── DOOR VIP ──────────────────────────────────────────────────────
	{ "DoorVIP", "PlayerVVIP",   false }, -- VVIP tembus VIP door
	{ "DoorVIP", "PlayerVIP",    false }, -- VIP tembus VIP door
	{ "DoorVIP", "PlayerNormal", true  }, -- Normal blocked

	-- ── DOOR VVIP ─────────────────────────────────────────────────────
	{ "DoorVVIP", "PlayerVVIP",   false }, -- VVIP tembus VVIP door
	{ "DoorVVIP", "PlayerVIP",    true  }, -- VIP BLOCKED
	{ "DoorVVIP", "PlayerNormal", true  }, -- Normal BLOCKED

	-- ── PLAYER ↔ PLAYER (semua tier saling tembus) ────────────────────
	{ "PlayerVVIP",   "PlayerVVIP",   false },
	{ "PlayerVVIP",   "PlayerVIP",    false },
	{ "PlayerVVIP",   "PlayerNormal", false },
	{ "PlayerVIP",    "PlayerVIP",    false },
	{ "PlayerVIP",    "PlayerNormal", false },
	{ "PlayerNormal", "PlayerNormal", false },

	-- ── PLAYER ↔ WORLD ────────────────────────────────────────────────
	{ "PlayerVVIP",   "Default", true },
	{ "PlayerVIP",    "Default", true },
	{ "PlayerNormal", "Default", true },

	-- ── CARRY ↔ DOOR VIP (Carry tembus VIP door) ─────────────────────
	{ "DoorVIP", "CarrySystem_Carrier", false },
	{ "DoorVIP", "CarrySystem_Carried", false },

	-- ── CARRY ↔ DOOR VVIP ────────────────────────────────────────────
	-- TRUE = Carry TIDAK tembus VVIP door.
	{ "DoorVVIP", "CarrySystem_Carrier", true },
	{ "DoorVVIP", "CarrySystem_Carried", true },

	-- ── CARRY ↔ PLAYER (Carry tembus semua player) ───────────────────
	{ "CarrySystem_Carrier", "PlayerVVIP",   false },
	{ "CarrySystem_Carrier", "PlayerVIP",    false },
	{ "CarrySystem_Carrier", "PlayerNormal", false },
	{ "CarrySystem_Carried", "PlayerVVIP",   false },
	{ "CarrySystem_Carried", "PlayerVIP",    false },
	{ "CarrySystem_Carried", "PlayerNormal", false },

	-- ── CARRY ↔ CARRY (sesama carry saling tembus) ───────────────────
	{ "CarrySystem_Carrier", "CarrySystem_Carrier", false },
	{ "CarrySystem_Carried", "CarrySystem_Carried", false },
	{ "CarrySystem_Carrier", "CarrySystem_Carried", false },

	-- ── CARRY ↔ WORLD ─────────────────────────────────────────────────
	{ "CarrySystem_Carrier", "Default", true },
	{ "CarrySystem_Carried", "Default", true },
}

for _, rule in ipairs(COLLISION_RULES) do
	pcall(
		PhysicsService.CollisionGroupSetCollidable,
		PhysicsService, rule[1], rule[2], rule[3]
	)
end

------------------------------------------------------------------------
-- TIER TO COLLISION GROUP MAPPING
------------------------------------------------------------------------

local TIER_TO_GROUP = {
	VVIP   = "PlayerVVIP",
	VIP    = "PlayerVIP",
	Normal = "PlayerNormal",
}

-- Single source of truth: RankConfig. Tidak ada logic tier duplikat di sini.
local RankConfig = require(game:GetService("ServerScriptService"):WaitForChild("RankConfig"))

------------------------------------------------------------------------
-- TIER DETECTION
--
-- FIX UTAMA (root cause bug VIP tidak kedapat waktu join group):
-- Sebelumnya fungsi ini HANYA cek attribute "Role" dan BoolValue VIP/VVIP.
-- Tidak pernah cek player:IsInGroup(RankConfig.GROUP_ID) sama sekali.
--
-- Sesuai catatan di RankConfig.lua: Roblox Communities SEKARANG TIDAK
-- otomatis kasih rank 1 waktu member baru join. Kalau attribute "Role"
-- di-set oleh script lain berdasarkan rank Roblox (bukan berdasarkan
-- keanggotaan), maka member baru akan tetap ke-detect "Normal" walaupun
-- mereka sudah jadi anggota community.
--
-- Fix: tambahkan IsInGroup sebagai fallback terakhir sebelum "Normal",
-- persis seperti fallback yang sudah didokumentasikan di RankConfig
-- (IsVIP / GetRoleName / GetQueueLimit semuanya sudah pakai isGroupMember).
------------------------------------------------------------------------

local function resolvePlayerTier(player)
	local role = player:GetAttribute("Role")

	-- 1) VVIP via role name (rank tinggi / manual assign) — auto-sync dari RankConfig
	if role and RankConfig.VVIP_ROLE_NAMES[role] then return "VVIP" end

	-- 2) VVIP via BoolValue (gamepass holder)
	local vvipObj = player:FindFirstChild("VVIP")
	if vvipObj and vvipObj:IsA("BoolValue") and vvipObj.Value then return "VVIP" end

	-- 3) VIP via role name (rank / manual assign) — auto-sync dari RankConfig
	if role and RankConfig.VIP_ROLE_NAMES[role] then return "VIP" end

	-- 4) VIP via BoolValue (gamepass holder)
	local vipObj = player:FindFirstChild("VIP")
	if vipObj and vipObj:IsA("BoolValue") and vipObj.Value then return "VIP" end

	-- 5) VIP via keanggotaan community — FIX: sebelumnya tidak ada sama sekali.
	--    pcall karena IsInGroup bisa throw kalau ada gangguan koneksi ke Roblox API.
	local ok, isMember = pcall(player.IsInGroup, player, RankConfig.GROUP_ID)
	if ok and isMember then return "VIP" end

	return "Normal"
end

------------------------------------------------------------------------
-- CACHE
-- Simpan group string per player. Di-invalidate saat status berubah.
------------------------------------------------------------------------

local playerGroupCache   = {} -- [player] = "PlayerVIP" / "PlayerVVIP" / "PlayerNormal"
local characterConns     = {} -- [character] = { Connection, ... }
local carrybleConns      = {} -- [character] = Connection

local CARRY_GROUPS = {
	["CarrySystem_Carrier"] = true,
	["CarrySystem_Carried"] = true,
}

local function getCachedGroup(player)
	if playerGroupCache[player] then
		return playerGroupCache[player]
	end
	local group = TIER_TO_GROUP[resolvePlayerTier(player)]
	playerGroupCache[player] = group
	return group
end

local function invalidateCache(player)
	playerGroupCache[player] = nil
end

------------------------------------------------------------------------
-- APPLY COLLISION GROUP
-- force = true  → set SEMUA part (override CarrySystem jika carry aktif)
-- force = false → skip part yang masih di CarrySystem group
------------------------------------------------------------------------

local function applyCollisionGroup(character, group, force)
	-- Putus listener sebelumnya
	local prev = characterConns[character]
	if prev then
		for _, conn in ipairs(prev) do
			if conn.Connected then conn:Disconnect() end
		end
	end
	characterConns[character] = {}

	-- Set semua part yang sudah ada
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			if force or not CARRY_GROUPS[part.CollisionGroup] then
				part.CollisionGroup = group
			end
		end
	end

	-- Watch part yang ditambah belakangan
	local conn = character.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			if force or not CARRY_GROUPS[desc.CollisionGroup] then
				desc.CollisionGroup = group
			end
		end
	end)
	table.insert(characterConns[character], conn)

	character.Destroying:Once(function()
		local conns = characterConns[character]
		if conns then
			for _, c in ipairs(conns) do
				if c.Connected then c:Disconnect() end
			end
			characterConns[character] = nil
		end
	end)
end

local function updatePlayerCollision(player, force)
	local character = player.Character
	if not character then return end
	applyCollisionGroup(character, getCachedGroup(player), force == true)
end

------------------------------------------------------------------------
-- CARRYBLE WATCHER
-- Monitor BoolValue "Carryble". Saat nilainya jadi true (carry selesai),
-- force-restore collision group asli player.
------------------------------------------------------------------------

local function connectCarryble(character, player, carryble)
	carrybleConns[character] = carryble.Changed:Connect(function(val)
		if val ~= true then return end -- true = carry selesai

		task.wait(0.15) -- tunggu CarryWeld cleanup selesai

		if not character.Parent or not player.Parent then return end
		updatePlayerCollision(player, true) -- force restore
	end)
end

local function setupCarrybleWatcher(character, player)
	-- Putus watcher lama
	local old = carrybleConns[character]
	if old then
		old:Disconnect()
		carrybleConns[character] = nil
	end

	local carryble = character:FindFirstChild("Carryble")
	if carryble and carryble:IsA("BoolValue") then
		connectCarryble(character, player, carryble)
	else
		-- Carryble belum ada, tunggu
		local waitConn
		waitConn = character.ChildAdded:Connect(function(child)
			if child.Name ~= "Carryble" or not child:IsA("BoolValue") then return end
			waitConn:Disconnect()
			connectCarryble(character, player, child)
		end)
		character.Destroying:Once(function()
			if waitConn.Connected then waitConn:Disconnect() end
		end)
	end

	character.Destroying:Once(function()
		local conn = carrybleConns[character]
		if conn then conn:Disconnect() end
		carrybleConns[character] = nil
	end)
end

------------------------------------------------------------------------
-- CHARACTER SETUP
------------------------------------------------------------------------

local CHAR_TIMEOUT = 3

local function onCharacterAdded(character, player)
	local startTime = tick()
	local heartbeat

	heartbeat = RunService.Heartbeat:Connect(function()
		if tick() - startTime > CHAR_TIMEOUT then
			heartbeat:Disconnect()
			warn("[CollisionManager] Timeout HRP:", player.Name)
			return
		end
		if not character:FindFirstChild("HumanoidRootPart") then return end

		heartbeat:Disconnect()
		task.wait(0.05)

		updatePlayerCollision(player, false)
		setupCarrybleWatcher(character, player)
	end)
end

------------------------------------------------------------------------
-- PLAYER SETUP
------------------------------------------------------------------------

local function onStatusChanged(player)
	invalidateCache(player)
	updatePlayerCollision(player, true)
end

local function watchStatusObject(player, obj)
	if obj:IsA("BoolValue") and (obj.Name == "VIP" or obj.Name == "VVIP") then
		obj.Changed:Connect(function()
			onStatusChanged(player)
		end)
	end
end

local function setupPlayer(player)
	-- Character events
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(char, player)
	end)
	if player.Character then
		onCharacterAdded(player.Character, player)
	end

	-- Role attribute
	player:GetAttributeChangedSignal("Role"):Connect(function()
		onStatusChanged(player)
	end)

	-- VIP / VVIP BoolValue — existing + future
	for _, child in ipairs(player:GetChildren()) do
		watchStatusObject(player, child)
	end
	player.ChildAdded:Connect(function(child)
		watchStatusObject(player, child)
	end)
end

------------------------------------------------------------------------
-- GROUP MEMBERSHIP RECHECK (periodic)
--
-- KENAPA PERLU: Roblox tidak punya event native untuk "player join group
-- saat sedang online di server yang sama". player:IsInGroup() hanya kita
-- panggil sekali waktu resolvePlayerTier() jalan (pertama kali karakter
-- spawn / status berubah). Kalau player join community DI TENGAH sesi
-- main, dia baru akan ke-detect VIP setelah cache di-invalidate.
--
-- Solusi: recheck berkala untuk player yang statusnya masih "Normal"
-- (hemat resource — tidak perlu recheck yang udah VIP/VVIP).
------------------------------------------------------------------------

local GROUP_RECHECK_INTERVAL = 30 -- detik

task.spawn(function()
	while true do
		task.wait(GROUP_RECHECK_INTERVAL)

		for _, player in ipairs(Players:GetPlayers()) do
			local currentGroup = playerGroupCache[player]

			-- Hanya recheck player yang masih dianggap Normal.
			-- VIP/VVIP dari role/gamepass sudah ter-cover oleh event listener.
			if currentGroup == "PlayerNormal" or currentGroup == nil then
				local ok, isMember = pcall(player.IsInGroup, player, RankConfig.GROUP_ID)
				if ok and isMember then
					onStatusChanged(player)
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	invalidateCache(player)

	local char = player.Character
	if not char then return end

	local conns = characterConns[char]
	if conns then
		for _, c in ipairs(conns) do
			if c.Connected then c:Disconnect() end
		end
		characterConns[char] = nil
	end

	local carry = carrybleConns[char]
	if carry then
		carry:Disconnect()
		carrybleConns[char] = nil
	end
end)

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

print("[CollisionManager] Ready — DoorVIP | DoorVVIP | CarrySystem | 3-tier | Group-aware")