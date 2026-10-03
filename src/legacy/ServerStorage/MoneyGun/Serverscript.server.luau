-- SERVER Script inside the Tool
-- [TOOLS] start/stop lewat batas terima + jeda terapkan (keadaan terakhir selalu diterapkan); Rate & Burst dari panel
-- (MoneyGunUI) dipakai dalam rentang Config (dulu selalu 50/12). Angka: ReplicatedStorage.Config.Tools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cfg = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools"))
local ToolRules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolRules"))
local M = Cfg.MONEY_GUN

local Tool = script.Parent
local RemoteEvent = Tool:FindFirstChild("RemoteEvent")
if not RemoteEvent then
	RemoteEvent = Instance.new("RemoteEvent")
	RemoteEvent.Parent = Tool
end
RemoteEvent.Name = "RemoteEvent"

-- ====== KONFIGURASI ======
local TEXTURE_ID = "rbxassetid://124266200071740" -- Ganti dengan Texture-ID kamu

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
local lastBurst = 0

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
end)

-- Komponen untuk pemegang tool SAAT INI (nil kalau `player` bukan pemegang / komponen kurang).
local function parts(player)
	local character = player.Parent and player.Character
	-- [FIX 2c] hanya pemegang tool yang boleh menembak (dulu: siapa pun bisa memakai Money Gun orang lain)
	if not character or Tool.Parent ~= character then return nil end
	local hrp = findHRP(character)
	local emitter = getOrCreateEmitter()
	local muzzle = emitter and emitter.Parent
	if not (hrp and emitter and muzzle) then
		warn("[MoneyGun] Komponen kurang: hrp/emitter/muzzle")
		return nil
	end
	return hrp, emitter, muzzle
end

-- start/stop: diterapkan lewat gate (dicek ulang pemegangnya saat diterapkan).
local pushState = ToolRules.gate(M.STATE_EVERY, function(req)
	local hrp, emitter, muzzle = parts(req.player)
	if not hrp then return end
	if req.action == "start" then
		emitter.Enabled = true
		emitter.Rate = req.rate
		aimMuzzleToVector(muzzle, hrp.CFrame.LookVector)
	else
		emitter.Rate = 0
		task.delay(0.05, function() emitter.Enabled = false end)
	end
end, os.clock, task.delay)

local bucket = ToolRules.bucket(Cfg.RECEIVE.RATE, Cfg.RECEIVE.BURST)

RemoteEvent.OnServerEvent:Connect(function(player, action, amount)
	if action ~= "start" and action ~= "stop" and action ~= "burst" then return end
	local character = player.Character
	if not character or Tool.Parent ~= character then return end
	if not ToolRules.take(bucket, os.clock()) then return end

	if action == "burst" then
		local now = os.clock()
		if now - lastBurst < M.BURST_COOLDOWN then return end -- [FIX 2c] anti-spam partikel
		local hrp, emitter, muzzle = parts(player)
		if not hrp then return end
		lastBurst = now
		aimMuzzleToVector(muzzle, hrp.CFrame.LookVector)
		emitter.Enabled = true
		emitter:Emit(ToolRules.choose(amount, M.BURST))
		task.delay(0.05, function() emitter.Enabled = false end)
	else
		pushState({ player = player, action = action, rate = ToolRules.choose(amount, M.RATE) })
	end
end)
