-- Hilangkan semua nama di atas kepala player (Username & DisplayName)
local Players = game:GetService("Players")

local function removeName(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		removeName(character)
	end)
end)

-- Untuk player yang sudah ada di game
for _, player in pairs(Players:GetPlayers()) do
	if player.Character then
		removeName(player.Character)
	end
end