--!strict
-- MapGen/Zones/Blockout — R1: kotak abu-abu seukuran bangunan untuk cek skala & tata letak di Play.
-- Semua tembus (decor) & agak transparan supaya map lama tetap terlihat. Dihapus setelah zona asli dibangun.

return function(b: any, L: any)
	local G = L.groundY
	local function box(parent: Instance, name: string, cx: number, cz: number, sx: number, sy: number, sz: number, colorKey: string, y0: number?)
		return b:part(parent, name, {
			size = Vector3.new(sx, sy, sz),
			cf = CFrame.new(cx, (y0 or G) + sy / 2, cz),
			color = colorKey,
			transparency = 0.35,
			decor = true,
		})
	end

	-- Stage (sekitar lantai dansa; DJ STAGE tidak disentuh)
	local stage = b:folder(nil, "Stage")
	local f = L.danceFloor
	local rim = box(stage, "DanceFloor_Rim_West", f.x - f.halfX - 1, -30, 2, 1, 108, "Lilac")
	box(stage, "DanceFloor_Rim_East", f.x + f.halfX + 1, -30, 2, 1, 108, "Lilac")
	box(stage, "DanceFloor_Rim_South", f.x, f.z + f.halfZ + 1, f.halfX * 2 + 4, 1, 2, "Lilac")
	box(stage, "Railing_Chrome_West", f.x - f.halfX - 6, -30, 1, 4, 108, "Chrome")
	box(stage, "Railing_Chrome_East", f.x + f.halfX + 6, -30, 1, 4, 108, "Chrome")
	b:label(stage, rim, "STAGE · lantai dansa")

	-- Plaza donasi (DonationBoards dipindah ke sini di R7)
	local plaza = b:folder(nil, "Plaza")
	local wall = box(plaza, "DonationWall", 88, -45, 4, 22, 70, "Lime")
	box(plaza, "Podium_Top3", 76, -45, 12, 2, 24, "Chrome")
	b:label(plaza, wall, "PLAZA DONASI")

	-- Harbor (timur): tumpukan kontainer 3 lebar × 2 tinggi, derek gantry, gudang, pagar kawat
	local harbor = b:folder(nil, "Harbor")
	local stacks = { { 120, -285 }, { 160, -285 }, { 200, -285 }, { 120, -250 }, { 160, -250 }, { 200, -250 }, { 200, -215 } }
	for i, p in stacks do
		box(harbor, string.format("ContainerStack_%02d", i), p[1], p[2], 29.2, 19.3, 28.9, "ContainerOrange")
	end
	local crane = b:model(harbor, "Crane_Gantry_01")
	for i, c in { { 162, -160 }, { 198, -160 }, { 162, -140 }, { 198, -140 } } do
		box(crane, string.format("Leg_%02d", i), c[1], c[2], 3, 60, 3, "ContainerRed")
	end
	box(crane, "Beam_Top", 180, -150, 52, 5, 26, "ContainerRed", G + 60)
	local warehouse = box(harbor, "Warehouse_Main", 165, -80, 60, 28, 45, "Concrete")
	box(harbor, "Fence_West_North", 97, -258, 1, 10, 84, "Chrome") -- berhenti di z −216: jalur efek donasi bebas
	box(harbor, "Fence_West_South", 97, -30, 1, 10, 130, "Chrome")
	b:label(harbor, warehouse, "HARBOR")

	-- Street (selatan): jalan, trotoar, deretan toko Y2K, halte, billboard
	local street = b:folder(nil, "Street")
	local road = box(street, "Road_Main", 65, 100, 310, 0.4, 22, "Asphalt")
	box(street, "Sidewalk_North", 65, 86, 310, 0.6, 6, "Concrete")
	box(street, "Sidewalk_South", 65, 114, 310, 0.6, 6, "Concrete")
	local shops = { { -75, 22 }, { -48, 28 }, { 50, 24 }, { 80, 30 }, { 110, 20 }, { 140, 26 }, { 170, 22 }, { 202, 28 } }
	for i, s in shops do
		box(street, string.format("Storefront_%02d", i), s[1], 139, 26, s[2], 28, "HotPink")
	end
	box(street, "BusStop_01", 40, 83, 12, 9, 4, "IceBlue")
	box(street, "Billboard_01", 190, 60, 30, 14, 2, "Lilac", G + 16)
	b:label(street, road, "STREET")

	-- Beach (barat): laut, dermaga, menara penjaga, container bar, area santai
	local beach = b:folder(nil, "Beach")
	local sea = box(beach, "Sea_Placeholder", -205, -70, 30, 0.4, 460, "Sea", G - 1)
	box(beach, "Pier_Main", -190, -20, 60, 1, 14, "Wood", G + 1)
	local tower = b:model(beach, "LifeguardTower_01")
	box(tower, "Base", -175, 70, 8, 14, 8, "Chrome")
	box(tower, "Cabin", -175, 70, 10, 6, 10, "HotPink", G + 14)
	box(beach, "ContainerBar_Main", -120, -140, 30, 10, 20, "ContainerBlue")
	box(beach, "Lounge_Area", -170, -60, 30, 1, 20, "Sand")
	b:label(beach, sea, "BEACH · laut")

	-- PoolDeck: dek kayu + 2 kolam kontainer
	local pool = b:folder(nil, "PoolDeck")
	local deck = box(pool, "Deck_Main", -120, -10, 60, 1, 100, "Wood")
	box(pool, "Pool_Container_01", -120, -25, 29.2, 9.6, 9.6, "IceBlue", G + 1)
	box(pool, "Pool_Container_02", -120, 5, 29.2, 9.6, 9.6, "IceBlue", G + 1)
	b:label(pool, deck, "CONTAINER POOL")

	-- Spawn: gerbang HAVN
	local spawn = b:folder(nil, "Spawn")
	local gate = b:model(spawn, "Gate_HAVN")
	box(gate, "Pillar_West", -14, 150, 4, 20, 4, "Chrome")
	box(gate, "Pillar_East", 14, 150, 4, 20, 4, "Chrome")
	local top = box(gate, "Sign_Top", 0, 150, 32, 4, 4, "HotPink", G + 20)
	b:label(spawn, top, "SPAWN · gerbang HAVN")
end
