--!strict
-- MapGen/Zones/ContainerWall — dinding batas dari tumpukan kontainer mesh PBR (30×10×10):
-- utara di belakang DJ STAGE (x −104…88, 2 baris, 3/2/1 tingkat berundak) dan timur (x 153…163, memanjang Z).
-- Siluet berundak mengikuti container park nyata (Boxpark, Stackt). Tidak masuk jalur roket donasi (x ≤ 88 / x ≥ 153).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local north = b:folder(nil, "North")
	local n = 0
	for row, z in { -203, -193 } do
		for i = 0, 5 do
			n += 1
			local x = -103 + 15 + i * 32
			local tiers = if row == 1 then (if i % 2 == 0 then 3 else 2) else (if i % 3 == 1 then 2 else 1)
			Prefabs.containerStack(b, north, string.format("ContainerStack_%02d", n), x, z, G, tiers, 0, n)
		end
	end
	local east = b:folder(nil, "East")
	for i = 0, 6 do
		local z = -206 + 15 + i * 32
		Prefabs.containerStack(b, east, string.format("ContainerStack_%02d", i + 1), 158, z, G, if i % 2 == 0 then 3 else 2, 90, i + 2)
	end
end
