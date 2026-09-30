--!strict
-- MapGen/Zones/DanceStairs — tangga masuk lubang dansa di sumbu spawn (R7). Lubang lama (objek tetap, TIDAK diubah) punya
-- 3 undakan setinggi 4.82 / 3.83 / 4.00 (terukur R0a) → harus lompat 3×. Tangga lebar 10 (x −5…5) turun ke utara dari bibir
-- selatan: tiap segmen menapak TEPAT di permukaan undakan lama di bawahnya (tanpa tumpang volume, tanpa muka sebidang),
-- anak tangga ≤ 0.67 (terbukti naik tanpa lompat sampai 3.0, R0c2), injakan 0.8.
-- R7b (permintaan user): bahan SAMA PERSIS dengan DanceFloorPit (terukur HAVN_R0: Granite, 163,162,165, MaterialVariant
-- "granite tile 3", tanpa neon) → tangga tampak dipahat dari lubang yang sama, bukan balok tempelan.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local S = L.danceStairs
	local m = b:model(nil, "Stairs_DanceFloor")
	local k = 0
	for _, seg in S.segments do
		-- seg = { top, base, zStart (tepi atas), steps }: `steps` anak tangga dari top ke base; anak tangga terakhir = permukaan lama
		local rise = (seg.top - seg.base) / seg.steps
		for i = 1, seg.steps - 1 do
			k += 1
			local top = seg.top - i * rise
			local z2 = seg.zStart - (i - 1) * S.run
			local z1 = z2 - S.run
			b:part(m, string.format("Step_%02d", k), {
				size = Vector3.new(S.maxX - S.minX, top - seg.base, S.run),
				cf = CFrame.new((S.minX + S.maxX) / 2, (top + seg.base) / 2, (z1 + z2) / 2),
				color = "Stone",
				material = "Granite",
				materialVariant = S.materialVariant,
			})
		end
	end
	for _, d in m:GetDescendants() do
		d:SetAttribute("AllowFixed", "DanceFloorPit")
	end
	Prefabs.markBelow(m)
end
