--!strict
-- MapGen/Zones/Yard — halaman pelabuhan timur (x 92…152, z −148…−64): gudang atap gergaji "HAVN DOCKS" menghadap barat
-- (latar papan donasi), forklift, palet & peti, drum, ban, kontainer, lampu jalan resmi.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	Prefabs.warehouse(b, b:folder(nil, "Buildings"), "Warehouse_Main", 130, -106, G, "HAVN DOCKS", 36, 48)
	local yard = b:folder(nil, "ContainerYard")
	Prefabs.containerStack(b, yard, "ContainerStack_01", 127, -71, G, 2, 0, 2)
	local props = b:folder(nil, "Props")
	b:clone(props, "Kit_Forklift", at(100, G, -140, 0), "Forklift_01")
	b:clone(props, "Kit_Pallet", at(98, G, -76, 0), "Pallet_01")
	b:clone(props, "Kit_Crate", at(97, G + 1.087, -77, 0), "Crate_01", 1.8)
	b:clone(props, "Kit_Crate", at(99.5, G + 1.087, -74.5, 15), "Crate_02", 1.8)
	b:clone(props, "Kit_Crate", at(98, G + 1.087 + 3.6, -76, 40), "Crate_03", 1.8)
	for n, p in { { 96, -122 }, { 97.8, -123 }, { 96.7, -120.4 }, { 99, -121 } } do
		b:clone(props, "Kit_OilBarrel", at(p[1], G, p[2], n * 35), string.format("OilBarrel_%02d", n), 1.4)
	end
	b:clone(props, "Kit_TireStack", at(146, G, -142, 0), "TireStack_01", 1.4)
	b:clone(props, "Kit_TireStack", at(148.5, G, -140, 0), "TireStack_02", 1.4)
	local lights = b:folder(nil, "Lights")
	for n, z in { -104, -72 } do
		b:clone(lights, "StreetLightPole_01_A", at(94, G, z, 180), string.format("StreetLight_%02d", n))
	end
end
