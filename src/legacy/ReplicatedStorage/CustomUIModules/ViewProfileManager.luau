-- ViewProfileManager - Production Version
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local ViewProfileManager = {}

local function isValid(player)
	return player and player:IsA("Player") and player.UserId > 0
end

local function notify(title, text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Profile",
			Text = text or "",
			Duration = duration or 4
		})
	end)
end

function ViewProfileManager:ViewProfile(targetPlayer)
	if not isValid(targetPlayer) then
		notify("⚠️ Invalid Player", "Profile not available for studio test players", 4)
		return false
	end

	local localPlayer = Players.LocalPlayer
	if targetPlayer.UserId == localPlayer.UserId then
		notify("Cannot View Own Profile", "You can't view your own profile", 3)
		return false
	end

	-- Try InspectPlayerFromUserId
	local success = pcall(function()
		GuiService:InspectPlayerFromUserId(targetPlayer.UserId)
	end)

	if success then
		return true
	end

	-- Fallback to InspectPlayerFromUserIdWithCtx
	local success2 = pcall(function()
		GuiService:InspectPlayerFromUserIdWithCtx(targetPlayer.UserId, "Profile")
	end)

	if success2 then
		return true
	end

	-- All methods failed
	notify("Profile Error ❌", "Could not open profile\nTry using the leaderboard (Tab key)", 4)
	return false
end

function ViewProfileManager:Init()
	return true
end

return ViewProfileManager