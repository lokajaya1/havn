-- ═══════════════════════════════════════════════════════════
-- CarryManager — protokol carry sisi client
-- Path: ReplicatedStorage.CustomUIModules.CarryManager
--
-- Semua tampilan (request / drop / toast / pemilih jenis) ada di CarryUI.
-- File ini murni protokol + pemulihan karakter setelah carry dilepas.
-- ═══════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local CarryUI = require(RS:WaitForChild("CustomUIModules"):WaitForChild("CarryUI"))

-- DanceShared membaca DanceAssets langsung; tunggu replikasinya dulu.
RS:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("Dances"):WaitForChild("DanceAssets")
local DanceShared = require(RS:WaitForChild("Modules"):WaitForChild("DanceShared"))

-- ── Constants ───────────────────────────────────────────────

local DEFAULT_JUMPPOWER  = 50
local DEFAULT_JUMPHEIGHT = 7.2

local REQUEST_TIMEOUT  = 15
local UNFREEZE_TIMEOUT = 3

-- ── State ───────────────────────────────────────────────────

local CarryManager = {}

local player      = Players.LocalPlayer
local CarryRemote = nil

local carryTypes      = {}
local state           = { active = false, partner = nil, carryModule = nil }
local initialized     = false
local remoteReady     = false
local pendingOutgoing = nil   -- request yang KITA kirim
local incoming        = nil   -- request yang MASUK ke kita
local stopDebounce    = false
local carrybleConn    = nil
local unfreezeConn    = nil

local function nameOf(plr)
	if typeof(plr) ~= "Instance" then return "Player" end
	return plr.DisplayName ~= "" and plr.DisplayName or plr.Name
end

-- ── Unfreeze loop ───────────────────────────────────────────
-- Setelah carry dilepas, humanoid kadang nyangkut di PlatformStand.
-- Loop pendek ini memaksa dia berdiri lagi, lalu berhenti sendiri.

local function stopUnfreezeLoop()
	if unfreezeConn then
		unfreezeConn:Disconnect()
		unfreezeConn = nil
	end
end

local function resetHumanoid(hum)
	hum.PlatformStand = false
	hum.AutoRotate    = true
	hum.WalkSpeed     = DanceShared.walkSpeedFor(player) -- menari/sync = 6, lainnya 16
	hum.JumpPower     = DEFAULT_JUMPPOWER
	hum.JumpHeight    = DEFAULT_JUMPHEIGHT
end

local function startUnfreezeLoop()
	stopUnfreezeLoop()

	local char = player.Character
	if not char or not char.Parent then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	resetHumanoid(hum)

	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		-- Dance tidak ikut dihentikan (di client stop hanya lokal: dance hilang
		-- di layar sendiri padahal server & pemain lain masih melihatnya).
		for _, trackObj in ipairs(animator:GetPlayingAnimationTracks()) do
			if not DanceShared.isDanceTrack(trackObj) then trackObj:Stop(0) end
		end
	end

	local startTime  = os.clock()
	local triedNudge = false

	unfreezeConn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime

		if elapsed > UNFREEZE_TIMEOUT or not char.Parent then
			stopUnfreezeLoop()
			return
		end

		local h = char:FindFirstChildOfClass("Humanoid")
		if not h then stopUnfreezeLoop() return end

		local st = h:GetState()
		if st == Enum.HumanoidStateType.Running
			or st == Enum.HumanoidStateType.RunningNoPhysics
			or st == Enum.HumanoidStateType.Landed
			or st == Enum.HumanoidStateType.Freefall then
			h.PlatformStand = false
			h.AutoRotate    = true
			stopUnfreezeLoop()
			return
		end

		resetHumanoid(h)

		if elapsed < 0.3 then
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
		else
			h:ChangeState(Enum.HumanoidStateType.Running)
			if elapsed >= 1 and not triedNudge then
				triedNudge = true
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then hrp.AssemblyLinearVelocity = Vector3.new(0, 10, 0) end
			end
		end
	end)
end

-- ── Watch Carryble ──────────────────────────────────────────

local function disconnectCarrybleWatch()
	if carrybleConn then
		carrybleConn:Disconnect()
		carrybleConn = nil
	end
