-- ═══════════════════════════════════════════════════════════
-- UNIFIED RANK MANAGER — Script
-- Location: ServerScriptService > UnifiedRankManager
-- ═══════════════════════════════════════════════════════════

local Players     = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")
local SSS         = game:GetService("ServerScriptService")
local RankConfig  = require(SSS:WaitForChild("RankConfig"))
local ShopConfig  = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig"))

local attributesReadyEvent      = Instance.new("BindableEvent")
attributesReadyEvent.Name       = "PlayerAttributesReady"
attributesReadyEvent.Parent     = SSS

local cache     = {}
local ShopReady = false

-- ─────────────────────────────────────────────────────────
local function clearCache(player) cache[player.UserId] = nil end
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
-- FIX UTAMA: getGroupRank lama cuma pakai IsInGroup buat keputusan internal
-- lalu MEMBUANG hasilnya — jadi member rankless (rank 0) dan non-member
-- sama-sama menghasilkan groupRank = 0, tidak bisa dibedakan lagi.
--
-- Diganti jadi getGroupInfo() yang cache & return DUA nilai:
-- rank DAN isGroupMember, supaya isGroupMember bisa diteruskan ke
-- RankConfig.GetRoleName / GetQueueLimit seperti yang memang dibutuhkan.
-- ─────────────────────────────────────────────────────────
local function getGroupInfo(player)
	ensureCache(player.UserId)
	local c = cache[player.UserId]
	if c.groupRank ~= nil and c.isGroupMember ~= nil then
		return c.groupRank, c.isGroupMember
	end

	local isMember = false
	local rank = 0

	local okMember, memberResult = pcall(player.IsInGroup, player, RankConfig.GROUP_ID)
	if okMember then isMember = memberResult end

	if isMember then
		local okRank, r = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
		rank = okRank and r or 0
	end

	c.groupRank     = rank
	c.isGroupMember = isMember
	return rank, isMember
end

local function ensureBool(player, name, value)
	local bv = player:FindFirstChild(name)
	if not bv then bv = Instance.new("BoolValue"); bv.Name = name; bv.Parent = player end
	bv.Value = value
end

-- ─────────────────────────────────────────────────────────
-- CORE — set semua attribute lalu fire event
-- ─────────────────────────────────────────────────────────
local function setAttributes(player, forceRefresh)
	if not player or not player.Parent then return end
	if forceRefresh then clearCache(player) end

	local groupRank, isGroupMember = getGroupInfo(player)
	local hasVIP    = hasGamepass(player, RankConfig.VIP_GAMEPASS_ID)
	local hasVVIP   = hasGamepass(player, RankConfig.VVIP_GAMEPASS_ID)

	local effective = groupRank
	-- FIX: member community (rankless) minimal dianggap setara rank VIP_MIN_RANK
	if isGroupMember and effective < RankConfig.VIP_MIN_RANK then
		effective = RankConfig.VIP_MIN_RANK
	end
	-- Gamepass VIP/VVIP tetap boost ke rank 5 seperti sebelumnya
	if (hasVIP or hasVVIP) and effective < 5 then
		effective = 5
	end

	-- FIX: kirim isGroupMember sebagai parameter ke-4 (sebelumnya hilang,
	-- jadi member rankless selalu ke-detect "Guest")
	local roleName  = RankConfig.GetRoleName(effective, hasVIP, hasVVIP, isGroupMember)
	local roleData  = RankConfig.RANKS[roleName] or RankConfig.RANKS.Guest
	local isPremium = roleData.isPremium == true
	-- FIX: isGroupMember juga dimasukkan ke perhitungan isVIP
	local isVIP     = hasVIP or hasVVIP or isGroupMember or (roleData.isVIP == true)
	local isOwner   = effective == RankConfig.OWNER_RANK
	local isAdmin   = effective >= RankConfig.ADMIN_MIN_RANK
	local isDeveloper = effective >= RankConfig.DEV_MIN_RANK
	-- FIX: kirim isGroupMember juga ke GetQueueLimit
	local queueLimit = RankConfig.GetQueueLimit(effective, hasVIP, hasVVIP, isGroupMember)

	player:SetAttribute("RankInGroup",   groupRank)
	player:SetAttribute("IsGroupMember", isGroupMember)
	player:SetAttribute("EffectiveRank", effective)
	player:SetAttribute("Role",          roleName)
	player:SetAttribute("RoleDisplay",   roleData.displayText)
	player:SetAttribute("TeamName",      roleData.teamName)
	player:SetAttribute("RoleColor",     roleData.color)
	player:SetAttribute("IsOwner",       isOwner)
	player:SetAttribute("IsAdmin",       isAdmin)
	player:SetAttribute("IsDeveloper",   isDeveloper)
	player:SetAttribute("IsVIP",         isVIP)
	player:SetAttribute("IsPremium",     isPremium)
	player:SetAttribute("QueueLimit",    queueLimit)

	ensureBool(player, "Owner", isOwner)
	ensureBool(player, "Admin", isAdmin)
	ensureBool(player, "VIP",   isVIP)

	attributesReadyEvent:Fire(player)

	print(string.format(
		"[RankManager] %s | GroupRank:%d Member:%s Effective:%d Role:%s VIP:%s VVIP:%s Admin:%s",
		player.Name, groupRank, tostring(isGroupMember), effective, roleName,
		tostring(hasVIP), tostring(hasVVIP), tostring(isAdmin)
		))
end

-- ─────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	task.spawn(setAttributes, player, true)
end)

Players.PlayerRemoving:Connect(clearCache)

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

-- ─────────────────────────────────────────────────────────
-- GROUP MEMBERSHIP RECHECK (periodic)
-- Roblox tidak punya event native untuk "player join group saat sedang
-- online". Recheck berkala untuk player yang belum terdeteksi member,
-- supaya yang join community di tengah sesi main juga ke-upgrade VIP
-- tanpa perlu rejoin server.
-- ─────────────────────────────────────────────────────────
local GROUP_RECHECK_INTERVAL = 30 -- detik

task.spawn(function()
	while true do
		task.wait(GROUP_RECHECK_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			local c = cache[player.UserId]
			if not c or not c.isGroupMember then
				local ok, isMember = pcall(player.IsInGroup, player, RankConfig.GROUP_ID)
				if ok and isMember then
					setAttributes(player, true)
				end
			end
		end
	end
end)

-- Init player yang sudah ada
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(setAttributes, p, true)
end

print("[RankManager] Ready")