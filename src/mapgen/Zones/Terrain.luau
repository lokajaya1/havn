--!strict
-- MapGen/Zones/Terrain — R2: tanah Industrial Beach. Hanya MENCATAT operasi terrain (b:terrain);
-- MapGen menjalankannya di Workspace.Terrain saat JALAN. Lubang lantai dansa & bawah DJ STAGE tidak disentuh.
-- Urutan penting: yang belakangan menimpa yang duluan.

return function(b: any, L: any)
	local B, G, D, P = L.boundary, L.groundY, L.reserved[1], L.danceFloorPit
	local bottom = G - 16
	-- persegi dunia (x1..x2, z1..z2) → isi dari `bottom` sampai `top`
	local function slab(material: string, x1: number, x2: number, z1: number, z2: number, top: number?, low: number?)
		local t, lo = top or G, low or bottom
		b:terrain("Block", material, CFrame.new((x1 + x2) / 2, (t + lo) / 2, (z1 + z2) / 2), Vector3.new(x2 - x1, t - lo, z2 - z1))
	end

	-- 1) dasar beton seluruh map, kecuali DJ STAGE & lubang lantai dansa
	slab("Concrete", B.minX, B.maxX, B.minZ, D.minZ) -- utara (belakang panggung)
	slab("Concrete", B.minX, D.minX, D.minZ, D.maxZ) -- kiri panggung
	slab("Concrete", D.maxX, B.maxX, D.minZ, D.maxZ) -- kanan panggung
	slab("Concrete", B.minX, P.minX, D.maxZ, P.maxZ) -- kiri lantai dansa
	slab("Concrete", P.maxX, B.maxX, D.maxZ, P.maxZ) -- kanan lantai dansa
	slab("Concrete", B.minX, B.maxX, P.maxZ, B.maxZ) -- selatan

	-- 2) pantai pasir (zona Beach, di luar lubang & panggung karena Beach di barat keduanya)
	local beach = L.zones.Beach
	slab("Sand", beach.minX, beach.maxX, beach.minZ, beach.maxZ)

	-- 3) jalan: trotoar Pavement + aspal (zona Street)
	local street = L.zones.Street
	slab("Pavement", street.minX, street.maxX, street.minZ, street.maxZ)
	slab("Asphalt", street.minX, street.maxX, L.road.minZ, L.road.maxZ)

	-- 4) laut barat: kosongkan, isi air, dasar pasir, lalu pantai landai (wedge) naik ke timur
	local S = L.sea
	slab("Air", S.minX, S.maxX, B.minZ, B.maxZ, G + 20, S.floorY)
	slab("Water", S.minX, S.maxX, B.minZ, B.maxZ, S.surfaceY, S.floorY)
	slab("Sand", S.minX, S.maxX, B.minZ, B.maxZ, S.floorY, bottom)
	-- wedge: sisi tinggi di +X (darat, y = G), turun ke −X (laut, y = floorY); diputar 90° supaya lereng menghadap barat
	local len, h = S.maxX - (S.minX + 5), G - S.floorY
	b:terrain(
		"Wedge",
		"Sand",
		CFrame.new(S.maxX - len / 2, S.floorY + h / 2, (B.minZ + B.maxZ) / 2) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(B.maxZ - B.minZ, h, len)
	)

	-- 5) warna material (palet) & air laut
	b:terrainColor("Sand", "Sand")
	b:terrainColor("Concrete", "Concrete")
	b:terrainColor("Pavement", "ConcreteDark")
	b:terrainColor("Asphalt", "Asphalt")
	b:water({ color = "Sea", transparency = 0.6, reflectance = 0.5, waveSize = 0.15, waveSpeed = 10 })
end
