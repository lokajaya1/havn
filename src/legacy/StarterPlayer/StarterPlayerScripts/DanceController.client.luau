-- DanceController with Fixed Favorites System
-- Place this in: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- Import custom TweenManager
local TweenManager = require(ReplicatedStorage.CustomTween.TweenManager)
local danceTweenManager = TweenManager.new()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for existing GUI from StarterGui
local screenGui = playerGui:WaitForChild("DanceGUI", 10)
if not screenGui then
	warn("DanceGUI not found in PlayerGui! Make sure it exists in StarterGui.")
	return
end

local DanceConfig = require(ReplicatedStorage.Config.DanceConfig)

-- Import SmoothDanceHelper for enhanced transitions
local SmoothDanceHelper = require(ReplicatedStorage.Modules.SmoothDanceHelper)

-- Initialize SyncManager with error handling
local SyncManager = nil
local CustomUIModules = ReplicatedStorage:FindFirstChild("CustomUIModules")
if CustomUIModules then
	local syncManagerModule = CustomUIModules:FindFirstChild("SyncManager")
	if syncManagerModule then
		local success, result = pcall(function()
			return require(syncManagerModule)
		end)
		if success then
			SyncManager = result
			print("SyncManager loaded from CustomUIModules")
		else
			warn("Failed to load SyncManager from CustomUIModules:", result)
		end
	end
else
	-- Fallback to old location
	local syncManagerFound = ReplicatedStorage:WaitForChild("SyncManager", 5)
	if syncManagerFound then
		local success, result = pcall(function()
			return require(syncManagerFound)
		end)
		if success then
			SyncManager = result
			SyncManager:Initialize()
			print("SyncManager loaded from ReplicatedStorage")
		else
			warn("Failed to load SyncManager:", result)
		end
	else
		warn("SyncManager not found - sync features disabled")
	end
end

-- Import the new AnimationCacheManager
local AnimationCacheManager = require(ReplicatedStorage.AnimationCache.AnimationCacheManager)

-- PREVENT DUPLICATE EXECUTION
local SCRIPT_ID = "DanceController_v1"
if _G[SCRIPT_ID] then
	warn("DanceController already running, preventing duplicate...")
	return
end
_G[SCRIPT_ID] = true

-- TopbarPlus Integration
local container = ReplicatedStorage:WaitForChild("TopbarPlus", 10)
if not container then
	warn("TopbarPlus not found in ReplicatedStorage!")
	return
end

local Icon
local success, errorMsg = pcall(function()
	Icon = require(container.Icon)
end)

if not success then
	warn("Failed to require Icon module:", errorMsg)
	return
end

-- Wait for RemoteEvent
local remoteEvent = ReplicatedStorage:WaitForChild("DanceRequest", 10)
if not remoteEvent then
	warn("DanceRequest RemoteEvent not found! Make sure the server script is running.")
	return
end

-- GET GUI ELEMENTS
local sidebar = screenGui:WaitForChild("Sidebar")

-- Ensure sidebar starts hidden and reset to default position
sidebar.Visible = false
sidebar.Position = UDim2.new(0.05, 0, 0.5, 0)

local headerFrame = sidebar:WaitForChild("HeaderFrame")
local titleLabel = headerFrame:WaitForChild("Title")
local tabContainer = headerFrame:WaitForChild("TabContainer")
local dancesTab = tabContainer:WaitForChild("DancesTab")
local favoritTab = tabContainer:WaitForChild("FavoritTab")

local searchFrame = sidebar:WaitForChild("SearchFrame")
local searchIcon = searchFrame:WaitForChild("SearchIcon")
local searchBox = searchFrame:WaitForChild("SearchBox")

local speedFrame = sidebar:WaitForChild("SpeedFrame")
local speedLabel = speedFrame:WaitForChild("SpeedLabel")
local speedDisplay = speedFrame:WaitForChild("SpeedDisplay")
local speedDecreaseBtn = speedFrame:WaitForChild("SpeedDecreaseBtn")
local speedIncreaseBtn = speedFrame:WaitForChild("SpeedIncreaseBtn")
local resetSpeedBtn = speedFrame:WaitForChild("ResetSpeedBtn")

