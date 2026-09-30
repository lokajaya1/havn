--!strict
-- MapGen/Zones/Quay — dermaga barat laut (x −104…−72, z −188…−64): derek STS teal = landmark yang terlihat dari
-- lantai dansa & pantai (lengan di atas teluk), tambat baja, garis kuning tepi, ban fender, tumpukan kontainer, props.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local q = L.quayWall
	Prefabs.stsCrane(b, b:folder(nil, "Cranes"), "Crane_STS_01", { xSea = -100, xLand = -76, zc = -126, gauge = 16, boomTip = -164, boomBack = -62, g = G })

	-- tepi dermaga: garis kuning, tambat tiap 16 stud, ban fender di muka dinding (menghadap air)
	local edge = b:folder(nil, "QuayEdge")
	b:part(edge, "Edge_Line", { size = Vector3.new(1, 0.1, q.maxZ - q.minZ - 20), cf = CFrame.new(q.x2 + 0.5, G + 0.05, (q.minZ + 20 + q.maxZ) / 2), color = "SafetyYellow", material = "Plastic", decor = true })
	local i = 0
	for z = -180, -72, 16 do
		i += 1
		Prefabs.bollard(b, edge, string.format("Bollard_%02d", i), q.x2 + 2, z, G)
		b:part(edge, string.format("Fender_%02d", i), { size = Vector3.new(0.9, 2.8, 2.8), cf = CFrame.new(q.x1 - 0.45, 2, z + 8), color = "Asphalt", material = "Plastic", shape = "Cylinder", allowBelowGround = true })
	end

	-- kontainer di dermaga (utara derek), memanjang ke arah Z
	local yard = b:folder(nil, "ContainerYard")
	Prefabs.containerStack(b, yard, "ContainerStack_01", -94, -171, G, 2, 90, 1)
	Prefabs.containerStack(b, yard, "ContainerStack_02", -82, -171, G, 1, 90, 3)

	-- props pelabuhan (selatan derek)
	local props = b:folder(nil, "Props")
	b:clone(props, "Kit_Forklift", at(-92, G, -84, 90), "Forklift_01")
	b:clone(props, "Kit_Pallet", at(-82, G, -96, 0), "Pallet_01")
	b:clone(props, "Kit_Crate", at(-83, G + 1.087, -97, 0), "Crate_01", 1.8)
	b:clone(props, "Kit_Crate", at(-80.5, G + 1.087, -94.5, 20), "Crate_02", 1.8)
	b:clone(props, "Kit_Pallet", at(-82, G, -106, 90), "Pallet_02")
	for n, p in { { -96, -100 }, { -94.2, -101 }, { -95.3, -98.4 } } do
		b:clone(props, "Kit_OilBarrel", at(p[1], G, p[2], n * 40), string.format("OilBarrel_%02d", n), 1.4)
	end
	b:clone(props, "Kit_TireStack", at(-78, G, -72, 0), "TireStack_01", 1.4)

	-- lampu jalan resmi Roblox (City Props) di sisi darat dermaga
	local lights = b:folder(nil, "Lights")
	for n, z in { -150, -96 } do
		b:clone(lights, "StreetLightPole_01_A", at(-74, G, z, 0), string.format("StreetLight_%02d", n))
	end
end
