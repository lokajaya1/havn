-- SyncManager
-- ReplicatedStorage > CustomUIModules > SyncManager (ModuleScript, client-side)
-- Dipakai menu interaksi pemain (MenuBinder) untuk minta sync dance.
-- Server: ServerScriptService.Misc.SyncCommand (remote "SyncRemote").

local RS = game:GetService("ReplicatedStorage")

local SyncManager = {}

local SyncRemote = nil

function SyncManager:Initialize()
	SyncRemote = RS:FindFirstChild("SyncRemote") or RS:WaitForChild("SyncRemote", 10)
	if not SyncRemote then
		warn("SyncManager: SyncRemote tidak ditemukan")
	end
end

function SyncManager:StartSync(targetPlayer)
	if not targetPlayer then return end
	if not SyncRemote then
		warn("SyncManager: SyncRemote belum ready")
		return
	end
	SyncRemote:FireServer("start", targetPlayer.Name)
end

function SyncManager:StopSync()
	if not SyncRemote then return end
	SyncRemote:FireServer("stop")
end

SyncManager:Initialize()

return SyncManager