local paginationFrame = sidebar:WaitForChild("PaginationFrame")
local pageInfoLabel = paginationFrame:WaitForChild("PageInfoLabel")
local EmoteTab = paginationFrame:WaitForChild("EmoteTab")

local scrollFrame = sidebar:WaitForChild("ScrollFrame")
local listLayout = scrollFrame:WaitForChild("UIListLayout")

-- Get DisableDance (Stop Sync) button
local disableDance = sidebar:FindFirstChild("DisableDance")
local disableDanceButton = nil

if not disableDance then
	warn("DisableDance frame not found in sidebar!")
	disableDance = sidebar:WaitForChild("DisableDance", 5)
	if not disableDance then
		warn("DisableDance frame still not found after waiting!")
	else
		print("DisableDance frame found after waiting")
	end
end

if disableDance then
	disableDanceButton = disableDance:FindFirstChild("TextButton")
	if not disableDanceButton then
		warn("TextButton not found in DisableDance frame!")
		disableDanceButton = disableDance:WaitForChild("TextButton", 5)
		if not disableDanceButton then
			warn("TextButton still not found in DisableDance frame!")
		else
			print("DisableDance TextButton found after waiting")
		end
	else
		print("DisableDance and TextButton found successfully")
	end
end

-- =============================================
-- COMPLETE VARIABLE DECLARATIONS
-- =============================================

-- Core Variables
local currentTab = "DANCES"
local favorites = {}
local currentDances = DanceConfig.danceName or {}
local currentlyPlaying = nil
local danceButtons = {}
local sidebarVisible = false
local currentPage = 1
local itemsPerPage = 20
local totalPages = 1
local allDances = DanceConfig.danceName or {}
local filteredDances = DanceConfig.danceName or {}
local currentSpeed = 1.0
local speedMultipliers = {0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0}
local currentSpeedIndex = 3

-- Sync Integration Variables
local isSyncing = false
local syncTarget = nil

-- Initialize global variables
_G.SyncRelationships = _G.SyncRelationships or {}
_G.CachedSyncStatus = _G.CachedSyncStatus or {isSyncing = false, target = "None"}

-- =============================================
-- FORWARD DECLARATIONS AND FUNCTION DEFINITIONS
-- =============================================

-- Forward declarations
local updateDanceList
local calculateTotalPages
local updatePageInfo
local getCurrentPageDances
local updateAllFavoriteButtons
local createDanceButton
local checkSyncStatus
local showSyncWarning
local updateAllButtonStates

