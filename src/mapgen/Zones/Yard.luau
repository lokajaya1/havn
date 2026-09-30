--!strict
-- MapGen/Zones/Yard — halaman pelabuhan timur (x 92…152, z −148…−64): gudang atap gergaji "HAVN DOCKS" menghadap barat
-- (latar papan donasi), forklift, palet & peti, drum, ban, kontainer, lampu jalan resmi.
-- S1 (sentuhan user): papan "DOCKS", 2 lampu & tumpukan peti/palet digeser ke utara (menjauh dari dinding donasi); lampu
-- selatan +10 dari posisi tangan user supaya tiangnya keluar dari jalur roket Nuke (P: radius 6, cek kotak MapGen).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	Prefabs.warehouse(b, b:folder(nil, "Buildings"), "Warehouse_Main", 130, -106, G, "DOCKS", 36, 48)
	local yard = b:folder(nil, "ContainerYard")
	Prefabs.containerStack(b, yard, "ContainerStack_01", 127, -71, G, 2, 0, 2)
	local props = b:folder(nil, "Props")
	b:clone(props, "Kit_Forklift", at(100, G, -140, 0), "Forklift_01")
	b:clone(props, "Kit_Pallet", at(98, G, -113, 0), "Pallet_01")
	b:clone(props, "Kit_Crate", at(97, G + 1.087, -114, 0), "Crate_01", 1.8)
	b:clone(props, "Kit_Crate", at(99.5, G + 1.087, -111.5, 15), "Crate_02", 1.8)
	b:clone(props, "Kit_Crate", at(98, G + 1.087 + 3.6, -113, 40), "Crate_03", 1.8)
	for n, p in { { 96, -122 }, { 97.8, -123 }, { 96.7, -120.4 }, { 99, -121 } } do
		b:clone(props, "Kit_OilBarrel", at(p[1], G, p[2], n * 35), string.format("OilBarrel_%02d", n), 1.4)
	end
	b:clone(props, "Kit_TireStack", at(146, G, -142, 0), "TireStack_01", 1.4)
	b:clone(props, "Kit_TireStack", at(148.5, G, -140, 0), "TireStack_02", 1.4)
	local lights = b:folder(nil, "Lights")
	for n, z in { -154.2, -132.2 } do
		Prefabs.facing(b, lights, "StreetLightPole_01_A", 94, G, z, 0, string.format("StreetLight_%02d", n))
	end
end
