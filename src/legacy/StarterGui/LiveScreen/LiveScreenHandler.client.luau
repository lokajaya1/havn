local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Warna: ReplicatedStorage.Modules.ThemeColor (themeColor) — T.X dibaca saat melukis → ikut tema pilihan pemain.
local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local T = ThemeColor.tokens

local player = Players.LocalPlayer
local gui = script.Parent
gui.Name = "LiveScreenGui"
ThemeColor.mark(gui)

-- ═══════════════════════════════════════════════════════════
-- ADMIN CHECK (reads Attribute from UnifiedRankManager)
-- ★ REMOVED: WHITELIST_USERIDS table
-- ★ NOW: Uses GetAttribute("IsAdmin") — auto-replicated from server
-- ═══════════════════════════════════════════════════════════
local MODE_COOLDOWN = 0.5

local function isAdmin()
	return player:GetAttribute("IsAdmin") or false
end

-- Wait for attribute to be set by UnifiedRankManager (server sets it with delay)
local function waitForAdminAttribute(timeout)
	if player:GetAttribute("IsAdmin") ~= nil then return true end
	local elapsed = 0
	while elapsed < (timeout or 10) do
		task.wait(0.2)
		elapsed += 0.2
		if player:GetAttribute("IsAdmin") ~= nil then return true end
	end
	return player:GetAttribute("IsAdmin") ~= nil
end

-- ==========================================
-- VALIDATION
-- ==========================================
local liveSystem = ReplicatedStorage:WaitForChild("LiveSystem", 10)
if not liveSystem then
	warn("✗ LiveSystem not found!")
	return
end

local remote = liveSystem:WaitForChild("UpdateScreenEvent", 5)
local cameraMode = liveSystem:WaitForChild("CameraMode", 5)
local cameraModeRemote = liveSystem:WaitForChild("UpdateCameraModeEvent", 5)
local screenMode = liveSystem:WaitForChild("ScreenMode", 5)
local screenModeRemote = liveSystem:WaitForChild("UpdateScreenModeEvent", 5)

if not remote or not cameraMode then
	warn("✗ Required values not found!")
	return
end

-- UI References
local mainFrame = gui:WaitForChild("MainFrame")
local header = mainFrame:WaitForChild("Header")
local closeBtn = header:WaitForChild("CloseBtn")
local container = mainFrame:WaitForChild("Container")
local scrollingFrame = container:WaitForChild("ScrollingFrame")
local templateBtn = scrollingFrame:WaitForChild("TemplateBtn")
local inputName = container:WaitForChild("InputName")
local enterBtn = inputName:WaitForChild("EnterBtn")
local showBtn = container:WaitForChild("ShowBtn")
local stopBtn = container:WaitForChild("StopBtn")
local statisBtn = container:WaitForChild("StatisBtn")
local dynamisBtn = container:WaitForChild("DynamisBtn")
local prevBtn = container:WaitForChild("PrevBtn")
local nextBtn = container:WaitForChild("NextBtn")

-- ==========================================
-- WARNA AWAL (themeColor)
-- Panel buatan Studio (hitam/putih) → token tema. Ukuran/posisi/transparansi tidak diubah.
-- ==========================================
mainFrame.BackgroundColor3 = T.BG
closeBtn.TextColor3 = T.TEXT
for _, holder in ipairs({ mainFrame, header, container }) do
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("TextLabel") then
			-- judul "Live Screen" (header/panel) → TEXT_STRONG; label di container → TEXT_DIM
			child.TextColor3 = (holder == container) and T.TEXT_DIM or T.TEXT_STRONG
		end
	end
end
scrollingFrame.BackgroundColor3 = T.CARD
scrollingFrame.ScrollBarImageColor3 = T.SCROLL
inputName.BackgroundColor3 = T.CARD
inputName.TextColor3 = T.TEXT
inputName.PlaceholderColor3 = T.TEXT_DIM
enterBtn.TextColor3 = T.TEXT
for _, actionBtn in ipairs({ showBtn, stopBtn, statisBtn, dynamisBtn, prevBtn, nextBtn }) do
	actionBtn.BackgroundColor3 = T.CARD
	actionBtn.TextColor3 = T.TEXT
end

-- ==========================================
-- VJ / LIVE BUTTONS (auto-create if needed)
-- ==========================================
local vjBtn = container:FindFirstChild("VJBtn")
local liveBtn = container:FindFirstChild("LiveBtn")

