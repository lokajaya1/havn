-- ═══════════════════════════════════════════════════════════
-- PrivateChatManager — buka whisper (TextChatService bawaan) ke pemain lain
-- Path: ReplicatedStorage.CustomUIModules.PrivateChatManager
--
-- Perintah "/w @username" (username unik; DisplayName bisa kembar → dulu bisa
-- terkirim ke orang yang salah). Menu bawaan Roblox (AvatarContextMenu) memakai
-- cara yang sama. Channel whisper resmi bernama "RBXWhisper:<id1>_<id2>"
-- (SocialRules.isWhisperChannel). Privasi/blokir diurus Roblox: kalau channel
-- tidak muncul, pemain diberi petunjuk netral (bukan "Whisper Failed" palsu).
-- Ruangan SOCIAL: claude/Rencana_Social.md. Angka: Config/Social (WHISPER).
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local RS = game:GetService("ReplicatedStorage")

local WHISPER = require(RS:WaitForChild("Config"):WaitForChild("Social")).WHISPER
local SocialRules = require(RS:WaitForChild("Modules"):WaitForChild("SocialRules"))

local PrivateChatManager = {}

local function notify(title, text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Private Chat",
			Text = text or "",
			Duration = duration or 4,
		})
	end)
end

local function openChatWindow()
	pcall(function()
		StarterGui:SetCore("ChatActive", true)
	end)
end

-- UserId ≤ 0 = pemain uji Studio (whisper hanya jalan di game yang dipublish)
local function isValid(player)
	return player and player:IsA("Player") and player.UserId > 0
end

local function findWhisper(textChannels, a, b)
	for _, ch in ipairs(textChannels:GetChildren()) do
		if ch:IsA("TextChannel") and SocialRules.isWhisperChannel(ch.Name, a, b) then
			return ch
		end
	end
	return nil
end

-- Tunggu channel whisper muncul (ChildAdded) paling lama `timeout` dtk.
local function waitWhisper(textChannels, a, b, timeout)
	local found = findWhisper(textChannels, a, b)
	if found then return found end
	local thread = coroutine.running()
	local done = false
	local conn
	local function finish(ch)
		if done then return end
		done = true
		if conn then conn:Disconnect() end
		task.spawn(thread, ch)
	end
	conn = textChannels.ChildAdded:Connect(function(ch)
		if ch:IsA("TextChannel") and SocialRules.isWhisperChannel(ch.Name, a, b) then
			finish(ch)
		end
	end)
	task.delay(timeout, finish, nil)
	return coroutine.yield()
end

local function hint(targetPlayer)
	notify("Private Chat", "Type /w @" .. targetPlayer.Name .. " in chat to whisper " .. targetPlayer.DisplayName, 6)
	openChatWindow()
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
		local textChannels = TextChatService:FindFirstChild("TextChannels")
		if not textChannels then
			hint(targetPlayer)
			return
		end

		local me, them = localPlayer.UserId, targetPlayer.UserId
		local channel = findWhisper(textChannels, me, them)

		if not channel then
			local general = textChannels:FindFirstChild("RBXGeneral") or textChannels:FindFirstChildWhichIsA("TextChannel")
			if not general then
				hint(targetPlayer)
				return
			end
			pcall(function()
				general:SendAsync("/w @" .. targetPlayer.Name)
			end)
			channel = waitWhisper(textChannels, me, them, WHISPER.WAIT)
		end

		if not channel or not targetPlayer.Parent then
			hint(targetPlayer)
			return
		end

		local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		if inputBar then
			inputBar.TargetTextChannel = channel
		end
		openChatWindow()
		notify("💬 Private Chat", "Now chatting with " .. targetPlayer.DisplayName, 3)
	end)

	return true
end

function PrivateChatManager:Init()
	return TextChatService ~= nil
end

return PrivateChatManager
