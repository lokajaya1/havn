-- ═══════════════════════════════════════════════════════════
-- RANK RULES — ModuleScript (murni: tanpa GetService / Instance / yield)
-- Location: ServerScriptService > RankRules
--
-- Rumus atribut rank pemain dari 4 masukan (rank grup, member komunitas,
-- pass VIP, pass VVIP) + bantuan jadwal cek ulang. Dipakai UnifiedRankManager.
-- Hasil compute() identik dengan perhitungan lama di setAttributes
-- (dibuktikan tes: semua kombinasi rank × member × VIP × VVIP).
-- ═══════════════════════════════════════════════════════════

local RankRules = {}

-- Urutan atribut saat dipasang (sama dengan urutan lama).
RankRules.ATTRIBUTES = {
	"RankInGroup", "IsGroupMember", "EffectiveRank", "Role", "RoleDisplay",
	"TeamName", "RoleColor", "IsOwner", "IsAdmin", "IsDeveloper", "IsVIP",
	"IsPremium", "QueueLimit",
}

-- cfg = RankConfig. info = { groupRank, isGroupMember, hasVIP, hasVVIP }.
function RankRules.compute(cfg, info)
	local groupRank, isGroupMember = info.groupRank, info.isGroupMember
	local hasVIP, hasVVIP = info.hasVIP, info.hasVVIP

	local effective = groupRank
	-- Member komunitas (rankless) minimal setara VIP_MIN_RANK.
	if isGroupMember and effective < cfg.VIP_MIN_RANK then
		effective = cfg.VIP_MIN_RANK
	end
	-- Pemilik pass VIP/VVIP minimal PASS_BOOST_RANK.
	if (hasVIP or hasVVIP) and effective < cfg.PASS_BOOST_RANK then
		effective = cfg.PASS_BOOST_RANK
	end

	local roleName = cfg.GetRoleName(effective, hasVIP, hasVVIP, isGroupMember)
	local roleData = cfg.RANKS[roleName] or cfg.RANKS.Guest

	return {
		RankInGroup   = groupRank,
		IsGroupMember = isGroupMember,
		EffectiveRank = effective,
		Role          = roleName,
		RoleDisplay   = roleData.displayText,
		TeamName      = roleData.teamName,
		RoleColor     = roleData.color,
		IsOwner       = effective == cfg.OWNER_RANK,
		IsAdmin       = effective >= cfg.ADMIN_MIN_RANK,
		IsDeveloper   = effective >= cfg.DEV_MIN_RANK,
		IsVIP         = hasVIP or hasVVIP or isGroupMember or (roleData.isVIP == true),
		IsPremium     = roleData.isPremium == true,
		QueueLimit    = cfg.GetQueueLimit(effective, hasVIP, hasVVIP, isGroupMember),
	}
end

-- Hasil GroupService:GetGroupsAsync → (member?, rank, rank tersedia?).
-- Kolom Rank sudah deprecated (multi-role) tapi masih diisi Roblox; kalau
-- suatu saat hilang, rank dianggap belum diketahui (hasRank = false).
function RankRules.fromGroups(groups, groupId)
	if type(groups) ~= "table" then return false, 0, false end
	for _, entry in ipairs(groups) do
		if type(entry) == "table" and entry.Id == groupId then
			local rank = tonumber(entry.Rank)
			return true, rank or 0, rank ~= nil
		end
	end
	return false, 0, true
end

-- Jeda sebelum percobaan ke-n (1, 2, …): `at` = detik sejak percobaan
-- pertama dijadwalkan, lalu tiap `every` detik sesudah daftar habis.
function RankRules.waitBefore(at, every, n)
	if n <= 1 then return at[1] or every end
	if n <= #at then return at[n] - at[n - 1] end
	return every
end

return RankRules
