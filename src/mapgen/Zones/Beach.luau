--!strict
-- MapGen/Zones/Beach — pantai barat (pasir rata x −88…−60 dirender y 6 = lantai; dek kayu x −60…−44):
-- Container Bar (kontainer PBR + meja bar + kursi bar ber-Seat + rak neon + kanopi bernama), kursi berjemur + payung,
-- bean bag, menara penjaga pantai, palem, papan selancar. Pola map club pantai: bar di samping, lounge menghadap air.

local Prefabs = require(script.Parent.Parent.Prefabs)

return function(b: any, L: any)
	local G = L.groundY
	local at = Prefabs.at

	-- Container Bar (z −45…−15): kontainer = dinding belakang, meja bar menghadap timur ke dek kayu
	local bar = b:model(b:folder(nil, "ContainerBar"), "ContainerBar_Main")
	b:clone(bar, "ContainerYellow", at(-82, G, -30, 90), "Container_Back")
	Prefabs.facing(b, bar, "Kit_NeonBarShelf", -75.5, G, -30, -90, "BarShelf") -- rak menghadap tamu (timur)
	for i, z in { -38, -30, -22 } do
		b:clone(bar, "Kit_BarCounter", at(-71.5, G, z, 90), string.format("BarCounter_%02d", i))
	end
	for i, z in { -38, -32, -26, -20 } do
		Prefabs.facing(b, bar, "Kit_BarStool", -67.5, G, z, 90, string.format("BarStool_%02d", i)) -- menghadap meja bar (barat)
	end
	for i, p in { { -77, -44 }, { -77, -16 }, { -64.5, -44 }, { -64.5, -16 } } do
		b:part(bar, "Canopy_Post_0" .. i, { size = Vector3.new(0.6, 11, 0.6), cf = CFrame.new(p[1], G + 5.5, p[2]), color = "Chrome", material = "Chrome" })
	end
	b:part(bar, "Canopy_Roof", { size = Vector3.new(14, 0.6, 30), cf = CFrame.new(-70.75, G + 11.3, -30), color = "PastelPink", material = "Plastic" })
	local sign = b:part(bar, "Canopy_Sign", { size = Vector3.new(0.6, 3, 22), cf = CFrame.new(-63.6, G + 13.1, -30), color = "Asphalt", material = "Metal" })
	b:sign(sign, "HAVN BEACH BAR", "Right", "HotPink")
	b:part(bar, "Neon_Canopy", { size = Vector3.new(0.3, 0.3, 30), cf = CFrame.new(-63.8, G + 10.9, -30), color = "Lime", material = "Neon" })
	for i, z in { -37, -23 } do
		b:clone(bar, "Kit_FairyLights", at(-64.2, G + 9.2, z, 0), string.format("FairyLights_%02d", i))
	end

	-- lounge: bean bag dekat bar
	local lounge = b:folder(nil, "Lounge")
	for i, p in { { -70, -58 }, { -64, -58 }, { -70, -52 }, { -64, -52 } } do
		Prefabs.facing(b, lounge, "Kit_BeanBag", p[1], G, p[2], 90, string.format("BeanBag_%02d", i)) -- menghadap laut (barat)
	end

	-- kursi berjemur menghadap laut (kepala ke timur) + payung
	local sun = b:folder(nil, "Sunbeds")
	local colors = { "HotPink", "IceBlue", "Lime", "Lilac", "HotPink", "IceBlue" }
	for i = 1, 6 do
		local z = 2 + (i - 1) * 7
		Prefabs.lounger(b, sun, string.format("Lounger_%02d", i), at(-76, G, z, 0), colors[i])
	end
	for i, z in { 5.5, 19.5, 33.5 } do
		Prefabs.umbrella(b, sun, string.format("Umbrella_%02d", i), -81, z, G, if i == 2 then "Lilac" else "PastelPink")
	end

	-- menara penjaga pantai, palem, papan selancar
	local deco = b:folder(nil, "Deco")
	Prefabs.facing(b, deco, "Kit_LifeguardTower", -74, G, 84, 90, "LifeguardTower_01", 0.7) -- menghadap laut (barat)
	for i, p in { { -86, -56 }, { -84, 50 }, { -66, 50 }, { -84, 97 } } do
		b:clone(deco, "Kit_PalmTree", at(p[1], G, p[2], i * 90), string.format("PalmTree_%02d", i), 0.55)
	end
	b:clone(deco, "Kit_Surfboards", at(-62, G, 66, 90), "Surfboards_01")
end
