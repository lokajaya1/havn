require(game:GetService("ReplicatedStorage").RagdollService)

local players = game:GetService("Players")

players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(chr)
		local hum = chr:WaitForChild("Humanoid") :: Humanoid

		hum:AddTag("Ragdollable")
		hum:AddTag("RagdollOnHumanoidFall")
		hum:AddTag("RagdollOnHumanoidDied")

	end)
end)

