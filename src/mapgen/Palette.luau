--!strict
-- MapGen/Palette — "HAVN MONOCHROME" (data murni, RGB 0–255). Token dikalibrasi dari DJ STAGE (terukur 30 Sep, Rencana_Workspace_R15.md
-- §10): Granite 163,162,165 (65%), hitam 0/17, slate 91,93,105, putih 223,223,222, neon putih 248,248,248, neon abu 163,162,165.
-- Kunci lama (HotPink, Lime, pastel, …) tetap ada supaya zona lama terbangun, tapi nilainya sudah monokrom:
-- aksen → hitam/putih, bagian Neon SELALU NeonWhite, kaca SELALU Smoke (Builder.color).

return {
	colors = {
		-- token monokrom (dipakai zona baru)
		Void = { 0, 0, 0 },
		Black = { 17, 17, 17 },
		Graphite = { 60, 60, 60 },
		Slate = { 91, 93, 105 },
		Stone = { 163, 162, 165 },
		OffWhite = { 223, 223, 222 },
		NeonWhite = { 248, 248, 248 },
		NeonSoft = { 163, 162, 165 },
		Smoke = { 40, 40, 44 }, -- kaca gelap (SmoothPlastic/Glass transparan)
		Timber = { 150, 108, 72 },
		-- dasar yang tetap
		Concrete = { 138, 141, 145 },
		ConcreteDark = { 92, 95, 99 },
		Asphalt = { 52, 54, 58 },
		Sand = { 230, 211, 163 },
		Sea = { 30, 140, 154 },
		Wood = { 120, 86, 58 },
		White = { 245, 245, 245 },
		Chrome = { 216, 222, 230 },
		Steel = { 60, 60, 60 },
		Blockout = { 200, 200, 205 },
		-- kunci lama → monokrom
		Rust = { 17, 17, 17 },
		ContainerRed = { 60, 60, 60 },
		ContainerBlue = { 91, 93, 105 },
		ContainerOrange = { 60, 60, 60 },
		ContainerGreen = { 60, 60, 60 },
		HotPink = { 17, 17, 17 },
		Lime = { 223, 223, 222 },
		IceBlue = { 223, 223, 222 },
		Lilac = { 223, 223, 222 },
		SafetyYellow = { 223, 223, 222 },
		CraneTeal = { 223, 223, 222 },
		PastelPink = { 17, 17, 17 },
		PastelMint = { 223, 223, 222 },
		PastelBlue = { 91, 93, 105 },
		Cream = { 223, 223, 222 },
	},
	-- Neon di klon kit ikut NeonWhite, kecuali kit yang cahayanya konten (layar arcade).
	neonKeep = { Kit_ArcadeMachines = true },
	-- tint SurfaceAppearance kontainer (perkalian warna → kontainer gelap; tint putih TIDAK bisa, R0b)
	containerTint = { 60, 60, 64 },
	containerKits = { ContainerRed = true, ContainerBlue = true, ContainerYellow = true, ContainerGreen = true },
	materials = {
		Concrete = "Concrete",
		Metal = "Metal",
		Corrugated = "CorrodedMetal",
		Chrome = "Foil",
		Glass = "Glass",
		Neon = "Neon",
		Wood = "WoodPlanks",
		Asphalt = "Asphalt",
		Plastic = "SmoothPlastic",
		Sand = "Sand",
		DiamondPlate = "DiamondPlate",
		Pavement = "Pavement",
	},
}
