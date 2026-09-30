--!strict
-- MapGen/Zones/Plaza — plaza donasi (x 52…92) di depan DonationBoards (papan menghadap barat): 2 bangku City Props
-- dengan Seat menghadap timur ke papan, strip neon lantai sebagai garis antre penonton papan. DonationBoards sendiri
-- TIDAK dibangun ulang (objek lama, dipertahankan) — hanya dasarnya disejajarkan ke y 6 lewat langkah Studio V6.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local f = b:folder(nil, "Seating")
	for i, z in { -62, -28 } do
		b:clone(f, "MetalBench_01_A", at(72, G, z, 90), string.format("Bench_%02d", i))
		b:seat(f, string.format("Seat_Bench_%02d", i), CFrame.new(72, G + 1.8, z) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(7, 0.4, 1.6))
	end
	b:part(b:folder(nil, "Markings"), "Neon_ViewLine", { size = Vector3.new(0.4, 0.05, 80), cf = CFrame.new(78, G + 0.025, -46), color = "HotPink", material = "Neon", decor = true })
end
