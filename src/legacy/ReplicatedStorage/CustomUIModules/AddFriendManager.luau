-- ═══════════════════════════════════════════════════════════
-- AddFriendManager — status pertemanan + prompt add friend
-- Path: ReplicatedStorage.CustomUIModules.AddFriendManager
--
-- IsFriendsWith adalah panggilan web yang yield, jadi hasilnya di-cache
-- CACHE_TIME detik. Invalidate dipakai setelah prompt dikirim, supaya UI
-- bisa cek ulang tanpa menunggu cache habis.
-- ═══════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local AddFriendManager = {}

local CACHE_TIME = 30
local cache = {}

local function isValid(player)
	return player and player:IsA("Player") and player.UserId > 0
end

local function notify(title, text, duration, icon)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Friend System",
			Text = text or "",
			Duration = duration or 4,
			Icon = icon
		})
	end)
end

local function getCached(userId)
	local c = cache[userId]
	if c and (tick() - c.time) < CACHE_TIME then
		return c.value
	end
	return nil
end

local function setCache(userId, value)
	cache[userId] = { value = value, time = tick() }
end

function AddFriendManager:IsFriend(targetPlayer)
	if not isValid(targetPlayer) then
		return false
	end
	local cached = getCached(targetPlayer.UserId)
	if cached ~= nil then
		return cached
	end
	local localPlayer = Players.LocalPlayer
	local success, isFriend = pcall(function()
		return localPlayer:IsFriendsWith(targetPlayer.UserId)
	end)
	local result = success and isFriend or false
	setCache(targetPlayer.UserId, result)
	return result
end

function AddFriendManager:GetFriendshipStatus(targetPlayer)
	if not targetPlayer then
		return { isFriend = false, status = "Unknown", canSendRequest = false }
	end
	if not isValid(targetPlayer) then
		return {
			isFriend = false,
			status = "Studio Player",
			canSendRequest = false,
			message = "Friend system only works in published games!"
		}
	end
	local localPlayer = Players.LocalPlayer
	if targetPlayer.UserId == localPlayer.UserId then
		return {
			isFriend = false,
			status = "Self",
			canSendRequest = false,
			message = "You can't add yourself!"
		}
	end
	local isFriend = self:IsFriend(targetPlayer)
	return {
		isFriend = isFriend,
		status = isFriend and "Friends" or "Not Friends",
		canSendRequest = not isFriend,
		message = isFriend and ("You're already friends with " .. targetPlayer.Name) or nil
	}
end

function AddFriendManager:SendFriendRequest(targetPlayer)
	if not isValid(targetPlayer) then
		notify("Studio Test Player", "Friend requests only work in published games!", 5)
		return false
	end
	local localPlayer = Players.LocalPlayer
	if targetPlayer.UserId == localPlayer.UserId then
		notify("Cannot Add Friend", "You can't add yourself!", 3)
		return false
	end
	local status = self:GetFriendshipStatus(targetPlayer)
	if status.isFriend then
		notify("Already Friends", "You're already friends with " .. targetPlayer.Name, 3)
		return false
	end

	local success = pcall(function()
		StarterGui:SetCore("PromptSendFriendRequest", targetPlayer)
	end)
	if success then
		task.delay(3, function()
			cache[targetPlayer.UserId] = nil
		end)
		return true
	end

	local success2 = pcall(function()
		StarterGui:SetCore("OpenPlayerList", true)
	end)
	if success2 then
		notify("Leaderboard Opened",
			"Find " .. targetPlayer.Name .. " in the leaderboard, then click Add Friend", 5)
		return true
	end

	notify("Friend Request Failed",
		"Could not send request. Try the leaderboard (Tab key)", 4)
	return false
end

-- Buang satu entri cache. Terima Player atau userId.
function AddFriendManager:Invalidate(target)
	local userId = target
	if typeof(target) == "Instance" and target:IsA("Player") then
		userId = target.UserId
	end
	if type(userId) == "number" then
		cache[userId] = nil
	end
end

function AddFriendManager:ClearCache()
	cache = {}
end

function AddFriendManager:Init()
	return true
end

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

return AddFriendManager