-- Pagination functions
calculateTotalPages = function()
	totalPages = math.ceil(#filteredDances / itemsPerPage)
	if totalPages < 1 then totalPages = 1 end
end

updatePageInfo = function()
	pageInfoLabel.Text = string.format("Page %d of %d (%d items)", currentPage, totalPages, #filteredDances)

	-- Update button states
	EmoteTab.BackgroundColor3 = currentPage < totalPages and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(30, 30, 35)
	EmoteTab.TextColor3 = currentPage < totalPages and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(100, 100, 100)
end

getCurrentPageDances = function()
	local startIndex = (currentPage - 1) * itemsPerPage + 1
	local endIndex = math.min(startIndex + itemsPerPage - 1, #filteredDances)

	local pageDances = {}
	for i = startIndex, endIndex do
		if filteredDances[i] then
			table.insert(pageDances, filteredDances[i])
		end
	end

	return pageDances
end

-- Safe function to update all favorite button states
updateAllFavoriteButtons = function()
	for _, button in pairs(danceButtons) do
		if button and button.Parent then
			local nameLabel = button:FindFirstChild("NameLabel")
			local favoriteBtn = button:FindFirstChild("FavoriteBtn")
			if nameLabel and favoriteBtn then
				local danceName = nameLabel.Text
				local isFavorite = table.find(favorites, danceName) ~= nil
				favoriteBtn.Text = isFavorite and "⭐" or "☆"

				-- Enhanced visual feedback
				favoriteBtn.TextColor3 = isFavorite and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(200, 200, 200)
			end
		end
	end
end

-- =============================================
-- FAVORITES SYSTEM
-- =============================================

local HttpService = game:GetService("HttpService")

-- Enhanced RemoteEvent handling with fallback
local favoritesRemote = ReplicatedStorage:FindFirstChild("FavoritesRemote")
if not favoritesRemote then
	print("Waiting for FavoritesRemote from server...")
	favoritesRemote = ReplicatedStorage:WaitForChild("FavoritesRemote", 30)

	if not favoritesRemote then
		warn("FavoritesRemote not found - using local storage only")
	else
		print("Found FavoritesRemote from server")
	end
else
	print("FavoritesRemote already exists")
end

-- Enhanced saveFavorites 
local function saveFavorites()
	print("Saving " .. #favorites .. " favorites...")

	-- Method 1: Save to server if available
	if favoritesRemote then
		task.spawn(function()
			local success, err = pcall(function()
				favoritesRemote:FireServer("save", favorites)
			end)

			if success then
				print("Saved to server")
			else
				warn("Failed to save to server: " .. tostring(err))
			end
		end)
	end

	-- Method 2: Always save locally as backup
	task.spawn(function()
		local success, err = pcall(function()
			local jsonData = HttpService:JSONEncode(favorites)
			player:SetAttribute("DanceFavorites_v2", jsonData)
			-- Also keep old format for compatibility
			player:SetAttribute("DanceFavorites_Local", jsonData)
		end)

		if success then
			print("Saved to local storage")
		else
			warn("Failed to save locally: " .. tostring(err))
		end
	end)
end

-- Create dance button function
createDanceButton = function(danceName, index)
	-- Get the DanceButton component template from ReplicatedStorage
	local danceButtonTemplate = ReplicatedStorage.Components.ButtonDance:WaitForChild("DanceButton")

	-- Clone the template
	local button = danceButtonTemplate:Clone()
	button.Name = "DanceButton_" .. index
	button.LayoutOrder = index
	button.Parent = scrollFrame

	-- Update the button text/name
	local nameLabel = button:FindFirstChild("NameLabel")
	if nameLabel then
		nameLabel.Text = danceName
	else
		button.Text = danceName
	end

	-- Update favorite button if it exists
	local favoriteBtn = button:FindFirstChild("FavoriteBtn")
	if favoriteBtn then
		local isFavorite = table.find(favorites, danceName) ~= nil
		favoriteBtn.Text = isFavorite and "⭐" or "☆"
		favoriteBtn.TextColor3 = isFavorite and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(200, 200, 200)

		-- Favorite click event with enhanced handling
		favoriteBtn.MouseButton1Click:Connect(function()
			local favIndex = table.find(favorites, danceName)

			if favIndex then
				-- Remove from favorites
				table.remove(favorites, favIndex)
				favoriteBtn.Text = "☆"
				favoriteBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
				print("Removed " .. danceName .. " from favorites")

				-- Use server method for immediate sync
				if favoritesRemote then
					pcall(function()
						favoritesRemote:FireServer("remove", danceName)
					end)
				end
			else
				-- Add to favorites
				table.insert(favorites, danceName)
				favoriteBtn.Text = "⭐"
				favoriteBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
				print("Added " .. danceName .. " to favorites")

				-- Use server method for immediate sync
				if favoritesRemote then
					pcall(function()
						favoritesRemote:FireServer("add", danceName)
					end)
				end
			end

			-- Save locally as backup
			saveFavorites()

			-- Update list if we're in favorites tab
			if currentTab == "FAVORITES" then
				filteredDances = favorites
				currentPage = 1
				calculateTotalPages()
				updateDanceList()
			end

			-- Add visual feedback
			local originalSize = favoriteBtn.Size
			if danceTweenManager then
				danceTweenManager:Tween(favoriteBtn, TweenInfo.new(0.1), {
					Size = UDim2.new(originalSize.X.Scale * 1.2, originalSize.X.Offset * 1.2, originalSize.Y.Scale * 1.2, originalSize.Y.Offset * 1.2)
				})
				task.wait(0.1)
				danceTweenManager:Tween(favoriteBtn, TweenInfo.new(0.1), {
					Size = originalSize
				})
			end
		end)
	end

	-- Dance click event
	button.MouseButton1Click:Connect(function()
		local syncStatus = checkSyncStatus()
		if syncStatus.isFollowing then
			showSyncWarning()
			return
		end

		-- Add smooth visual transition for button
		local nameLabel = button:FindFirstChild("NameLabel")

		if currentlyPlaying == danceName then
			-- Stopping dance
			currentlyPlaying = nil

			if nameLabel then
				danceTweenManager:Tween(nameLabel, TweenInfo.new(0.4), {
					TextColor3 = Color3.fromRGB(200, 200, 200)
				})
			end

			remoteEvent:FireServer("", currentSpeed)

		else
			-- Starting new dance
			updateAllButtonStates()
			currentlyPlaying = danceName

			if nameLabel then
				nameLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
				danceTweenManager:Tween(nameLabel, TweenInfo.new(0.5), {
					TextColor3 = Color3.fromRGB(100, 200, 255)
				})
			end

			remoteEvent:FireServer(danceName, currentSpeed)
		end

		--print("Client: Smooth transition request - " .. (danceName or "STOP"))
	end)

	-- Store button reference
	danceButtons[index] = button

	return button
end

-- Update dance list function
updateDanceList = function()
	--print("Updating dance list for tab:", currentTab)

	-- Clear existing buttons
	for _, button in pairs(danceButtons) do
		if button and button.Parent then
			button:Destroy()
		end
	end
	danceButtons = {}

	-- Get current page dances
	local pageDances = getCurrentPageDances()
	currentDances = pageDances

	-- Create new buttons
	for i, danceName in ipairs(pageDances) do
		createDanceButton(danceName, i)
	end

	-- Update canvas size
	if scrollFrame then
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #pageDances * 50)
	end

	-- Update pagination info
	updatePageInfo()

	--print("Updated dance list with " .. #pageDances .. " items")
end



-- Enhanced loadFavorites with better error handling
local function loadFavorites()
	print("Loading favorites...")

	-- Method 1: Try server first
	if favoritesRemote then
		print("Requesting favorites from server...")
		local success, err = pcall(function()
			favoritesRemote:FireServer("load")
		end)

		if not success then
			warn("Failed to request from server: " .. tostring(err))
		end

		-- Wait briefly for server response
		task.wait(0.5)
	end

	-- Method 2: Fallback to local storage if server fails or no response
	if #favorites == 0 then
		print("Loading from local storage...")
		local success, result = pcall(function()
			local savedData = player:GetAttribute("DanceFavorites_v2")
			if savedData and savedData ~= "" then
				return HttpService:JSONDecode(savedData)
			end
			return nil
		end)

		if success and result and type(result) == "table" then
			favorites = result
			print("Loaded " .. #favorites .. " favorites from local storage")
		else
			-- Try old format
			local oldSuccess, oldResult = pcall(function()
				local oldData = player:GetAttribute("DanceFavorites_Local")
				if oldData and oldData ~= "" then
					return HttpService:JSONDecode(oldData)
				end
				return nil
			end)

			if oldSuccess and oldResult and type(oldResult) == "table" then
				favorites = oldResult
				print("Migrated " .. #favorites .. " favorites from old format")
				-- Save in new format
				saveFavorites()
			else
				favorites = {}
				print("No existing favorites found")
			end
		end
	end
end



-- Enhanced server response handler
if favoritesRemote then
	favoritesRemote.OnClientEvent:Connect(function(action, data)
		print("Server response:", action, data and #data or "nil")

		if action == "loaded" and data and type(data) == "table" then
			favorites = data
			print("Server loaded " .. #favorites .. " favorites")

			-- Save to local backup
			saveFavorites()

			-- Update UI if needed
			if currentTab == "FAVORITES" then
				filteredDances = favorites
				currentPage = 1
				calculateTotalPages()
				updateDanceList()
			end

			-- Update favorite buttons
			updateAllFavoriteButtons()

		elseif action == "updated" and data and type(data) == "table" then
			favorites = data
			print("Server updated " .. #favorites .. " favorites")

			-- Update UI if needed
			if currentTab == "FAVORITES" then
				filteredDances = favorites
				currentPage = 1
				calculateTotalPages()
				updateDanceList()
			end

			-- Update favorite buttons
			updateAllFavoriteButtons()
		end
	end)
else
	print("No FavoritesRemote - using local storage only")
end

-- =============================================
-- SYNC INTEGRATION
-- =============================================

-- Handle sync status responses from server
local SyncRemote = game.ReplicatedStorage:WaitForChild("SyncRemote")
SyncRemote.OnClientEvent:Connect(function(action, data)
	if action == "syncStatus" then
		_G.CachedSyncStatus = data

		-- Immediately update UI based on received status
		if data.isSyncing and data.target ~= "None" then
			isSyncing = true
			syncTarget = data.target

			if disableDance and disableDanceButton then
				disableDance.Visible = true
				disableDanceButton.Text = "Stop Sync"
				disableDanceButton.BackgroundColor3 = Color3.fromRGB(255, 69, 58)
				disableDanceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		else
			isSyncing = false
			syncTarget = "None"

			-- LEAD DISCONNECT FIX: Handle lead disconnect reason
			if data.reason == "leadLeft" and data.leadName then
				-- Show notification that lead dancer left
				StarterGui:SetCore("SendNotification", {
					Title = "🚪 Lead Dancer Left";
					Text = data.leadName .. " has left the game. Sync stopped.";
					Duration = 4;
				})

				-- Reset currently playing state
				currentlyPlaying = nil

				-- Update all dance buttons to normal state
				updateAllButtonStates()
			end

			if disableDance then
				disableDance.Visible = false
			end
		end

		-- LEAD DISCONNECT FIX: Handle lead disconnect notification
	elseif action == "leadDisconnected" then
		if data and data.leadName and data.message then
			-- Show detailed notification
			StarterGui:SetCore("SendNotification", {
				Title = "🎵 Sync Ended";
				Text = data.message;
				Duration = 5;
			})

			-- Force reset sync state
			isSyncing = false
			syncTarget = "None"
			currentlyPlaying = nil

			-- Update UI state
			if disableDance then
				disableDance.Visible = false
			end

			-- Update all button states
			updateAllButtonStates()

			-- Clear cached sync status
			_G.CachedSyncStatus = {isSyncing = false, target = "None"}
		end
	end
end)

checkSyncStatus = function()
	-- Check server-side sync tracking via SyncRemote
	local SyncRemote = game.ReplicatedStorage:FindFirstChild("SyncRemote")

	if SyncRemote then
		-- Request sync status from server
		SyncRemote:FireServer("getSyncStatus")

		-- Check cached sync status
		if _G.CachedSyncStatus then
			if _G.CachedSyncStatus.isSyncing and _G.CachedSyncStatus.target ~= "None" then
				isSyncing = true
				syncTarget = _G.CachedSyncStatus.target

				-- Immediately update DisableDance frame
				if disableDance and disableDanceButton then
					disableDance.Visible = true
					disableDanceButton.Text = "Stop Sync"
					disableDanceButton.BackgroundColor3 = Color3.fromRGB(255, 69, 58)
					disableDanceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
				end

				return {
					isFollowing = true,
					target = _G.CachedSyncStatus.target,
					hasAnimation = true
				}
			end
		end
	end

	-- No sync detected
	isSyncing = false
	syncTarget = "None"

	-- Clear sync relationships
	if _G.SyncRelationships then
		for key, _ in pairs(_G.SyncRelationships) do
			if string.find(key, player.Name) then
				_G.SyncRelationships[key] = nil
			end
		end
	end

	-- Hide DisableDance frame
	if disableDance then
		disableDance.Visible = false
	end

	return {isFollowing = false, target = "None", hasAnimation = false}
end

-- Function to show sync warning
showSyncWarning = function()
	StarterGui:SetCore("SendNotification", {
		Title = "Sync Active";
		Text = "Stop sync with " .. syncTarget .. " first to control dances";
		Duration = 3;
	})
end

-- Update dance button visual state based on sync status
local function updateDanceButtonState(button, danceName)
	local syncStatus = checkSyncStatus()

	if syncStatus.isFollowing then
		-- Disabled state when syncing
		button.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
		button.AutoButtonColor = false

		-- Update text elements if they exist
		local nameLabel = button:FindFirstChild("NameLabel")
		if nameLabel then
			nameLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
		else
			button.TextColor3 = Color3.fromRGB(100, 100, 100)
		end

		-- Dim any icons if they exist
		local danceIcon = button:FindFirstChild("DanceIcon")
		if danceIcon then
			danceIcon.ImageColor3 = Color3.fromRGB(100, 100, 100)
		end
	else
		-- Normal state when not syncing
		button.AutoButtonColor = true

		if currentlyPlaying == danceName then
			-- Active/playing state
			local nameLabel = button:FindFirstChild("NameLabel")
			if nameLabel then
				nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			else
				button.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		else
			-- Inactive state
			button.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
			local nameLabel = button:FindFirstChild("NameLabel")
			if nameLabel then
				nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			else
				button.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end

		-- Restore icon color if it exists
		local danceIcon = button:FindFirstChild("DanceIcon")
		if danceIcon then
			danceIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
end

-- Function to update all button states
updateAllButtonStates = function()
	for _, button in pairs(danceButtons) do
		if button and button.Parent then
			local nameLabel = button:FindFirstChild("NameLabel")
			local danceName = nameLabel and nameLabel.Text or ""
			updateDanceButtonState(button, danceName)
		end
	end
end

-- =============================================
-- SPEED CONTROL FUNCTIONS
-- =============================================

local function updateSpeedDisplay()
	currentSpeed = speedMultipliers[currentSpeedIndex]
	speedDisplay.Text = string.format("%.1fx", currentSpeed)
end

local function changeSpeed(direction)
	-- Check sync status before allowing speed change
	local syncStatus = checkSyncStatus()
	if syncStatus.isFollowing then
		showSyncWarning()
		return
	end

	if direction == "increase" and currentSpeedIndex < #speedMultipliers then
		currentSpeedIndex = currentSpeedIndex + 1
	elseif direction == "decrease" and currentSpeedIndex > 1 then
		currentSpeedIndex = currentSpeedIndex - 1
	end

	updateSpeedDisplay()

	-- Update button states
	speedDecreaseBtn.BackgroundColor3 = currentSpeedIndex > 1 and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(40, 40, 45)
	speedIncreaseBtn.BackgroundColor3 = currentSpeedIndex < #speedMultipliers and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(40, 40, 45)

	-- Always use server method for speed changes
	if currentlyPlaying then
		remoteEvent:FireServer(currentlyPlaying, currentSpeed)
	end
end

local function resetSpeed()
	-- Check sync status before allowing speed reset
	local syncStatus = checkSyncStatus()
	if syncStatus.isFollowing then
		showSyncWarning()
		return
	end

	currentSpeedIndex = 3 -- Reset to 1.0x
	updateSpeedDisplay()

	-- Update button states
	speedDecreaseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	speedIncreaseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)

	-- Always use server method for speed reset
	if currentlyPlaying then
		remoteEvent:FireServer(currentlyPlaying, currentSpeed)
	end
end

local function changePage(direction)
	if direction == "next" and currentPage < totalPages then
		currentPage = currentPage + 1
	elseif direction == "prev" and currentPage > 1 then
		currentPage = currentPage - 1
	end

	updatePageInfo()
	updateDanceList()
end

-- =============================================
-- SEARCH FUNCTION
-- =============================================

local function searchDances(query)
	local sourceList = currentTab == "DANCES" and DanceConfig.danceName or favorites
	if query == "" then
		filteredDances = sourceList
	else
		filteredDances = {}
		for _, dance in ipairs(sourceList) do
			if string.lower(dance):find(string.lower(query)) then
				table.insert(filteredDances, dance)
			end
		end
	end

	-- Reset to page 1 when searching
	currentPage = 1
	calculateTotalPages()
	updateDanceList()
end

-- =============================================
-- UI EVENT HANDLERS
-- =============================================

-- Search event
searchBox.Changed:Connect(function(property)
	if property == "Text" then
		searchDances(searchBox.Text)
	end
end)

-- Tab switching with modern animation
dancesTab.MouseButton1Click:Connect(function()
	if currentTab ~= "DANCES" then
		currentTab = "DANCES"

		-- Animate tab switch
		danceTweenManager:Tween(dancesTab, TweenInfo.new(0.3), {
			BackgroundColor3 = Color3.fromRGB(100, 120, 255)
		})
		danceTweenManager:Tween(favoritTab, TweenInfo.new(0.3), {
			BackgroundColor3 = Color3.fromRGB(40, 40, 45)
		})

		dancesTab.TextColor3 = Color3.fromRGB(255, 255, 255)
		favoritTab.TextColor3 = Color3.fromRGB(150, 150, 155)

		filteredDances = DanceConfig.danceName
		currentPage = 1
		calculateTotalPages()
		searchBox.Text = ""
		updateDanceList()
	end
end)

favoritTab.MouseButton1Click:Connect(function()
	if currentTab ~= "FAVORITES" then
		currentTab = "FAVORITES"

		-- Animate tab switch
		danceTweenManager:Tween(favoritTab, TweenInfo.new(0.3), {
			BackgroundColor3 = Color3.fromRGB(100, 120, 255)
		})
		danceTweenManager:Tween(dancesTab, TweenInfo.new(0.3), {
			BackgroundColor3 = Color3.fromRGB(40, 40, 45)
		})

		favoritTab.TextColor3 = Color3.fromRGB(255, 255, 255)
		dancesTab.TextColor3 = Color3.fromRGB(150, 150, 155)

		filteredDances = favorites
		currentPage = 1
		calculateTotalPages()
		searchBox.Text = ""
		updateDanceList()
	end
end)

-- Modern sidebar toggle
local function toggleSidebar()
	sidebarVisible = not sidebarVisible

	if sidebarVisible then
		-- Show the sidebar
		sidebar.Visible = true

		local showTween = danceTweenManager:Tween(sidebar, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.05, 0, 0.5, 0)
		})
	else
		local hideTween = danceTweenManager:Tween(sidebar, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(-1, 0, 0.5, 0)
		})

		-- Hide the sidebar after animation completes
		hideTween.Completed:Connect(function()
			sidebar.Visible = false
		end)
	end
end

-- Export global functions
_G.ToggleDanceGUI = function()
	toggleSidebar()
end

_G.IsDanceGUIOpen = function()
	return sidebarVisible and sidebar.Visible
end

_G.CloseDanceGUI = function()
	if sidebarVisible then
		toggleSidebar()
	end
end

_G.OpenDanceGUI = function()
	if not sidebarVisible then
		toggleSidebar()
	end
end

-- Speed Button Event Handlers
speedDecreaseBtn.MouseButton1Click:Connect(function()
	changeSpeed("decrease")

	-- Visual feedback
	danceTweenManager:Tween(speedDecreaseBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	})
	task.wait(0.1)
	danceTweenManager:Tween(speedDecreaseBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = currentSpeedIndex > 1 and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(40, 40, 45)
	})
end)

speedIncreaseBtn.MouseButton1Click:Connect(function()
	changeSpeed("increase")

	-- Visual feedback
	danceTweenManager:Tween(speedIncreaseBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	})
	task.wait(0.1)
	danceTweenManager:Tween(speedIncreaseBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = currentSpeedIndex < #speedMultipliers and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(40, 40, 45)
	})
end)

resetSpeedBtn.MouseButton1Click:Connect(function()
	resetSpeed()

	-- Visual feedback
	danceTweenManager:Tween(resetSpeedBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(100, 100, 110)
	})
	task.wait(0.1)
	danceTweenManager:Tween(resetSpeedBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	})
end)

