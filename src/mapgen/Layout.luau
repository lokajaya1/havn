--!strict
-- MapGen/Layout — denah v3 PRESISI (data murni, koordinat dunia; utara = −Z). Lihat Rencana_Workspace.md §3–§4.
-- Aturan: batas terrain & zona di kelipatan 4 (voxel terrain 4×4×4); objek lama yang dipertahankan memakai ukuran
-- TERUKUR dari place (dibulatkan keluar 0.1 stud). Lantai asli map lama = y 6.0.

export type Area = { name: string, minX: number, maxX: number, minZ: number, maxZ: number, maxY: number? }

local function area(name: string, minX: number, maxX: number, minZ: number, maxZ: number, maxY: number?): Area
	return { name = name, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, maxY = maxY }
end

return {
	grid = 4,
	groundY = 6, -- permukaan lantai (slab part) = lantai map lama
	-- Terrain darat di bawah lantai sengaja DIRENDAHKAN ke y 0 dan slab dibuat tebal (y −2…6): permukaan terrain yang
	-- dirender Roblox bisa sedikit naik dari batas voxel (uji Studio 13:21 — terrain menembus slab y 4…6), jadi terrain
	-- selalu tertanam ≥ 6 stud di bawah permukaan lantai dan tidak pernah terlihat di atas slab.
	landY = 0, -- puncak terrain darat di bawah slab (voxel penuh)
	slabBottomY = -2, -- dasar slab lantai (tertanam 2 stud ke terrain → tepi tidak pernah bolong)
	beachY = 4, -- puncak pasir pantai & batu pemecah ombak (terrain yang TERLIHAT)
	baseY = -16, -- dasar terrain
	-- air voxel sampai y 0. BUKTI raycast Studio 30 Sep 14:20: permukaan air dirender TEPAT y 0.00 (beda dengan darat
	-- yang dirender batas voxel + 2). Benda apung memakai renderY.
	sea = { surfaceY = 0, floorY = -12, renderY = 0 },
	-- batas map = dinding DoorVVIP (zona Boundary)
	boundary = area("Boundary", -172, 164, -208, 104),
	-- lantai part (slab) yang bisa diinjak
	walkable = area("Walkable", -104, 164, -208, 104),
	-- jangkauan terrain yang DIHAPUS dulu (mencakup terrain lama x −212…236, z −272…208)
	terrainWipe = { minX = -220, maxX = 240, minZ = -276, maxZ = 212, minY = -24, maxY = 64 },
	-- jangkauan terrain baru
	terrainExtent = { minX = -216, maxX = 212, minZ = -256, maxZ = 152 },
	land = area("Land", -104, 212, -256, 152), -- beton rata y 4 (termasuk cincin luar di balik bangunan batas)
	seaArea = area("Sea", -216, -104, -256, 152), -- air y −12…0 di atas pasir
	breakwater = area("Breakwater", -176, -168, -256, 152),
	beachSand = area("BeachSand", -104, -60, -64, 104), -- pasir rata y 4 (x −88…−60) + lereng ke air (x −136…−88)
	beachSlope = { minX = -136, maxX = -88 },
	boardwalk = area("Boardwalk", -60, -44, -64, 104), -- dek kayu y 6
	road = area("Road", -44, 164, 48, 64), -- jalan klub (aspal)
	sidewalk = area("Sidewalk", -44, 164, 64, 76), -- trotoar depan deret toko
	quayWall = { x1 = -106, x2 = -104, minZ = -208, maxZ = -64, bottomY = -14 },
	-- lubang terrain di dalam bibir lubang dansa (tepi tersembunyi di dalam part bibir)
	pitCarve = { minX = -40, maxX = 44, minZ = -108, maxZ = 36, minY = -8, maxY = 8 },

	-- Objek TETAP (terukur dari place): slab lantai tidak boleh menimpa, props tidak boleh menabrak.
	fixed = {
		area("DJ STAGE", -40.6, 43.6, -174.3, -140.5), -- panggung utama (floorDj + tabledj)
		area("DJ STAGE front", -30.4, 33.2, -140.5, -138.0), -- meja depan + tulisan HAVN
		area("DJ STAGE entrance W", -71.0, -40.5, -174.3, -156.9),
		area("DJ STAGE entrance E", 43.1, 73.7, -174.3, -156.9),
		area("DanceFloorPit", -43.6, 49.5, -112.0, 42.4), -- bibir luar lubang dansa (atas y 7.21)
		-- lajur Granite timur lubang dansa (satu-satunya yang tersisa di Studio; x 39.85…49.36, dicek 30 Sep 14:05),
		-- dipotong sampai z 44 di V4 (K4). Lajur kedua (x 70…80) sudah tidak ada sejak KOSONGKAN → tidak dicadangkan.
		area("PitStrip_West", 39.8, 49.5, -123.6, 44.1),
	} :: { Area },
	-- Objek lama yang berdiri DI ATAS lantai: slab boleh di bawahnya, props tidak boleh menabrak.
	standing = {
		area("DonationBoards", 83.1, 86.8, -89.6, -4.8),
		-- dipindah utuh di V4 ke sisi barat plaza spawn, menghadap timur (ke pad spawn), dasar tepat y 6
		area("TimePlayedLeaderboard", -23.8, -20.2, 76.8, 99.2),
		area("360Cam", 53.9, 63.5, -111.0, -98.0),
		area("DJ STAGE stairs W", -60.4, -37.4, -157.2, -146.6),
		area("DJ STAGE stairs E", 40.0, 63.0, -157.2, -146.6),
	} :: { Area },
	-- Jalur roket efek donasi: garis lurus NukeLaunch → NukeTarget (DonationMarkers, tidak dipindah). Tidak boleh ada
	-- part dalam radius 6 stud dari garis (diperiksa 3D, titik tiap 1 stud).
	nukePath = { from = { 143, 17.5, -184.5 }, to = { 1, 7.5, -119 }, radius = 6 },
	zones = {
		Ground = area("Ground", -108, 164, -208, 104),
		Boundary = area("Boundary", -176, 168, -212, 108),
		Spawn = area("Spawn", -24, 24, 64, 100), -- gerbang di z 72 + pad di z 86
		Stage = area("Stage", -44, 52, -140, -112),
		Quay = area("Quay", -168, -56, -188, -64), -- termasuk lengan derek di atas teluk
		ContainerWall = area("ContainerWall", -104, 164, -208, 104), -- utara (x ≤ 88) + timur (x 152…164)
		LaunchPad = area("LaunchPad", 92, 152, -208, -148),
		Yard = area("Yard", 92, 152, -148, -64),
		VipLounge = area("VipLounge", 92, 152, -64, 40),
		Plaza = area("Plaza", 52, 92, -124, 44),
		Beach = area("Beach", -104, -44, -64, 104),
		Bay = area("Bay", -220, -84, -208, 104), -- teluk + dermaga (mulai tepi pasir x −88) + pemecah ombak + laut luar
		Street = area("Street", -44, 164, 44, 104),
	} :: { [string]: Area },
	-- lantai dansa cekung (bagian dari objek tetap): lantai beton 51.1 × 115.2 di (2.95, −5.72, −32.42)
	danceFloor = { x = 2.95, y = -5.44, z = -32.42, halfX = 25.55, halfZ = 57.6 },
}
