-- SyncManager
-- ReplicatedStorage > Modules > SyncManager (ModuleScript, client-side)
-- Semua notifikasi popup dihapus.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local SyncManager = {}

local player     = Players.LocalPlayer
local SyncRemote = nil

-- ═══════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════
function SyncManager:Initialize()
	SyncRemote = RS:FindFirstChild("SyncRemote") or RS:WaitForChild("SyncRemote", 10)
	if not SyncRemote then
		warn("SyncManager: SyncRemote tidak ditemukan")
	end
end

-- ═══════════════════════════════════════════════════════════
-- START SYNC
-- Langsung FireServer — tanpa popup notifikasi
-- ═══════════════════════════════════════════════════════════
function SyncManager:StartSync(targetPlayer)
	if not targetPlayer then return end
	if not SyncRemote then
		warn("SyncManager: SyncRemote belum ready")
		return
	end
	SyncRemote:FireServer("start", targetPlayer.Name)
end

-- ═══════════════════════════════════════════════════════════
-- STOP SYNC
-- ═══════════════════════════════════════════════════════════
function SyncManager:StopSync()
	if not SyncRemote then return end
	SyncRemote:FireServer("stop")
end

-- ═══════════════════════════════════════════════════════════
-- GET SYNC STATUS
-- ═══════════════════════════════════════════════════════════
function SyncManager:GetSyncStatus()
	if _G.GetSimpleSyncStatus then
		return _G.GetSimpleSyncStatus()
	end
	return { isFollowing = false, target = "None" }
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════
function SyncManager:SyncStatus()
	local s = self:GetSyncStatus()
	print("=== SyncManager Status ===")
	print("  isFollowing:", s.isFollowing)
	print("  target:", s.target)
end

-- ═══════════════════════════════════════════════════════════
-- FORCE STOP
-- StopSync() sudah fire SyncRemote "stop" sekali.
-- Support remote lama + global helpers untuk kompatibilitas.
-- ═══════════════════════════════════════════════════════════
local function forceStopAllMethods()
	pcall(function() SyncManager:StopSync() end)

	local oldFolder = RS:FindFirstChild("Syncing")
	if oldFolder then
		local unsync = oldFolder:FindFirstChild("UnSync")
		if unsync then pcall(function() unsync:FireServer() end) end
	end

	if _G.ForceStopSync then pcall(_G.ForceStopSync) end
	if _G.StopDanceSync  then pcall(_G.StopDanceSync)  end
end

-- ═══════════════════════════════════════════════════════════
-- EXPORTS GLOBAL
-- ═══════════════════════════════════════════════════════════
_G.ForceStopSyncAllMethodsEnhanced = forceStopAllMethods

_G.EnhancedStopSync = function()
	forceStopAllMethods()
	task.spawn(function()
		task.wait(0.3)
		if _G.CheckDanceSyncStatus  then _G.CheckDanceSyncStatus()  end
		if _G.ForceHideDisableDance then _G.ForceHideDisableDance() end
		if _G.isSyncing  ~= nil then _G.isSyncing  = false end
		if _G.syncTarget ~= nil then _G.syncTarget = "None" end
	end)
end

_G.TestEnhancedSync = function(targetPlayerName)
	local t = Players:FindFirstChild(targetPlayerName)
	if not t then print("Player not found:", targetPlayerName); return end
	SyncManager:StartSync(t)
	task.delay(8, function() SyncManager:StopSync() end)
end

-- ═══════════════════════════════════════════════════════════
-- AUTO-INITIALIZE
-- ═══════════════════════════════════════════════════════════
SyncManager:Initialize()

return SyncManager