-- Pagination Event Handlers
EmoteTab.MouseButton1Click:Connect(function()
	changePage("Emote")
end)

-- Setup Stop Sync button functionality
if disableDanceButton then
	disableDanceButton.MouseButton1Click:Connect(function()
		local syncStatus = checkSyncStatus()
		if syncStatus.isFollowing then

			if SyncManager and SyncManager.StopSync then
				SyncManager:StopSync()
				print("SYNC STOPPED: SyncManager.StopSync")
			end

			-- Use existing stop sync function
			if _G.StopDanceSync then
				_G.StopDanceSync()
			end

			local SyncRemote = ReplicatedStorage:FindFirstChild("SyncRemote")
			if SyncRemote then
				SyncRemote:FireServer("stop")
				print("SYNC STOPPED: SyncRemote")
			end

			-- Reset currently playing state
			currentlyPlaying = nil

			-- Reset all dance buttons to normal state
			for _, button in pairs(danceButtons) do
				if button and button.Parent then
					local nameLabel = button:FindFirstChild("NameLabel")
					local danceName = nameLabel and nameLabel.Text or ""
					updateDanceButtonState(button, danceName)
				end
			end

			-- Show notification
			StarterGui:SetCore("SendNotification", {
				Title = "Sync Stopped";
				Text = "Dance sync has been stopped";
				Duration = 2;
			})
		else
			StarterGui:SetCore("SendNotification", {
				Title = "Not Syncing";
				Text = "You are not currently syncing with anyone";
				Duration = 2;
			})
		end
	end)
