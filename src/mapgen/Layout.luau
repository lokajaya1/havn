--!strict
-- MapGen/Layout — denah zona (data murni, koordinat dunia; utara = −Z). Lihat Rencana_Workspace.md §2.

export type Area = { name: string, minX: number, maxX: number, minZ: number, maxZ: number }

return {
	groundY = 6, -- tinggi tanah map sekarang (dasar props lama ±5.9–6.0)
	-- area yang TIDAK boleh diisi MapGen (DJ STAGE apa adanya)
	reserved = {
		{ name = "DJ STAGE", minX = -77, maxX = 79, minZ = -229, maxZ = -85 },
	} :: { Area },
	zones = {
		Stage = { name = "Stage", minX = -80, maxX = 65, minZ = -85, maxZ = 40 },
		Plaza = { name = "Plaza", minX = 65, maxX = 95, minZ = -90, maxZ = 0 },
		Harbor = { name = "Harbor", minX = 95, maxX = 220, minZ = -300, maxZ = 40 },
		Street = { name = "Street", minX = -90, maxX = 220, minZ = 40, maxZ = 160 },
		Beach = { name = "Beach", minX = -220, maxX = -90, minZ = -300, maxZ = 160 },
		PoolDeck = { name = "PoolDeck", minX = -150, maxX = -90, minZ = -60, maxZ = 40 },
		Spawn = { name = "Spawn", minX = -30, maxX = 30, minZ = 140, maxZ = 160 },
	} :: { [string]: Area },
	-- lantai dansa cekung: lantai beton 51 × 115 di (3, −5.7, −32.4); tengah yang diukur user (1.5, −5.6, −9)
	danceFloor = { x = 3, y = -5.6, z = -32.4, halfX = 25.5, halfZ = 57.5 },
	-- jalur efek donasi besar (DonationMarkers) yang tidak boleh ditutup bangunan
	nukeCorridor = { name = "NukeCorridor", minX = 95, maxX = 150, minZ = -215, maxZ = -150 },
}
