-- ═══════════════════════════════════════════════════════════
-- ShowAvatarModule - THUMBNAIL EMOTE POSE (like Roblox Profile)
-- Location: ReplicatedStorage > CustomUIModules > ShowAvatarModule
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ShowAvatarModule = {}
local IS_STUDIO = RunService:IsStudio()

local function getThumbnailUrl(userId, thumbType, size)
	thumbType = thumbType or "Avatar"
	size = size or 420
	return string.format("rbxthumb://type=%s&id=%d&w=%d&h=%d", thumbType, userId, size, size)
end

function ShowAvatarModule:ShowCharacter(targetPlayer, imageLabel)
	if not targetPlayer or not imageLabel then return false end

	local userId = targetPlayer.UserId

	if userId < 1 then
		local localPlayer = Players.LocalPlayer
		if localPlayer and localPlayer.UserId > 0 then
			userId = localPlayer.UserId
		else
			imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
			return false
		end
	end

	imageLabel.Image = getThumbnailUrl(userId, "Avatar", 420)
	return true
end

function ShowAvatarModule:ShowBust(targetPlayer, imageLabel)
	if not targetPlayer or not imageLabel then return false end
	local userId = targetPlayer.UserId
	if userId < 1 then
		imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		return false
	end
	imageLabel.Image = getThumbnailUrl(userId, "AvatarBust", 420)
	return true
end

function ShowAvatarModule:ShowHeadshot(targetPlayer, imageLabel)
	if not targetPlayer or not imageLabel then return false end
	local userId = targetPlayer.UserId
	if userId < 1 then
		imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		return false
	end
	imageLabel.Image = getThumbnailUrl(userId, "AvatarHeadShot", 420)
	return true
end

function ShowAvatarModule:RefreshCharacter(targetPlayer, imageLabel)
	return self:ShowCharacter(targetPlayer, imageLabel)
end

function ShowAvatarModule:ClearViewport(imageLabel)
	if imageLabel then imageLabel.Image = "" end
end

function ShowAvatarModule:ClearCache(_) end

return ShowAvatarModule