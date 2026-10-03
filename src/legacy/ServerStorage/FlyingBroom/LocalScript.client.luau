-- Flying Broom Client | LocalScript → Tool/Flying Broom
-- FIX v2:
--   [BUG UTAMA] local fly = false HARUS dideklarasi SEBELUM _G.BroomApplyEffect
--   Di Lua, closure hanya bisa tangkap upvalue yang sudah dideklarasi saat
--   fungsi dibuat. Sebelumnya fly dideklarasi SETELAH _G.BroomApplyEffect
--   sehingga closure tangkap global fly (nil) → if not fly selalu true → return!

local Players  = game:GetService("Players")
local UIS      = game:GetService("UserInputService")
local RS       = game:GetService("RunService")
local RepStore = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local tool   = script.Parent
local mouse  = player:GetMouse()
local cam    = workspace.CurrentCamera

-- ── Config ────────────────────────────────────────────────
local function cfg()
	return _G.BroomConfig or {
		speed      = 80,
		trailOn    = true,
		trailColor = Color3.fromRGB(255, 200, 50),
	}
end

-- ── RemoteEvent ───────────────────────────────────────────
local effectEvent = RepStore:WaitForChild("BroomEffectSync", 15)
if not effectEvent then
	warn("[BroomClient] BroomEffectSync tidak ditemukan — tambahkan BroomEffectServer ke ServerScriptService")
end

-- ── Cari semua ParticleEmitter & Light (rekursif) ─────────
local allParticles = {}
local allLights    = {}

