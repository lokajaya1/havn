local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════
-- ★ REMOVED: WHITELIST_USERIDS table
-- ★ NOW: Uses player:GetAttribute("IsAdmin") set by UnifiedRankManager

local MODE_COOLDOWN = 0.5

-- ★ Durasi live screen berdasarkan harga donasi
local DONATION_SCREEN_DURATIONS = {
	{minPrice = 10,    duration = 5  },
	{minPrice = 50,    duration = 8  },
	{minPrice = 100,   duration = 12 },
	{minPrice = 200,   duration = 16 },
	{minPrice = 500,   duration = 25 },
	{minPrice = 1000,  duration = 35 },
	{minPrice = 2000,  duration = 45 },
	{minPrice = 3000,  duration = 55 },
	{minPrice = 5000,  duration = 70 },
	{minPrice = 10000, duration = 90 },
}

-- ★ Reads attribute set by UnifiedRankManager (EffectiveRank >= 250 = Admin)
local function isAdmin(plr)
	return plr:GetAttribute("IsAdmin") or false
end

local function getScreenDuration(price)
	local matched = 5
	for _, entry in ipairs(DONATION_SCREEN_DURATIONS) do
		if price >= entry.minPrice then matched = entry.duration end
	end
	return matched
end

-- ═══════════════════════════════════════════════════════════
-- SETUP SYSTEM
-- ═══════════════════════════════════════════════════════════
local liveSystem = ReplicatedStorage:WaitForChild("LiveSystem")
local currentTarget = liveSystem:WaitForChild("CurrentTarget")
local cameraMode = liveSystem:WaitForChild("CameraMode")
local remote = liveSystem:WaitForChild("UpdateScreenEvent")

local cameraModeRemote = liveSystem:FindFirstChild("UpdateCameraModeEvent")
if not cameraModeRemote then
	cameraModeRemote = Instance.new("RemoteEvent")
	cameraModeRemote.Name = "UpdateCameraModeEvent"
	cameraModeRemote.Parent = liveSystem
end

-- ═══════════════════════════════════════════════════════════
-- SCREEN MODE
-- ═══════════════════════════════════════════════════════════
local screenMode = liveSystem:FindFirstChild("ScreenMode")
if not screenMode then
	screenMode = Instance.new("StringValue")
	screenMode.Name = "ScreenMode"
	screenMode.Value = "Gambar"
	screenMode.Parent = liveSystem
else
	screenMode.Value = "Gambar"
end

local screenModeRemote = liveSystem:FindFirstChild("UpdateScreenModeEvent")
if not screenModeRemote then
	screenModeRemote = Instance.new("RemoteEvent")
	screenModeRemote.Name = "UpdateScreenModeEvent"
	screenModeRemote.Parent = liveSystem
end

-- ═══════════════════════════════════════════════════════════
-- ★ DONATION SCREEN SIGNAL (BindableEvent dari DonationServer)
-- ═══════════════════════════════════════════════════════════
local donationScreenSignal = liveSystem:FindFirstChild("DonationScreenSignal")
if not donationScreenSignal then
	donationScreenSignal = Instance.new("BindableEvent")
	donationScreenSignal.Name = "DonationScreenSignal"
	donationScreenSignal.Parent = liveSystem
end

-- ═══════════════════════════════════════════════════════════
-- DEBOUNCE TRACKING
-- ═══════════════════════════════════════════════════════════
local lastScreenModeTime = 0
local lastCameraModeTime = 0

-- ═══════════════════════════════════════════════════════════
-- ★ DONATION AUTO-DISPLAY STATE
-- ═══════════════════════════════════════════════════════════
local donationVersion    = 0
local isDonationActive   = false
local savedAdminTarget   = ""
local savedAdminMode     = "Gambar"
local savedAdminCamMode  = "Static"

-- ═══════════════════════════════════════════════════════════
-- ★ FORCE TARGET REFRESH
-- ═══════════════════════════════════════════════════════════
local function forceSetTarget(playerName)
	if currentTarget.Value == playerName then
		currentTarget.Value = ""
		task.wait()
	end
	currentTarget.Value = playerName
end

-- ═══════════════════════════════════════════════════════════
-- ★ FORCE MODE REFRESH
-- ═══════════════════════════════════════════════════════════
local function forceSetMode(mode)
	if screenMode.Value == mode then
		screenMode.Value = (mode == "Live") and "Gambar" or "Live"
		task.wait()
	end
	screenMode.Value = mode
end

