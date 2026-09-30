--!strict
-- MapGen/Zones/VipLounge — VIP PAVILION timur (R5): kotak hitam 2 lantai menghadap panggung (barat). Lantai dasar = lounge
-- dengan fasad kaca gelap + pintu 10 × 11, bar dengan rak backlit putih; atap = dek VIP y 18 (ruang di bawah 11 ≥ A1) dengan
-- pagar kaca bening, naik lewat tangga luar lebar 10 (anak tangga 0.6) + landasan. Pola map club: VIP DITINGGIKAN.
-- Area x 96…151, z −8…39 dikelilingi dinding tak terlihat CollisionGroup "DoorVIP" (VIP & VVIP tembus, pemain biasa
-- terhalang — PlayerCollisionManager, pengganti `Vip Door02` lama). Lantai atas: dek x 100…128 (y 16) menghadap barat.
-- Lantai dasar: bar kontainer VIP + sofa. Semua Seat menghadap barat (dek) / timur (kursi bar).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local x1, x2, z1, z2 = 96, 151, -8, 39 -- dinding (tebal 1) di luar garis ini, tetap di dalam zona x 92…152, z −64…40

	-- dinding DoorVIP (tak terlihat) di keliling area
	local walls = b:folder(nil, "VipWalls")
	local H = 30
	for _, w in {
		{ "Wall_West", x1 - 0.5, (z1 + z2) / 2, 1, z2 - z1 + 2 },
		{ "Wall_East", x2 + 0.5, (z1 + z2) / 2, 1, z2 - z1 + 2 },
		{ "Wall_North", (x1 + x2) / 2, z1 - 0.5, x2 - x1, 1 },
		{ "Wall_South", (x1 + x2) / 2, z2 + 0.5, x2 - x1, 1 },
	} do
		b:part(walls, w[1], { size = Vector3.new(w[4], H, w[5]), cf = CFrame.new(w[2], G + H / 2, w[3]), transparency = 1, collisionGroup = "DoorVIP" })
	end

	-- tanda batas VIP (R3): tiang antre hitam + tali putih (warna kit diubah Palette.kitRecolor), gerbang PORTAL hitam
	-- bahasa sama dengan gerbang HAVN: bukaan 12 × 12, garis neon putih 0.2 di sisi dalam, huruf "VIP" putih di balok atas.
	local edge = b:folder(nil, "Edge")
	for i, z in { -4, 4.5, 27, 35 } do
		b:clone(edge, "Kit_VipRope", at(x1 + 1.5, G, z, 0), string.format("VipRope_%02d", i), 0.95)
	end
	local gate = b:model(edge, "Gate_VIP")
	local gx, gzc, gw, gh = x1 + 1, 16, 12, 12
	for i, side in { -1, 1 } do
		b:part(gate, "Column_0" .. i, { size = Vector3.new(1, gh + 1.5, 1), cf = CFrame.new(gx, G + (gh + 1.5) / 2, gzc + side * (gw / 2 + 0.5)), color = "Black", material = "Metal" })
		b:part(gate, "Neon_Inner_0" .. i, { size = Vector3.new(0.2, gh, 0.2), cf = CFrame.new(gx, G + gh / 2, gzc + side * (gw / 2 - 0.1)), color = "NeonWhite", material = "Neon" })
	end
	local lintel = b:part(gate, "Lintel", { size = Vector3.new(1, 1.5, gw + 2), cf = CFrame.new(gx, G + gh + 0.75, gzc), color = "Black", material = "Metal" })
	b:part(gate, "Neon_Inner_Top", { size = Vector3.new(0.2, 0.2, gw), cf = CFrame.new(gx, G + gh - 0.1, gzc), color = "NeonWhite", material = "Neon" })
	b:sign(lintel, "VIP", "Left", "NeonWhite")
	b:sign(lintel, "VIP", "Right", "NeonWhite")

	-- R5 pavilion menempel dinding DoorVIP utara & timur (tanpa lorong sempit, A4): x 121…151, z −8…29; atap y 17…18;
	-- tangga luar lebar 10 di selatan (z 29…39, menempel dinding selatan) naik ke barat sampai x 131 + landasan x 121…131
	local px1, px2, pz1, pz2 = x1 + 25, x2, z1, z2 - 10
	local dz1, dz2 = 11, 21 -- pintu segaris gerbang VIP (z 10…22)
	local roofY = G + 12 -- 18
	local pav = b:model(b:folder(nil, "Pavilion"), "Pavilion_Main")
	local function slab(name: string, ax: number, bx: number, y1: number, y2: number, az: number, bz: number, colorKey: string, material: string, extra: { [string]: any }?)
		local spec: { [string]: any } = { size = Vector3.new(bx - ax, y2 - y1, bz - az), cf = CFrame.new((ax + bx) / 2, (y1 + y2) / 2, (az + bz) / 2), color = colorKey, material = material }
		for k, v in extra or {} do
			spec[k] = v
		end
		return b:part(pav, name, spec :: any)
	end
	slab("Roof", px1, px2, roofY - 1, roofY, pz1, pz2, "Black", "Metal")
	slab("Wall_North", px1, px2, G, roofY - 1, pz1, pz1 + 2, "Black", "Concrete")
	slab("Wall_South", px1, px2, G, roofY - 1, pz2 - 2, pz2, "Black", "Concrete")
	slab("Wall_East", px2 - 2, px2, G, roofY - 1, pz1 + 2, pz2 - 2, "Black", "Concrete")
	-- fasad barat kaca gelap + pintu lebar 10, tinggi 11
	slab("Facade_North", px1, px1 + 1, G, roofY - 1, pz1 + 2, dz1, "Smoke", "Plastic", { transparency = 0.45 })
	slab("Facade_South", px1, px1 + 1, G, roofY - 1, dz2, pz2 - 2, "Smoke", "Plastic", { transparency = 0.45 })
	for i, z in { dz1 - 0.6, dz2 } do -- kusen di LUAR bukaan → lebar bersih tetap 10
		slab("Door_Frame_0" .. i, px1 - 0.2, px1 + 1.2, G, roofY - 1, z, z + 0.6, "Black", "Metal")
	end
	-- parapet + nama "VIP LOUNGE" di tepi barat atap (menghadap panggung), garis neon putih di bawah atap
	local fascia = slab("Fascia_West", px1 - 0.4, px1, roofY - 1, roofY + 1.5, pz1, pz2, "Black", "Metal")
	b:sign(fascia, "VIP LOUNGE", "Left", "NeonWhite")
	b:part(pav, "Neon_Roofline", { size = Vector3.new(0.2, 0.2, pz2 - pz1), cf = CFrame.new(px1 - 0.5, roofY - 1.1, (pz1 + pz2) / 2), color = "NeonWhite", material = "Neon", decor = true })
	-- lampu langit-langit lembut (sumber tersembunyi)
	local roof = pav:FindFirstChild("Roof") :: BasePart
	b:surfaceLight(roof, "Bottom", "CoolLight", 0.6, 12, 120)

	-- tangga luar + landasan padat (tanpa kolong) → atap
	local stairsF = b:folder(nil, "Stairs")
	Prefabs.stairs(b, stairsF, "Stairs_Main", px2, pz2, pz2 + 10, G, roofY - G, 0.6)
	local land = b:model(stairsF, "Landing")
	b:part(land, "Landing_Base", { size = Vector3.new(10, roofY - G, 10), cf = CFrame.new(px1 + 5, (G + roofY) / 2, pz2 + 5), color = "Black", material = "Concrete" })
	-- pagar kaca bening 3.5 (tepi atap & landasan), terbuka 10 di jalur landasan → atap (x 121…131, z 29)
	local rails = b:folder(nil, "Rails")
	local function rail(name: string, ax: number, bx: number, az: number, bz: number)
		b:part(rails, name, { size = Vector3.new(math.max(bx - ax, 0.3), 3.5, math.max(bz - az, 0.3)), cf = CFrame.new((ax + bx) / 2, roofY + 1.75, (az + bz) / 2), color = "Smoke", material = "Plastic", transparency = 0.6 })
	end
	rail("Rail_North", px1, px2, pz1, pz1 + 0.3)
	rail("Rail_West", px1, px1 + 0.3, pz1, pz2)
	rail("Rail_East", px2 - 0.3, px2, pz1, pz2)
	rail("Rail_South", px1 + 10, px2, pz2 - 0.3, pz2)
	rail("Rail_Landing_South", px1, px1 + 10, pz2 + 9.7, pz2 + 10)
	rail("Rail_Landing_West", px1, px1 + 0.3, pz2, pz2 + 10)

	-- perabot atap: meja tinggi & kursi telur menghadap panggung (barat), speaker
	local deckF = b:folder(nil, "DeckFurniture")
	Prefabs.seatFacing(b, deckF, "Kit_HighTable", px1 + 6.5, roofY, 1, 90, "HighTable_01")
	Prefabs.seatFacing(b, deckF, "Kit_HighTable", px1 + 6.5, roofY, 19, 90, "HighTable_02")
	Prefabs.seatFacing(b, deckF, "Kit_EggChair", px1 + 18, roofY, 3, 90, "EggChair_01")
	Prefabs.seatFacing(b, deckF, "Kit_EggChair", px1 + 18, roofY, 17, 90, "EggChair_02")
	for i, z in { pz1 + 3, pz2 - 3 } do
		Prefabs.facing(b, deckF, "Kit_SpeakerTripod", px1 + 2.5, roofY, z, 90, string.format("Speaker_%02d", i)) -- ke panggung (barat)
	end

	-- lantai dasar: bar (meja hitam, atas putih) + rak backlit putih di dinding timur, 4 kursi bar menghadap meja, sofa
	local bar = b:model(b:folder(nil, "VipBar"), "VipBar_Main")
	local bzc = (pz1 + pz2) / 2 + 2 -- 12.5
	b:part(bar, "Counter", { size = Vector3.new(2, 3.5, 18), cf = CFrame.new(px2 - 9, G + 1.75, bzc), color = "Black", material = "Plastic" })
	local top = b:part(bar, "Counter_Top", { size = Vector3.new(2.4, 0.2, 18.4), cf = CFrame.new(px2 - 9, G + 3.6, bzc), color = "OffWhite", material = "Plastic" })
	b:surfaceLight(top, "Top", "WarmLight", 1, 8, 90)
	local shelf = b:part(bar, "BackShelf", { size = Vector3.new(1, 6, 18), cf = CFrame.new(px2 - 2.5, G + 6, bzc), color = "Black", material = "Metal" })
	b:surfaceLight(shelf, "Left", "CoolLight", 1.2, 8, 90)
	for i, y in { 4, 6, 8 } do
		b:part(bar, "Neon_Shelf_0" .. i, { size = Vector3.new(0.2, 0.2, 18), cf = CFrame.new(px2 - 3.1, G + y, bzc), color = "NeonWhite", material = "Neon", decor = true })
	end
	local vipSign = b:part(bar, "Sign_Bar", { size = Vector3.new(0.3, 2, 10), cf = CFrame.new(px2 - 3.15, G + 10, bzc), color = "Black", material = "Metal" })
	b:sign(vipSign, "VIP BAR", "Left", "NeonWhite")
	for i, dz in { -6.75, -2.25, 2.25, 6.75 } do
		Prefabs.seatFacing(b, bar, "Kit_BarStool", px2 - 12.5, G, bzc + dz, -90, string.format("BarStool_%02d", i))
	end
	Prefabs.seatFacing(b, b:folder(nil, "Lounge"), "Kit_NeonSofa", px1 + 10, G, pz1 + 5.5, 180, "NeonSofa_01") -- menempel dinding utara
end
