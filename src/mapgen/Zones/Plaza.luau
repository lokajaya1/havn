--!strict
-- MapGen/Zones/Plaza — plaza donasi (x 52…92). DonationBoards (objek lama, TIDAK dibangun ulang/dipindah) menghadap barat di
-- x 83.6…83.9. R6: dinding latar hitam 4 tebal di belakang papan (x 87…91, 0.2 dari area berdiri papan x ≤ 86.8), tinggi sampai
-- y 43 (puncak papan LIVE 36.84 + 6), bingkai garis neon putih 0.2 mengelilingi grup GOLD & ROBUX (1 stud di luar papan
-- terukur), pita judul "HAVN SUPPORTERS" di atas. S1 (sentuhan user): 2 bangku plaza dihapus (Seat-nya ikut), atap/list hitam
-- di puncak dinding menjorok sampai muka papan (x 83.9) dengan lampu lembut, nama bingkai sesuai isi papan (DonationConfig:
-- grup Top/Feed/Live z −46…−4 = ROBUX → Frame_Rbx, grup Cash* z −90…−49 = GOLD → Frame_Gold).

return function(b: any, L: any)
	local G = L.groundY

	-- dinding latar papan donasi
	local wall = b:model(b:folder(nil, "DonationWall"), "DonationWall_Main")
	local wx1, wx2, wz1, wz2, top = 87, 91, -94, -3, 43
	local face = b:part(wall, "Wall", { size = Vector3.new(wx2 - wx1, top - G, wz2 - wz1), cf = CFrame.new((wx1 + wx2) / 2, (G + top) / 2, (wz1 + wz2) / 2), color = "Black", material = "Concrete" })
	local band = b:part(wall, "Title_Band", { size = Vector3.new(0.15, 3.2, 40), cf = CFrame.new(wx1 - 0.075, top - 2.4, (wz1 + wz2) / 2), color = "Black", material = "Metal" })
	b:sign(band, "HAVN SUPPORTERS", "Left", "NeonWhite")
	b:part(wall, "Neon_Top", { size = Vector3.new(0.2, 0.2, wz2 - wz1), cf = CFrame.new(wx1 - 0.1, top - 0.4, (wz1 + wz2) / 2), color = "NeonWhite", material = "Neon", decor = true })
	-- bingkai grup (terukur R0a §10): ROBUX z −45.96…−4.91, GOLD z −89.52…−49.86, y 6…36.84 → +1 stud
	local x = wx1 - 0.1
	for _, g in { { "Rbx", -46.96, -3.91 }, { "Gold", -90.52, -48.86 } } do
		local z1, z2, y1, y2 = g[2], g[3], G + 1, 37.84
		local m = b:model(wall, "Frame_" .. g[1])
		b:part(m, "Neon_Top", { size = Vector3.new(0.2, 0.2, z2 - z1), cf = CFrame.new(x, y2, (z1 + z2) / 2), color = "NeonWhite", material = "Neon", decor = true })
		b:part(m, "Neon_Bottom", { size = Vector3.new(0.2, 0.2, z2 - z1), cf = CFrame.new(x, y1, (z1 + z2) / 2), color = "NeonWhite", material = "Neon", decor = true })
		b:part(m, "Neon_North", { size = Vector3.new(0.2, y2 - y1, 0.2), cf = CFrame.new(x, (y1 + y2) / 2, z1), color = "NeonWhite", material = "Neon", decor = true })
		b:part(m, "Neon_South", { size = Vector3.new(0.2, y2 - y1, 0.2), cf = CFrame.new(x, (y1 + y2) / 2, z2), color = "NeonWhite", material = "Neon", decor = true })
	end
	b:surfaceLight(face, "Left", "CoolLight", 0.4, 10, 60) -- cahaya latar lembut (tanpa bayangan)
	-- atap/list (S1): tebal 1.1 di atas dinding, menjorok ke barat sampai muka papan; lampu sisi barat seperti dinding
	local cap = b:part(wall, "Wall_Cap", { size = Vector3.new(wx2 - 83.9, 1.1, wz2 - wz1), cf = CFrame.new((83.9 + wx2) / 2, top + 0.55, (wz1 + wz2) / 2), color = "Black", material = "Concrete" })
	b:surfaceLight(cap, "Left", "CoolLight", 0.4, 10, 60)
end
