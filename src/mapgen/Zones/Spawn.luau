--!strict
-- MapGen/Zones/Spawn — plaza spawn di tengah selatan: 2 SpawnLocation netral (z 86) menghadap utara, gerbang krom
-- "HAVN" di z 72 membingkai garis pandang lurus: gerbang → penyeberangan → lantai dansa → DJ STAGE (pola map club:
-- pintu masuk = momen, panggung di ujung sumbu). TimePlayedLeaderboard berdiri di sisi barat plaza.

return function(b: any, L: any)
	local G = L.groundY
	local gz = 72
	local gate = b:model(nil, "Gate_HAVN")
	for _, x in { -14, 14 } do
		b:part(gate, if x < 0 then "Pillar_West" else "Pillar_East", { size = Vector3.new(4, 20, 4), cf = CFrame.new(x, G + 10, gz), color = "Chrome", material = "Chrome" })
		b:part(gate, if x < 0 then "Neon_West" else "Neon_East", { size = Vector3.new(0.6, 18, 4.2), cf = CFrame.new(x + (if x < 0 then 2.3 else -2.3), G + 10, gz), color = "HotPink", material = "Neon" })
	end
	local top = b:part(gate, "Sign_Top", { size = Vector3.new(32, 5, 3), cf = CFrame.new(0, G + 22.5, gz), color = "Steel", material = "Metal" })
	b:part(gate, "Neon_Sign_Under", { size = Vector3.new(32, 0.4, 3.2), cf = CFrame.new(0, G + 19.8, gz), color = "IceBlue", material = "Neon" })
	b:sign(top, "HAVN", "Front", "IceBlue")
	b:sign(top, "HAVN", "Back", "IceBlue")
	local pads = b:folder(nil, "SpawnPads")
	b:spawn(pads, "Spawn_Main_A", CFrame.new(-8, G + 0.5, 86))
	b:spawn(pads, "Spawn_Main_B", CFrame.new(8, G + 0.5, 86))
end
