-- ═══════════════════════════════════════════════════════════
-- UNIFIED RANK MANAGER — Script
-- Location: ServerScriptService > UnifiedRankManager
-- ═══════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local Marketplace  = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local SSS          = game:GetService("ServerScriptService")
local RankConfig   = require(SSS:WaitForChild("RankConfig"))
local RankRules    = require(SSS:WaitForChild("RankRules"))
local ShopConfig   = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig"))

local attributesReadyEvent      = Instance.new("BindableEvent")
attributesReadyEvent.Name       = "PlayerAttributesReady"
attributesReadyEvent.Parent     = SSS

local cache     = {} -- gamepass per pemain (dibersihkan tiap forceRefresh)
local ShopReady = false

-- Info grup per pemain: { rank, isMember, ok }. TIDAK dibersihkan forceRefresh:
-- IsInGroup/GetRankInGroup di server di-cache Roblox sejak panggilan pertama,
-- jadi bertanya ulang memberi jawaban yang sama. Yang diulang hanya yang
-- GAGAL (ok = false) dan cek keanggotaan lewat GetGroupsAsync (lihat bawah).
local groupInfo = {}
local retrying  = {} -- [player] = true selama loop coba-ulang jalan
local rechecking = {} -- [player] = true selama loop cek-member jalan
local setAttributes -- diisi di bawah (dipakai loop cek ulang)

-- ─────────────────────────────────────────────────────────
local function clearCache(player) cache[player.UserId] = nil end
local function forgetPlayer(player)
	cache[player.UserId]     = nil
	groupInfo[player.UserId] = nil
	retrying[player]         = nil
	rechecking[player]       = nil
end
local function ensureCache(uid)  if not cache[uid] then cache[uid] = {} end end

local function hasGamepass(player, passId)
	if not passId then return false end  -- FIX: passId nil langsung return false
	local key = "gp_"..passId
	ensureCache(player.UserId)
	local c = cache[player.UserId]
	if c[key] ~= nil then return c[key] end

	local result = false
	-- Coba ShopServer (gift tracking) kalau sudah ready
	if ShopReady and _G.ShopServer then
		local name = passId == RankConfig.VIP_GAMEPASS_ID  and "VIP Access"
			or passId == RankConfig.VVIP_GAMEPASS_ID and "VVIP Access" or nil
		if name then
			local ok, owns = pcall(_G.ShopServer.HasGamepass, player.UserId, name, true)
			if ok and owns then result = true end
		end
	end
	-- Fallback Roblox API (pass baru ATAU pass HAVN lama)
	if not result then
		result = ShopConfig.userOwnsPass(player.UserId, ShopConfig.getGamepassById(passId))
	end
	c[key] = result
	return result
end

-- ─────────────────────────────────────────────────────────
-- INFO GRUP: rank DAN isGroupMember (member rankless ≠ bukan member).
-- IsInGroup / GetRankInGroup error → cadangan GroupService:GetGroupsAsync.
-- Masih gagal → ok = false: dipakai dulu seperti dulu (rank 0 / member
-- sesuai IsInGroup), lalu dicoba ulang di latar (scheduleRetry). Dulu hasil
-- error dianggap final → admin kehilangan akses sepanjang sesi.
-- ─────────────────────────────────────────────────────────
local function fetchGroupInfo(player)
	local okMember, isMember = pcall(player.IsInGroup, player, RankConfig.GROUP_ID)
	if okMember and not isMember then
		return { rank = 0, isMember = false, ok = true }
	end
	if okMember then
		local okRank, rank = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
		if okRank and type(rank) == "number" then
			return { rank = rank, isMember = true, ok = true }
		end
	end

	local okGroups, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if okGroups and type(groups) == "table" then
		local member, rank, hasRank = RankRules.fromGroups(groups, RankConfig.GROUP_ID)
		return { rank = rank, isMember = member, ok = hasRank }
	end

	return { rank = 0, isMember = okMember and isMember == true, ok = false }
end

local function getGroupInfo(player, refresh)
	local info = groupInfo[player.UserId]
	if not info or (refresh and not info.ok) then
		info = fetchGroupInfo(player)
		groupInfo[player.UserId] = info
	end
	return info
end

-- API grup gagal → coba lagi (RankConfig.GROUP_RETRY_AT, lalu tiap
-- GROUP_RETRY_EVERY) sampai berhasil; atribut dipasang ulang saat pulih.
local function scheduleRetry(player)
	if retrying[player] then return end
	retrying[player] = true
	task.spawn(function()
		local attempt = 0
		while player.Parent and retrying[player] do
			attempt += 1
			task.wait(RankRules.waitBefore(RankConfig.GROUP_RETRY_AT, RankConfig.GROUP_RETRY_EVERY, attempt))
			if not (player.Parent and retrying[player]) then break end
			local info = fetchGroupInfo(player)
			if info.ok then
				groupInfo[player.UserId] = info
				retrying[player] = nil
				setAttributes(player, false)
				return
			end
		end
		retrying[player] = nil
	end)
end

