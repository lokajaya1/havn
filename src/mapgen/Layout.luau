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
	sea = { surfaceY = 0, floorY = -12, renderY = 0, swimMaxX = -104 }, -- swimMaxX: perairan renang = x < −104 (teluk; dinding dermaga x −106…−104)
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
	beachSand = area("BeachSand", -104, -56, -64, 104), -- pasir rata y 4 (x −100…−56) + tebing pasir curam ke air (x −108…−100)
	-- R4 (Rencana_Workspace_R15.md §16): lereng landai 48 stud (air dangkal ±15 stud untuk avatar tinggi → bolak-balik
	-- lari↔renang) diganti tebing pasir 8 stud (kemiringan 2:1): dari dalam 0 ke 12 dalam 8 stud.
	beachSlope = { minX = -108, maxX = -100 },
	boardwalk = area("Boardwalk", -56, -44, -64, 104), -- dek kayu y 6 (lebar 12)
	-- Teras kolam "HAVN POOL" (R4b, foto acuan user): dek kayu y 4.5 (1.5 di bawah lantai), kolam air terrain y −12…4
	-- (lebar 24 = P13), dinding/coping putih 4 tebal (tepi air tersembunyi, P5), sunken lounge lantai 2.5.
	-- S1 (sentuhan user 30 Sep): lantai kolam PART putih y −10…−6 (dalam 10) dari dinding utara sampai kaki tangga.
	poolTerrace = { minX = -100, maxX = -56, minZ = -60, maxZ = 24, deckY = 4.5 },
	pool = { minX = -100, maxX = -68, minZ = -48, maxZ = 16, wall = 4, surfaceY = 4, floorY = -12, partFloorTop = -6, partFloorBottom = -10 }, -- termasuk dinding
	lounge = { minX = -92, maxX = -72, minZ = -60, maxZ = -50, floorY = 2.5 }, -- termasuk tangga turun x −76…−72
	road = area("Road", -44, 164, 48, 64), -- jalan klub (aspal)
	sidewalk = area("Sidewalk", -44, 164, 64, 76), -- trotoar depan deret toko (muka toko di z 76 + 1)
	-- S1: trotoar = kerb (sentuhan user +0.39 → dibulatkan 6.4); slab sampai muka toko z 77 (tanpa alur di depan pintu venue).
	-- Semua benda di trotoar (gerbang HAVN, lampu, bangku + Seat, hidran, pot, telepon, vending) menapak tepat di sini.
	sidewalkTop = 6.4,
	sidewalkSlabMaxZ = 77,
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
		-- lajur Granite timur lubang dansa (Pit_Rim_East x 39.85…49.36, z −123.55…42.34, terukur 30 Sep 22:40). Dulu maxZ 44.1
		-- → lubang lantai 1.76 × 9.7 di z 42.34…44.1 (ditambal tangan user) → S1: 42.4 (dibulatkan keluar 0.1).
		area("PitStrip_West", 39.8, 49.5, -123.6, 42.4),
	} :: { Area },
	-- Objek lama yang berdiri DI ATAS lantai: slab boleh di bawahnya, props tidak boleh menabrak.
	standing = {
		area("DonationBoards", 83.1, 86.8, -89.6, -4.8, 36.9), -- puncak papan LIVE 36.84: di atasnya boleh (atap dinding, S1)
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
		Yard = area("Yard", 92, 152, -172, -64), -- S1: lampu halaman sampai z −158
		VipLounge = area("VipLounge", 68, 132, -60, 48), -- S1: seluruh VIP digeser vipOffset (dinding x 72.6…129.6, z −4…45)
		Plaza = area("Plaza", 52, 92, -124, 44),
		Beach = area("Beach", -104, -44, -64, 104),
		Bay = area("Bay", -220, -84, -208, 104), -- teluk + dermaga (mulai tepi pasir x −88) + pemecah ombak + laut luar
		Street = area("Street", -44, 164, 32, 104), -- S1: halte di sisi utara jalan (z ±39)
		Party = area("Party", -48, 110, -112, 100), -- B1: dekor ulang tahun sementara (gerbang → lubang dansa) + B2 HAVN STUDIO
	} :: { [string]: Area },
	-- B1 "HAVN BIRTHDAY" (Rencana_Workspace_Birthday.md): zona SEMENTARA di sumbu inti. Angka terukur 1 Okt: bibir lubang y 7.21,
	-- bibir selatan z 32.04…42.34, bibir barat x −43.46…−33.95, timur x 39.85…49.36, lantai dansa y −5.44 (x −22.6…28.5,
	-- z −90…25.16, undakan selatan mulai z 18.8); garis pandang spawn → tepi atas layar panggung lewat z −98 di y 36.8.
	party = {
		rimY = 7.21,
		gate = { z = 72, colOuterX = 14, topY = 24.4, logoHalfX = 5 }, -- logo HAVN |x| ≤ 4 di kedua muka balok: TIDAK disentuh
		arch = { z = 37.2, halfWidth = 14.8, legTop = 16 }, -- bukaan bersih ≥ 24 × 16 di atas bibir selatan
		-- B1b: HAPPY di ATAS BIRTHDAY (terbaca atas → bawah), huruf lebih besar (tampak dari spawn)
		-- B3 (user 07:56 "tulisan terbang", 08:02 "gantry menghalangi DJ STAGE"): tulisan = BUNTING — kartu huruf kecil digantung
		-- di kabel lampu kanopi (garis ke-3, z −15), terbaca dari selatan & utara (sisi utara urutan dibalik). Tanpa papan/gantry.
		bunting = { line = 3, text = "HAPPY BIRTHDAY", cardW = 3.6, cardH = 4.4, gap = 0.6, centerX = 3 },
		canopy = { westX = -42.8, eastX = 48.8, lines = { -75, -45, -15 }, topY = 27, sag = 3, bulbEvery = 3.5 },
		cake = { x = 3, z = -1.5, floorY = -5.44 }, -- tepi pita z 7.65 → 11.15 dari undakan selatan z 18.8 (A4 ≥ 10)
		confetti = { texture = "rbxassetid://3077044894", rate = 3, y = 42, minX = -22, maxX = 28, minZ = -90, maxZ = 25 }, -- tekstur = confetti Nuke (B0)
		-- B2 spot foto di HAVN STUDIO (terukur dari Prefabs.venue V17): ruang x 82.5…105.5, lantai 6.1, plafon 20, cyclorama z 97.8,
		-- bingkai foto tiang x 87.4…88.0 & 100.0…100.6 (z 88.7…89.3), balok atas y 16…16.6; pintu x 89…99.
		studio = { cx = 94, frameZ = 89, postOuter = 7.9, frameTop = 16.6, floorY = 6.1, ceilY = 20, wallZ = 97.8, cornerX = { 84.5, 103.5 }, cornerZ = 96 },
	},
	-- S1 (sentuhan user 30 Sep, Rencana_Workspace_Sentuhan.md): seluruh VIP Lounge (termasuk dinding DoorVIP) digeser
	-- tangan Δ(−22.37, 0, +5.01) → dibulatkan (beda ≤ 0.04). Dermaga dinaikkan 0.27 (dek atas 6.27, di atas pasir render).
	vipOffset = { x = -22.4, z = 5 },
	pierLift = 0.27,
	-- lantai dansa cekung (bagian dari objek tetap): lantai beton 51.1 × 115.2 di (2.95, −5.72, −32.42)
	danceFloor = { x = 2.95, y = -5.44, z = -32.42, halfX = 25.55, halfZ = 57.6 },
}
