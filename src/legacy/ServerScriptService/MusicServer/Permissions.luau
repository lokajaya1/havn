-- MusicServer/Permissions  (ModuleScript)  dipindah dari init.server
-- Siapa boleh apa: admin, premium, DJ siaran live, batas antrian per pemain.

local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Shared = require(RS:WaitForChild("MusicShared"))
local Live   = require(script.Parent:WaitForChild("Live"))

local RankConfig = (function()
	local mod = SSS:FindFirstChild("RankConfig")
	if not mod then return nil end
	local ok, m = pcall(require, mod)
	return (ok and type(m) == "table") and m or nil
end)()

local function isAdmin(p)   return p ~= nil and p:GetAttribute("IsAdmin")   == true end
local function isPremium(p) return p ~= nil and p:GetAttribute("IsPremium") == true end

-- DJ = admin ATAU peran di Shared.liveDjRoles. Saat server ini siaran
-- live, hanya DJ yang boleh request lagu dan skip.
local function isDJ(p)
	if isAdmin(p) then return true end
	local role = p and p:GetAttribute("Role")
	for _, r in ipairs(Shared.liveDjRoles or {}) do
		if role == r then return true end
	end
	return false
end
-- Saat live (server ini stasiun ATAU ikut siaran server lain) hanya DJ yang boleh request.
local function liveBlocks(p) return (Live.isActive() or Live.isFollowing()) and not isDJ(p) end
-- Saat live: skip hanya oleh DJ yang menyalakan siaran (admin lain juga dikunci).
local function skipBlocked(p) return Live.isFollowing() or (Live.isActive() and p.UserId ~= Live.djId()) end

local function queueLimit(p)
	if isAdmin(p) then return 999 end
	-- Nilai dari UnifiedRankManager: rank + gamepass VIP/VVIP (baru/lama) + member community.
	-- Atribut GroupRank/HasVIPGamepass di bawah tidak pernah di-set (terbukti Studio
	-- 2026-09-28), jadi dulu semua non-admin dapat batas Guest.
	local attr = p:GetAttribute("QueueLimit")
	if type(attr) == "number" and attr == attr and attr >= 1 then
		return math.floor(attr)
	end
	if RankConfig and RankConfig.GetQueueLimit then
		return RankConfig.GetQueueLimit(
			p:GetAttribute("GroupRank") or 0,
			p:GetAttribute("HasVIPGamepass")  == true,
			p:GetAttribute("HasVVIPGamepass") == true
		)
	end
	if isPremium(p) then return 3 end
	if p:GetAttribute("IsVVIP") == true or p:GetAttribute("HasVVIPGamepass") == true then return 2 end
	return 1
end

return {
	isAdmin     = isAdmin,
	isPremium   = isPremium,
	isDJ        = isDJ,
	liveBlocks  = liveBlocks,
	skipBlocked = skipBlocked,
	queueLimit  = queueLimit,
}