-- Join komunitas di tengah sesi (prompt CommunNFav / InfoTopBar / Donasi):
-- IsInGroup di server tidak pernah melihatnya (di-cache sejak panggilan
-- pertama; PromptJoinAsync hanya membersihkan cache di client). Bukan-member
-- dicek lewat GetGroupsAsync (tidak di-cache) pada RankConfig.MEMBER_RECHECK_AT,
-- lalu tiap MEMBER_RECHECK_EVERY. Ketemu → VIP tanpa rejoin.
local function scheduleMemberRecheck(player)
	if rechecking[player] then return end
	rechecking[player] = true
	task.spawn(function()
		local attempt = 0
		while player.Parent and rechecking[player] do
			attempt += 1
			task.wait(RankRules.waitBefore(RankConfig.MEMBER_RECHECK_AT, RankConfig.MEMBER_RECHECK_EVERY, attempt))
			if not (player.Parent and rechecking[player]) then break end
			local current = groupInfo[player.UserId]
			if current and current.isMember then break end
			local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
			if ok and type(groups) == "table" then
				local member, rank = RankRules.fromGroups(groups, RankConfig.GROUP_ID)
				if member then
					groupInfo[player.UserId] = { rank = rank, isMember = true, ok = true }
					rechecking[player] = nil
					setAttributes(player, false)
					print("[RankManager] " .. player.Name .. " bergabung ke komunitas → atribut diperbarui")
					return
				end
			end
		end
		rechecking[player] = nil
	end)
end

local function ensureBool(player, name, value)
	local bv = player:FindFirstChild(name)
	if not bv then bv = Instance.new("BoolValue"); bv.Name = name; bv.Parent = player end
	bv.Value = value
end

-- ─────────────────────────────────────────────────────────
-- CORE — set semua attribute lalu fire event
-- ─────────────────────────────────────────────────────────
-- Rumus atribut: RankRules.compute (murni, dites semua kombinasi).
setAttributes = function(player, forceRefresh)
	if not player or not player.Parent then return end
	if forceRefresh then clearCache(player) end

	local group   = getGroupInfo(player, forceRefresh)
	local hasVIP  = hasGamepass(player, RankConfig.VIP_GAMEPASS_ID)
	local hasVVIP = hasGamepass(player, RankConfig.VVIP_GAMEPASS_ID)
	if not player.Parent then return end -- keluar selama API di atas menunggu

	local attrs = RankRules.compute(RankConfig, {
		groupRank     = group.rank,
		isGroupMember = group.isMember,
		hasVIP        = hasVIP,
		hasVVIP       = hasVVIP,
	})
	for _, name in ipairs(RankRules.ATTRIBUTES) do
		player:SetAttribute(name, attrs[name])
	end

	ensureBool(player, "Owner", attrs.IsOwner)
	ensureBool(player, "Admin", attrs.IsAdmin)
	ensureBool(player, "VIP",   attrs.IsVIP)

	attributesReadyEvent:Fire(player)

	print(string.format(
		"[RankManager] %s | GroupRank:%d Member:%s Effective:%d Role:%s VIP:%s VVIP:%s Admin:%s%s",
		player.Name, group.rank, tostring(group.isMember), attrs.EffectiveRank, attrs.Role,
		tostring(hasVIP), tostring(hasVVIP), tostring(attrs.IsAdmin),
		group.ok and "" or " (API grup gagal — dicoba lagi)"
		))

	if not group.ok then
		scheduleRetry(player)
	elseif not group.isMember then
		scheduleMemberRecheck(player)
	end
end

-- ─────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	task.spawn(setAttributes, player, true)
end)

Players.PlayerRemoving:Connect(forgetPlayer)

-- ─────────────────────────────────────────────────────────
-- SHOPSERVER POLLING
-- ─────────────────────────────────────────────────────────
task.spawn(function()
	local deadline = tick() + 30
	repeat task.wait(0.2) until (_G.ShopServer and _G.ShopServer.HasGamepass) or tick() > deadline

	if _G.ShopServer and _G.ShopServer.HasGamepass then
		ShopReady = true
		print("[RankManager] ShopServer connected — re-check gamepass")
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(setAttributes, p, true)
		end
	else
		warn("[RankManager] ShopServer timeout — hanya pakai Roblox API")
	end
end)

-- Gamepass purchase real-time
Marketplace.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	if passId == RankConfig.VIP_GAMEPASS_ID or passId == RankConfig.VVIP_GAMEPASS_ID then
		task.delay(1, function()
			if player and player.Parent then setAttributes(player, true) end
		end)
	end
end)

-- Gift integration
task.spawn(function()
	local folder = SSS:WaitForChild("ShopServerEvents", 15)
	if not folder then warn("[RankManager] ShopServerEvents tidak ditemukan"); return end
	local event = folder:WaitForChild("OnOwnershipChanged", 10)
	if not event then warn("[RankManager] OnOwnershipChanged tidak ditemukan"); return end
	event.Event:Connect(function(player, passName, owned)
		if not owned or not player or not player.Parent then return end
		if passName ~= "VIP Access" and passName ~= "VVIP Access" then return end
		task.delay(0.5, function()
			if player and player.Parent then
				setAttributes(player, true)
				print("[RankManager] Gift →", player.Name, passName)
			end
		end)
	end)
	print("[RankManager] Gift listener aktif")
end)

-- Join komunitas di tengah sesi: lihat scheduleMemberRecheck (dulu loop
-- IsInGroup tiap 30 dtk — tidak pernah melihat member baru karena hasil
-- IsInGroup di server di-cache sejak panggilan pertama).

-- Init player yang sudah ada
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(setAttributes, p, true)
end

print("[RankManager] Ready")