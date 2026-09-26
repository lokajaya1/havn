-- =====================================================
-- FAVORITE PROMPT DATASTORE (PRODUCTION - OPTIMIZED)
-- =====================================================
local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")

local FavoriteStore = DSS:GetDataStore("FavoritePrompted")

-- =====================================================
-- REMOTE EVENT
-- =====================================================
local remote = Instance.new("RemoteEvent")
remote.Name = "MarkFavoritePrompted"
remote.Parent = RS

-- =====================================================
-- LOAD DATA SAAT PLAYER JOIN
-- =====================================================
Players.PlayerAdded:Connect(function(player)
	local key = "fav_" .. player.UserId
	local prompted = false
	
	-- Retry logic untuk DataStore failures
	local attempts = 0
	local maxAttempts = 3
	
	while attempts < maxAttempts do
		local success, result = pcall(function()
			return FavoriteStore:GetAsync(key)
		end)
		
		if success then
			prompted = result == true
			break
		else
			attempts += 1
			if attempts < maxAttempts then
				task.wait(1) -- Wait 1 detik sebelum retry
			end
		end
	end
	
	player:SetAttribute("FavoritePrompted", prompted)
end)

-- =====================================================
-- SAVE DATA (HANYA 1X)
-- =====================================================
remote.OnServerEvent:Connect(function(player)
	-- Guard: cegah double save
	if player:GetAttribute("FavoritePrompted") then
		return
	end
	
	-- Set attribute dulu (instant)
	player:SetAttribute("FavoritePrompted", true)
	
	-- Save ke DataStore (async)
	local key = "fav_" .. player.UserId
	
	task.spawn(function()
		local success = pcall(function()
			FavoriteStore:SetAsync(key, true)
		end)
		
		if not success then
			-- Retry 1x jika gagal
			task.wait(2)
			pcall(function()
				FavoriteStore:SetAsync(key, true)
			end)
		end
	end)
end)