-- ═══════════════════════════════════════════════════════════
-- ★ SHOW DONOR ON SCREEN
-- ═══════════════════════════════════════════════════════════
local function showDonorOnScreen(playerName, price)
	if not playerName or playerName == "" then return end

	local donorPlayer = Players:FindFirstChild(playerName)
	if not donorPlayer or not donorPlayer.Character then
		print("[LiveScreen] Donor not in server or no character, skip screen")
		return
	end

	local duration = getScreenDuration(price)

	donationVersion += 1
	local myVersion = donationVersion

	if not isDonationActive then
		savedAdminTarget  = currentTarget.Value
		savedAdminMode    = screenMode.Value
		savedAdminCamMode = cameraMode.Value
	end
	isDonationActive = true

	forceSetMode("Live")
	forceSetTarget(playerName)
	cameraMode.Value = "Static"

	print(string.format(
		"[LiveScreen] 📺 Donation: %s | %d Robux | %ds | v%d | Saved: %s/%s",
		playerName, price, duration, myVersion, savedAdminMode, savedAdminTarget
		))

	task.delay(duration, function()
		if donationVersion ~= myVersion then
			print(string.format("[LiveScreen] ⏭ Timer v%d skipped (v%d active)", myVersion, donationVersion))
			return
		end

		isDonationActive = false

		if savedAdminMode == "Live" and savedAdminTarget ~= "" then
			cameraMode.Value = savedAdminCamMode
			forceSetMode("Live")
			forceSetTarget(savedAdminTarget)
			print(string.format("[LiveScreen] 🔄 Restored admin: Live/%s", savedAdminTarget))
		else
			currentTarget.Value = ""
			screenMode.Value = "Gambar"
			print("[LiveScreen] ⏹ Donation ended, back to Gambar")
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- LISTEN: DonationScreenSignal dari DonationServer
-- ═══════════════════════════════════════════════════════════
donationScreenSignal.Event:Connect(function(playerName, price)
	showDonorOnScreen(playerName, price)
end)

-- ═══════════════════════════════════════════════════════════
-- REMOTE: Target Player (admin manual control)
-- ★ CHANGED: isWhitelisted → isAdmin
-- ═══════════════════════════════════════════════════════════
-- Non-admin cukup dicatat SEKALI per pemain (remote bisa di-spam → Output banjir).
local warnedUnauthorized = {}

remote.OnServerEvent:Connect(function(player, targetName)
	if not isAdmin(player) then
		if not warnedUnauthorized[player] then
			warnedUnauthorized[player] = true
			warn("[LiveScreen] Unauthorized access by:", player.Name)
		end
		return
	end

	if type(targetName) ~= "string" then return end

	if isDonationActive then
		donationVersion += 1
		isDonationActive = false
		print("[LiveScreen] Admin override, donation display cancelled")
	end

	if targetName == "" then
		currentTarget.Value = ""
		print("[LiveScreen] Broadcast stopped by:", player.Name)
		return
	end

	local targetPlayer = Players:FindFirstChild(targetName)
	if not targetPlayer then
		warn("[LiveScreen] Target not found:", targetName)
		return
	end

	currentTarget.Value = targetName
	print("[LiveScreen] Broadcast started for:", targetName)
end)

-- ═══════════════════════════════════════════════════════════
-- REMOTE: Camera Mode (with debounce)
-- ★ CHANGED: isWhitelisted → isAdmin
-- ═══════════════════════════════════════════════════════════
cameraModeRemote.OnServerEvent:Connect(function(player, newMode)
	if not isAdmin(player) then return end
	if newMode ~= "Static" and newMode ~= "Dynamic" then return end

	local now = os.clock()
	if now - lastCameraModeTime < 0.2 then return end
	lastCameraModeTime = now

	if cameraMode.Value == newMode then return end

	cameraMode.Value = newMode
	print("[LiveScreen] Camera mode:", newMode, "by:", player.Name)
end)

-- ═══════════════════════════════════════════════════════════
-- REMOTE: Screen Mode (with debounce)
-- ★ CHANGED: isWhitelisted → isAdmin
-- ═══════════════════════════════════════════════════════════
screenModeRemote.OnServerEvent:Connect(function(player, newMode)
	if not isAdmin(player) then return end
	if newMode ~= "Live" and newMode ~= "Gambar" then return end

	local now = os.clock()
	if now - lastScreenModeTime < MODE_COOLDOWN then return end
	lastScreenModeTime = now

	if isDonationActive then
		donationVersion += 1
		isDonationActive = false
		print("[LiveScreen] Admin mode switch, donation display cancelled")
	end

	if screenMode.Value == newMode then return end

	screenMode.Value = newMode
	print("[LiveScreen] Screen mode:", newMode, "by:", player.Name)
end)

-- ═══════════════════════════════════════════════════════════
-- Cleanup
-- ═══════════════════════════════════════════════════════════
Players.PlayerRemoving:Connect(function(leavingPlayer)
	warnedUnauthorized[leavingPlayer] = nil

	if isDonationActive and currentTarget.Value == leavingPlayer.Name then
		donationVersion += 1
		isDonationActive = false
		currentTarget.Value = ""
		screenMode.Value = "Gambar"
		print("[LiveScreen] Donor left, back to Gambar")
		return
	end

	if currentTarget.Value == leavingPlayer.Name then
		currentTarget.Value = ""
		print("[LiveScreen] Target left, broadcast stopped:", leavingPlayer.Name)
	end
end)

print("[LiveScreen] ✅ Server loaded! Attribute-based admin | Default: Gambar | Donation auto-display ready")