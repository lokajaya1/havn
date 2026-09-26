-- Sistem Reset Karakter dan Rejoin Game
-- /normal atau /re → reset tampilan karakter (tanpa respawn, posisi tetap)
-- /rejoin          → rejoin ke game

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

-- ✅ Dictionary lookup: O(1), tidak perlu loop
local RESET_COMMANDS = { ["/normal"] = true, ["/re"] = true }

local function resetCharacter(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Network call → task.spawn agar non-blocking
	task.spawn(function()
		local ok, result = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
		if ok then
			pcall(humanoid.ApplyDescription, humanoid, result)
		else
			warn("[ResetCharacter] Gagal fetch description untuk " .. player.Name .. ": " .. tostring(result))
		end
	end)
end

local function rejoinGame(player)
	task.spawn(function()
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player })
		if not ok then
			warn("[RejoinGame] Gagal rejoin untuk " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		local msg = message:lower()
		if RESET_COMMANDS[msg] then
			resetCharacter(player)
		elseif msg == "/rejoin" then
			rejoinGame(player)
		end
	end)
end)