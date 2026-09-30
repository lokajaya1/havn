--!strict
-- MapGen/Zones/Bay — teluk renang barat (pengganti kolam): dermaga kayu ber-ujung T dari pantai, ponton renang apung,
-- pelampung batas renang, mercusuar & tetrapod di pemecah ombak, kapal kargo sebagai latar di laut luar.
-- Benda di air ditandai AllowBelowGround; benda apung memakai permukaan air yang dirender (Layout.sea.renderY).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G, W = L.groundY, L.sea
	local wy = W.renderY
	local at = Prefabs.at
	Prefabs.pier(b, b:folder(nil, "Piers"), "Pier_Main", -88, -148, 60, 8, G, W.floorY)
	local swim = b:folder(nil, "Swim")
	Prefabs.pontoon(b, swim, "Pontoon_01", -136, 4, wy + 0.0)
	for i, p in { { -150, -30 }, { -150, 30 }, { -118, -34 }, { -118, 36 } } do
		Prefabs.markBelow(b:clone(swim, "Kit_Buoy", at(p[1], wy - 1.2, p[2], 0), string.format("Buoy_%02d", i)))
	end
	b:clone(swim, "Kit_LifeBuoy", at(-162, G, 70.2, 0), "LifeBuoy_01")
	local bw = b:folder(nil, "Breakwater")
	b:clone(bw, "Kit_Lighthouse", at(-172, G, -198, 0), "Lighthouse_01", 0.2)
	for i, z in { -150, -90, -30, 30, 90 } do
		Prefabs.markBelow(b:clone(bw, "Kit_Tetrapod", at(-172, G - 1.5, z, i * 50), string.format("Tetrapod_%02d", i)))
	end
	local sea = b:folder(nil, "OpenSea")
	Prefabs.markBelow(b:clone(sea, "Kit_CargoShip", at(-200, wy - 4, -40, 90), "CargoShip_01", 1.5))
	Prefabs.markBelow(b:clone(sea, "Kit_Boat", at(-128, wy - 0.6, 72, 0), "Boat_01", 2.5))
end