end

local function watchCarryble()
	disconnectCarrybleWatch()

	local char = player.Character
	if not char then return end

	local carryble = char:FindFirstChild("Carryble")
	if not carryble or not carryble:IsA("BoolValue") then return end

	if carryble.Value then
		startUnfreezeLoop()
		return
	end

	carrybleConn = carryble.Changed:Connect(function(newVal)
		if newVal == true then
			disconnectCarrybleWatch()
			startUnfreezeLoop()
		end
	end)
end

-- ── Helpers ─────────────────────────────────────────────────

local function fireServer(args)
	if CarryRemote then CarryRemote:FireServer(args) end
end

local function clearState()
	state.active      = false
	state.partner     = nil
	state.carryModule = nil
	pendingOutgoing   = nil
	CarryUI.HideDrop()
end

-- ── Initialize ──────────────────────────────────────────────

function CarryManager:Initialize()
	if initialized then return end
	initialized = true
	self:_loadCarryTypes()
	task.spawn(function() self:_connectRemote() end)
end

function CarryManager:_connectRemote()
	local replic = RS:WaitForChild("CarryReplic", 15)
	local remotes = replic and replic:WaitForChild("CarryRemotes", 10)
	CarryRemote = remotes and remotes:WaitForChild("CarryRemote", 10)

	if not CarryRemote then
		warn("[CarryManager] CarryReplic.CarryRemotes.CarryRemote tidak ditemukan")
		return
	end

	remoteReady = true

	CarryRemote.OnClientEvent:Connect(function(args)
		if type(args) == "table" and args.cmd then
			self:_handleServerEvent(args)
		end
	end)
end

-- ── Load carry types ────────────────────────────────────────
-- Satu entry per ModuleScript. Yang dikirim ke server memang module-nya,
-- jadi tidak ada gunanya memecah satu module jadi beberapa judul.

function CarryManager:_loadCarryTypes()
	local function add(mod)
		if mod:IsA("ModuleScript") and not carryTypes[mod.Name] then
			carryTypes[mod.Name] = { module = mod, title = mod.Name }
		end
	end

	local replic  = RS:FindFirstChild("CarryReplic")
	local choices = replic and replic:FindFirstChild("CarryChoices")
	if choices then
		for _, mod in ipairs(choices:GetChildren()) do add(mod) end
	end

	local assets = RS:FindFirstChild("Assets")
	assets = assets and assets:FindFirstChild("Carry")
	if assets then
		for _, mod in ipairs(assets:GetChildren()) do add(mod) end
	end

	local count = 0
	for _ in pairs(carryTypes) do count += 1 end

	if count == 0 then
		warn("[CarryManager] Tidak ada jenis carry di CarryReplic.CarryChoices maupun Assets.Carry")
	else
		print("[CarryManager] " .. count .. " jenis carry termuat")
	end
end

-- ── Server events ───────────────────────────────────────────

function CarryManager:_handleServerEvent(args)
	local cmd = args.cmd

	if cmd == "GetMessage" then
		self:_onRequestReceived(args.messageSentBy, args.carrychoicesss)

	elseif cmd == "GetCarryInfo" then
		pendingOutgoing   = nil
		incoming          = nil
		state.active      = true
		state.partner     = args.otherPlr
		state.carryModule = args.carrychoicesss

		CarryUI.HideRequest()
		CarryUI.ShowDrop("In a carry with " .. nameOf(args.otherPlr), function()
			self:StopCarry()
		end)

		watchCarryble()

	elseif cmd == "Messagesserror" then
		-- Kalau ini datang selagi pendingOutgoing masih ada, artinya target
		-- memang menjawab (Decline manual atau auto-decline). Kasus "server
		-- tidak menjawab sama sekali" ditangani watchdog di SendCarryRequest.
		local pending = pendingOutgoing
		pendingOutgoing = nil

		if pending then
			CarryUI.Toast("Request Declined", pending.targetName .. " declined your request", 3)
		else
			CarryUI.Toast("Cannot Carry", nameOf(args.targetPlr) .. " is busy right now", 3)
		end

	elseif cmd == "TooFar" then
		pendingOutgoing = nil
		CarryUI.Toast("Too Far", "Get closer to " .. nameOf(args.targetPlr) .. " to carry", 3)

	elseif cmd == "DestroyCarryInfo" then
		if state.active then
			clearState()
			stopDebounce = false
			startUnfreezeLoop()
		end
	end
