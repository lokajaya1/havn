-- ═══════════════════════════════════════════════════════════
-- CarryStateDetector — pantau status carry, tampilkan panel drop
-- Path: ReplicatedStorage.CustomUIModules.CarryStateDetector
--
-- Modul ini tidak membangun UI. Tampilan panel drop dipegang CarryUI,
-- sumber kebenaran status dipegang CarryManager. Di sini cuma polling
-- 0.5 detik dan penerjemahan status → tampil / sembunyi.
--
-- ScreenGui DropCarryGui lama dimatikan (bukan dihancurkan, supaya script
-- warisan yang masih memegang referensinya tidak error), karena kalau
-- dibiarkan hidup panelnya dobel di posisi yang sama.
-- ═══════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local CarryStateDetector = {}

local player       = Players.LocalPlayer
local CarryManager = nil
local CarryUI      = nil

local connection  = nil
local monitoring  = false
local lastState   = false
local initialized = false

local POLL_RATE   = 0.5
local accumulator = 0

-- ═══════════════════════════════════════════════════════════
-- DEPENDENSI
-- ═══════════════════════════════════════════════════════════

local function loadModule(name)
	local folder = RS:FindFirstChild("CustomUIModules")
	local mod    = folder and folder:FindFirstChild(name)
	if not mod then
		warn("[CarryStateDetector] Modul tidak ada:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[CarryStateDetector] " .. name .. " gagal di-require:", result)
		return nil
	end
	return result
end

local function disableLegacyGui(playerGui)
	local legacy = playerGui:FindFirstChild("DropCarryGui")
	if not legacy then return end
	legacy.Enabled = false
	legacy:SetAttribute("SupersededByCarryUI", true)
end

-- ═══════════════════════════════════════════════════════════
-- STATUS TEXT
-- ═══════════════════════════════════════════════════════════

local function statusText()
	if not CarryManager then return "You are being carried" end

	local ok, partner = pcall(CarryManager.GetPartner, CarryManager)
	if ok and partner and typeof(partner) == "Instance" then
		return "In carry with " .. (partner.DisplayName or partner.Name)
	end
	return "You are being carried"
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════

function CarryStateDetector:Initialize()
	if initialized then return true end

	CarryManager = loadModule("CarryManager")
	CarryUI      = loadModule("CarryUI")

	if not CarryUI then
		warn("[CarryStateDetector] CarryUI tidak ada — panel drop carry mati")
		return false
	end

	local playerGui = player:FindFirstChild("PlayerGui")
		or player:WaitForChild("PlayerGui", 30)
	if not playerGui then
		warn("[CarryStateDetector] PlayerGui tidak ditemukan")
		return false
	end

	disableLegacyGui(playerGui)

	self:StartMonitoring()

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		self:OnCharacterRespawned()
	end)

	initialized = true
	print("[CarryStateDetector] Ready")
	return true
end

-- ═══════════════════════════════════════════════════════════
-- DETECT
-- ═══════════════════════════════════════════════════════════

function CarryStateDetector:DetectCarryState()
	if CarryManager and CarryManager.GetCarryState then
		local ok, r = pcall(CarryManager.GetCarryState, CarryManager)
		if ok and r and (r.isCarrying or r.isBeingCarried) then
			return true
		end
	end

	-- Cadangan: cek karakter langsung, hanya berguna kalau CarryManager
	-- belum siap atau gagal di-require.
	local char = player.Character
	if not char then return false end

	local carryble = char:FindFirstChild("Carryble")
	if carryble and carryble:IsA("BoolValue") and carryble.Value == false then
		return true
	end

	local hum = char:FindFirstChild("Humanoid")
	if hum and hum.PlatformStand then return true end

	return false
end

-- ═══════════════════════════════════════════════════════════
-- MONITORING
-- ═══════════════════════════════════════════════════════════

function CarryStateDetector:StartMonitoring()
	if monitoring then return end
	monitoring  = true
	accumulator = 0

	connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < POLL_RATE then return end
		accumulator = 0

		local carried = self:DetectCarryState()
		if carried ~= lastState then
			lastState = carried
			if carried then self:ShowDrop() else self:HideDrop() end
		end
	end)
end

function CarryStateDetector:StopMonitoring()
	if connection then connection:Disconnect(); connection = nil end
	monitoring = false
end

-- ═══════════════════════════════════════════════════════════
-- SHOW / HIDE
-- ═══════════════════════════════════════════════════════════

function CarryStateDetector:ShowDrop()
	if not CarryUI then return end
	CarryUI.ShowDrop(statusText(), function()
		if CarryManager and CarryManager.StopCarry then
			pcall(CarryManager.StopCarry, CarryManager)
		end
		lastState = false
	end)
end

function CarryStateDetector:HideDrop()
	if CarryUI then CarryUI.HideDrop() end
end

-- ═══════════════════════════════════════════════════════════
-- RESPAWN
-- ═══════════════════════════════════════════════════════════

function CarryStateDetector:OnCharacterRespawned()
	lastState = false
	if CarryUI then
		CarryUI.HideDrop()
		CarryUI.HideRequest()
	end

	-- Script warisan bisa menyalakan GUI lamanya lagi saat respawn
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui then disableLegacyGui(playerGui) end
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

function CarryStateDetector:SetCarryState(s)
	if s ~= lastState then
		lastState = s
		if s then self:ShowDrop() else self:HideDrop() end
	end
end

function CarryStateDetector:IsCarried() return lastState end
function CarryStateDetector:Cleanup()   self:StopMonitoring() end

return CarryStateDetector