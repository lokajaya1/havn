--!strict
-- MapGen/Zones/Harbor — R3: pelabuhan kontainer (timur). Jalur efek donasi (NukeCorridor) dibiarkan kosong.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local industrial = { "ContainerRed", "ContainerBlue", "ContainerOrange", "ContainerGreen", "ContainerRed", "ContainerBlue", "Lilac", "ContainerOrange", "IceBlue", "ContainerGreen", "HotPink" }

	-- Yard kontainer: {x, z, tinggi per kolom, yaw}
	local yard = b:folder(nil, "ContainerYard")
	local stacks = {
		{ 120, -248, { 3, 2, 3 }, 0 },
		{ 160, -248, { 2, 3, 1 }, 0 },
		{ 200, -248, { 3, 3, 2 }, 0 },
		{ 170, -215, { 1, 2, 2 }, 0 },
		{ 205, -215, { 2, 1, 3 }, 0 },
		{ 214, -182, { 1, 2 }, 90 },
		{ 214, -20, { 2, 1 }, 90 },
		{ 214, 18, { 1, 2, 1 }, 90 },
	}
	for i, s in stacks do
		Prefabs.stack(b, yard, string.format("ContainerStack_%02d", i), at(s[1], G, s[2], s[4]), s[3], industrial, i * 3)
	end

	-- Derek gantry di atas yard
	Prefabs.crane(b, b:folder(nil, "Cranes"), "Crane_Gantry_01", 180, -150, G)

	-- Gudang (pintu & papan menghadap barat: Plaza / lantai dansa)
	Prefabs.warehouse(b, b:folder(nil, "Buildings"), "Warehouse_Main", 165, -80, G, "HAVN DOCKS")

	-- Pagar kawat sisi barat; celah z −215…−150 = jalur roket efek donasi
	local fences = b:folder(nil, "Fences")
	Prefabs.fence(b, fences, "Fence_West_North", 98, -264, 98, -217, G)
	Prefabs.fence(b, fences, "Fence_West_South", 98, -140, 98, -104, G)

	-- Marka kuning jalur forklift
	local marks = b:folder(nil, "Markings")
	for i, m in { { 170, -231, 110, 1 }, { 152, -100, 1, 80 }, { 190, -120, 70, 1 }, { 190, -40, 1, 120 } } do
		b:part(marks, string.format("LaneLine_%02d", i), { size = Vector3.new(m[3], 0.1, m[4]), cf = CFrame.new(m[1], G + 0.05, m[2]), color = "SafetyYellow", material = "Plastic", decor = true })
	end

	-- Props dari MapKit (mesh map lama)
	local props = b:folder(nil, "Props")
	local list = {
		{ "Kit_DrumFire", "DrumFire_01", 128, -130, 0 },
		{ "Kit_DrumFire", "DrumFire_02", 150, -95, 0 },
		{ "Kit_DrumFire", "DrumFire_03", 205, -120, 0 },
		{ "Kit_TyrePile", "TyrePile_01", 132, -118, 20 },
		{ "Kit_TyrePile", "TyrePile_02", 225, -150, 0 },
		{ "Kit_BoxPile", "BoxPile_01", 190, -110, 0 },
		{ "Kit_BoxPile", "BoxPile_02", 120, -60, 90 },
		{ "Kit_TrafficCone", "TrafficCone_01", 108, -100, 0 },
		{ "Kit_TrafficCone", "TrafficCone_02", 112, -96, 30 },
		{ "Kit_TrafficCone", "TrafficCone_03", 160, -30, 0 },
		{ "Kit_Barrier", "Barrier_01", 120, -10, 0 },
		{ "Kit_Barrier", "Barrier_02", 150, 20, 90 },
		{ "Kit_CarRusty", "CarRusty_01", 125, -35, 35 },
	}
	for _, p in list do
		b:clone(props, p[1], at(p[3], G, p[4], p[5]), p[2])
	end
	local lights = b:folder(nil, "Lights")
	for i, p in { { 104, -250 }, { 104, -120 }, { 104, -40 }, { 104, 30 }, { 160, -175 }, { 225, -95 } } do
		b:clone(lights, "Kit_StreetLight", at(p[1], G, p[2], 90), string.format("StreetLight_%02d", i))
	end
end
