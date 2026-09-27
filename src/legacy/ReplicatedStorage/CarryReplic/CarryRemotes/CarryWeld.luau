-- ═══════════════════════════════════════════════════════════
-- CarryWeld — Server-side carry weld logic
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")

local DanceShared = require(game:GetService("ReplicatedStorage").Modules.DanceShared)

local DEFAULT_WALKSPEED  = 16
local DEFAULT_JUMPPOWER  = 50
local DEFAULT_JUMPHEIGHT = 7.2

local function getTorso(char)
	return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end

local function getAnimator(char)
	local hum = char:FindFirstChild("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

local function setOwnership(char, owner)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				if part:CanSetNetworkOwnership() then
					part:SetNetworkOwner(owner)
				end
			end)
		end
	end
end

local function setMassless(char, enabled)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = enabled
		end
	end
end

local function destroyCarryWelds(char)
	if not char or not char.Parent then return end
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("Weld") or d:IsA("WeldConstraint")) and d.Name == "CarryWeld" then
			d:Destroy()
		end
	end
end

-- Semua animasi KECUALI dance: dance/sync tetap jalan selama & sesudah carry
-- (dulu ikut dihentikan lalu diputar ulang watchdog dari detik 0).
local function stopAllAnimations(char)
	local animator = getAnimator(char)
	if not animator then return end
	pcall(function()
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if not DanceShared.isDanceTrack(track) then
				track:Stop(0)
			end
		end
	end)
end

local function buildAnimId(raw)
	if not raw then return nil end
	local str = tostring(raw)
	if str:find("rbxassetid://") then return str end
	local nums = str:match("%d+")
	if not nums then return nil end
	return "rbxassetid://" .. nums
end

local function resetHumanoid(char, plr)
	local hum = char:FindFirstChild("Humanoid")
	if not hum then return end
	pcall(function()
		hum.PlatformStand = false
		hum.AutoRotate    = true
		-- Pemain yang masih menari/sync kembali ke kecepatan dance, bukan 16.
		hum.WalkSpeed     = plr and DanceShared.walkSpeedFor(plr) or DEFAULT_WALKSPEED
		hum.JumpPower     = DEFAULT_JUMPPOWER
		hum.JumpHeight    = DEFAULT_JUMPHEIGHT
	end)
	if plr then
		pcall(function()
			plr.DevComputerMovementMode = Enum.DevComputerMovementMode.UserChoice
		end)
	end
end

local function loadAndPlayAnim(char, animId, looped)
	local animator = getAnimator(char)
	if not animator then
		warn("[CarryWeld] No Animator on", char.Name)
		return nil
	end

	local fullId = buildAnimId(animId)
	if not fullId then
		warn("[CarryWeld] Invalid anim ID:", tostring(animId))
		return nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = fullId

	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if not ok or not track then
		warn("[CarryWeld] LoadAnimation FAILED:", fullId)
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action4

	if looped then
		track.Looped = true
	end

	track:Play(0.1)
	return track
end

-- ═══════════════════════════════════════════════════════════
-- MAIN
-- ═══════════════════════════════════════════════════════════

local carryModule = function(
	initiator: Player,
	recipient: Player,
	mainPart: BasePart,
	offset: CFrame,
	animCarry,
	animLift,
	looped: boolean?
)
	if not initiator or not recipient then return nil end

	local iChar = initiator.Character
	local rChar = recipient.Character
	if not iChar or not rChar then return nil end

	local iTorso = getTorso(iChar)
	local rTorso = getTorso(rChar)
	if not iTorso or not rTorso then return nil end

	local iHum = iChar:FindFirstChild("Humanoid")
	local rHum = rChar:FindFirstChild("Humanoid")
	if not iHum or not rHum then return nil end

	local iStatus = iChar:FindFirstChild("Carryble")
	local rStatus = rChar:FindFirstChild("Carryble")
	if not iStatus or not rStatus then return nil end

	local released = false
	local conns = {}
	local carrierTrack = nil
	local carriedTrack = nil

	mainPart = mainPart or iTorso
	offset = offset or CFrame.new(0, 7, 0)

	rHum.PlatformStand = true
	rTorso.Anchored = false
	recipient.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable

	stopAllAnimations(rChar)
	task.wait(0.05)

	if animCarry then
		carrierTrack = loadAndPlayAnim(iChar, animCarry, looped)
	end
	if animLift then
		carriedTrack = loadAndPlayAnim(rChar, animLift, looped)
	end

	local weld = Instance.new("Weld")
	weld.Name  = "CarryWeld"
	weld.Part0 = mainPart
	weld.Part1 = rTorso
	weld.C0    = offset
	weld.Parent = rTorso

	setMassless(rChar, true)

	task.wait(0.15)
	setOwnership(rChar, initiator)

	local function releaseCarry()
		if released then return end
		released = true

		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)

		if carrierTrack then pcall(carrierTrack.Stop, carrierTrack, 0) end
		if carriedTrack then pcall(carriedTrack.Stop, carriedTrack, 0) end

		stopAllAnimations(rChar)

		destroyCarryWelds(rChar)
		destroyCarryWelds(iChar)

		resetHumanoid(rChar, recipient)
		resetHumanoid(iChar, initiator)
		setMassless(rChar, false)

		pcall(function()
			rStatus.Value = true
			iStatus.Value = true
		end)

		pcall(function()
			setOwnership(rChar, recipient)
		end)
	end

	table.insert(conns, Players.ChildRemoved:Connect(function(leaving)
		if leaving == initiator or leaving == recipient then
			releaseCarry()
		end
	end))

	table.insert(conns, iStatus.Changed:Connect(function(val)
		if val == true and rStatus.Value == false then releaseCarry() end
	end))

	table.insert(conns, rStatus.Changed:Connect(function(val)
		if val == true and iStatus.Value == false then releaseCarry() end
	end))

	return releaseCarry
end

return carryModule