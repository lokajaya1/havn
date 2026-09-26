-- ═══════════════════════════════════════════════════════════
-- HideAvatarManager - Proper Roblox Character Hiding
-- Production-Ready Version
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")

local HideAvatarManager = {}

local hiddenPlayers = {}

local function sendNotification(title, message, duration)
	if _G.NotificationManager and _G.NotificationManager.Show then
		_G.NotificationManager.Show(title, message, duration)
	end
end

-- ════════════════════════════════════════════════════════════
-- CHARACTER VISIBILITY
-- ════════════════════════════════════════════════════════════

local function setDescendantVisibility(character, visible)
	if not character then return false end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Part") then
			descendant.Transparency = visible and 0 or 1
			descendant.CanCollide = visible
			descendant.CastShadow = visible

		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = visible and 0 or 1

		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant.Enabled = visible

		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = visible

		elseif descendant:IsA("Accessory") then
			local handle = descendant:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.Transparency = visible and 0 or 1
				handle.CanCollide = visible
			end
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("Decal") and child.Name:lower():find("face") then
				child.Transparency = visible and 0 or 1
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if visible then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			humanoid.NameDisplayDistance = 100
			humanoid.HealthDisplayDistance = 100
		else
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.NameDisplayDistance = 0
			humanoid.HealthDisplayDistance = 0
		end
	end

	return true
end

local function storeOriginalState(character)
	local data = {
		parts = {},
		decals = {},
		guis = {},
		effects = {}
	}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			data.parts[descendant] = descendant.Transparency
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			data.decals[descendant] = descendant.Transparency
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			data.guis[descendant] = descendant.Enabled
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			data.effects[descendant] = descendant.Enabled
		end
	end

	return data
end

local function restoreOriginalState(character, originalData)
	if not character or not originalData then return false end

	for part, transparency in pairs(originalData.parts or {}) do
		if part and part.Parent then
			part.Transparency = transparency
			part.CanCollide = true
			part.CastShadow = true
		end
	end

	for decal, transparency in pairs(originalData.decals or {}) do
		if decal and decal.Parent then
			decal.Transparency = transparency
		end
	end

	for gui, enabled in pairs(originalData.guis or {}) do
		if gui and gui.Parent then
			gui.Enabled = enabled
		end
	end

	for effect, enabled in pairs(originalData.effects or {}) do
		if effect and effect.Parent then
			effect.Enabled = enabled
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("Decal") and child.Name:lower():find("face") then
				child.Transparency = 0
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 100
		humanoid.HealthDisplayDistance = 100
	end

	return true
end

-- ════════════════════════════════════════════════════════════
-- PUBLIC API
-- ════════════════════════════════════════════════════════════

function HideAvatarManager:HideAvatar(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		sendNotification("Error", "Invalid player", 3)
		return false
	end

	local character = targetPlayer.Character
	if not character then
		sendNotification("Error", targetPlayer.Name .. " has no character", 3)
		return false
	end

	if hiddenPlayers[targetPlayer.UserId] then
		return self:ShowAvatar(targetPlayer)
	end

	local originalData = storeOriginalState(character)
	hiddenPlayers[targetPlayer.UserId] = {
		player = targetPlayer,
		character = character,
		data = originalData,
		hiddenAt = tick()
	}

	local success = setDescendantVisibility(character, false)

	if success then
		sendNotification("Avatar Hidden", targetPlayer.Name .. " is now hidden", 3)

		local connection
		connection = targetPlayer.CharacterAdded:Connect(function(newCharacter)
			if hiddenPlayers[targetPlayer.UserId] then
				task.wait(0.5)
				hiddenPlayers[targetPlayer.UserId].character = newCharacter
				hiddenPlayers[targetPlayer.UserId].data = storeOriginalState(newCharacter)
				setDescendantVisibility(newCharacter, false)
			else
				connection:Disconnect()
			end
		end)

		return true
	else
		hiddenPlayers[targetPlayer.UserId] = nil
		sendNotification("Error", "Failed to hide " .. targetPlayer.Name, 3)
		return false
	end
end

function HideAvatarManager:ShowAvatar(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local hiddenData = hiddenPlayers[targetPlayer.UserId]
	if not hiddenData then
		sendNotification("Notice", targetPlayer.Name .. " is already visible", 3)
		return false
	end

	local character = targetPlayer.Character or hiddenData.character
	if not character then
		hiddenPlayers[targetPlayer.UserId] = nil
		return false
	end

	local success = restoreOriginalState(character, hiddenData.data)

	if success then
		hiddenPlayers[targetPlayer.UserId] = nil
		sendNotification("Avatar Shown", targetPlayer.Name .. " is now visible", 3)
		return true
	else
		sendNotification("Error", "Failed to show " .. targetPlayer.Name, 3)
		return false
	end
end

function HideAvatarManager:ToggleAvatar(targetPlayer)
	if hiddenPlayers[targetPlayer.UserId] then
		return self:ShowAvatar(targetPlayer)
	else
		return self:HideAvatar(targetPlayer)
	end
end

function HideAvatarManager:IsAvatarHidden(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end
	return hiddenPlayers[targetPlayer.UserId] ~= nil
end

function HideAvatarManager:ShowAllAvatars()
	local count = 0
	for userId, data in pairs(hiddenPlayers) do
		if data.player and data.player.Parent then
			self:ShowAvatar(data.player)
			count = count + 1
		end
	end
	return count
end

function HideAvatarManager:GetHiddenPlayers()
	local list = {}
	for userId, data in pairs(hiddenPlayers) do
		if data.player and data.player.Parent then
			table.insert(list, data.player)
		end
	end
	return list
end

Players.PlayerRemoving:Connect(function(player)
	if hiddenPlayers[player.UserId] then
		hiddenPlayers[player.UserId] = nil
	end
end)

return HideAvatarManager