if not vjBtn or not liveBtn then
	local refPos = statisBtn.Position
	local refSize = statisBtn.Size
	local btnY = refPos.Y.Offset + refSize.Y.Offset + 45

	if not liveBtn then
		liveBtn = Instance.new("TextButton")
		liveBtn.Name = "LiveBtn"
		liveBtn.Size = UDim2.new(0, 80, 0, 30)
		liveBtn.Position = UDim2.new(0, 10, 0, btnY)
		liveBtn.BackgroundColor3 = T.CARD_HOVER
		liveBtn.BackgroundTransparency = 0.1
		liveBtn.TextColor3 = T.TEXT
		liveBtn.Text = "📺 LIVE"
		liveBtn.Font = Enum.Font.GothamBold
		liveBtn.TextSize = 12
		liveBtn.Parent = container
		Instance.new("UICorner", liveBtn).CornerRadius = UDim.new(0, 6)
	end

	if not vjBtn then
		vjBtn = Instance.new("TextButton")
		vjBtn.Name = "VJBtn"
		vjBtn.Size = UDim2.new(0, 80, 0, 30)
		vjBtn.Position = UDim2.new(0, 100, 0, btnY)
		vjBtn.BackgroundColor3 = T.ACCENT
		vjBtn.BackgroundTransparency = 0.1
		vjBtn.TextColor3 = T.ON_ACCENT
		vjBtn.Text = "🎬 VJ"
		vjBtn.Font = Enum.Font.GothamBold
		vjBtn.TextSize = 12
		vjBtn.Parent = container
		Instance.new("UICorner", vjBtn).CornerRadius = UDim.new(0, 6)
	end

	print("✅ VJ/Live buttons auto-created")
end

-- ==========================================
-- STATE
-- ==========================================
local playerButtons = {}
local sortedPlayerList = {}
local visiblePlayerList = {}
local selectedPlayerName = ""
local currentScreenModeLocal = "VJ"
local lastModeSwitchTime = 0

-- ==========================================
-- FORWARD DECLARATIONS
-- ==========================================
local updateButtonHighlight
local setCameraMode
local setScreenMode
local broadcastPlayerByName
local broadcastPlayerFromInput
local updateCameraModeUI
local updateScreenModeUI

-- ==========================================
-- PLAYER LIST
-- ==========================================
updateButtonHighlight = function(targetName)
	for _, btn in pairs(playerButtons) do
		btn.BackgroundColor3 = T.CARD
		btn.BackgroundTransparency = 0.3
		btn.TextColor3 = T.TEXT
	end

	if targetName ~= "" and playerButtons[targetName] then
		local btn = playerButtons[targetName]
		btn.BackgroundColor3 = T.ACCENT
		btn.BackgroundTransparency = 0.3
		btn.TextColor3 = T.ON_ACCENT
	end

	selectedPlayerName = targetName
end

local function createPlayerButton(targetPlayer)
	local btn = templateBtn:Clone()
	btn.Name = targetPlayer.Name
	btn.Text = targetPlayer.DisplayName
	btn.Visible = true
	btn.BackgroundColor3 = T.CARD
	btn.BackgroundTransparency = 0.3
	btn.TextColor3 = T.TEXT
	btn.Parent = scrollingFrame

	btn.MouseButton1Click:Connect(function()
		selectedPlayerName = targetPlayer.Name
		updateButtonHighlight(targetPlayer.Name)
		setScreenMode("Live")
		setCameraMode("Static")
		broadcastPlayerByName(targetPlayer.Name)
	end)

	return btn
end