else
	warn("DisableDanceButton not found - Stop Sync functionality disabled")
end

-- =============================================
-- PERIODIC SYNC STATUS CHECK
-- =============================================

task.spawn(function()
	while true do
		task.wait(0.5)

		-- Check sync status
		local syncStatus = checkSyncStatus()
		local currentIsSync = syncStatus.isFollowing or false
		local currentTarget = syncStatus.target or "None"

		-- Update if status changed
		if currentIsSync ~= isSyncing or currentTarget ~= syncTarget then
			isSyncing = currentIsSync
			syncTarget = currentTarget

			-- Update speed controls state
			local speedControlsEnabled = not currentIsSync
			speedDecreaseBtn.Visible = speedControlsEnabled
			speedIncreaseBtn.Visible = speedControlsEnabled
			resetSpeedBtn.Visible = speedControlsEnabled

			if not speedControlsEnabled then
				speedDisplay.Text = "SYNC"
				speedDisplay.TextColor3 = Color3.fromRGB(255, 159, 10)
				speedLabel.Text = "Status:"
			else
				speedDisplay.Text = string.format("%.1fx", currentSpeed)
				speedDisplay.TextColor3 = Color3.fromRGB(100, 120, 255)
				speedLabel.Text = "Speed:"
			end

			-- Update DisableDance button
			if disableDance and disableDanceButton then
				if currentIsSync then
					disableDance.Visible = true
				else
					disableDance.Visible = false
				end
			end

			-- Update all dance buttons state
			for _, button in pairs(danceButtons) do
				if button and button.Parent then
					local nameLabel = button:FindFirstChild("NameLabel")
					local danceName = nameLabel and nameLabel.Text or ""
					updateDanceButtonState(button, danceName)
				end
			end
		end
	end
end)