local function refreshEffectTargets()
	table.clear(allParticles)
	table.clear(allLights)
	for _, obj in ipairs(tool:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			table.insert(allParticles, obj)
		elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
			table.insert(allLights, obj)
		end
	end
end
refreshEffectTargets()

tool.DescendantAdded:Connect(function(obj)
	if obj:IsA("ParticleEmitter") or obj:IsA("PointLight")
		or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
		refreshEffectTargets()
	end
end)

-- ══════════════════════════════════════════════════════════
-- PENTING: SEMUA local state harus dideklarasi DI SINI
-- sebelum fungsi yang menggunakannya (terutama _G.BroomApplyEffect)
-- ══════════════════════════════════════════════════════════
local fly        = false   -- ← HARUS sebelum _G.BroomApplyEffect!
local lastClick  = 0
local currentVel = Vector3.zero
local bodyVel, bodyGyro, flyConn
local idleTrack, flyTrack
local char, HRP, humanoid, animator

-- ── Apply effect (lokal + server) ────────────────────────
local function applyEffect(enabled, color)
	-- 1. Update lokal langsung (tanpa delay)
	for _, pe in ipairs(allParticles) do
		pe.Enabled = enabled
		if color then pe.Color = ColorSequence.new(color) end
	end
	for _, pl in ipairs(allLights) do
		pl.Enabled = enabled
		if color then pl.Color = color end
	end

	-- 2. Sync ke server hanya kalau tool sedang equipped (di karakter)
	--    Kalau di backpack: particles tidak visible ke siapa pun, skip sync
	if effectEvent and tool.Parent == player.Character then
		effectEvent:FireServer("effect", enabled, color)
	end
end

-- ── Global API (dipanggil UI saat ganti warna/trail) ──────
-- Definisi ini SETELAH local fly = false → closure menangkap upvalue benar
_G.BroomApplyEffect = function()
	local c = cfg()

	-- Selalu update warna lokal (biar config dan visual sinkron)
	if c.trailOn then
		for _, pe in ipairs(allParticles) do
			pe.Color = ColorSequence.new(c.trailColor)
		end
		for _, pl in ipairs(allLights) do
			pl.Color = c.trailColor
		end
	end

	-- Sedang terbang → terapkan Trail ON/OFF + warna (lokal + server).
	-- [TOOLS] dulu selalu mengirim enabled = true → Trail OFF saat terbang tidak mematikan efek.
	if fly then
		applyEffect(c.trailOn, c.trailOn and c.trailColor or nil)
	end
end

-- ── Animasi ───────────────────────────────────────────────
local ACCEL            = 6
local TILT_ANGLE       = 25
local DOUBLE_CLICK_MAX = 0.3

local ANIM_IDLE = "rbxassetid://118703314621593"
local ANIM_FLY  = "rbxassetid://115410396577254"

local idleAnim = Instance.new("Animation"); idleAnim.AnimationId = ANIM_IDLE
local flyAnim  = Instance.new("Animation"); flyAnim.AnimationId  = ANIM_FLY

local function resolveChar()
	char     = player.Character
	if not char then return false end
	HRP      = char:FindFirstChild("HumanoidRootPart")
	humanoid = char:FindFirstChildOfClass("Humanoid")
	animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	return HRP ~= nil and humanoid ~= nil and animator ~= nil
end

local function stopAllAnim()
	if idleTrack then idleTrack:Stop(); idleTrack = nil end
	if flyTrack  then flyTrack:Stop();  flyTrack  = nil end
end

local function playIdle()
	if flyTrack then flyTrack:Stop(); flyTrack = nil end
	if not idleTrack then idleTrack = animator:LoadAnimation(idleAnim) end
	if not idleTrack.IsPlaying then idleTrack:Play() end
end

local function playFly()
	if idleTrack then idleTrack:Stop(); idleTrack = nil end
	if not flyTrack then flyTrack = animator:LoadAnimation(flyAnim) end
	if not flyTrack.IsPlaying then flyTrack:Play() end
end

local function clearMotors()
	if flyConn  then flyConn:Disconnect();  flyConn  = nil end
	if bodyVel  then bodyVel:Destroy();     bodyVel  = nil end
	if bodyGyro then bodyGyro:Destroy();    bodyGyro = nil end
	currentVel = Vector3.zero
end

-- ── Fly Start / Stop ──────────────────────────────────────
local function startFly()
	if not resolveChar() then return end

	local c = cfg()
	-- Selalu apply warna TERBARU dari config saat mulai terbang
	-- Ini menangkap perubahan warna yang dibuat saat tidak terbang
	applyEffect(c.trailOn, c.trailOn and c.trailColor or nil)

	bodyVel          = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVel.Velocity = Vector3.zero
	bodyVel.P        = 5e3
	bodyVel.Parent   = HRP

	bodyGyro           = Instance.new("BodyGyro")
	bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bodyGyro.P         = 5e3
	bodyGyro.Parent    = HRP

	humanoid.PlatformStand = true
	playIdle()

	flyConn = RS.RenderStepped:Connect(function(dt)
		local spd      = cfg().speed
		local inputVel = Vector3.zero

		if UIS.TouchEnabled then
			local moveDir = humanoid.MoveDirection
			inputVel = moveDir * spd
			if moveDir.Magnitude > 0.05 then
				local lookY = cam.CFrame.LookVector.Y
				if math.abs(lookY) > 0.15 then
					inputVel += Vector3.new(0, spd * (lookY - math.sign(lookY) * 0.15) * 1.2, 0)
				end
			end
		else
			local look  = cam.CFrame.LookVector
			local right = cam.CFrame.RightVector
			if UIS:IsKeyDown(Enum.KeyCode.W)         then inputVel += look  * spd end
			if UIS:IsKeyDown(Enum.KeyCode.S)         then inputVel -= look  * spd end
			if UIS:IsKeyDown(Enum.KeyCode.A)         then inputVel -= right * spd end
			if UIS:IsKeyDown(Enum.KeyCode.D)         then inputVel += right * spd end
			if UIS:IsKeyDown(Enum.KeyCode.Space)     then inputVel += Vector3.new(0,  spd, 0) end
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then inputVel -= Vector3.new(0,  spd, 0) end
		end

		local smoothXZ = Vector3.new(currentVel.X, 0, currentVel.Z)
			:Lerp(Vector3.new(inputVel.X, 0, inputVel.Z), ACCEL * dt)
		currentVel       = Vector3.new(smoothXZ.X, inputVel.Y, smoothXZ.Z)
		bodyVel.Velocity = currentVel

		if Vector3.new(inputVel.X, 0, inputVel.Z).Magnitude > 0 or math.abs(inputVel.Y) > 0.1 then
			playFly()
		else
			playIdle()
		end

		if Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude > 1 then
			local camLook = cam.CFrame.LookVector
			local base    = CFrame.lookAt(HRP.Position, HRP.Position + Vector3.new(camLook.X, 0, camLook.Z))
			bodyGyro.CFrame = base * CFrame.Angles(math.rad(-TILT_ANGLE), 0, 0)
		else
			bodyGyro.CFrame = HRP.CFrame
		end
	end)
end

local function stopFly()
	clearMotors()
	applyEffect(false, nil)
	if resolveChar() then humanoid.PlatformStand = false end
	stopAllAnim()
end

local function toggleFly()
	fly = not fly
	if fly then startFly() else stopFly() end
end

-- ── Input ─────────────────────────────────────────────────
mouse.Button1Down:Connect(function()
	if tool.Parent ~= player.Character then return end
	local now = os.clock()
	if now - lastClick <= DOUBLE_CLICK_MAX then
		toggleFly()
		lastClick = 0
	else
		lastClick = now
	end
end)

tool.Unequipped:Connect(function()
	if fly then fly = false; stopFly() end
end)

player.CharacterAdded:Connect(function()
	fly = false
	clearMotors()
	idleTrack, flyTrack = nil, nil
	task.defer(refreshEffectTargets)
end)