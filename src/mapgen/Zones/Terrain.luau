--!strict
-- MapGen/Zones/Terrain — terrain v3 PRESISI. Hanya MENCATAT operasi (b:terrain); MapGen menjalankannya saat JALAN.
-- Semua kotak sejajar grid 4 stud (dibuktikan V0: kotak sejajar = voxel penuh, permukaan rata). Urutan penting:
-- yang belakangan menimpa yang duluan. Terrain hanya tanah dasar (y 4), pasir, dasar laut & air; lantai yang diinjak = slab
-- part (zona Ground, permukaan y 6).

return function(b: any, L: any)
	local W, Y0, LY, BY, S = L.terrainWipe, L.baseY, L.landY, L.beachY, L.sea
	local function block(material: string, x1: number, x2: number, y1: number, y2: number, z1: number, z2: number)
		b:terrain("Block", material, CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), Vector3.new(x2 - x1, y2 - y1, z2 - z1))
	end

	-- 1) hapus semua terrain lama (termasuk hasil R2/R3b)
	block("Air", W.minX, W.maxX, W.minY, W.maxY, W.minZ, W.maxZ)

	-- 2) darat: beton rata sampai y 0 (tertanam di bawah slab lantai y −2…6, panggung, dan cincin luar)
	local Ld = L.land
	block("Concrete", Ld.minX, Ld.maxX, Y0, LY, Ld.minZ, Ld.maxZ)

	-- 3) laut barat: pasir dasar + air y −12…0; pemecah ombak batu
	local Sa = L.seaArea
	block("Sand", Sa.minX, Sa.maxX, Y0, S.floorY, Sa.minZ, Sa.maxZ)
	block("Water", Sa.minX, Sa.maxX, S.floorY, S.surfaceY, Sa.minZ, Sa.maxZ)
	local Bw = L.breakwater
	block("Rock", Bw.minX, Bw.maxX, Y0, BY, Bw.minZ, Bw.maxZ)

	-- 4) pantai: pasir rata y 4, lalu tebing pasir curam (wedge 8 stud) ke dasar laut; air di atas tebing.
	--    Urutan WAJIB: Air → Water → pasir (P12: Water di atas voxel padat tidak mengosongkannya, bukti rig R4 20:45).
	local Bs, Sl = L.beachSand, L.beachSlope
	block("Sand", Sl.maxX, Bs.maxX, Y0, BY, Bs.minZ, Bs.maxZ)
	block("Air", Sl.minX, Sl.maxX, S.floorY, BY, Bs.minZ, Bs.maxZ)
	block("Water", Sl.minX, Sl.maxX, S.floorY, S.surfaceY, Bs.minZ, Bs.maxZ)
	local len, h = Sl.maxX - Sl.minX, BY - S.floorY
	b:terrain(
		"Wedge",
		"Sand",
		CFrame.new((Sl.minX + Sl.maxX) / 2, (S.floorY + BY) / 2, (Bs.minZ + Bs.maxZ) / 2) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(Bs.maxZ - Bs.minZ, h, len)
	)

	-- 4b) teras kolam: pasir di bawah dek dibuang (beton darat y 0 dirender ≈ 2, di bawah dek 4.5 & lounge 2.5), lalu
	--     kolam: Air dulu, baru Water (P12) — air masuk ke dalam dinding kolam 4 tebal.
	local Pt, Pl = L.poolTerrace, L.pool
	block("Air", Pt.minX, Pt.maxX, Y0 + 16, 8, Pt.minZ, Pt.maxZ)
	block("Air", Pl.minX, Pl.maxX, Pl.floorY, Pl.surfaceY, Pl.minZ, Pl.maxZ)
	block("Water", Pl.minX, Pl.maxX, Pl.floorY, Pl.surfaceY, Pl.minZ, Pl.maxZ)

	-- 5) lubang lantai dansa: kosongkan di dalam bibir (tepi tersembunyi di dalam part bibir)
	local P = L.pitCarve
	block("Air", P.minX, P.maxX, P.minY, P.maxY, P.minZ, P.maxZ)

	-- 6) warna material & air
	b:terrainColor("Sand", "Sand")
	b:terrainColor("Concrete", "ConcreteDark")
	b:terrainColor("Rock", "Steel")
	-- K4: air lebih tenang & jernih (global: laut + kolam)
	b:water({ color = "Sea", transparency = 0.75, reflectance = 0.5, waveSize = 0.05, waveSpeed = 8 })
end
