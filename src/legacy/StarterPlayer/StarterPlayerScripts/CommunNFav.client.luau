-- =====================================================
-- COMMUNITY JOIN & FAVORITE (PRODUCTION - OPTIMIZED)
-- =====================================================
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local GROUP_ID = 277580244
local PLACE_ID = game.PlaceId

-- =====================================================
-- CONFIG DELAY
-- =====================================================
local GROUP_IDLE_TIME = 2
local GROUP_DELAY_AFTER_IDLE = 1
local FAVORITE_IDLE_TIME = 3
local FAVORITE_DELAY_AFTER_GROUP = 4

-- =====================================================
-- UTIL
-- =====================================================
local function waitForCharacter()
	if player.Character then return player.Character end
	return player.CharacterAdded:Wait()
end

local function waitUntilIdle(seconds)
	local char = waitForCharacter()
	local hum = char:WaitForChild("Humanoid")
	local idle = 0
	local last = tick()

	while idle < seconds do
		RunService.Heartbeat:Wait()
		local now = tick()
		local dt = now - last
		last = now
		if hum.MoveDirection.Magnitude > 0 then
			idle = 0
		else
			idle += dt
		end
	end
end

-- =====================================================
-- GROUP PROMPT
-- =====================================================
task.spawn(function()
	waitForCharacter()

	-- Early check: skip idle jika udah join
	if player:IsInGroup(GROUP_ID) then
		return
	end

	waitUntilIdle(GROUP_IDLE_TIME)
	task.wait(GROUP_DELAY_AFTER_IDLE)

	-- Final check sebelum prompt
	if player:IsInGroup(GROUP_ID) then
		return
	end

	pcall(function()
		GroupService:PromptJoinAsync(GROUP_ID)
	end)
end)

-- =====================================================
-- FAVORITE PROMPT (SETELAH GROUP)
-- =====================================================
task.spawn(function()
	waitForCharacter()

	-- Tunggu dulu sampe group kelar
	task.wait(GROUP_IDLE_TIME + GROUP_DELAY_AFTER_IDLE + FAVORITE_DELAY_AFTER_GROUP)

	-- Check attribute dari server
	if player:GetAttribute("FavoritePrompted") then
		return
	end

	waitUntilIdle(FAVORITE_IDLE_TIME)

	local conn
	conn = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function()
		if conn then conn:Disconnect() end

		-- Pastikan remote exists sebelum fire
		local remote = RS:WaitForChild("MarkFavoritePrompted", 5)
		if remote then
			remote:FireServer()
		end
	end)

	pcall(function()
		AvatarEditorService:PromptSetFavorite(
			PLACE_ID,
			Enum.AvatarItemType.Asset,
			true
		)
	end)
end)