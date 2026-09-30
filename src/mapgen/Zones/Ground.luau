--!strict
-- MapGen/Zones/Ground — lantai yang diinjak = SLAB PART setebal 8 stud (y −2…6), tertanam di terrain rata y 0.
-- Permukaan tepat y 6.000 (lantai map lama). Slab dipotong persis mengikuti objek tetap (DJ STAGE, lubang dansa,
-- lajur Granite) sehingga tidak ada celah & tidak ada tumpang. Dinding dermaga menutup tepi terrain ke air.
-- S1: trotoar = kerb (atas L.sidewalkTop 6.4) sampai muka toko z 77 (L.sidewalkSlabMaxZ).

type Rect = { x1: number, x2: number, z1: number, z2: number }

-- Kurangi daftar lubang dari satu persegi → potongan persegi yang saling lepas (sapuan per sumbu X).
local function subtract(r: Rect, holes: { Rect }): { Rect }
	local xs = { r.x1, r.x2 }
	for _, h in holes do
		for _, x in { h.x1, h.x2 } do
			if x > r.x1 and x < r.x2 then
				table.insert(xs, x)
			end
		end
	end
	table.sort(xs)
	local cols = {}
	for i = 1, #xs - 1 do
		local xa, xb = xs[i], xs[i + 1]
		if xb - xa > 1e-6 then
			local zs = { { r.z1, r.z2 } }
			for _, h in holes do
				if h.x1 < xb - 1e-6 and h.x2 > xa + 1e-6 then
					local nz = {}
					for _, s in zs do
						if h.z2 <= s[1] or h.z1 >= s[2] then
							table.insert(nz, s)
						else
							if h.z1 > s[1] then
								table.insert(nz, { s[1], h.z1 })
							end
							if h.z2 < s[2] then
								table.insert(nz, { h.z2, s[2] })
							end
						end
					end
					zs = nz
				end
			end
			table.insert(cols, { xa = xa, xb = xb, zs = zs })
		end
	end
	-- gabungkan kolom bersebelahan yang pola Z-nya sama
	local out: { Rect } = {}
	local open: { [string]: Rect } = {}
	for _, c in cols do
		local nextOpen: { [string]: Rect } = {}
		for _, s in c.zs do
			local key = string.format("%.3f:%.3f", s[1], s[2])
			local prev = open[key]
			if prev and math.abs(prev.x2 - c.xa) < 1e-6 then
				prev.x2 = c.xb
				nextOpen[key] = prev
			else
				local nr = { x1 = c.xa, x2 = c.xb, z1 = s[1], z2 = s[2] }
				table.insert(out, nr)
				nextOpen[key] = nr
			end
		end
		open = nextOpen
	end
	return out
end

local function rect(a: any): Rect
	return { x1 = a.minX, x2 = a.maxX, z1 = a.minZ, z2 = a.maxZ }
end

return function(b: any, L: any)
	local G, LY = L.groundY, L.slabBottomY
	local holes: { Rect } = {}
	for _, f in L.fixed do
		table.insert(holes, rect(f))
	end
	local bw, road, sand, walk = rect(L.boardwalk), rect(L.road), rect(L.beachSand), rect(L.sidewalk)
	walk.z2 = L.sidewalkSlabMaxZ

	-- urutan prioritas: dek kayu → jalan aspal → trotoar → beton (sisanya), pasir pantai bukan slab
	local layers = {
		{ name = "Boardwalk", material = "Wood", color = "Wood", area = bw, minus = {} },
		{ name = "Road", material = "Asphalt", color = "Asphalt", area = road, minus = { bw } },
		{ name = "Sidewalk", material = "Pavement", color = "ConcreteDark", area = walk, minus = { bw, road }, top = L.sidewalkTop },
		{ name = "Concrete", material = "Concrete", color = "Concrete", area = rect(L.walkable), minus = { bw, road, sand, walk } },
	}
	local slabs = b:folder(nil, "Slabs")
	for _, layer in layers do
		local cut = table.clone(holes)
		for _, m in layer.minus do
			table.insert(cut, m)
		end
		local pieces = subtract(layer.area, cut)
		table.sort(pieces, function(p, q)
			return if p.x1 ~= q.x1 then p.x1 < q.x1 else p.z1 < q.z1
		end)
		local top = layer.top or G
		for i, p in pieces do
			b:part(slabs, string.format("Slab_%s_%02d", layer.name, i), {
				size = Vector3.new(p.x2 - p.x1, top - LY, p.z2 - p.z1),
				cf = CFrame.new((p.x1 + p.x2) / 2, (top + LY) / 2, (p.z1 + p.z2) / 2),
				color = layer.color,
				material = layer.material,
				floor = true,
			})
		end
	end

	-- dinding dermaga: menutup tepi terrain darat ↔ air (air masuk ke dalam dinding, tidak terlihat bolong)
	local q = L.quayWall
	b:part(b:folder(nil, "Quay"), "QuayWall_West", {
		size = Vector3.new(q.x2 - q.x1, G - q.bottomY, q.maxZ - q.minZ),
		cf = CFrame.new((q.x1 + q.x2) / 2, (G + q.bottomY) / 2, (q.minZ + q.maxZ) / 2),
		color = "ConcreteDark",
		material = "Concrete",
	})
end
