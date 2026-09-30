--!strict
-- MapGen/Zones/Spawn — gerbang HAVN krom + 2 SpawnLocation baru di tepi selatan pulau (pengganti spawn lama z ±170).

return function(b: any, L: any)
	local G = L.groundY
	local gate = b:model(nil, "Gate_HAVN")
	for _, x in { -14, 14 } do
		b:part(gate, if x < 0 then "Pillar_West" else "Pillar_East", { size = Vector3.new(4, 20, 4), cf = CFrame.new(x, G + 10, 92), color = "Chrome", material = "Chrome" })
		b:part(gate, if x < 0 then "Neon_West" else "Neon_East", { size = Vector3.new(0.6, 18, 4.2), cf = CFrame.new(x + (if x < 0 then 2.1 else -2.1), G + 10, 92), color = "HotPink", material = "Neon" })
	end
	local top = b:part(gate, "Sign_Top", { size = Vector3.new(32, 5, 3), cf = CFrame.new(0, G + 22.5, 92), color = "Steel", material = "Metal" })
	b:sign(top, "HAVN", "Front", "IceBlue")
	b:sign(top, "HAVN", "Back", "IceBlue")
	local pads = b:folder(nil, "SpawnPads")
	b:spawn(pads, "Spawn_Main_A", CFrame.new(-8, G + 0.5, 84))
	b:spawn(pads, "Spawn_Main_B", CFrame.new(8, G + 0.5, 84))
end
