--!strict
-- MapGen/Zones/Party — "HAVN BIRTHDAY" (B1, Rencana_Workspace_Birthday.md): dekor pesta ulang tahun SEMENTARA di sumbu inti
-- spawn → gerbang HAVN → bibir selatan → lantai dansa. Monokrom + sentuhan pink (pilihan user dari preview B0).
-- Sejak V20 = tema map "Birthday" (themeMap, claude/Rencana_Tema.md): dibangun ke ServerStorage.ThemeMap.Birthday dengan
-- G.themeMap("Birthday", "JALAN") dan dipasang/dilepas admin dari panel (Settings › ADMIN › Tema map). G.build JALAN menolak zona ini.
--   Gate    garland balon di sisi luar kolom & atas balok gerbang — logo "HAVN" (|x| ≤ 4 di kedua muka balok) TIDAK disentuh
--   Arch    lengkung balon di bibir selatan (bukaan bersih 24 × 11 = A1/A3, puncak ±20 di atas bibir)
--   Bunting kartu huruf "HAPPY BIRTHDAY" digantung di kabel lampu kanopi (B3; dulu tulisan melayang lalu gantry → menutupi
--           panggung), terbaca dari dua arah
--   Canopy  3 garis lampu peri tiang-ke-tiang di atas lantai dansa, 6 gugus balon terikat di kabel (B3), bola cermin
--   Cake    kue raksasa 3 tingkat (padat) di lantai dansa = pusat foto
--   Confetti 3 emitter ringan (pink/putih/perak) di atas lantai dansa
--   Studio  (B2) spot foto di HAVN STUDIO: garland mengelilingi bingkai foto, kolom balon di sudut, "HAPPY BIRTHDAY" di cyclorama
-- Semua dekor tembus & tanpa bayangan (kamera Popper hanya terhalang part CanCollide), kecuali kue. Tanpa skrip.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local P = L.party
	local RIM = P.rimY
	local PIT = "DanceFloorPit,PitStrip_West"

	-- 1) garland gerbang (sisi luar kolom + atas balok, menjauhi logo)
	local gate = b:folder(nil, "Gate")
	local g = P.gate
	local base = L.sidewalkTop
	for i, side in { -1, 1 } do
		local x = side * (g.colOuterX + 1.3)
		local label = if side < 0 then "West" else "East"
		Prefabs.garland(b, gate, "Garland_Column_" .. label, { Vector3.new(x, base + 1.4, g.z), Vector3.new(x, g.topY, g.z) }, 1001 + i, { floorY = base })
		Prefabs.garland(b, gate, "Garland_Top_" .. label, { Vector3.new(x, g.topY + 1.2, g.z), Vector3.new(side * (g.logoHalfX + 3), g.topY + 1.2, g.z) }, 2001 + i, {
			minY = g.topY,
			maxX = if side < 0 then -g.logoHalfX - 0.2 else nil,
			minX = if side > 0 then g.logoHalfX + 0.2 else nil,
		})
	end

	-- 2) lengkung balon di bibir selatan (kaki tegak + setengah lingkaran)
	local arch = b:folder(nil, "Arch")
	local a = P.arch
	local pts = { Vector3.new(-a.halfWidth, RIM + 1.4, a.z), Vector3.new(-a.halfWidth, a.legTop, a.z) }
	for k = 1, 12 do
		local t = math.pi - k * math.pi / 12
		table.insert(pts, Vector3.new(a.halfWidth * math.cos(t), a.legTop + a.halfWidth * math.sin(t), a.z))
	end
	table.insert(pts, Vector3.new(a.halfWidth, RIM + 1.4, a.z))
	Prefabs.garland(b, arch, "Arch_Balloons", pts, 3001, { floorY = RIM })

	-- 4) kanopi: tiang di bibir barat & timur, tali melengkung + bola lampu neon, gugus balon, bola cermin
	local canopy = b:folder(nil, "Canopy")
	local C = P.canopy
	local span = C.eastX - C.westX
	local function stringY(x: number): number
		local t = (x - C.westX) / span
		return C.topY - C.sag * 4 * t * (1 - t)
	end
	for li, z in C.lines do
		local line = b:model(canopy, string.format("Lights_%02d", li))
		for side, x in { C.westX, C.eastX } do
			b:part(line, if side == 1 then "Post_West" else "Post_East", { size = Vector3.new(0.5, C.topY + 0.5 - RIM, 0.5), cf = CFrame.new(x, (RIM + C.topY + 0.5) / 2, z), color = "Black", material = "Metal", decor = true, noShadow = true })
		end
		local seg = 8
		for s = 1, seg do
			local x1, x2 = C.westX + span * (s - 1) / seg, C.westX + span * s / seg
			local y1, y2 = stringY(x1), stringY(x2)
			local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
			b:part(line, string.format("Wire_%02d", s), { size = Vector3.new(len, 0.12, 0.12), cf = CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, z) * CFrame.Angles(0, 0, math.atan2(y2 - y1, x2 - x1)), color = "Black", material = "Plastic", decor = true, noShadow = true })
		end
		local n = 0
		local x = C.westX + C.bulbEvery
		while x < C.eastX - 1 do
			n += 1
			b:part(line, string.format("Bulb_%02d", n), { size = Vector3.new(0.45, 0.45, 0.45), cf = CFrame.new(x, stringY(x) - 0.35, z), color = "NeonWhite", material = "Neon", shape = "Ball", decor = true })
			x += C.bulbEvery
		end
	end
	-- gugus balon diikat DI kabel (B3): pusat gugus tepat di bawah kabel, balon atas menyentuh kabel
	local ci = 0
	for li, z in C.lines do
		-- kabel bunting: gugus di ujung kabel (di luar deretan kartu), supaya huruf tidak tertutup balon
		local xs = if li == P.bunting.line then { C.westX + 8, C.eastX - 8 } else { -12, 18 }
		for _, x in xs do
			ci += 1
			local wy = stringY(x) -- jalur gugus menembus kabel → balon teratas pasti menyentuh kabel (terikat)
			Prefabs.garland(b, canopy, string.format("Cluster_%02d", ci), { Vector3.new(x, wy - 2.4, z), Vector3.new(x, wy + 0.2, z) }, 5000 + ci, { spread = 0.8, perStep = 3, step = 0.9, minSize = 1.8, maxSize = 2.4 })
		end
	end
	-- bunting: kartu hitam bergaris pink, huruf putih; sisi selatan (Back) terbaca kiri→kanan = x naik, sisi utara (Front) urutan
	-- dibalik supaya terbaca dari lantai dansa juga. Tepi atas kartu tepat di kabel (tergantung).
	local B = P.bunting
	local bunting = b:model(canopy, "Bunting")
	local bz = C.lines[B.line]
	local chars = {}
	for ch in string.gmatch(B.text, ".") do
		table.insert(chars, ch)
	end
	local pitch = B.cardW + B.gap
	local x0 = B.centerX - (#chars - 1) * pitch / 2
	for i, ch in chars do
		local back = chars[#chars + 1 - i] -- huruf sisi utara di slot yang sama (urutan terbalik)
		if ch ~= " " or back ~= " " then -- slot spasi di satu sisi = kartu polos di sisi itu (jeda antar kata)
			local x = x0 + (i - 1) * pitch
			local card = b:part(bunting, string.format("Card_%02d", i), { size = Vector3.new(B.cardW, B.cardH, 0.15), cf = CFrame.new(x, stringY(x) - 0.06 - B.cardH / 2, bz), color = "Black", material = "Plastic", decor = true, noShadow = true })
			if ch ~= " " then
				b:balloonText(card, ch, "Back", "White", "PartyPink")
			end
			if back ~= " " then
				b:balloonText(card, back, "Front", "White", "PartyPink")
			end
		end
	end
	local mz = C.lines[2]
	local topBall = stringY(P.cake.x) - 1.2
	b:part(canopy, "MirrorBall_Rod", { size = Vector3.new(0.15, 1.2, 0.15), cf = CFrame.new(P.cake.x, topBall + 0.6, mz), color = "PartySilver", material = "Metal", decor = true, noShadow = true })
	b:part(canopy, "MirrorBall", { size = Vector3.new(6, 6, 6), cf = CFrame.new(P.cake.x, topBall - 3, mz), color = "PartySilver", material = "Foil", reflectance = 0.4, shape = "Ball", decor = true, noShadow = true })

	-- 5) kue raksasa 3 tingkat (padat) di lantai dansa: hitam–putih–hitam, pita pink & perak, 7 lilin putih + nyala neon
	local K = P.cake
	local cake = b:model(b:folder(nil, "Cake"), "Cake_Main")
	local up = CFrame.Angles(0, 0, math.rad(90)) -- silinder Roblox memanjang di sumbu X → tegak
	local y = K.floorY
	for i, t in { { 18, 5, "Black", "PartyPink" }, { 13, 5, "White", "PartyPink" }, { 8, 4, "Black", "PartySilver" } } do
		b:part(cake, "Tier_0" .. i, { size = Vector3.new(t[2], t[1], t[1]), cf = CFrame.new(K.x, y + t[2] / 2, K.z) * up, color = t[3], material = "Plastic", reflectance = 0.05, shape = "Cylinder" })
		b:part(cake, "Band_0" .. i, { size = Vector3.new(0.5, t[1] + 0.3, t[1] + 0.3), cf = CFrame.new(K.x, y + t[2] - 0.45, K.z) * up, color = t[4], material = if t[4] == "PartySilver" then "Metal" else "Plastic", reflectance = 0.2, shape = "Cylinder", decor = true })
		y += t[2]
	end
	for i = 1, 7 do
		local ang = (i - 1) * 2 * math.pi / 7
		local cx, cz = K.x + 2.6 * math.cos(ang), K.z + 2.6 * math.sin(ang)
		b:part(cake, string.format("Candle_%02d", i), { size = Vector3.new(2.2, 0.5, 0.5), cf = CFrame.new(cx, y + 1.1, cz) * up, color = "White", material = "Plastic", shape = "Cylinder", decor = true })
		b:part(cake, string.format("Flame_%02d", i), { size = Vector3.new(0.5, 0.5, 0.5), cf = CFrame.new(cx, y + 2.45, cz), color = "NeonWhite", material = "Neon", shape = "Ball", decor = true })
	end
	Prefabs.markBelow(cake)

	-- 6) confetti ringan dari atas lantai dansa
	local F = P.confetti
	local emitter = b:part(b:folder(nil, "Confetti"), "Confetti_Source", {
		size = Vector3.new(F.maxX - F.minX, 0.2, F.maxZ - F.minZ),
		cf = CFrame.new((F.minX + F.maxX) / 2, F.y, (F.minZ + F.maxZ) / 2),
		transparency = 1,
		decor = true,
	})
	for _, c in { { "Confetti_Pink", "PartyPink" }, { "Confetti_White", "White" }, { "Confetti_Silver", "PartySilver" } } do
		b:confetti(emitter, c[1], c[2], F.texture, F.rate)
	end

	-- 7) spot foto HAVN STUDIO (B2): garland di luar bingkai (bukaan 12 × 10 tetap bebas), kolom balon di 2 sudut belakang,
	--    pita tulisan di atas cyclorama (terlihat lewat bingkai dari pintu, di atas kepala avatar tertinggi)
	local S = P.studio
	local studio = b:folder(nil, "Studio")
	local small = { minSize = 0.9, maxSize = 1.8, spread = 0.7, step = 0.9 }
	for i, side in { -1, 1 } do
		local x = S.cx + side * (S.postOuter + 0.5)
		local label = if side < 0 then "West" else "East"
		Prefabs.garland(b, studio, "Frame_Garland_" .. label, { Vector3.new(x, S.floorY + 0.9, S.frameZ), Vector3.new(x, S.frameTop, S.frameZ) }, 6001 + i, {
			minSize = small.minSize, maxSize = small.maxSize, spread = small.spread, step = small.step, floorY = S.floorY,
			maxX = if side < 0 then S.cx - S.postOuter + 1.9 else nil, -- tidak masuk bukaan bingkai (tepi dalam tiang 88.0 / 100.0)
			minX = if side > 0 then S.cx + S.postOuter - 1.9 else nil,
		})
		Prefabs.garland(b, studio, "Corner_Balloons_" .. label, { Vector3.new(S.cornerX[i], S.floorY + 0.9, S.cornerZ), Vector3.new(S.cornerX[i], S.floorY + 5, S.cornerZ) }, 6101 + i, {
			minSize = 1.2, maxSize = 2.0, spread = 0.6, step = 0.9, floorY = S.floorY,
		})
	end
	Prefabs.garland(b, studio, "Frame_Garland_Top", { Vector3.new(S.cx - S.postOuter - 0.5, S.frameTop + 1, S.frameZ), Vector3.new(S.cx + S.postOuter + 0.5, S.frameTop + 1, S.frameZ) }, 6201, {
		minSize = small.minSize, maxSize = small.maxSize, spread = small.spread, step = small.step, minY = S.frameTop,
	})
	local banner = b:part(studio, "Text_Backdrop", { size = Vector3.new(20, 2.8, 0.1), cf = CFrame.new(S.cx, S.frameTop + 1.4 - 0.2, S.wallZ - 0.1), transparency = 1, decor = true })
	b:balloonText(banner, "HAPPY BIRTHDAY", "Front", "White", "PartyPink")

	-- lubang dansa & lajur granit timur = objek tetap: dekor di atas/di bibirnya diizinkan (tes: tanpa menembus part lubang)
	for _, f in { arch, canopy, b.root:FindFirstChild("Cake"), b.root:FindFirstChild("Confetti") } do
		Prefabs.allowFixed(f, PIT)
	end
end
