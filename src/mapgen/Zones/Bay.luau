--!strict
-- MapGen/Zones/Bay — teluk renang barat (pengganti kolam): dermaga kayu ber-ujung T dari pantai, ponton renang apung,
-- pelampung batas renang, mercusuar & tetrapod di pemecah ombak, kapal kargo sebagai latar di laut luar.
-- Benda di air ditandai AllowBelowGround; benda apung memakai permukaan air yang dirender (Layout.sea.renderY).
-- R4 (P14): tidak ada benda COLLIDABLE yang mengapung di permukaan area renang — platform renang padat dari dasar laut,
-- pelampung/perahu/kapal = hiasan tembus. Dermaga lebar 12 (bersih ≥ 10 untuk avatar lebar 8.6).
-- S1 (sentuhan user): dermaga utuh naik L.pierLift (dek atas 6.27), perahu mengapung di permukaan (dulu −0.6),
-- platform renang 3 anak tangga padat (Prefabs.swimPlatform).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G, W = L.groundY, L.sea
	local wy = W.renderY
	local at = Prefabs.at
	Prefabs.shift(Prefabs.pier(b, b:folder(nil, "Piers"), "Pier_Main", -88, -148, 60, 12, G, W.floorY), Vector3.new(0, L.pierLift, 0))
	local swim = b:folder(nil, "Swim")
	Prefabs.swimPlatform(b, swim, "SwimPlatform_01", -136, 4, wy, W.floorY)
	for i, p in { { -150, -30 }, { -150, 30 }, { -118, -34 }, { -118, 36 } } do
		Prefabs.decor(Prefabs.markBelow(b:clone(swim, "Kit_Buoy", at(p[1], wy - 1.2, p[2], 0), string.format("Buoy_%02d", i))))
	end
	b:clone(swim, "Kit_LifeBuoy", at(-162, G, 70.2, 0), "LifeBuoy_01")
	local bw = b:folder(nil, "Breakwater")
	b:clone(bw, "Kit_Lighthouse", at(-172, G, -198, 0), "Lighthouse_01", 0.2)
	for i, z in { -150, -90, -30, 30, 90 } do
		Prefabs.markBelow(b:clone(bw, "Kit_Tetrapod", at(-172, G - 1.5, z, i * 50), string.format("Tetrapod_%02d", i)))
	end
	local sea = b:folder(nil, "OpenSea")
	Prefabs.decor(Prefabs.markBelow(b:clone(sea, "Kit_CargoShip", at(-200, wy - 4, -40, 90), "CargoShip_01", 1.5)))
	Prefabs.decor(Prefabs.markBelow(b:clone(sea, "Kit_Boat", at(-128, wy, 80, 0), "Boat_01", 2.5)))
end