-- =============================================
-- INITIALIZATION AND STARTUP
-- =============================================

-- Load favorites with enhanced timing
task.spawn(function()
	-- Wait for character and UI to be ready
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	task.wait(3) -- Give more time for everything to load

	print("Starting favorites load sequence...")
	loadFavorites()

	-- Additional retry mechanism
	task.wait(2)
	if #favorites == 0 and favoritesRemote then
		print("Retrying favorites load...")
		pcall(function()
			favoritesRemote:FireServer("load")
		end)
		task.wait(1)
	end

	print("Favorites initialization complete: " .. #favorites .. " items")

	-- Update UI after loading
	updateAllFavoriteButtons()

	if currentTab == "FAVORITES" then
		filteredDances = favorites
		calculateTotalPages()
		updateDanceList()
	end
end)

-- Start preloading when player spawns
local function onCharacterAdded(character)
	task.wait(2)
	task.spawn(function()
		AnimationCacheManager:startCaching(player)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Initialize
filteredDances = DanceConfig.danceName
currentPage = 1
calculateTotalPages()
updateSpeedDisplay()
updateDanceList()

-- =============================================
-- DEBUG FUNCTIONS
-- =============================================

_G.DebugFavorites = function()
	print("=== FAVORITES DEBUG ===")
	print("Favorites count:", #favorites)
	print("FavoritesRemote exists:", favoritesRemote ~= nil)
	print("Current tab:", currentTab)

	for i, fav in ipairs(favorites) do
		print(i .. ". " .. fav)
	end

	-- Test local storage
	local success, data = pcall(function()
		return player:GetAttribute("DanceFavorites_v2")
	end)

	if success and data then
		print("Local storage length:", string.len(data))
	else
		print("No local storage found")
	end
end

_G.TestFavoriteLoad = function()
	print("Testing favorite load...")
	loadFavorites()
end

_G.ClearFavorites = function()
	favorites = {}
	saveFavorites()
	updateAllFavoriteButtons()
	print("Cleared all favorites")
end

_G.CheckSidebarPosition = function()
	print("Current sidebar position:", sidebar.Position)
	print("Current sidebar visible:", sidebar.Visible)
end

_G.ResetSidebarPosition = function()
	sidebar.Position = UDim2.new(0.05, 0, 0.5, 0)
	print("Sidebar position reset to default")
end

print("DanceController with Fixed Favorites System loaded successfully!")