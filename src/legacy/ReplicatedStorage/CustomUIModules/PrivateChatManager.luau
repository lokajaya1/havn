-- PrivateChatManager - Production Version
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local PrivateChatManager = {}

-- Helper: Send notification
local function notify(title, text, duration, icon)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Private Chat",
			Text = text or "",
			Duration = duration or 4,
			Icon = icon
		})
	end)
end

-- Helper: Check if player is valid
local function isValid(player)
	return player and player:IsA("Player") and player.UserId > 0
end

function PrivateChatManager:OpenPrivateChat(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		notify("Error", "Invalid player", 3)
		return false
	end

	local localPlayer = Players.LocalPlayer

	if targetPlayer == localPlayer then
		notify("Cannot Whisper", "You can't whisper yourself!", 3)
		return false
	end

	if not isValid(targetPlayer) then
		notify("⚠️ Studio Limitation", "Private chat only works in published games!", 5)
		return false
	end

	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		notify("Error", "Chat system unavailable", 3)
		return false
	end

	task.spawn(function()
		local success, errorMsg = pcall(function()
			local textChannels = TextChatService:FindFirstChild("TextChannels")
			if not textChannels then
				error("TextChannels not found")
			end

			-- Check if whisper channel already exists
			local whisperChannelName = "RBXWhisper:" .. tostring(targetPlayer.UserId)
			local whisperChannel = textChannels:FindFirstChild(whisperChannelName)

			if whisperChannel then
				local chatInputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
				if chatInputBar then
					chatInputBar.TargetTextChannel = whisperChannel
					task.wait(0.1)
					pcall(function()
						StarterGui:SetCore("ChatActive", true)
					end)
					notify("💬 Private Chat", "Now chatting with " .. targetPlayer.DisplayName, 3)
				end
				return
			end

			-- Create new whisper channel
			local generalChannel = textChannels:FindFirstChild("RBXGeneral")
			if not generalChannel then
				error("RBXGeneral channel not found")
			end

			local whisperCommand = "/w " .. targetPlayer.DisplayName
			pcall(function()
				generalChannel:SendAsync(whisperCommand)
			end)

			-- Wait for channel creation
			local maxAttempts = 50
			for i = 1, maxAttempts do
				task.wait(0.1)
				whisperChannel = textChannels:FindFirstChild(whisperChannelName)
				if whisperChannel then
					break
				end
			end

			if not whisperChannel then
				error("Channel creation timed out")
			end

			local chatInputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
			if not chatInputBar then
				error("ChatInputBar not found")
			end

			chatInputBar.TargetTextChannel = whisperChannel
			task.wait(0.2)
			pcall(function()
				StarterGui:SetCore("ChatActive", true)
			end)
			notify("💬 Private Chat", "Now chatting with " .. targetPlayer.DisplayName, 3)
		end)

		if not success then
			if string.find(errorMsg:lower(), "privacy") or string.find(errorMsg:lower(), "blocking") then
				notify("Whisper Blocked", targetPlayer.DisplayName .. " has privacy settings blocking whispers", 6)
			elseif string.find(errorMsg:lower(), "timeout") then
				notify("Whisper Failed", "Could not connect. Try typing: /w " .. targetPlayer.DisplayName, 8)
			else
				notify("Whisper Failed", "Could not start chat. Try: /w " .. targetPlayer.DisplayName, 6)
			end

			pcall(function()
				StarterGui:SetCore("ChatActive", true)
			end)
		end
	end)

	return true
end

function PrivateChatManager:Init()
	return TextChatService ~= nil
end

return PrivateChatManager