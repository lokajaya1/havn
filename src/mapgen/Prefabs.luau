--!strict
-- MapGen/Prefabs — objek industrial Y2K dari part primitif (tanpa Instance.new langsung; semua lewat Builder).

local Prefabs = {}

local function at(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end
Prefabs.at = at

-- Kontainer 29.2 × 9.6 × 9.6 (panjang di sumbu X lokal). base = CFrame tengah-bawah.
Prefabs.containerSize = Vector3.new(29.2, 9.6, 9.6)
function Prefabs.container(b: any, parent: Instance, name: string, base: CFrame, colorKey: string)
	local m = b:model(parent, name)
	local S = Prefabs.containerSize
	b:part(m, "Body", { size = S, cf = base * CFrame.new(0, S.Y / 2, 0), color = colorKey, material = "Corrugated" })
	b:part(m, "Door_End", { size = Vector3.new(0.3, S.Y - 0.4, S.Z - 0.4), cf = base * CFrame.new(S.X / 2 + 0.15, S.Y / 2, 0), color = colorKey, material = "Metal" })
	for i, z in { -1.6, 1.6 } do
		b:part(m, "LockBar_0" .. i, { size = Vector3.new(0.3, S.Y - 1.4, 0.3), cf = base * CFrame.new(S.X / 2 + 0.4, S.Y / 2, z), color = "Chrome", material = "Metal" })
	end
	return m
end

-- Tumpukan: kolom berjajar di sumbu Z lokal, tiap kolom `levels[i]` kontainer; warna bergilir.
function Prefabs.stack(b: any, parent: Instance, name: string, base: CFrame, levels: { number }, colors: { string }, seed: number)
	local m = b:model(parent, name)
	local S = Prefabs.containerSize
	local n = 0
	for col, h in levels do
		for lv = 1, h do
			n += 1
			local key = colors[((seed + n) % #colors) + 1]
			local cf = base * CFrame.new(0, (lv - 1) * S.Y, (col - (#levels + 1) / 2) * (S.Z + 0.4))
			Prefabs.container(b, m, string.format("Container_%s_%02d", (string.gsub(key, "Container", "")), n), cf, key)
		end
	end
	return m
end

-- Derek gantry: 4 kaki, girder, boom, kabin, troli + kabel + kontainer menggantung, strip neon.
function Prefabs.crane(b: any, parent: Instance, name: string, cx: number, cz: number, g: number)
	local m = b:model(parent, name)
	local H, hx, hz = 60, 18, 10
	for _, c in { { "NW", -hx, -hz }, { "NE", hx, -hz }, { "SW", -hx, hz }, { "SE", hx, hz } } do
		b:part(m, "Leg_" .. c[1], { size = Vector3.new(3, H, 3), cf = CFrame.new(cx + c[2], g + H / 2, cz + c[3]), color = "ContainerOrange", material = "Metal" })
		b:part(m, "Neon_Leg_" .. c[1], { size = Vector3.new(3.2, 1, 3.2), cf = CFrame.new(cx + c[2], g + H - 3, cz + c[3]), color = "HotPink", material = "Neon" })
	end
	for _, z in { { "North", -hz }, { "South", hz } } do
		b:part(m, "Girder_" .. z[1], { size = Vector3.new(60, 4, 3), cf = CFrame.new(cx, g + H + 2, cz + z[2]), color = "ContainerOrange", material = "Metal" })
	end
	b:part(m, "Beam_West", { size = Vector3.new(3, 4, 2 * hz), cf = CFrame.new(cx - hx, g + H + 2, cz), color = "ContainerOrange", material = "Metal" })
	b:part(m, "Beam_East", { size = Vector3.new(3, 4, 2 * hz), cf = CFrame.new(cx + hx, g + H + 2, cz), color = "ContainerOrange", material = "Metal" })
	b:part(m, "Cab", { size = Vector3.new(7, 6, 7), cf = CFrame.new(cx + hx - 4, g + H - 3, cz), color = "Chrome", material = "Metal" })
	b:part(m, "Cab_Glass", { size = Vector3.new(0.3, 3, 6), cf = CFrame.new(cx + hx - 7.7, g + H - 2.5, cz), color = "IceBlue", material = "Glass", transparency = 0.4 })
	b:part(m, "Trolley", { size = Vector3.new(8, 3, 2 * hz + 3), cf = CFrame.new(cx - 10, g + H - 0.5, cz), color = "Steel", material = "Metal" })
	b:part(m, "Cable", { size = Vector3.new(0.4, 28, 0.4), cf = CFrame.new(cx - 10, g + H - 16, cz), color = "Steel", material = "Metal", decor = true })
	b:part(m, "Spreader", { size = Vector3.new(30, 1.2, 9), cf = CFrame.new(cx - 10, g + H - 30, cz), color = "SafetyYellow", material = "Metal" })
	Prefabs.container(b, m, "Container_Hanging", at(cx - 10, g + H - 40.6, cz), "Lilac")
	return m
end

-- Gudang atap gergaji: 4 dinding bergelombang, 3 gigi atap + kaca, 3 pintu gulung di sisi barat, neon, papan nama.
function Prefabs.warehouse(b: any, parent: Instance, name: string, cx: number, cz: number, g: number, sign: string)
	local m = b:model(parent, name)
	local W, H, D = 60, 24, 45
	local function wall(n: string, sx: number, sz: number, x: number, z: number)
		b:part(m, n, { size = Vector3.new(sx, H, sz), cf = CFrame.new(x, g + H / 2, z), color = "ContainerBlue", material = "Corrugated" })
	end
	wall("Wall_North", W, 1, cx, cz - D / 2)
	wall("Wall_South", W, 1, cx, cz + D / 2)
	wall("Wall_East", 1, D, cx + W / 2, cz)
	wall("Wall_West", 1, D, cx - W / 2, cz)
	for i = 1, 3 do
		local x = cx - W / 2 + (i - 0.5) * (W / 3)
		b:part(m, "Roof_Tooth_0" .. i, { size = Vector3.new(D, 6, W / 3), cf = CFrame.new(x, g + H + 3, cz) * CFrame.Angles(0, math.rad(90), 0), color = "Rust", material = "Corrugated", shape = "Wedge" })
		b:part(m, "Roof_Glass_0" .. i, { size = Vector3.new(0.4, 5.6, D - 1), cf = CFrame.new(x + W / 6 - 0.3, g + H + 3, cz), color = "IceBlue", material = "Glass", transparency = 0.35 })
	end
	for i, z in { -14, 0, 14 } do
		b:part(m, "Door_Roll_0" .. i, { size = Vector3.new(0.4, 14, 10), cf = CFrame.new(cx - W / 2 - 0.4, g + 7, cz + z), color = "Steel", material = "DiamondPlate" })
		b:part(m, "Neon_Door_0" .. i, { size = Vector3.new(0.4, 0.6, 10), cf = CFrame.new(cx - W / 2 - 0.5, g + 14.8, cz + z), color = if i == 2 then "Lime" else "HotPink", material = "Neon" })
	end
	b:part(m, "Neon_Roofline", { size = Vector3.new(0.5, 0.6, D), cf = CFrame.new(cx - W / 2 - 0.5, g + H - 0.5, cz), color = "IceBlue", material = "Neon" })
	b:part(m, "LoadingDock", { size = Vector3.new(8, 1.5, D), cf = CFrame.new(cx - W / 2 - 4.5, g + 0.75, cz), color = "Concrete", material = "Concrete" })
	b:part(m, "Dock_Edge", { size = Vector3.new(0.4, 1.6, D), cf = CFrame.new(cx - W / 2 - 8.6, g + 0.8, cz), color = "SafetyYellow", material = "Plastic" })
	local board = b:part(m, "Sign_Board", { size = Vector3.new(0.6, 5, 26), cf = CFrame.new(cx - W / 2 - 0.8, g + H - 5, cz), color = "Steel", material = "Metal" })
	b:sign(board, sign, "Left", "HotPink")
	return m
end

-- Pagar kawat: tiang tiap `step`, panel kawat tembus pandang, rel atas. Garis lurus dari (x1,z1) ke (x2,z2).
function Prefabs.fence(b: any, parent: Instance, name: string, x1: number, z1: number, x2: number, z2: number, g: number)
	local m = b:model(parent, name)
	local dx, dz = x2 - x1, z2 - z1
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.floor(len / 12 + 0.5))
	local yaw = math.atan2(-dz, dx)
	for i = 0, n do
		local t = i / n
		b:part(m, string.format("Post_%02d", i + 1), { size = Vector3.new(0.6, 10, 0.6), cf = CFrame.new(x1 + dx * t, g + 5, z1 + dz * t), color = "Chrome", material = "Metal" })
	end
	local mid = CFrame.new((x1 + x2) / 2, 0, (z1 + z2) / 2) * CFrame.Angles(0, yaw, 0)
	b:part(m, "Mesh_Panel", { size = Vector3.new(len, 9, 0.2), cf = mid + Vector3.new(0, g + 4.5, 0), color = "Chrome", material = "DiamondPlate", transparency = 0.6 })
	b:part(m, "Rail_Top", { size = Vector3.new(len, 0.4, 0.4), cf = mid + Vector3.new(0, g + 9.8, 0), color = "Chrome", material = "Metal" })
	return m
end

return Prefabs
