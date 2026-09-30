--!strict
-- MapGen/Zones/VipLounge — VIP Lounge timur (pola map club: VIP DITINGGIKAN menghadap lantai dansa, naik tangga).
-- Area x 96…151, z −8…39 dikelilingi dinding tak terlihat CollisionGroup "DoorVIP" (VIP & VVIP tembus, pemain biasa
-- terhalang — PlayerCollisionManager, pengganti `Vip Door02` lama). Lantai atas: dek x 100…128 (y 16) menghadap barat.
-- Lantai dasar: bar kontainer VIP + sofa. Semua Seat menghadap barat (dek) / timur (kursi bar).

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at
	local x1, x2, z1, z2 = 96, 151, -8, 39 -- dinding (tebal 1) di luar garis ini, tetap di dalam zona x 92…152, z −64…40
	local deckY = G + 10

	-- dinding DoorVIP (tak terlihat) di keliling area
	local walls = b:folder(nil, "VipWalls")
	local H = 30
	for _, w in {
		{ "Wall_West", x1 - 0.5, (z1 + z2) / 2, 1, z2 - z1 + 2 },
		{ "Wall_East", x2 + 0.5, (z1 + z2) / 2, 1, z2 - z1 + 2 },
		{ "Wall_North", (x1 + x2) / 2, z1 - 0.5, x2 - x1, 1 },
		{ "Wall_South", (x1 + x2) / 2, z2 + 0.5, x2 - x1, 1 },
	} do
		b:part(walls, w[1], { size = Vector3.new(w[4], H, w[5]), cf = CFrame.new(w[2], G + H / 2, w[3]), transparency = 1, collisionGroup = "DoorVIP" })
	end

	-- tanda batas VIP: tali beludru di sisi barat & selatan, gerbang neon "VIP"
	local edge = b:folder(nil, "Edge")
	for i, z in { -3, 5.5, 26, 34.5 } do
		b:clone(edge, "Kit_VipRope", at(x1 + 1.5, G, z, 0), string.format("VipRope_%02d", i))
	end
	local gate = b:model(edge, "Gate_VIP")
	for i, z in { 11, 21 } do
		b:part(gate, "Post_0" .. i, { size = Vector3.new(1, 12, 1), cf = CFrame.new(x1 + 1, G + 6, z), color = "Chrome", material = "Chrome" })
		b:part(gate, "Neon_Post_0" .. i, { size = Vector3.new(0.4, 11, 0.4), cf = CFrame.new(x1 + 0.4, G + 6, z), color = "Lilac", material = "Neon" })
	end
	local sign = b:part(gate, "Sign", { size = Vector3.new(1, 3, 12), cf = CFrame.new(x1 + 1, G + 13.5, 16), color = "Asphalt", material = "Metal" })
	b:sign(sign, "VIP", "Left", "Lilac")

	-- dek atas (menghadap lantai dansa di barat) + 4 kolom krom + pagar kaca + tepi neon
	local deck = b:model(b:folder(nil, "Deck"), "Deck_Upper")
	local dx1, dx2, dz1, dz2 = 100, 128, 4, 36
	b:part(deck, "Floor", { size = Vector3.new(dx2 - dx1, 1, dz2 - dz1), cf = CFrame.new((dx1 + dx2) / 2, deckY - 0.5, (dz1 + dz2) / 2), color = "Asphalt", material = "DiamondPlate" })
	for i, p in { { dx1 + 1, dz1 + 1 }, { dx1 + 1, dz2 - 1 }, { dx2 - 1, dz1 + 1 }, { dx2 - 1, dz2 - 7 } } do
		b:part(deck, "Column_0" .. i, { size = Vector3.new(1.2, deckY - 1 - G, 1.2), cf = CFrame.new(p[1], (G + deckY - 1) / 2, p[2]), color = "Chrome", material = "Chrome" })
	end
	for _, r in {
		{ "Rail_West", dx1 + 0.2, (dz1 + dz2) / 2, 0.3, dz2 - dz1 },
		{ "Rail_North", (dx1 + dx2) / 2, dz1 + 0.2, dx2 - dx1, 0.3 },
		{ "Rail_South", (dx1 + dx2) / 2, dz2 - 0.2, dx2 - dx1, 0.3 },
		{ "Rail_East", dx2 - 0.2, (dz1 + dz2 - 6) / 2, 0.3, dz2 - dz1 - 6 }, -- terbuka 6 stud di ujung tangga
	} do
		b:part(deck, r[1], { size = Vector3.new(r[4], 3.5, r[5]), cf = CFrame.new(r[2], deckY + 1.75, r[3]), color = "IceBlue", material = "Glass", transparency = 0.5 })
	end
	b:part(deck, "Neon_West", { size = Vector3.new(0.3, 0.3, dz2 - dz1), cf = CFrame.new(dx1 - 0.15, deckY - 0.5, (dz1 + dz2) / 2), color = "Lilac", material = "Neon" })
	b:part(deck, "Neon_North", { size = Vector3.new(dx2 - dx1, 0.3, 0.3), cf = CFrame.new((dx1 + dx2) / 2, deckY - 0.5, dz1 - 0.15), color = "HotPink", material = "Neon" })
	Prefabs.stairs(b, deck, "Stairs", dx2 + 20, dz2 - 6, dz2, G, deckY - G)

	-- perabot dek: meja tinggi ber-kursi & kursi telur menghadap barat, speaker
	local deckF = b:folder(nil, "DeckFurniture")
	Prefabs.seatFacing(b, deckF, "Kit_HighTable", 108, deckY, 12, 90, "HighTable_01")
	Prefabs.seatFacing(b, deckF, "Kit_HighTable", 108, deckY, 26, 90, "HighTable_02")
	Prefabs.seatFacing(b, deckF, "Kit_EggChair", 119, deckY, 10, 90, "EggChair_01")
	Prefabs.seatFacing(b, deckF, "Kit_EggChair", 119, deckY, 22, 90, "EggChair_02")
	for i, z in { 6.5, 33 } do
		Prefabs.facing(b, deckF, "Kit_SpeakerTripod", 103, deckY, z, 90, string.format("Speaker_%02d", i)) -- ke panggung (barat)
	end

	-- lantai dasar: bar kontainer VIP (kontainer = dinding belakang di timur), rak neon, meja bar, kursi bar, sofa
	local bar = b:model(b:folder(nil, "VipBar"), "VipBar_Main")
	b:clone(bar, "ContainerGreen", at(146, G, 9, 90), "Container_Back")
	Prefabs.facing(b, bar, "Kit_NeonBarShelf", 139.6, G, 9, 90, "BarShelf") -- rak terbuka menghadap tamu (barat)
	for i, z in { 1, 9, 17 } do
		b:clone(bar, "Kit_BarCounter", at(136, G, z, 90), string.format("BarCounter_%02d", i))
	end
	for i, z in { 1, 6, 12, 17 } do
		Prefabs.seatFacing(b, bar, "Kit_BarStool", 132, G, z, -90, string.format("BarStool_%02d", i))
	end
	local vipSign = b:part(bar, "Sign_Bar", { size = Vector3.new(0.6, 3, 16), cf = CFrame.new(141.3, G + 11.5, 9), color = "Asphalt", material = "Metal" })
	b:sign(vipSign, "VIP BAR", "Left", "HotPink")
	Prefabs.seatFacing(b, b:folder(nil, "Lounge"), "Kit_NeonSofa", 116, G, 0, 90, "NeonSofa_01")
end