local function getSortedPlayers()
	local allPlayers = Players:GetPlayers()
	table.sort(allPlayers, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	return allPlayers
end

local function refreshPlayerList()
	for _, btn in pairs(scrollingFrame:GetChildren()) do
		if btn:IsA("TextButton") and btn ~= templateBtn then
			btn:Destroy()
		end
	end

	playerButtons = {}
	sortedPlayerList = getSortedPlayers()
	visiblePlayerList = {}

	for _, targetPlayer in ipairs(sortedPlayerList) do
		local btn = createPlayerButton(targetPlayer)
		playerButtons[targetPlayer.Name] = btn
		table.insert(visiblePlayerList, targetPlayer.Name)
	end
end

local function filterPlayerList(searchText)
	searchText = string.lower(searchText)
	visiblePlayerList = {}

	for _, targetPlayer in ipairs(sortedPlayerList) do
		local btn = playerButtons[targetPlayer.Name]
		if btn then
			local isMatch = searchText == ""
				or string.find(string.lower(btn.Text), searchText, 1, true) ~= nil
			btn.Visible = isMatch
			if isMatch then
				table.insert(visiblePlayerList, targetPlayer.Name)
			end
		end
	end
end

local function getCurrentPlayerIndex()
	if selectedPlayerName == "" then return nil end
	for i, name in ipairs(visiblePlayerList) do
		if name == selectedPlayerName then return i end
	end
	return nil
end

local function navigatePlayer(direction)
	if #visiblePlayerList == 0 then return end

	local idx = getCurrentPlayerIndex()
	local newIdx

	if not idx then
		newIdx = 1
	elseif direction == "next" then
		newIdx = (idx % #visiblePlayerList) + 1
	else
		newIdx = ((idx - 2) % #visiblePlayerList) + 1
	end

	local targetName = visiblePlayerList[newIdx]
	if targetName then
		selectedPlayerName = targetName
		updateButtonHighlight(targetName)
		setScreenMode("Live")
		setCameraMode("Static")
		broadcastPlayerByName(targetName)
	end
end

-- ==========================================
-- CAMERA MODE
-- ==========================================
-- Latar Statis/Dinamis transparan (BackgroundTransparency = 1) → status hanya terlihat dari warna teks:
-- aktif = ACCENT (teks sorot; ON_ACCENT tidak terbaca di atas panel gelap), tidak aktif = TEXT.
updateCameraModeUI = function(mode)
	if mode == "Static" then
		statisBtn.BackgroundColor3 = T.ACCENT
		statisBtn.TextColor3 = T.ACCENT
		statisBtn.BackgroundTransparency = 1
		dynamisBtn.BackgroundColor3 = T.CARD_HOVER
		dynamisBtn.TextColor3 = T.TEXT
		dynamisBtn.BackgroundTransparency = 1
	elseif mode == "Dynamic" then
		statisBtn.BackgroundColor3 = T.CARD_HOVER
		statisBtn.TextColor3 = T.TEXT
		statisBtn.BackgroundTransparency = 1
		dynamisBtn.BackgroundColor3 = T.ACCENT
		dynamisBtn.TextColor3 = T.ACCENT
		dynamisBtn.BackgroundTransparency = 1
	end
end

setCameraMode = function(mode)
	if cameraMode.Value == mode then return end
	updateCameraModeUI(mode)
	if cameraModeRemote then
		cameraModeRemote:FireServer(mode)
	end
end

-- ==========================================
-- SCREEN MODE (Live / VJ) — WITH COOLDOWN
-- ==========================================
updateScreenModeUI = function(mode)
	currentScreenModeLocal = mode

	if mode == "Live" then
		liveBtn.BackgroundColor3 = T.ACCENT
		liveBtn.TextColor3 = T.ON_ACCENT
		liveBtn.BackgroundTransparency = 0.1
		vjBtn.BackgroundColor3 = T.CARD_HOVER
		vjBtn.TextColor3 = T.TEXT
		vjBtn.BackgroundTransparency = 0.1
	elseif mode == "VJ" then
		liveBtn.BackgroundColor3 = T.CARD_HOVER
		liveBtn.TextColor3 = T.TEXT
		liveBtn.BackgroundTransparency = 0.1
		vjBtn.BackgroundColor3 = T.ACCENT
		vjBtn.TextColor3 = T.ON_ACCENT
		vjBtn.BackgroundTransparency = 0.1
	end
end

setScreenMode = function(mode)
	if currentScreenModeLocal == mode then return end

	local now = tick()
	if now - lastModeSwitchTime < MODE_COOLDOWN then return end
	lastModeSwitchTime = now

	updateScreenModeUI(mode)

	if screenModeRemote then
		screenModeRemote:FireServer(mode)
	end
end

-- ==========================================
-- BROADCAST
-- ==========================================
broadcastPlayerByName = function(targetName)
	if not targetName or targetName == "" then return end
	local targetPlayer = Players:FindFirstChild(targetName)
	if not targetPlayer then
		warn("[LiveScreen] Player not found:", targetName)
		return
	end
	remote:FireServer(targetName)
end

broadcastPlayerFromInput = function()
	local searchText = inputName.Text
	if searchText == "" then return end

	local foundPlayer = nil

	for _, p in ipairs(sortedPlayerList) do
		if p.Name:lower() == searchText:lower() then
			foundPlayer = p; break
		end
	end

	if not foundPlayer then
		for _, p in ipairs(sortedPlayerList) do
			if p.DisplayName:lower() == searchText:lower() then
				foundPlayer = p; break
			end
		end
	end

	if not foundPlayer then
		for _, p in ipairs(sortedPlayerList) do
			if string.find(p.DisplayName:lower(), searchText:lower(), 1, true) then
				foundPlayer = p; break
			end
		end
	end

	if foundPlayer then
		selectedPlayerName = foundPlayer.Name
		updateButtonHighlight(foundPlayer.Name)
		broadcastPlayerByName(foundPlayer.Name)
	else
		warn("[LiveScreen] No match:", searchText)
	end
end

local function stopBroadcast()
	remote:FireServer("")
	selectedPlayerName = ""
	updateButtonHighlight("")
	setScreenMode("VJ")
end

-- ==========================================
-- UI EVENTS
-- ==========================================
enterBtn.MouseButton1Click:Connect(function()
	if inputName.Text ~= "" then
		setScreenMode("Live")
		setCameraMode("Static")
		broadcastPlayerFromInput()
	end
end)

inputName:GetPropertyChangedSignal("Text"):Connect(function()
	filterPlayerList(inputName.Text)
end)

showBtn.MouseButton1Click:Connect(function()
	setScreenMode("Live")
	setCameraMode("Static")
	broadcastPlayerFromInput()
end)

stopBtn.MouseButton1Click:Connect(function()
	stopBroadcast()
end)

statisBtn.MouseButton1Click:Connect(function()
	setCameraMode("Static")
end)

dynamisBtn.MouseButton1Click:Connect(function()
	setCameraMode("Dynamic")
end)

vjBtn.MouseButton1Click:Connect(function()
	setScreenMode("VJ")
end)

liveBtn.MouseButton1Click:Connect(function()
	setScreenMode("Live")
end)

prevBtn.MouseButton1Click:Connect(function()
	navigatePlayer("prev")
end)

nextBtn.MouseButton1Click:Connect(function()
	navigatePlayer("next")
end)

closeBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
end)

-- ==========================================
-- AUTO-REFRESH (debounced)
-- ==========================================
local refreshDebounce = false
local function debouncedRefresh()
	if refreshDebounce then return end
	refreshDebounce = true
	task.wait(0.3)
	refreshPlayerList()
	refreshDebounce = false
end

Players.PlayerAdded:Connect(debouncedRefresh)
Players.PlayerRemoving:Connect(debouncedRefresh)

mainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if mainFrame.Visible then
		refreshPlayerList()
	end
end)

-- ==========================================
-- SYNC: Listen for ScreenMode/CameraMode changes
-- ==========================================
if screenMode then
	screenMode.Changed:Connect(function(newMode)
		updateScreenModeUI(newMode)
	end)
end

if cameraMode then
	cameraMode.Changed:Connect(function(newMode)
		updateCameraModeUI(newMode)
	end)
end

-- ==========================================
-- ★ ADMIN-GATED ACCESS (via Attribute)
-- Waits for UnifiedRankManager to set IsAdmin
-- Hides GUI for non-admins, shows for admins
-- Reacts to mid-game rank changes
-- ==========================================
templateBtn.Visible = false
mainFrame.Visible = false

local function applyAdminAccess()
	local admin = isAdmin()
	gui.Enabled = admin

	if not admin then
		mainFrame.Visible = false
	end

	if admin then
		print("👑 [LiveScreen] Admin access granted for:", player.Name)
	end
end

-- Wait for attribute to arrive from server
waitForAdminAttribute(10)

-- Apply on load
applyAdminAccess()

-- Listen for mid-game rank changes (e.g. gamepass purchase, promotion)
player:GetAttributeChangedSignal("IsAdmin"):Connect(applyAdminAccess)

-- Init if admin
if isAdmin() then
	task.spawn(function()
		task.wait(0.5)
		updateCameraModeUI("Static")
		updateScreenModeUI("VJ")
		refreshPlayerList()
	end)
end

print("✨ LiveScreenClient loaded — Attribute-based admin, smooth switching!")