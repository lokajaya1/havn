-- SERVER Script inside the Tool

local Tool = script.Parent
local RemoteEvent = Tool:FindFirstChild("RemoteEvent") or Instance.new("RemoteEvent", Tool)
RemoteEvent.Name = "RemoteEvent"

local RunService = game:GetService("RunService")

-- ====== KONFIGURASI ======
local TEXTURE_ID = "rbxassetid://124266200071740" -- Ganti dengan Texture-ID kamu

local SPRAY_RATE      = 50
local BURST_COUNT     = 12
local LIFETIME        = NumberRange.new(4.5, 6.0)
local SPEED           = NumberRange.new(15, 20)
local SPREAD          = Vector2.new(60, 60)
local ROT_SPEED       = NumberRange.new(-20, 20)
local DRAG            = 3.0
local GRAVITY_SCALE   = 0.10
local SIZE            = NumberSequence.new({
	NumberSequenceKeypoint.new(0.00, 0.55),
	NumberSequenceKeypoint.new(0.80, 0.55),
	NumberSequenceKeypoint.new(1.00, 0.00),
})
local TRANSPARENCY    = NumberSequence.new({
	NumberSequenceKeypoint.new(0.00, 0.0),
	NumberSequenceKeypoint.new(0.85, 0.0),
	NumberSequenceKeypoint.new(1.00, 1.0),
})

local DEBUG = false

-- ===== UTIL =====
local function getHandle()
	local h = Tool:FindFirstChild("Handle")
	if not h then
		warn("[MoneyGun] Handle tidak ditemukan.")
	end
	return h
end

local function getOrCreateMuzzle()
	local handle = getHandle()
	if not handle then return nil end
	local muzzle = handle:FindFirstChild("Muzzle")
	if not muzzle then
		muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Parent = handle
		muzzle.WorldCFrame = handle.CFrame * CFrame.new(0, 0, -handle.Size.Z/2)
	end
	return muzzle
end

local function getOrCreateEmitter()
	local muzzle = getOrCreateMuzzle()
	if not muzzle then return nil end
	local emitter = muzzle:FindFirstChild("MoneyEmitter")
	if not emitter then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "MoneyEmitter"
		emitter.Parent = muzzle
		emitter.Texture = TEXTURE_ID
		emitter.Rate = 0
		emitter.Lifetime = LIFETIME
		emitter.Speed = SPEED
		emitter.SpreadAngle = SPREAD
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = ROT_SPEED
		emitter.Drag = DRAG
		emitter.Size = SIZE
		emitter.Transparency = TRANSPARENCY
		emitter.LightInfluence = 0
		emitter.LockedToPart = false
		emitter.ZOffset = 0
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Enabled = false
		emitter.Acceleration = Vector3.new(0, -workspace.Gravity * GRAVITY_SCALE, 0)
	end
	return emitter
end

local function findHRP(model: Model)
	return model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
end

local function aimMuzzleToVector(muzzle: Attachment, lookVec: Vector3)
	if not (muzzle and lookVec) then return end
	local pos = muzzle.WorldPosition
	muzzle.WorldCFrame = CFrame.lookAt(pos, pos + lookVec)
end

-- ===== STATE =====
local sprayingPlayers = {}
local lastBurst = 0
local BURST_COOLDOWN = 0.15

-- ===== EVENT =====
Tool.Equipped:Connect(function()
	local emitter = getOrCreateEmitter()
	if emitter then
		emitter.Enabled = true
		emitter:Emit(1)
		task.delay(0.15, function() emitter.Enabled = false end)
		if DEBUG then print("[MoneyGun] Self-test emit OK") end
	end
end)

Tool.Unequipped:Connect(function()
	local emitter = getOrCreateEmitter()
	if emitter then
		emitter.Rate = 0
		emitter.Enabled = false
	end
	for plr, conn in pairs(sprayingPlayers) do
		if conn then conn:Disconnect() end
		sprayingPlayers[plr] = nil
	end
end)

RemoteEvent.OnServerEvent:Connect(function(player, action)
	local character = player.Character
	if not character then return end
	-- [FIX 2c] hanya pemegang tool yang boleh menembak (dulu: siapa pun bisa memakai Money Gun orang lain)
	if Tool.Parent ~= character or type(action) ~= "string" then return end
	local hrp = findHRP(character)
	local emitter = getOrCreateEmitter()
	local muzzle = emitter and emitter.Parent
	if not (hrp and emitter and muzzle) then
		warn("[MoneyGun] Komponen kurang: hrp/emitter/muzzle")
		return
	end

	if action == "start" then
		emitter.Enabled = true
		emitter.Rate = SPRAY_RATE
		aimMuzzleToVector(muzzle, hrp.CFrame.LookVector)

	elseif action == "stop" then
		emitter.Rate = 0
		task.delay(0.05, function() emitter.Enabled = false end)

	elseif action == "burst" then
		local now = os.clock()
		if now - lastBurst < BURST_COOLDOWN then return end -- [FIX 2c] anti-spam partikel
		lastBurst = now
		aimMuzzleToVector(muzzle, hrp.CFrame.LookVector)
		emitter.Enabled = true
		emitter:Emit(BURST_COUNT)
		task.delay(0.05, function() emitter.Enabled = false end)

	elseif action == "hold" then
		-- optional: bisa dipakai buat logic tambahan
	end
end)