end

-- ── Incoming request ────────────────────────────────────────

function CarryManager:_onRequestReceived(fromPlayer, carryModule)
	if not fromPlayer then return end

	local ts = os.clock()
	incoming = { from = fromPlayer, module = carryModule, timestamp = ts }

	local carryName = (typeof(carryModule) == "Instance" and carryModule.Name)
		or tostring(carryModule or "Carry")

	CarryUI.ShowRequest(fromPlayer, carryName, REQUEST_TIMEOUT,
		function() self:RespondToRequest(true)  end,
		function() self:RespondToRequest(false) end)

	task.delay(REQUEST_TIMEOUT, function()
		if not incoming or incoming.timestamp ~= ts then return end
		incoming = nil
		fireServer({ cmd = "Declinecarry" })
		CarryUI.HideRequest()
		CarryUI.Toast("Request Expired", "Carry request timed out", 2)
	end)
end

function CarryManager:RespondToRequest(accepted)
	local req = incoming
	incoming = nil

	CarryUI.HideRequest()
	if not req or not remoteReady then return end

	if accepted then
		fireServer({ cmd = "Carry", firstPlr = req.from, carrychoicesss = req.module })
	else
		fireServer({ cmd = "Declinecarry" })
	end
end

-- ── Outgoing request ────────────────────────────────────────

function CarryManager:SendCarryRequest(targetPlayer, carryTypeId)
	if not remoteReady then
		CarryUI.Toast("Not Ready", "Carry system masih loading...", 3)
		return
	end
	if state.active then
		CarryUI.Toast("Busy", "Kamu sedang dalam carry", 3)
		return
	end
	if pendingOutgoing then
		CarryUI.Toast("Wait", "Masih menunggu jawaban...", 2)
		return
	end

	local entry = carryTypes[carryTypeId]
	if not entry then
		warn("[CarryManager] Jenis carry tidak ada:", carryTypeId)
		return
	end

	local ts = os.clock()
	pendingOutgoing = { targetName = nameOf(targetPlayer), timestamp = ts }

	fireServer({ cmd = "AskCarry", targetPlr = targetPlayer, carrychoicesss = entry.module })
	CarryUI.Toast("Request Sent", "Waiting for " .. nameOf(targetPlayer) .. "...", 2)

	-- Watchdog: satu-satunya sumber "No Response". Kalau server sempat
	-- menjawab, pendingOutgoing sudah di-nil-kan di handler dan ini no-op.
	task.delay(REQUEST_TIMEOUT + 2, function()
		if not pendingOutgoing or pendingOutgoing.timestamp ~= ts then return end
		local name = pendingOutgoing.targetName
		pendingOutgoing = nil
		CarryUI.Toast("No Response", name .. " didn't respond to your carry request", 3)
	end)
end

-- ── Stop ────────────────────────────────────────────────────

function CarryManager:StopCarry()
	if not remoteReady or stopDebounce then return end
	stopDebounce = true

	fireServer({ cmd = "StopCarry" })
	pendingOutgoing = nil
	CarryUI.HideDrop()
	watchCarryble()

	task.delay(2, function()
		if state.active then
			clearState()
			startUnfreezeLoop()
		end
		stopDebounce = false
	end)

	CarryUI.Toast("Carry Stopped", "You stopped the carry", 2)
end

function CarryManager:OnCharacterRespawned()
	stopUnfreezeLoop()
	disconnectCarrybleWatch()
	clearState()
	incoming     = nil
	stopDebounce = false
	CarryUI.HideRequest()
	CarryUI.HideSelect()
end

-- ── Getters ─────────────────────────────────────────────────

function CarryManager:GetCarryTypes() return carryTypes end
function CarryManager:IsInCarry()     return state.active end
function CarryManager:GetPartner()    return state.partner end

return CarryManager