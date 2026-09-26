local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local function getOrCreateEvent(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = ReplicatedStorage
	end
	return ev
end
local GlobalPlayEvent = getOrCreateEvent("GlobalPlayEvent")
local GlobalVoteEvent = getOrCreateEvent("GlobalVoteEvent")
local QueueUpdateEvent = getOrCreateEvent("QueueUpdateEvent")
local VolumeUpdateEvent = getOrCreateEvent("VolumeUpdateEvent")
local CurrentSongUpdateEvent = getOrCreateEvent("CurrentSongUpdateEvent")
local ListMusicFolder = ReplicatedStorage:WaitForChild("ListMusic")
local queueList = {}
local currentSong = nil
local currentOwner = nil
local currentVolume = 0.5
local currentStartTime = 0
local voteData = nil
local currentTimePosition = 0
local songChanging = false
local isProcessingEnd = false
local function broadcastQueue()
	QueueUpdateEvent:FireAllClients(queueList)
end
local function broadcastPlay(action, data)
	print("[Server → Clients]", action, data and data.Name or "")
	GlobalPlayEvent:FireAllClients(action, data)
end
local function broadcastVote(action, data)
	GlobalVoteEvent:FireAllClients(action, data)
end
local function resetVotes()
	voteData = {
		action = nil,
		yes = 0,
		voters = {},
		total = 10
	}
end
local function startNextSong()
	if songChanging then
		print("[Server] ⚠️ Gagal startNextSong: masih transition")
		return
	end
	if #queueList == 0 then
		print("[Server] Queue kosong → Stop")
		currentSong, currentOwner = nil, nil
		broadcastPlay("Stop")
		return
	end

	songChanging = true
	local nextSong = queueList[1]
	if not nextSong then
		songChanging = false
		return
	end

	currentSong = nextSong.Name
	currentOwner = nextSong.Owner
	currentStartTime = tick()
	currentTimePosition = 0

	print("[Server] ▶️ Now playing:", currentSong, "by", currentOwner)
	broadcastPlay("Play", {
		Name = currentSong,
		Owner = currentOwner,
		TimePosition = 0
	})
	task.delay(0.5, function()
		isProcessingEnd = false
		songChanging = false
	end)
end
QueueUpdateEvent.OnServerEvent:Connect(function(player, action, songName)
	local sound = ListMusicFolder:FindFirstChild(songName)
	if not sound then return end

	if action == "Add" then
		for _, item in ipairs(queueList) do
			if item.Name == songName then return end
		end
		table.insert(queueList, {
			Name = songName,
			Owner = player.DisplayName,
			OwnerId = player.UserId
		})
		print("[Server] ➕ Ditambah ke queue:", songName)

	elseif action == "Remove" then
		for i, item in ipairs(queueList) do
			if item.Name == songName then
				if item.OwnerId == player.UserId then
					table.remove(queueList, i)
					print("[Server] ❌ Dihapus oleh:", player.DisplayName)
				else
					warn("[Server] ⚠️", player.DisplayName, "coba hapus lagu milik orang lain:", item.Owner)
				end
				break
			end
		end
	end

	broadcastQueue()
end)
GlobalPlayEvent.OnServerEvent:Connect(function(player, action, data)
	if action == "RequestPlay" then
		if not currentSong then
			startNextSong()
		end
	elseif action == "Stop" then
		print("[Server] ⏹ Stop oleh:", player.DisplayName)
		if #queueList > 0 then
			table.remove(queueList, 1)
			broadcastQueue()
		end
		currentSong, currentOwner = nil, nil
		broadcastPlay("Stop")
		print("[Server] 🔇 Lagu dihentikan & dihapus dari queue.")

	elseif action == "Ended" then
		if isProcessingEnd then
			print("[Server] ⚠️ Abaikan duplikat Ended event")
			return
		end
		isProcessingEnd = true
		print("[Server] ⏹ Lagu selesai:", currentSong)

		if #queueList > 0 and queueList[1].Name == currentSong then
			table.remove(queueList, 1)
			broadcastQueue()
		else
			print("[Server] ⚠️ Lagu yang selesai bukan currentSong, abaikan remove.")
		end
		task.delay(0.5, function()
			if #queueList > 0 then
				print("[Server] ▶️ Auto memutar lagu berikutnya...")
				startNextSong()
			else
				print("[Server] ✅ Queue kosong setelah Ended → Stop.")
				currentSong, currentOwner = nil, nil
				broadcastPlay("Stop")
			end
		end)
	elseif action == "RequestVote" then
		resetVotes()
		voteData.action = data
		print("[Server] 🗳️ Voting dimulai oleh", player.DisplayName, "untuk", data)
		GlobalPlayEvent:FireAllClients("ShowVoteNotification", player.DisplayName .. " ingin " .. data)
		broadcastVote("ShowAgreement", data)
	end
end)
GlobalVoteEvent.OnServerEvent:Connect(function(player, response)
	if not voteData or not voteData.action then return end
	if voteData.voters[player.UserId] then return end
	voteData.voters[player.UserId] = true
	if response == "Yes" then
		voteData.yes += 1
	end
	local yesVotes = voteData.yes
	local total = voteData.total
	broadcastVote("VoteUpdate", {Yes = yesVotes, Total = total})
	local targetVotes = 10
	if yesVotes >= targetVotes then
		if voteData.action == "Stop" then
			print("[Server] 🛑 Vote STOP berhasil")
			if #queueList > 0 then
				table.remove(queueList, 1)
				broadcastQueue()
			end
			currentSong, currentOwner = nil, nil
			broadcastPlay("Stop")
			print("[Server] 🔇 Lagu dihentikan & dihapus dari queue melalui vote.")
		elseif voteData.action == "Next" then
			print("[Server] ⏭️ Vote NEXT berhasil")
			if #queueList > 0 then
				table.remove(queueList, 1)
				broadcastQueue()
			end
			if #queueList > 0 then
				startNextSong()
			else
				print("[Server] ✅ Tidak ada lagu berikutnya, berhenti.")
				currentSong, currentOwner = nil, nil
				broadcastPlay("Stop")
			end
		end
		broadcastVote("HideAgreement")
	end
end)
VolumeUpdateEvent.OnServerEvent:Connect(function(player, volume)
	currentVolume = math.clamp(volume, 0, 1)
	VolumeUpdateEvent:FireAllClients(currentVolume)
end)
Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	QueueUpdateEvent:FireClient(player, queueList)
	if currentSong then
		local resumeData = {
			Name = currentSong,
			Owner = currentOwner,
			TimePosition = tick() - currentStartTime
		}
		GlobalPlayEvent:FireClient(player, "Play", resumeData)
	end
end)