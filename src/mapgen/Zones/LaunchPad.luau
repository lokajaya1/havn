--!strict
-- MapGen/Zones/LaunchPad — landasan roket efek donasi di bawah NukeLaunch (143, 17.5, −184.5). Semua rendah (< y 10),
-- ≥ 6 stud dari garis roket (diperiksa 3D). Barikade & pagar kawat di tepi utara.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	Prefabs.launchPad(b, b.root, "LaunchPad_Main", 143, -184.5, G)
	local edge = b:folder(nil, "NorthEdge")
	for i = 0, 6 do
		b:clone(edge, "Kit_JerseyBarrier", at(96 + i * 8, G, -204.5, 90), string.format("Barrier_%02d", i + 1))
	end
	for i = 0, 4 do
		b:clone(edge, "Kit_ChainFence", at(98 + i * 11.8, G, -207.2, 0), string.format("ChainFence_%02d", i + 1))
	end
	Prefabs.lowSign(b, b.root, "Sign_LaunchPad", 121, -152, G, "HAVN LAUNCH PAD", 0)
end
