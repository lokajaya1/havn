--!strict
-- MapGen/Zones/Boundary — dinding batas map tak terlihat, CollisionGroup DoorVVIP (hanya VVIP tembus,
-- lihat PlayerCollisionManager). Menggantikan `CollisionWater` lama yang terlalu luas.

return function(b: any, L: any)
	local B = L.boundary
	local H, T = 145, 2
	local y = L.sea.floorY + H / 2
	local w = (B.maxX - B.minX) + 2 * T
	local d = (B.maxZ - B.minZ)
	local walls = {
		{ "Wall_North", (B.minX + B.maxX) / 2, B.minZ - T / 2, w, T },
		{ "Wall_South", (B.minX + B.maxX) / 2, B.maxZ + T / 2, w, T },
		{ "Wall_West", B.minX - T / 2, (B.minZ + B.maxZ) / 2, T, d },
		{ "Wall_East", B.maxX + T / 2, (B.minZ + B.maxZ) / 2, T, d },
	}
	for _, v in walls do
		b:part(b.root, v[1], {
			size = Vector3.new(v[4], H, v[5]),
			cf = CFrame.new(v[2], y, v[3]),
			transparency = 1,
			collisionGroup = "DoorVVIP",
		})
	end
end
