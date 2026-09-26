local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvents
local syncRemoteEvent = ReplicatedStorage:WaitForChild("Sync")
local unsyncRemoteEvent = ReplicatedStorage:WaitForChild("Unsync")

-- Bindables
local syncBindable = Instance.new("BindableEvent")
local unsyncBindable = Instance.new("BindableEvent")

-- Fungsi Sync (dengan target)
local function onSync(targetPlayer)
	if targetPlayer and targetPlayer:IsA("Player") then
		syncRemoteEvent:FireServer(targetPlayer)
	end
end

-- Fungsi Unsync
local function onUnsync(targetPlayer)
	-- targetPlayer juga bakal kebaca, tapi kita ga perlu
	unsyncRemoteEvent:FireServer()
end

syncBindable.Event:Connect(onSync)
unsyncBindable.Event:Connect(onUnsync)

-- Fungsi aman SetCore
local function safeSetCore(key, value)
	local success = false
	repeat
		success = pcall(function()
			StarterGui:SetCore(key, value)
		end)
		task.wait()
	until success
end

-- Aktifkan AvatarContextMenu
safeSetCore("AvatarContextMenuEnabled", true)
safeSetCore("RemoveAvatarContextMenuOption", Enum.AvatarContextMenuOption.Emote)

-- Tambahkan menu (hanya muncul kalau klik player)
safeSetCore("AddAvatarContextMenuOption", {"Sync Current Dance", syncBindable})
safeSetCore("AddAvatarContextMenuOption", {"Unsync", unsyncBindable})
