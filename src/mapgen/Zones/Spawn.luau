--!strict
-- MapGen/Zones/Spawn — plaza spawn di tengah selatan: 2 SpawnLocation netral (z 86) menghadap utara, gerbang PORTAL hitam
-- di z 72 (R3, monokrom seperti DJ STAGE): bukaan 24 × 15 membingkai garis pandang spawn → lantai dansa → DJ STAGE (spot foto
-- pertama), garis neon putih 0.2 menyusuri sisi dalam bukaan, huruf 3D "HAVN" identik dengan DJ STAGE (Kit_LogoHAVN, Inter
-- ExtraBold) di kedua sisi balok atas. TimePlayedLeaderboard berdiri di sisi barat plaza.
-- S1 (sentuhan user): gerbang menapak trotoar kerb (L.sidewalkTop), logo "HAVN" kecil lebar 8 (skala 0.55, huruf 1.17)
-- simetris di tengah balok kedua sisi, pad spawn tak terlihat (tetap berfungsi).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.sidewalkTop -- gerbang berdiri di trotoar
	local gz = 72
	local W, H, D, T = 24, 15, 3, 2 -- lebar bukaan, tinggi bukaan, tebal portal (z), tebal kolom/balok
	local gate = b:model(nil, "Gate_HAVN")
	for _, side in { -1, 1 } do
		local x = side * (W / 2 + T / 2)
		b:part(gate, if side < 0 then "Column_West" else "Column_East", { size = Vector3.new(T, H + 3, D), cf = CFrame.new(x, G + (H + 3) / 2, gz), color = "Black", material = "Metal" })
		b:part(gate, if side < 0 then "Neon_Inner_West" else "Neon_Inner_East", { size = Vector3.new(0.2, H, 0.2), cf = CFrame.new(side * (W / 2 - 0.1), G + H / 2, gz), color = "NeonWhite", material = "Neon" })
	end
	b:part(gate, "Lintel", { size = Vector3.new(W + 2 * T, 3, D), cf = CFrame.new(0, G + H + 1.5, gz), color = "Black", material = "Metal" })
	b:part(gate, "Neon_Inner_Top", { size = Vector3.new(W, 0.2, 0.2), cf = CFrame.new(0, G + H - 0.1, gz), color = "NeonWhite", material = "Neon" })
	b:part(gate, "Threshold", { size = Vector3.new(W + 2 * T, 0.1, D + 1), cf = CFrame.new(0, G + 0.05, gz), color = "Black", material = "Granite", decor = true })
	-- huruf 3D (tinggi 2.13 × 0.55 = 1.17, lebar 8) di tengah balok atas; depan kit = +Z → selatan (spawn) & utara (panggung)
	local s = 0.55
	local ly = G + H + (3 - 2.16 * s) / 2
	Prefabs.facing(b, gate, "Kit_LogoHAVN", 0, ly, gz + D / 2 + 0.25 * s, 180, "Logo_South", s)
	Prefabs.facing(b, gate, "Kit_LogoHAVN", 0, ly, gz - D / 2 - 0.25 * s, 0, "Logo_North", s)
	local pads = b:folder(nil, "SpawnPads")
	local P = L.groundY -- pad di plaza (bukan trotoar)
	b:spawn(pads, "Spawn_Main_A", CFrame.new(-8, P + 0.5, 86), 1)
	b:spawn(pads, "Spawn_Main_B", CFrame.new(8, P + 0.5, 86), 1)
end
