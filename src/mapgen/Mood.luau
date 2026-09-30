--!strict
-- MapGen/Mood — suasana SENJA + NEON (K4) untuk Lighting (data murni; diterapkan MapGen.lighting). Nilai lama dari
-- place (30 Sep) dicatat supaya bisa dikembalikan: Brightness 3, Ambient/OutdoorAmbient 70,70,70, EnvDiffuse 0.1,
-- Atmosphere Density 0.3 Haze 2.1 Glare 0.67, ColorCorrection netral, SunRays 0.03, Sky bintang 3000.
-- GraphicsClient (menu grafis pemain) membaca Lighting saat mulai sebagai DEFAULT → tetap cocok.

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

return {
	lighting = {
		ClockTime = 17.6, -- 17:36, sama dengan sekarang (senja)
		Brightness = 2.2, -- lebih lembut dari 3 → neon & layar LED lebih menonjol
		Ambient = rgb(70, 58, 84), -- bayangan ungu tipis (senja)
		OutdoorAmbient = rgb(118, 96, 122),
		ColorShift_Top = rgb(255, 166, 114), -- tetap: cahaya matahari oranye
		ColorShift_Bottom = rgb(84, 60, 120), -- pantulan bawah ungu
		EnvironmentDiffuseScale = 0.35, -- langit ikut menerangi (krom, kaca)
		EnvironmentSpecularScale = 1,
		ShadowSoftness = 0.3,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.3, Offset = 0.15, Haze = 1.6, Glare = 0.5, Color = rgb(220, 160, 190), Decay = rgb(120, 90, 140) },
	colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.12, TintColor = rgb(255, 242, 250) },
	-- Bloom ambang tinggi: hanya Neon & layar terang yang berpendar, lantai/bangunan tidak silau
	bloom = { Name = "Bloom", Intensity = 0.6, Size = 24, Threshold = 1.6 },
}
