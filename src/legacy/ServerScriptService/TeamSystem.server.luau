-- ═══════════════════════════════════════════════════════════
-- TEAM SYSTEM — Script
-- Location: ServerScriptService > TeamSystem
--
-- Perubahan penting:
-- • leaderstats sekarang dibuat dari satu tabel LEADERSTATS (urutan = urutan
--   kolom di leaderboard default). "Likes" ditaruh PALING ATAS karena
--   leaderboard default menyortir pemain berdasarkan stat pertama.
-- • Semua stat adalah MIRROR dari Player Attribute. Script lain
--   (LikeSystem, dsb) cuma perlu SetAttribute — tidak boleh menyentuh
--   leaderstats langsung, supaya tidak ada dua pemilik untuk satu nilai.
-- ═══════════════════════════════════════════════════════════
local Players    = game:GetService("Players")
local Teams      = game:GetService("Teams")
local SSS        = game:GetService("ServerScriptService")
local RankConfig = require(SSS:WaitForChild("RankConfig"))

local attributesReadyEvent = SSS:WaitForChild("PlayerAttributesReady", 30)

-- ── Definisi kolom leaderboard ──────────────────────────────
-- URUTAN PENTING:
--   1. Stat pertama = kunci sortir leaderboard default (harus angka).
--   2. Kolom paling kanan yang duluan kepotong di layar sempit / mobile.
local LEADERSTATS = {
	{ name = "Likes", class = "IntValue",    attribute = "Likes",    default = 0 },
	{ name = "Team",  class = "StringValue", attribute = "TeamName", default = "GUEST" },
}

-- ── Cache warna team dari RankConfig ────────────────────────
local teamColorCache = {}
for _, data in pairs(RankConfig.RANKS) do
	if data.teamName and not teamColorCache[data.teamName] then
		teamColorCache[data.teamName] = data.color
	end
end

-- ─────────────────────────────────────────────────────────────
local function countInTeam(teamName)
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("TeamName") == teamName then n += 1 end
	end
	return n
end

local function getOrCreateTeam(teamName)
	local existing = Teams:FindFirstChild(teamName)
	if existing then return existing end
	local color = teamColorCache[teamName]
	local team  = Instance.new("Team")
	team.Name           = teamName
	team.AutoAssignable = false
	team.TeamColor      = color and BrickColor.new(color) or BrickColor.new("Medium stone grey")
	team.Parent         = Teams
	print("[TeamSystem] Team dibuat:", teamName)
	return team
end

local function removeIfEmpty(teamName)
	if not teamName or countInTeam(teamName) > 0 then return end
	local team = Teams:FindFirstChild(teamName)
	if team then team:Destroy(); print("[TeamSystem] Team dihapus:", teamName) end
end

local function assignTeam(player)
	if not player or not player.Parent then return end
	local teamName = player:GetAttribute("TeamName")
	if not teamName or teamName == "" then return end

	local team = getOrCreateTeam(teamName)
	if player.Team == team then return end

	local oldName = player.Team and player.Team.Name or nil
	player.Team   = team
	print("[TeamSystem]", player.Name, "→", teamName)

	-- Stat "Team" di leaderstats tidak di-set di sini lagi.
	-- Mirror attribute (di bawah) yang mengurusnya, jadi hanya ada satu jalur.

	if oldName and oldName ~= teamName then
		task.delay(0.1, function() removeIfEmpty(oldName) end)
	end
end

-- ── leaderstats: mirror satu arah dari Attribute ────────────
local function coerce(value, spec)
	if spec.class == "StringValue" then
		if value == nil or value == "" then return spec.default end
		return tostring(value)
	end
	local n = tonumber(value)
	if not n then return spec.default end
	-- IntValue tidak menerima pecahan / angka negatif untuk kasus ini
	return math.max(0, math.floor(n))
end

local function buildLeaderstats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
	end

	for _, spec in ipairs(LEADERSTATS) do
		local stat = ls:FindFirstChild(spec.name)
		if not stat then
			stat = Instance.new(spec.class)
			stat.Name = spec.name
			stat.Value = coerce(player:GetAttribute(spec.attribute), spec)
			stat.Parent = ls
		else
			stat.Value = coerce(player:GetAttribute(spec.attribute), spec)
		end

		player:GetAttributeChangedSignal(spec.attribute):Connect(function()
			if stat.Parent then
				stat.Value = coerce(player:GetAttribute(spec.attribute), spec)
			end
		end)
	end

	-- Parent DULUAN setelah semua stat terisi, supaya leaderboard tidak
	-- sempat merender kolom setengah jadi.
	ls.Parent = player
	return ls
end

-- ── Setup per player — satu fungsi, dipanggil di dua tempat ─
local function onPlayerAdded(player)
	-- leaderstats dibuat DULU supaya TimePlayedClass bisa
	-- WaitForChild("leaderstats") dan inject stat "Time"
	buildLeaderstats(player)

	player:GetAttributeChangedSignal("TeamName"):Connect(function()
		assignTeam(player)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- EVENTS
-- ─────────────────────────────────────────────────────────────
if attributesReadyEvent then
	attributesReadyEvent.Event:Connect(assignTeam)
else
	warn("[TeamSystem] PlayerAttributesReady tidak ditemukan — assign team hanya lewat attribute changed.")
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local teamName = player:GetAttribute("TeamName")
	task.delay(0.5, function() removeIfEmpty(teamName) end)
end)

-- Init player yang sudah ada (Studio / late join)
-- Pakai fungsi yang SAMA — tidak ada duplikasi
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[TeamSystem] Ready")