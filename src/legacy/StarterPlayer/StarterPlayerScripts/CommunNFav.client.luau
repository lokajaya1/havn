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
-- GROUP PROMPT → lalu FAVORITE PROMPT (berurutan)
-- Dulu dua task terpisah dengan jeda tetap: kalau pemain belum menjawab ajakan komunitas, ajakan favorit
-- muncul menumpuk di atasnya. Sekarang favorit menunggu ajakan komunitas ditutup (PromptJoinAsync menunggu).
-- =====================================================
local function promptGroup()
	-- Early check: skip idle jika udah join
	if player:IsInGroup(GROUP_ID) then
		return false
	end

	waitUntilIdle(GROUP_IDLE_TIME)
	task.wait(GROUP_DELAY_AFTER_IDLE)

	-- Final check sebelum prompt
	if player:IsInGroup(GROUP_ID) then
		return false
	end

	pcall(function()
		GroupService:PromptJoinAsync(GROUP_ID)
	end)
	return true
end

local function promptFavorite()
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
end

task.spawn(function()
	waitForCharacter()
	local started = os.clock()
	local shown = promptGroup()
	if shown then
		task.wait(FAVORITE_DELAY_AFTER_GROUP) -- sesudah ajakan komunitas ditutup
	else
		-- tanpa ajakan komunitas: jadwal lama (favorit ±7 dtk sesudah karakter ada)
		local due = GROUP_IDLE_TIME + GROUP_DELAY_AFTER_IDLE + FAVORITE_DELAY_AFTER_GROUP
		task.wait(math.max(0, due - (os.clock() - started)))
	end
	promptFavorite()
end)
