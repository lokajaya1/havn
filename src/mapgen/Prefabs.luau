--!strict
-- MapGen/Prefabs — objek industrial Y2K. Bangunan besar dari part (derek, gudang, pagar, landasan); mesh dari
-- ServerStorage.MapKit lewat Builder:clone (kontainer PBR 30×10×10, props pelabuhan). Semua lewat Builder.

local KitFront = require(script.Parent.KitFront)

local Prefabs = {}

local function at(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end
Prefabs.at = at

-- Warna kontainer mesh di MapKit.Import (SurfaceAppearance, warna tetap dari tekstur).
Prefabs.containerKits = { "ContainerRed", "ContainerBlue", "ContainerYellow", "ContainerGreen" }

-- Tumpukan kontainer mesh: `tiers` tingkat di (x, z), yaw 0 = panjang di sumbu X. Tiap tingkat menapak tepat di atas
-- tingkat bawahnya (tinggi diambil dari mesh). seed memilih warna bergilir.
function Prefabs.containerStack(b: any, parent: Instance, name: string, x: number, z: number, g: number, tiers: number, yaw: number, seed: number)
	local m = b:model(parent, name)
	local y = g
	for t = 1, tiers do
		local kit = Prefabs.containerKits[((seed + t - 2) % #Prefabs.containerKits) + 1]
		local _, size = b:clone(m, kit, at(x, y, z, yaw), string.format("Container_%s_%02d", string.sub(kit, 10), t))
		y += if size.Y > 0 then size.Y else 10
	end
	return m
end

-- Derek kapal-ke-darat (STS): 4 kaki di dermaga, lengan (boom) di atas air ke arah −X, menara & tali penahan,
-- rumah mesin di belakang, kabin, troli + spreader + kontainer menggantung. Aksen neon Y2K.
export type CraneSpec = { xSea: number, xLand: number, zc: number, gauge: number, boomTip: number, boomBack: number, g: number }
function Prefabs.stsCrane(b: any, parent: Instance, name: string, s: CraneSpec)
	local m = b:model(parent, name)
	local g, zc, hz = s.g, s.zc, s.gauge / 2
	local H = 50 -- tinggi kaki
	local boomY = g + H + 3 -- bawah lengan
	local teal, metal = "CraneTeal", "Metal"
	for _, c in { { "SeaNorth", s.xSea, zc - hz }, { "SeaSouth", s.xSea, zc + hz }, { "LandNorth", s.xLand, zc - hz }, { "LandSouth", s.xLand, zc + hz } } do
		b:part(m, "Leg_" .. c[1], { size = Vector3.new(3, H, 3), cf = CFrame.new(c[2], g + H / 2, c[3]), color = teal, material = metal })
		b:part(m, "Band_Leg_" .. c[1], { size = Vector3.new(3.3, 1, 3.3), cf = CFrame.new(c[2], g + 30, c[3]), color = "Black", material = "Metal" })
		b:part(m, "Bogie_" .. c[1], { size = Vector3.new(4, 2, 5), cf = CFrame.new(c[2], g + 1, c[3]), color = "Steel", material = metal })
	end
	local span = math.abs(s.xLand - s.xSea)
	local midX = (s.xLand + s.xSea) / 2
	for _, z in { { "North", zc - hz }, { "South", zc + hz } } do
		b:part(m, "Brace_" .. z[1], { size = Vector3.new(span, 2.5, 2), cf = CFrame.new(midX, g + 28, z[2]), color = teal, material = metal })
	end
	for _, x in { { "Sea", s.xSea }, { "Land", s.xLand } } do
		b:part(m, "Portal_" .. x[1], { size = Vector3.new(3, 3, s.gauge + 3), cf = CFrame.new(x[2], g + H + 1.5, zc), color = teal, material = metal })
	end
	-- lengan: 2 girder sejajar + ikatan silang
	local boomLen = s.boomBack - s.boomTip
	local boomMid = (s.boomBack + s.boomTip) / 2
	for _, z in { { "North", zc - 5 }, { "South", zc + 5 } } do
		b:part(m, "Boom_" .. z[1], { size = Vector3.new(boomLen, 4, 2.5), cf = CFrame.new(boomMid, boomY + 2, z[2]), color = teal, material = metal })
	end
	local nTie = math.floor(boomLen / 12)
	for i = 0, nTie do
		local x = s.boomTip + i * boomLen / nTie
		b:part(m, string.format("Boom_Tie_%02d", i + 1), { size = Vector3.new(1, 1, 10), cf = CFrame.new(x, boomY + 3.5, zc), color = teal, material = metal })
	end
	b:part(m, "Neon_Boom", { size = Vector3.new(boomLen, 0.4, 0.4), cf = CFrame.new(boomMid, boomY - 0.2, zc), color = "IceBlue", material = "Neon" })
	-- menara di atas kaki darat + tali penahan ke ujung lengan & ke belakang
	local apexY = boomY + 22
	for _, z in { { "North", zc - 5 }, { "South", zc + 5 } } do
		b:part(m, "Tower_" .. z[1], { size = Vector3.new(2.5, apexY - boomY - 4, 2.5), cf = CFrame.new(s.xLand, (boomY + 4 + apexY) / 2, z[2]), color = teal, material = metal })
		for _, t in { { "Front", s.boomTip + 2 }, { "Back", s.boomBack - 2 } } do
			local a, bb = Vector3.new(s.xLand, apexY, z[2]), Vector3.new(t[2], boomY + 4, z[2])
			b:part(m, "Stay_" .. t[1] .. "_" .. z[1], { size = Vector3.new(0.7, 0.7, (bb - a).Magnitude), cf = CFrame.lookAt((a + bb) / 2, bb), color = "Steel", material = metal })
		end
	end
	b:part(m, "Tower_Cap", { size = Vector3.new(3, 2, 13), cf = CFrame.new(s.xLand, apexY + 1, zc), color = teal, material = metal })
	b:part(m, "Neon_Tower_Cap", { size = Vector3.new(0.3, 0.3, 13.2), cf = CFrame.new(s.xLand, apexY + 2.15, zc), color = "NeonWhite", material = "Neon" })
	-- rumah mesin (belakang) & kabin operator (di bawah lengan, sisi laut)
	b:part(m, "Machinery_House", { size = Vector3.new(10, 8, 14), cf = CFrame.new(s.boomBack - 6, boomY + 8, zc), color = "Chrome", material = "Chrome" })
	b:part(m, "Neon_Machinery", { size = Vector3.new(0.3, 0.3, 14.2), cf = CFrame.new(s.boomBack - 11.15, boomY + 11.85, zc), color = "NeonWhite", material = "Neon" })
	b:part(m, "Cab", { size = Vector3.new(6, 6, 6), cf = CFrame.new(s.xSea - 6, boomY - 3, zc), color = "Chrome", material = "Chrome" })
	b:part(m, "Cab_Glass", { size = Vector3.new(0.3, 3.5, 5.4), cf = CFrame.new(s.xSea - 9.1, boomY - 3, zc), color = "IceBlue", material = "Glass", transparency = 0.35 })
	-- troli, kabel, spreader, kontainer menggantung di atas air
	local tx = s.boomTip + 24
	b:part(m, "Trolley", { size = Vector3.new(8, 3, 12), cf = CFrame.new(tx, boomY - 1.5, zc), color = "Steel", material = metal })
	local spreadTop = boomY - 18
	for i, dz in { -3.5, 3.5 } do
		for j, dx in { -10, 10 } do
			b:part(m, string.format("Cable_%02d", (i - 1) * 2 + j), { size = Vector3.new(0.3, boomY - 3 - spreadTop, 0.3), cf = CFrame.new(tx + dx * 0.3, (boomY - 3 + spreadTop) / 2, zc + dz), color = "Steel", material = metal, decor = true })
		end
	end
	b:part(m, "Spreader", { size = Vector3.new(30, 1.2, 10), cf = CFrame.new(tx, spreadTop - 0.6, zc), color = "SafetyYellow", material = metal })
	b:clone(m, "ContainerBlue", at(tx, spreadTop - 1.2 - 9.962, zc), "Container_Hanging")
	-- rel kaki di dermaga
	return m
end

-- Gudang atap gergaji: dinding bergelombang, 3 gigi atap + kaca, 3 pintu gulung di sisi barat, neon, papan nama.
function Prefabs.warehouse(b: any, parent: Instance, name: string, cx: number, cz: number, g: number, sign: string, W: number, D: number)
	local m = b:model(parent, name)
	local H = 24
	local function wall(n: string, sx: number, sz: number, x: number, z: number)
		b:part(m, n, { size = Vector3.new(sx, H, sz), cf = CFrame.new(x, g + H / 2, z), color = "ContainerBlue", material = "Corrugated" })
	end
	wall("Wall_North", W, 1, cx, cz - D / 2 + 0.5)
	wall("Wall_South", W, 1, cx, cz + D / 2 - 0.5)
	wall("Wall_East", 1, D - 2, cx + W / 2 - 0.5, cz)
	wall("Wall_West", 1, D - 2, cx - W / 2 + 0.5, cz)
	for i = 1, 3 do
		local x = cx - W / 2 + (i - 0.5) * (W / 3)
		b:part(m, "Roof_Tooth_0" .. i, { size = Vector3.new(D, 6, W / 3), cf = CFrame.new(x, g + H + 3, cz) * CFrame.Angles(0, math.rad(90), 0), color = "Rust", material = "Corrugated", shape = "Wedge" })
		b:part(m, "Roof_Glass_0" .. i, { size = Vector3.new(0.4, 5.6, D - 1), cf = CFrame.new(x + W / 6 - 0.3, g + H + 3, cz), color = "IceBlue", material = "Glass", transparency = 0.35 })
	end
	local doorZ = { -D / 3.2, 0, D / 3.2 }
	for i, z in doorZ do
		b:part(m, "Door_Roll_0" .. i, { size = Vector3.new(0.4, 14, 10), cf = CFrame.new(cx - W / 2 - 0.2, g + 7, cz + z), color = "Steel", material = "DiamondPlate" })
		b:part(m, "Neon_Door_0" .. i, { size = Vector3.new(0.4, 0.6, 10), cf = CFrame.new(cx - W / 2 - 0.3, g + 14.3, cz + z), color = if i == 2 then "Lime" else "HotPink", material = "Neon" })
	end
	b:part(m, "Neon_Roofline", { size = Vector3.new(0.5, 0.6, D), cf = CFrame.new(cx - W / 2 - 0.25, g + H - 0.3, cz), color = "IceBlue", material = "Neon" })
	b:part(m, "LoadingDock", { size = Vector3.new(8, 1.5, D), cf = CFrame.new(cx - W / 2 - 4, g + 0.75, cz), color = "Concrete", material = "Concrete" })
	b:part(m, "Dock_Edge", { size = Vector3.new(0.4, 1.6, D), cf = CFrame.new(cx - W / 2 - 8.2, g + 0.8, cz), color = "SafetyYellow", material = "Plastic" })
	local board = b:part(m, "Sign_Board", { size = Vector3.new(0.6, 5, 26), cf = CFrame.new(cx - W / 2 - 0.3, g + H - 4.5, cz), color = "Steel", material = "Metal" })
	b:sign(board, sign, "Left", "HotPink")
	return m
end

-- Landasan roket donasi (tepat di bawah NukeLaunch): cakram baja Ø16 + tepi neon + tanda silang + 2 suar rendah
-- (sisi timur dibiarkan kosong: dinding kontainer timur mulai x 153).
function Prefabs.launchPad(b: any, parent: Instance, name: string, x: number, z: number, g: number)
	local m = b:model(parent, name)
	local up = CFrame.Angles(0, 0, math.rad(90))
	b:part(m, "Pad_Rim", { size = Vector3.new(0.2, 17, 17), cf = CFrame.new(x, g + 0.1, z) * up, color = "OffWhite", material = "Plastic", shape = "Cylinder" })
	b:part(m, "Pad_Disk", { size = Vector3.new(0.4, 16, 16), cf = CFrame.new(x, g + 0.2, z) * up, color = "Steel", material = "DiamondPlate", shape = "Cylinder" })
	for i, yaw in { 45, -45 } do
		b:part(m, "Mark_Cross_0" .. i, { size = Vector3.new(11, 0.1, 1.2), cf = CFrame.new(x, g + 0.45, z) * CFrame.Angles(0, math.rad(yaw), 0), color = "SafetyYellow", material = "Plastic", decor = true })
	end
	for i, d in { { 0, -11 }, { 0, 11 } } do
		b:part(m, "Beacon_Pole_0" .. i, { size = Vector3.new(8, 0.8, 0.8), cf = CFrame.new(x + d[1], g + 4, z + d[2]) * up, color = "Chrome", material = "Metal", shape = "Cylinder" })
		b:part(m, "Beacon_Light_0" .. i, { size = Vector3.new(0.8, 0.8, 0.8), cf = CFrame.new(x + d[1], g + 8.4, z + d[2]), color = "NeonWhite", material = "Neon", shape = "Ball" })
	end
	return m
end

-- Toko Y2K 2 lantai (lantai dasar 14, atas 11 stud — tinggi lantai komersial ±3.9 m): muka menghadap utara (−Z) di
-- zFront, kaca etalase + bingkai krom, awning ≥ 10 stud di atas trotoar, papan neon bernama, jendela atas, parapet.
export type ShopSpec = { name: string, text: string, body: string, accent: string, awning: string, shutter: boolean? }
function Prefabs.storefront(b: any, parent: Instance, x1: number, x2: number, zFront: number, depth: number, g: number, s: ShopSpec)
	local m = b:model(parent, s.name)
	local w = x2 - x1
	local cx = (x1 + x2) / 2
	local H = 25
	local zf = zFront + 1 -- muka bangunan (1 stud di belakang garis trotoar untuk bingkai & kaca)
	b:part(m, "Body", { size = Vector3.new(w - 1, H, depth - 1), cf = CFrame.new(cx, g + H / 2, zf + (depth - 1) / 2), color = s.body, material = "Concrete" })
	b:part(m, "Parapet", { size = Vector3.new(w - 1, 1, depth - 1), cf = CFrame.new(cx, g + H + 0.5, zf + (depth - 1) / 2), color = "Chrome", material = "Chrome" })
	-- lantai dasar: etalase kaca / rolling door, bingkai krom, kickplate
	local gw = w - 6
	if s.shutter then
		b:part(m, "Shutter", { size = Vector3.new(gw, 10, 0.4), cf = CFrame.new(cx, g + 5, zf - 0.2), color = "Steel", material = "DiamondPlate" })
	else
		b:part(m, "Window_Shop", { size = Vector3.new(gw, 9, 0.3), cf = CFrame.new(cx, g + 5.5, zf - 0.15), color = "IceBlue", material = "Glass", transparency = 0.35 })
		b:part(m, "Kickplate", { size = Vector3.new(gw, 1, 0.5), cf = CFrame.new(cx, g + 0.5, zf - 0.25), color = "Chrome", material = "Chrome" })
	end
	for i, dx in { -gw / 2 - 0.5, gw / 2 + 0.5 } do
		b:part(m, "Frame_Post_0" .. i, { size = Vector3.new(1, 11, 0.8), cf = CFrame.new(cx + dx, g + 5.5, zf - 0.4), color = "Chrome", material = "Chrome" })
	end
	b:part(m, "Frame_Head", { size = Vector3.new(gw + 2, 1, 0.8), cf = CFrame.new(cx, g + 11.5, zf - 0.4), color = "Chrome", material = "Chrome" })
	-- awning miring (bawah 12 stud di atas lantai) menjorok 4 stud ke trotoar
	b:part(m, "Awning", { size = Vector3.new(gw + 2, 1.5, 4), cf = CFrame.new(cx, g + 12.75, zf - 2) * CFrame.Angles(math.rad(-12), 0, 0), color = s.awning, material = "Plastic" })
	-- papan neon nama toko
	local board = b:part(m, "Sign_Board", { size = Vector3.new(gw, 4, 0.6), cf = CFrame.new(cx, g + 16.5, zf - 0.3), color = "Asphalt", material = "Metal" })
	b:sign(board, s.text, "Front", s.accent)
	for i, dy in { -2.2, 2.2 } do
		b:part(m, "Neon_Sign_0" .. i, { size = Vector3.new(gw, 0.3, 0.3), cf = CFrame.new(cx, g + 16.5 + dy, zf - 0.45), color = s.accent, material = "Neon" })
	end
	-- lantai atas: 2 jendela kaca biru es + ambang krom
	for i, dx in { -w / 4, w / 4 } do
		b:part(m, "Window_Upper_0" .. i, { size = Vector3.new(w / 3, 5, 0.3), cf = CFrame.new(cx + dx, g + 21.5, zf - 0.15), color = "PastelBlue", material = "Glass", transparency = 0.25 })
		b:part(m, "Sill_0" .. i, { size = Vector3.new(w / 3 + 0.6, 0.4, 0.8), cf = CFrame.new(cx + dx, g + 18.8, zf - 0.4), color = "Chrome", material = "Chrome" })
	end
	return m
end

-- Tandai semua part sebuah objek boleh di bawah lantai (tiang di air, benda apung, batu setengah terbenam).
function Prefabs.markBelow(inst: Instance?)
	if not inst then
		return
	end
	if inst:IsA("BasePart") then
		inst:SetAttribute("AllowBelowGround", true)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("AllowBelowGround", true)
		end
	end
end

-- Kursi berjemur Y2K: rangka krom + bantal warna + Seat. Panjang di sumbu X lokal, kepala di +X lokal.
function Prefabs.lounger(b: any, parent: Instance, name: string, cf: CFrame, colorKey: string)
	local m = b:model(parent, name)
	b:part(m, "Frame", { size = Vector3.new(7, 0.4, 2.6), cf = cf * CFrame.new(0, 1.2, 0), color = "Chrome", material = "Chrome" })
	for i, d in { { -3.2, -1.1 }, { -3.2, 1.1 }, { 3.2, -1.1 }, { 3.2, 1.1 } } do
		b:part(m, "Leg_0" .. i, { size = Vector3.new(0.3, 1, 0.3), cf = cf * CFrame.new(d[1], 0.5, d[2]), color = "Chrome", material = "Chrome" })
	end
	b:part(m, "Cushion", { size = Vector3.new(4.4, 0.5, 2.4), cf = cf * CFrame.new(-1, 1.65, 0), color = colorKey, material = "Plastic" })
	b:part(m, "Backrest", { size = Vector3.new(2.8, 0.5, 2.4), cf = cf * CFrame.new(2.2, 2.3, 0) * CFrame.Angles(0, 0, math.rad(35)), color = colorKey, material = "Plastic" })
	b:seat(m, "Seat", cf * CFrame.new(-0.5, 1.95, 0), Vector3.new(4, 0.2, 2))
	return m
end

-- Payung pantai: tiang krom + kanopi cakram + tepi neon.
function Prefabs.umbrella(b: any, parent: Instance, name: string, x: number, z: number, g: number, colorKey: string)
	local m = b:model(parent, name)
	local up = CFrame.Angles(0, 0, math.rad(90))
	b:part(m, "Pole", { size = Vector3.new(8, 0.35, 0.35), cf = CFrame.new(x, g + 4, z) * up, color = "Chrome", material = "Metal", shape = "Cylinder" })
	b:part(m, "Canopy", { size = Vector3.new(0.5, 9, 9), cf = CFrame.new(x, g + 8.25, z) * up, color = colorKey, material = "Fabric", shape = "Cylinder" })
	b:part(m, "Canopy_Rim", { size = Vector3.new(0.2, 9.3, 9.3), cf = CFrame.new(x, g + 7.95, z) * up, color = "OffWhite", material = "Plastic", shape = "Cylinder" })
	return m
end

-- Dermaga kayu di atas air dari (x1) ke laut (x2 < x1), lebar w, dek atas tepat y g; tiang silinder tiap 12 stud
-- sampai dasar laut, pagar krom 3.5 stud di kedua sisi, ujung berbentuk T.
function Prefabs.pier(b: any, parent: Instance, name: string, x1: number, x2: number, zc: number, w: number, g: number, floor: number)
	local m = b:model(parent, name)
	local len = x1 - x2
	local deck = b:part(m, "Deck", { size = Vector3.new(len, 1, w), cf = CFrame.new((x1 + x2) / 2, g - 0.5, zc), color = "Wood", material = "Wood" })
	local head = b:part(m, "Deck_Head", { size = Vector3.new(16, 1, 20), cf = CFrame.new(x2 - 8, g - 0.5, zc), color = "Wood", material = "Wood" })
	local up = CFrame.Angles(0, 0, math.rad(90))
	local n = 0
	local function pylon(x: number, z: number)
		n += 1
		b:part(m, string.format("Pylon_%02d", n), { size = Vector3.new(g - 1 - floor, 1.2, 1.2), cf = CFrame.new(x, (g - 1 + floor) / 2, z) * up, color = "Wood", material = "Wood", shape = "Cylinder" })
	end
	for x = x1 - 6, x2 + 1, -12 do
		pylon(x, zc - w / 2 + 0.6)
		pylon(x, zc + w / 2 - 0.6)
	end
	for _, d in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		pylon(x2 - 8 + d[1] * 7.4, zc + d[2] * 9.4)
	end
	for i, side in { -1, 1 } do
		local z = zc + side * (w / 2 - 0.2)
		b:part(m, "Rail_Top_0" .. i, { size = Vector3.new(len - 2, 0.3, 0.3), cf = CFrame.new((x1 + x2) / 2 - 1, g + 3.5, z), color = "Chrome", material = "Metal" })
		local k = 0
		for x = x1 - 2, x2, -8 do
			k += 1
			b:part(m, string.format("Rail_Post_%d_%02d", i, k), { size = Vector3.new(0.3, 3.5, 0.3), cf = CFrame.new(x, g + 1.75, z), color = "Chrome", material = "Metal" })
		end
	end
	for i, side in { -1, 1 } do
		b:part(m, "Neon_Head_0" .. i, { size = Vector3.new(0.6, 6, 0.6), cf = CFrame.new(x2 - 15.5, g + 3, zc + side * 9.5), color = if i == 1 then "HotPink" else "IceBlue", material = "Neon" })
	end
	Prefabs.markBelow(deck)
	Prefabs.markBelow(head)
	for _, p in m:GetChildren() do
		if string.match(p.Name, "^Pylon_") then
			Prefabs.markBelow(p)
		end
	end
	return m
end

-- Ponton renang apung: dek putih + strip pink + tangga, permukaan dek 0.75 di atas permukaan air.
function Prefabs.pontoon(b: any, parent: Instance, name: string, x: number, z: number, waterY: number)
	local m = b:model(parent, name)
	b:part(m, "Deck", { size = Vector3.new(16, 1.5, 16), cf = CFrame.new(x, waterY, z), color = "White", material = "Plastic", allowBelowGround = true })
	b:part(m, "Stripe", { size = Vector3.new(16.2, 0.3, 16.2), cf = CFrame.new(x, waterY - 0.3, z), color = "HotPink", material = "Plastic", allowBelowGround = true })
	for i, dz in { -1.2, 1.2 } do
		b:part(m, "Ladder_Rail_0" .. i, { size = Vector3.new(0.3, 4, 0.3), cf = CFrame.new(x - 8.3, waterY, z + dz), color = "Chrome", material = "Metal", allowBelowGround = true })
	end
	return m
end

-- Kursi/meja mesh ber-Seat yang diputar supaya Seat-nya menghadap arah `heading` (derajat; 90 = barat/−X,
-- −90 = timur/+X, 0 = utara/−Z). Arah Seat asli dibaca dari kit (Builder:seatHeading).
function Prefabs.seatFacing(b: any, parent: Instance, kit: string, x: number, y: number, z: number, heading: number, name: string, scale: number?)
	local yaw = heading - (b:seatHeading(kit) or 0)
	return b:clone(parent, kit, at(x, y, z, yaw), name, scale, heading)
end

-- Kit berarah diputar supaya SISI DEPAN-nya (KitFront, terukur) menghadap `heading` (derajat; 0 = utara/−Z, 90 = barat/−X,
-- −90 = timur/+X, 180 = selatan/+Z). Kit "any" dipasang tanpa putaran tambahan. Titik (x, z) = tengah kotak pembatas.
function Prefabs.facing(b: any, parent: Instance, kit: string, x: number, y: number, z: number, heading: number, name: string, scale: number?)
	local yaw = heading - (KitFront.headingOf(kit) or heading)
	return b:clone(parent, kit, at(x, y, z, yaw), name, scale, heading)
end

-- Tangga lurus dari lantai g naik `rise` stud ke arah −X mulai x0 (anak tangga 0.5 tinggi × 1 panjang), lebar w.
function Prefabs.stairs(b: any, parent: Instance, name: string, x0: number, z1: number, z2: number, g: number, rise: number)
	local m = b:model(parent, name)
	local n = math.floor(rise / 0.5 + 0.5)
	for k = 1, n do
		local h = k * 0.5
		b:part(m, string.format("Step_%02d", k), { size = Vector3.new(1, h, z2 - z1), cf = CFrame.new(x0 - (k - 0.5), g + h / 2, (z1 + z2) / 2), color = "Steel", material = "DiamondPlate" })
	end
	b:part(m, "Neon_Edge", { size = Vector3.new(n, 0.2, 0.2), cf = CFrame.new(x0 - n / 2, g + rise / 2 + 0.3, z1 + 0.1) * CFrame.Angles(0, 0, math.atan2(-rise, n)), color = "HotPink", material = "Neon", decor = true })
	return m
end

-- Tambat (bollard) baja di tepi dermaga.
function Prefabs.bollard(b: any, parent: Instance, name: string, x: number, z: number, g: number)
	return b:part(parent, name, { size = Vector3.new(1.8, 1.4, 1.4), cf = CFrame.new(x, g + 0.9, z) * CFrame.Angles(0, 0, math.rad(90)), color = "Steel", material = "Metal", shape = "Cylinder" })
end

-- Papan nama rendah di 2 tiang.
function Prefabs.lowSign(b: any, parent: Instance, name: string, x: number, z: number, g: number, text: string, yaw: number)
	local m = b:model(parent, name)
	local base = at(x, g, z, yaw)
	for i, dx in { -8, 8 } do
		b:part(m, "Post_0" .. i, { size = Vector3.new(0.6, 8, 0.6), cf = base * CFrame.new(dx, 4, 0), color = "Chrome", material = "Metal" })
	end
	local board = b:part(m, "Board", { size = Vector3.new(18, 3.5, 0.5), cf = base * CFrame.new(0, 6.5, 0), color = "Steel", material = "Metal" })
	b:sign(board, text, "Front", "Lime")
	b:sign(board, text, "Back", "Lime")
	return m
end

return Prefabs
