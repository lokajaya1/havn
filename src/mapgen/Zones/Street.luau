--!strict
-- MapGen/Zones/Street — jalan klub selatan (x −44…164): marka aspal, penyeberangan di sumbu spawn, deret toko Y2K
-- 2 lantai sebagai dinding batas selatan (muka ke utara), lampu jalan / halte / bangku / hidran / pot (City Props resmi
-- Roblox), mesin arcade, telepon umum, vending di depan toko. Semua dasar tepat di lantai y 6.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local R, W = L.road, L.sidewalk

	-- marka: garis tengah putus-putus (lewati penyeberangan), zebra cross x −12…12
	local marks = b:folder(nil, "Markings")
	local n = 0
	for x = R.minX + 6, R.maxX - 6, 12 do
		if math.abs(x) > 16 then
			n += 1
			b:part(marks, string.format("Lane_Dash_%02d", n), { size = Vector3.new(6, 0.05, 0.6), cf = CFrame.new(x, G + 0.025, (R.minZ + R.maxZ) / 2), color = "White", material = "Plastic", decor = true })
		end
	end
	for i, x in { -10, -6, -2, 2, 6, 10 } do
		b:part(marks, string.format("Crosswalk_%02d", i), { size = Vector3.new(2, 0.05, R.maxZ - R.minZ - 2), cf = CFrame.new(x, G + 0.025, (R.minZ + R.maxZ) / 2), color = "White", material = "Plastic", decor = true })
	end

	-- deret toko (z 76…100): barat 1, timur 5 × 28 stud; celah x −24…24 = plaza spawn
	local shops = b:folder(nil, "Shops")
	local zf, depth = W.maxZ, 24
	Prefabs.storefront(b, shops, -44, -24, zf, depth, G, { name = "Shop_Surf", text = "SURF SHOP", body = "PastelMint", accent = "IceBlue", awning = "Lilac" })
	local east = {
		{ name = "Shop_Arcade", text = "ARCADE 2000", body = "Lilac", accent = "Lime", awning = "HotPink" },
		{ name = "Shop_Records", text = "HAVN RECORDS", body = "Cream", accent = "HotPink", awning = "Asphalt", shutter = true },
		{ name = "Shop_CyberCafe", text = "CYBER CAFE", body = "PastelBlue", accent = "IceBlue", awning = "ContainerBlue" },
		{ name = "Shop_PhoneZone", text = "PHONE ZONE", body = "PastelPink", accent = "HotPink", awning = "Chrome" },
		{ name = "Shop_Boba", text = "BOBA Y2K", body = "Cream", accent = "Lime", awning = "PastelMint" },
	}
	for i, s in east do
		Prefabs.storefront(b, shops, 24 + (i - 1) * 28, 24 + i * 28, zf, depth, G, s)
	end

	-- perabot jalan (trotoar z 64…76)
	local props = b:folder(nil, "Props")
	b:clone(props, "Kit_ArcadeMachines", at(38, G, 74, 90), "ArcadeMachines_01")
	b:clone(props, "Kit_PhoneBooth", at(122, G, 73.5, 180), "PhoneBooth_01")
	b:clone(props, "Kit_VendingMachine", at(150, G, 73, 180), "VendingMachine_01")
	b:clone(props, "Bus_Stop_01_A", at(96, G, 68, 0), "BusStop_01")
	b:seat(props, "Seat_BusStop_01", CFrame.new(96, G + 1.8, 68), Vector3.new(14, 0.4, 1.6))
	for i, p in { { -34, 67 }, { -20, 67 }, { 20, 67 } } do
		b:clone(props, "MetalBench_01_A", at(p[1], G, p[2], 90), string.format("Bench_%02d", i))
		b:seat(props, string.format("Seat_Bench_%02d", i), CFrame.new(p[1], G + 1.8, p[2]), Vector3.new(7, 0.4, 1.6))
	end
	for i, x in { 64, 132 } do
		b:clone(props, "Planter_Rectangle_01_A", at(x, G, 66.5, 0), string.format("Planter_%02d", i))
	end
	for i, x in { 50, 140 } do
		b:clone(props, "FireHydrant_01_A", at(x, G, 65.5, 0), string.format("Hydrant_%02d", i))
	end
	local lights = b:folder(nil, "Lights")
	-- tiang kit ada di sisi −Z mesh, lampu di +Z → diputar 180°: tiang di trotoar (z ≈ 67), lampu menjorok ke atas jalan
	for i, x in { -40, 28, 78, 112, 144 } do
		b:clone(lights, "StreetLightPole_01_A", at(x, G, 62.9, 180), string.format("StreetLight_%02d", i))
	end
end
