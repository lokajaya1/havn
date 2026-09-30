-- StarterPlayerScripts/MapFX  (LocalScript)
-- Gerak hiasan map yang dulu dijalankan skrip SERVER di Workspace (direplikasi terus ke semua pemain).
-- Sekarang tiap client menggerakkan sendiri part yang diberi tag (dipasang sekali di Studio):
--   MapFX_Sway : pohon bergoyang (BasePart)
--   MapFX_Spin : berputar di sumbu Y lokal, atribut SpinRad (rad/dtk)        — patung
--   MapFX_Yaw  : Orientation.Y bertambah, atribut YawDeg (derajat/dtk)      — kamera 360Cam
--   MapFX_Beam : folder lampu Beam panggung (Model anak berisi Motor6D Pan/Tilt + lampu)
-- Rumus ada di MapFX/Motion (sama persis dengan skrip lama). Part di sini Anchored, server tidak lagi
-- mengubahnya, jadi perubahan lokal tidak ditimpa replikasi.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Motion = require(script:WaitForChild("Motion"))

type Sway = { part: BasePart, x: number, y: number, z: number, tall: number }
type Spin = { part: BasePart, base: CFrame, rate: number }
type Yaw = { part: BasePart, pos: Vector3, rx: number, ry: number, rz: number, rate: number }
type Lamp = { pan: Motor6D, tilt: Motor6D, light: Light, panC0: CFrame, tiltC0: CFrame }
type Beam = { folder: Instance, lamps: { Lamp }, phase: number, busy: boolean }

local sways: { [Instance]: Sway } = {}
local spins: { [Instance]: Spin } = {}
local yaws: { [Instance]: Yaw } = {}
local beams: { [Instance]: Beam } = {}
local elapsed = 0

local function numAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function addSway(inst: Instance)
	if not inst:IsA("BasePart") or sways[inst] then
		return
	end
	local pos = inst.CFrame.Position
	sways[inst] = { part = inst, x = pos.X, y = pos.Y - Motion.tree.sink, z = pos.Z, tall = inst.Size.Y / 2 }
end

local function addSpin(inst: Instance)
	if not inst:IsA("BasePart") or spins[inst] then
		return
	end
	spins[inst] = { part = inst, base = inst.CFrame, rate = numAttr(inst, "SpinRad", Motion.spinDefault) }
end

local function addYaw(inst: Instance)
	if not inst:IsA("BasePart") or yaws[inst] then
		return
	end
	local rx, ry, rz = inst.CFrame:ToOrientation()
	yaws[inst] = {
		part = inst,
		pos = inst.CFrame.Position,
		rx = rx,
		ry = math.deg(ry),
		rz = rz,
		rate = numAttr(inst, "YawDeg", Motion.yawDefault),
	}
end

local function addBeam(folder: Instance)
	if beams[folder] then
		return
	end
	local cfg = Motion.beam
	local lamps: { Lamp } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local pan = child:FindFirstChild("Pan", true)
			local tilt = child:FindFirstChild("Tilt", true)
			local light = child:FindFirstChildWhichIsA("SpotLight", true) or child:FindFirstChildWhichIsA("SurfaceLight", true)
			if pan and tilt and light and pan:IsA("Motor6D") and tilt:IsA("Motor6D") then
				light.Brightness = numAttr(folder, "Brightness", cfg.brightness)
				table.insert(lamps, { pan = pan, tilt = tilt, light = light, panC0 = pan.C0, tiltC0 = tilt.C0 })
			end
		end
	end
	if #lamps == 0 then
		warn("[MapFX] Beam tanpa lampu:", folder:GetFullName())
		return
	end
	beams[folder] = { folder = folder, lamps = lamps, phase = 0, busy = false }
end

local function blackoutChase(beam: Beam)
	local cfg = Motion.beam
	local full = numAttr(beam.folder, "Brightness", cfg.brightness)
	beam.busy = true
	for _, lamp in beam.lamps do
		TweenService:Create(lamp.light, TweenInfo.new(cfg.fadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
		task.wait(cfg.chaseGap)
	end
	for _, lamp in beam.lamps do
		TweenService:Create(lamp.light, TweenInfo.new(cfg.fadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Brightness = full }):Play()
		task.wait(cfg.chaseGap)
	end
	beam.busy = false
end

local function watch(tag: string, add: (Instance) -> (), store: { [Instance]: any })
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		store[inst] = nil
	end)
end

watch("MapFX_Sway", addSway, sways)
watch("MapFX_Spin", addSpin, spins)
watch("MapFX_Yaw", addYaw, yaws)
watch("MapFX_Beam", addBeam, beams)

RunService.Heartbeat:Connect(function(dt: number)
	elapsed += dt
	local t = Motion.treeTime(elapsed)
	for _, s in sways do
		local x, y, z, rx, rz = Motion.sway(s.x, s.y, s.z, s.tall, t)
		s.part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(rx, 0, rz)
	end
	for _, s in spins do
		s.part.CFrame = s.base * CFrame.fromEulerAnglesXYZ(0, Motion.spinAngle(s.rate, elapsed), 0)
	end
	for _, y in yaws do
		local deg = Motion.yawDegrees(y.ry, y.rate, elapsed)
		y.part.CFrame = CFrame.new(y.pos) * CFrame.fromOrientation(y.rx, math.rad(deg), y.rz)
	end
	local cfg = Motion.beam
	for _, b in beams do
		b.phase += Motion.beamSpeed(cfg) * dt
		for i, lamp in b.lamps do
			local pan, tilt = Motion.beamAngles(cfg, b.phase, i, #b.lamps)
			lamp.pan.C0 = lamp.panC0 * CFrame.Angles(0, pan, 0)
			lamp.tilt.C0 = lamp.tiltC0 * CFrame.Angles(tilt, 0, 0)
		end
		if not b.busy and math.random() < Motion.blackoutChance(cfg, dt) then
			task.spawn(blackoutChase, b)
		end
	end
end)
