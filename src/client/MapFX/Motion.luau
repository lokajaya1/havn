--!strict
-- MapFX/Motion — rumus gerak hiasan map (domain murni: tanpa GetService/Instance/yield).
-- Disalin dari skrip server lama di Workspace supaya tampilannya sama persis; bedanya sekarang
-- dihitung di tiap client (0 byte jaringan). Satuan sudut: radian kecuali disebut lain.

local Motion = {}

-- Pohon bergoyang (skrip lama "Animated Tree"/"(Animated) Realistic tree": T mulai -99999,
-- tiap wait() T += 0.12, wait() lama ≈ 1/30 dtk; posisi dasar diturunkan 0.2 stud).
Motion.tree = {
	t0 = -99999,
	step = 0.12,
	stepsPerSecond = 30,
	sink = 0.2,
}

function Motion.treeTime(elapsed: number): number
	local c = Motion.tree
	return c.t0 + c.step * c.stepsPerSecond * elapsed
end

-- Posisi & kemiringan pohon pada waktu T. Masukan: posisi dasar (sudah diturunkan `sink`)
-- dan setengah tinggi part. Hasil: x, y, z, rotX, rotZ (sama dengan CFrame lama:
-- CFrame.new(x, y, z) * CFrame.Angles(rotX, 0, rotZ)).
function Motion.sway(px: number, py: number, pz: number, tall: number, t: number): (number, number, number, number, number)
	local x = px + (math.sin(t + (px / 5)) * math.sin(t / 9)) / 3
	local z = pz + (math.sin(t + (pz / 6)) * math.sin(t / 12)) / 4
	return x, py, z, (z - pz) / tall, (x - px) / -tall
end

-- Patung berputar (skrip lama: tiap wait() CFrame *= fromEulerAnglesXYZ(0, 0.020, 0) → 0.6 rad/dtk).
Motion.spinDefault = 0.020 * 30

function Motion.spinAngle(radPerSecond: number, elapsed: number): number
	return (radPerSecond * elapsed) % (2 * math.pi)
end

-- Kamera 360 (skrip lama: Heartbeat, Orientation.Y += 30 * dt derajat).
Motion.yawDefault = 30

function Motion.yawDegrees(baseDeg: number, degPerSecond: number, elapsed: number): number
	return (baseDeg + degPerSecond * elapsed) % 360
end

-- Lampu Beam panggung ("FINAL CLUB LIGHT SCRIPT V6").
export type BeamConfig = {
	loopPeriod: number,
	panAmp: number,
	tiltCenter: number,
	tiltAmp: number,
	brightness: number,
	blackoutPerFrame: number,
	frameRate: number,
	fadeTime: number,
	chaseGap: number,
}

Motion.beam = {
	loopPeriod = 14,
	panAmp = math.rad(70),
	tiltCenter = math.rad(55),
	tiltAmp = math.rad(18),
	brightness = 12,
	blackoutPerFrame = 0.0006, -- peluang per Heartbeat di skrip lama (±60 fps)
	frameRate = 60,
	fadeTime = 0.4,
	chaseGap = 0.05,
} :: BeamConfig

function Motion.beamSpeed(cfg: BeamConfig): number
	return (2 * math.pi) / cfg.loopPeriod
end

-- index mulai 1 (urutan anak folder Beam, sama dengan skrip lama).
function Motion.beamAngles(cfg: BeamConfig, phase: number, index: number, count: number): (number, number)
	local offset = (index / count) * math.pi * 2
	local pan = cfg.panAmp * math.sin(phase + offset)
	local tilt = cfg.tiltCenter + cfg.tiltAmp * math.sin(phase * 1.2 + offset)
	return pan, tilt
end

-- Peluang blackout dalam satu frame sepanjang dt (tidak tergantung fps client).
function Motion.blackoutChance(cfg: BeamConfig, dt: number): number
	return math.clamp(cfg.blackoutPerFrame * cfg.frameRate * dt, 0, 1)
end

return Motion
