--!strict
-- MapGen/Zones/Beach — pantai barat + teras kolam "HAVN POOL" (R4b, foto acuan user 30 Sep: kolam modern, coping putih,
-- sunken lounge, pergola hitam, dek kayu). Monokrom + kayu hangat (D5). Ukuran dari Layout.poolTerrace/pool/lounge.
--   dek y 4.5 (turun 2 anak tangga 0.5 dari dek kayu pantai y 6) · kolam 24 × 56 air y 4 dalam 14 (P13) · coping 0.5 di atas air
--   · tangga putih lebar di ujung selatan kolam (anak tangga 0.5, terbukti tanpa lompat) · sunken lounge lantai 2.5 + sofa
--   built-in (6 Seat) + meja api (lampu hangat) · pergola bilah hitam (bawah bilah 12.4 di atas dek ≥ A1) · 8 kursi berjemur
--   menghadap kolam & laut · bar kolam 4 kursi + dinding foto "HAVN POOL". Pantai selatan: menara penjaga, palem, papan selancar.

local Prefabs = require(script.Parent.Parent.Prefabs)

type Box = { x1: number, x2: number, y1: number, y2: number, z1: number, z2: number }

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local T, P, Lo = L.poolTerrace, L.pool, L.lounge
	local D = T.deckY
	local root = b:folder(nil, "PoolTerrace")
	local function blk(parent: Instance, name: string, x: Box, colorKey: string, material: string, extra: { [string]: any }?)
		local spec: { [string]: any } = {
			size = Vector3.new(x.x2 - x.x1, x.y2 - x.y1, x.z2 - x.z1),
			cf = CFrame.new((x.x1 + x.x2) / 2, (x.y1 + x.y2) / 2, (x.z1 + x.z2) / 2),
			color = colorKey,
			material = material,
		}
		for k, v in extra or {} do
			spec[k] = v
		end
		return b:part(parent, name, spec :: any)
	end
	local function box(x1: number, x2: number, y1: number, y2: number, z1: number, z2: number): Box
		return { x1 = x1, x2 = x2, y1 = y1, y2 = y2, z1 = z1, z2 = z2 }
	end

	-- 1) dek kayu (y −2…4.5) = teras dikurangi kolam+dinding & lubang lounge (5 persegi, tanpa celah/tumpang — diuji)
	local deck = b:folder(root, "Deck")
	local W = P.wall
	for i, r in {
		box(T.minX, Lo.minX, -2, D, T.minZ, P.minZ), -- barat laut
		box(Lo.minX, P.maxX, -2, D, Lo.maxZ, P.minZ), -- strip antara lounge & kolam
		box(Lo.maxX, T.maxX, -2, D, T.minZ, Lo.maxZ), -- timur laut
		box(P.maxX, T.maxX, -2, D, Lo.maxZ, T.maxZ), -- timur (kursi berjemur)
		box(T.minX, P.maxX, -2, D, P.maxZ, T.maxZ), -- selatan (bar)
	} do
		blk(deck, string.format("Deck_%02d", i), r, "Timber", "Wood", { floor = true })
	end
	-- tepi teras (menutup muka pasir/terrain, P5) & tangga turun dari dek kayu pantai (y 6) di sisi timur
	blk(deck, "Rim_North", box(T.minX - 1, T.maxX, 0, G, T.minZ - 1, T.minZ), "OffWhite", "Plastic")
	blk(deck, "Rim_South", box(T.minX - 1, T.maxX, 0, G, T.maxZ, T.maxZ + 1), "OffWhite", "Plastic")
	blk(deck, "Rim_West", box(T.minX - 1, T.minX, P.floorY, G, T.minZ, T.maxZ), "OffWhite", "Plastic")
	for k = 1, 2 do
		local top = G - k * 0.5
		blk(deck, "Step_East_0" .. k, box(T.maxX - k, T.maxX - k + 1, D, top, T.minZ, T.maxZ), "Timber", "Wood")
	end

	-- 2) kolam: dinding/coping putih 4 tebal (y −12…4.5), air terrain y 4 (zona Terrain), tanpa lantai part
	local pool = b:folder(root, "Pool")
	local walls = {
		Wall_West = box(P.minX, P.minX + W, P.floorY, D, P.minZ, P.maxZ),
		Wall_East = box(P.maxX - W, P.maxX, P.floorY, D, P.minZ, P.maxZ),
		Wall_North = box(P.minX + W, P.maxX - W, P.floorY, D, P.minZ, P.minZ + W),
		Wall_South = box(P.minX + W, P.maxX - W, P.floorY, D, P.maxZ - W, P.maxZ),
	}
	local wallParts: { [string]: BasePart } = {}
	for _, n in { "Wall_West", "Wall_East", "Wall_North", "Wall_South" } do
		wallParts[n] = blk(pool, n, walls[n], "OffWhite", "Plastic")
	end
	b:surfaceLight(wallParts.Wall_West, "Right", "CoolLight", 1, 16, 90) -- lampu bawah air (sumber tersembunyi)
	b:surfaceLight(wallParts.Wall_East, "Left", "CoolLight", 1, 16, 90)
	-- tangga putih lebar di ujung selatan (keluar dari air tanpa lompat): pelat 0.5, anak tangga 0.5 × 1, sampai dalam 5
	local ix1, ix2 = P.minX + W, P.maxX - W
	local k = 0
	while true do
		k += 1
		local top = D - k * 0.5
		if top < P.surfaceY - 5 then
			break
		end
		blk(pool, string.format("Step_%02d", k), box(ix1, ix2, top - 0.5, top, P.maxZ - W - k, P.maxZ - W - k + 1), "OffWhite", "Plastic")
	end
	b:part(pool, "Neon_Coping", { size = Vector3.new(ix2 - ix1, 0.2, 0.2), cf = CFrame.new((ix1 + ix2) / 2, D - 0.1, P.minZ + W + 0.1), color = "NeonWhite", material = "Neon", decor = true })

	-- 3) sunken lounge: lantai 2.5, tangga 3 × 0.5 (lebar 10) dari dek di sisi timur, sofa built-in utara & barat, meja api
	local lounge = b:folder(root, "Lounge")
	local sx = Lo.maxX - 4 -- tangga x −76…−72
	blk(lounge, "Floor", box(Lo.minX, sx + 1, 0, Lo.floorY, Lo.minZ, Lo.maxZ), "Stone", "Concrete", { floor = true })
	for s = 1, 3 do
		local top = D - s * 0.5
		blk(lounge, "Step_0" .. s, box(Lo.maxX - s, Lo.maxX - s + 1, 0, top, Lo.minZ, Lo.maxZ), "Stone", "Concrete")
	end
	local seatY = 3.8
	blk(lounge, "Sofa_North", box(Lo.minX, sx, Lo.floorY, seatY, Lo.minZ, Lo.minZ + 2), "OffWhite", "Plastic")
	blk(lounge, "Sofa_North_Back", box(Lo.minX, sx, seatY, 5.5, Lo.minZ, Lo.minZ + 0.6), "OffWhite", "Plastic")
	blk(lounge, "Sofa_West", box(Lo.minX, Lo.minX + 2, Lo.floorY, seatY, Lo.minZ + 2, Lo.maxZ), "OffWhite", "Plastic")
	blk(lounge, "Sofa_West_Back", box(Lo.minX, Lo.minX + 0.6, seatY, 5.5, Lo.minZ + 2, Lo.maxZ), "OffWhite", "Plastic")
	local seats = b:folder(lounge, "Seats")
	for i = 1, 4 do -- menghadap selatan (+Z); mulai setelah sofa barat (x −90)
		local x = Lo.minX + 3.5 + (i - 1) * 3.5
		local p = Vector3.new(x, seatY + 0.1, Lo.minZ + 1.1)
		b:seat(seats, string.format("Seat_North_%02d", i), CFrame.new(p) * CFrame.Angles(0, math.pi, 0), Vector3.new(3, 0.2, 1.6))
	end
	for i, z in { Lo.minZ + 4, Lo.minZ + 7.5 } do -- menghadap timur (+X)
		local p = Vector3.new(Lo.minX + 1.1, seatY + 0.1, z)
		b:seat(seats, string.format("Seat_West_%02d", i), CFrame.new(p) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(3, 0.2, 1.6))
	end
	local fx, fz = (Lo.minX + sx) / 2 + 1, (Lo.minZ + Lo.maxZ) / 2 + 0.5
	blk(lounge, "FireTable", box(fx - 3, fx + 3, Lo.floorY, Lo.floorY + 1, fz - 1, fz + 1), "OffWhite", "Plastic")
	local burner = blk(lounge, "FireTable_Burner", box(fx - 2.5, fx + 2.5, Lo.floorY + 1, Lo.floorY + 1.1, fz - 0.4, fz + 0.4), "Black", "Metal", { decor = true })
	b:surfaceLight(burner, "Top", "WarmLight", 2, 12, 120)

	-- 4) pergola bilah hitam di atas lounge (bawah bilah y 16.9: 12.4 di atas dek, 14.4 di atas lantai lounge)
	local perg = b:model(lounge, "Pergola")
	local px1, px2, pz1, pz2 = Lo.minX - 3, Lo.maxX + 3, Lo.minZ + 0.5, Lo.maxZ + 1.5
	local py = 17
	for i, p in { { px1, pz1 }, { px1, pz2 }, { px2, pz1 }, { px2, pz2 } } do
		b:part(perg, "Post_0" .. i, { size = Vector3.new(0.8, py - D, 0.8), cf = CFrame.new(p[1], (D + py) / 2, p[2]), color = "Black", material = "Metal" })
	end
	for i, z in { pz1, pz2 } do
		b:part(perg, "Beam_0" .. i, { size = Vector3.new(px2 - px1 + 0.8, 0.8, 0.8), cf = CFrame.new((px1 + px2) / 2, py + 0.4, z), color = "Black", material = "Metal" })
	end
	local n = 0
	for x = px1 + 1, px2 - 1, 2 do
		n += 1
		b:part(perg, string.format("Slat_%02d", n), { size = Vector3.new(0.4, 0.6, pz2 - pz1 + 1), cf = CFrame.new(x, py + 1.1, (pz1 + pz2) / 2), color = "Black", material = "Metal" })
	end

	-- 5) kursi berjemur di dek timur (kepala ke timur → menghadap kolam & laut), 8 Seat
	local sun = b:folder(root, "Sunbeds")
	for i = 1, 8 do
		local z = P.minZ + 6 + (i - 1) * 7
		Prefabs.lounger(b, sun, string.format("Lounger_%02d", i), at((P.maxX + T.maxX - 2) / 2, D, z, 0), if i % 2 == 0 then "Black" else "OffWhite")
	end

	-- 6) bar kolam + dinding foto "HAVN POOL" di dek selatan (menghadap utara, ke kolam)
	local bar = b:model(b:folder(root, "PoolBar"), "PoolBar_Main")
	local bz = T.maxZ
	blk(bar, "BackWall", box(P.minX + W, P.maxX - W, D, D + 11.5, bz - 1, bz), "Black", "Metal")
	blk(bar, "Counter", box(P.minX + W + 4, P.maxX - W - 4, D, D + 3.5, bz - 3, bz - 1), "Black", "Plastic")
	blk(bar, "Counter_Top", box(P.minX + W + 3.8, P.maxX - W - 3.8, D + 3.5, D + 3.7, bz - 3.2, bz - 1), "OffWhite", "Plastic")
	local sign = blk(bar, "Sign_Board", box(P.minX + W + 6, P.maxX - W - 6, D + 7, D + 10, bz - 1.2, bz - 1), "Black", "Metal")
	b:sign(sign, "HAVN POOL", "Front", "NeonWhite")
	b:part(bar, "Neon_Sign_Under", { size = Vector3.new((P.maxX - W - 6) - (P.minX + W + 6), 0.2, 0.2), cf = CFrame.new((P.minX + P.maxX) / 2, D + 6.6, bz - 1.2), color = "NeonWhite", material = "Neon", decor = true })
	b:surfaceLight(bar.Counter_Top, "Top", "WarmLight", 1, 8, 90)
	for i, x in { P.minX + W + 5.5, P.minX + W + 9.5, P.minX + W + 13.5, P.minX + W + 17.5 } do
		Prefabs.facing(b, bar, "Kit_BarStool", x, D, bz - 5, 180, string.format("BarStool_%02d", i)) -- menghadap meja (selatan)
	end
	Prefabs.markBelow(root) -- teras sengaja di bawah lantai y 6 (dek 4.5, lounge 2.5, kolam)

	-- 7) pantai selatan: menara penjaga pantai, palem, papan selancar
	local deco = b:folder(nil, "Deco")
	Prefabs.facing(b, deco, "Kit_LifeguardTower", -74, G, 84, 90, "LifeguardTower_01", 0.7) -- menghadap laut (barat)
	for i, p in { { -86, 36 }, { -84, 50 }, { -66, 50 }, { -84, 97 } } do
		b:clone(deco, "Kit_PalmTree", at(p[1], G, p[2], i * 90), string.format("PalmTree_%02d", i), 0.55)
	end
	b:clone(deco, "Kit_Surfboards", at(-62, G, 66, 90), "Surfboards_01")
end
