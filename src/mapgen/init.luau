--!strict
-- ServerStorage/MapGen (ModuleScript) — alat STUDIO untuk membangun map dari kode (tidak pernah di-require game).
-- Command Bar (mode Edit):
--   local G = require(game.ServerStorage.MapGen:Clone())   -- :Clone() = hindari cache require Command Bar
--   G.build("Ground", "CEK")     → laporan saja, tidak mengubah apa pun
--   G.build("Ground", "JALAN")   → ganti Workspace.Map.<zona> (bisa Ctrl+Z)
--   G.draft("SIMPAN") / G.draft("TAMPIL")  → pindah Workspace.Map ↔ ServerStorage.MapDraft (sebelum Publish)
-- Tema map (themeMap, claude/Rencana_Tema.md) — dekor yang di-switch admin saat game jalan:
--   G.themeMap("Birthday", "CEK")     → bangun di memori + semua cek, tidak mengubah apa pun
--   G.themeMap("Birthday", "JALAN")   → bangun ulang ke ServerStorage.ThemeMap.Birthday (bisa Ctrl+Z)
--   G.themeMap("Birthday", "TAMPIL")  → pindah ke Workspace.ThemeMap untuk dilihat/diubah tangan di mode Edit
--   G.themeMap("Birthday", "SIMPAN")  → kembalikan ke ServerStorage (WAJIB sebelum Save/Publish)
--   G.themeMap(nil, "DAFTAR")         → laporan semua tema: part, skrip, versi, cocok dengan kode atau tidak

local Builder = require(script.Builder)
local Naming = require(script.Naming)
local Layout = require(script.Layout)
local KitFront = require(script.KitFront)

local zones: { [string]: (any, any) -> () } = {
	Terrain = require(script.Zones.Terrain),
	Ground = require(script.Zones.Ground),
	Boundary = require(script.Zones.Boundary),
	Spawn = require(script.Zones.Spawn),
	Quay = require(script.Zones.Quay),
	ContainerWall = require(script.Zones.ContainerWall),
	LaunchPad = require(script.Zones.LaunchPad),
	Yard = require(script.Zones.Yard),
	Street = require(script.Zones.Street),
	Beach = require(script.Zones.Beach),
	Bay = require(script.Zones.Bay),
	VipLounge = require(script.Zones.VipLounge),
	Plaza = require(script.Zones.Plaza),
	Party = require(script.Zones.Party),
}

local Mood = require(script.Mood)

local MapGen = { version = "V20", layout = Layout, mood = Mood, kitFront = KitFront }

-- Tema map: nama tema → zona MapGen. Harus cocok dengan ReplicatedStorage.Config.ThemeMap.list (dicek tes).
-- Zona tema TIDAK dipasang ke Workspace.Map (G.build JALAN menolak) — hanya lewat G.themeMap → ServerStorage.ThemeMap.
MapGen.themeMaps = { Birthday = "Party" } :: { [string]: string }
local THEME_DIR = "ThemeMap"

local function themeOfZone(zoneName: string): string?
	for theme, zone in MapGen.themeMaps do
		if zone == zoneName then
			return theme
		end
	end
	return nil
end

type Env = { workspace: Instance, serverStorage: Instance, history: any?, terrain: any?, out: ((string) -> ())? }

local function defaultEnv(): Env
	return {
		workspace = workspace,
		serverStorage = game:GetService("ServerStorage"),
		history = game:GetService("ChangeHistoryService"),
	}
end

-- Kotak pembatas (sumbu dunia) dari CFrame + ukuran (termasuk yang diputar).
local function aabb(cf: CFrame, size: Vector3)
	local h = size / 2
	local ax = cf:VectorToWorldSpace(Vector3.new(h.X, 0, 0))
	local ay = cf:VectorToWorldSpace(Vector3.new(0, h.Y, 0))
	local az = cf:VectorToWorldSpace(Vector3.new(0, 0, h.Z))
	local e = Vector3.new(
		math.abs(ax.X) + math.abs(ay.X) + math.abs(az.X),
		math.abs(ax.Y) + math.abs(ay.Y) + math.abs(az.Y),
		math.abs(ax.Z) + math.abs(ay.Z) + math.abs(az.Z)
	)
	local p = cf.Position
	return { minX = p.X - e.X, maxX = p.X + e.X, minZ = p.Z - e.Z, maxZ = p.Z + e.Z, minY = p.Y - e.Y, maxY = p.Y + e.Y }
end

local function overlap(a: any, b: any): boolean
	return a.maxX > b.minX + 0.01 and a.minX < b.maxX - 0.01 and a.maxZ > b.minZ + 0.01 and a.minZ < b.maxZ - 0.01
end

local function inside(p: BasePart, a: any): boolean
	local box = aabb(p.CFrame, p.Size)
	return box.minX >= a.minX - 0.01 and box.maxX <= a.maxX + 0.01 and box.minZ >= a.minZ - 0.01 and box.maxZ <= a.maxZ + 0.01
end

-- maxY (opsional) = puncak objek: part yang seluruhnya di atasnya tidak menabrak (mis. atap di atas papan donasi).
local function touches(p: BasePart, a: any): boolean
	local box = aabb(p.CFrame, p.Size)
	return overlap(box, a) and (a.maxY == nil or box.minY < a.maxY - 0.01)
end

-- Periksa operasi terrain: di dalam jangkauan, SEJAJAR GRID 4 (voxel penuh = permukaan rata), material sah.
local function onGrid(v: number): boolean
	local g = Layout.grid
	return math.abs(v / g - math.floor(v / g + 0.5)) < 1e-4
end

function MapGen.checkTerrain(ops: { any }): { string }
	local issues = {}
	local W = Layout.terrainWipe
	for i, o in ops do
		if o.op == "Block" or o.op == "Wedge" then
			local box = aabb(o.cf, o.size)
			if box.minX < W.minX - 0.01 or box.maxX > W.maxX + 0.01 or box.minZ < W.minZ - 0.01 or box.maxZ > W.maxZ + 0.01 then
				table.insert(issues, ("terrain #%d (%s) keluar jangkauan terrain"):format(i, o.material))
			end
			for _, v in { box.minX, box.maxX, box.minY, box.maxY, box.minZ, box.maxZ } do
				if not onGrid(v) then
					table.insert(issues, ("terrain #%d (%s) tidak sejajar grid %d (%.2f)"):format(i, o.material, Layout.grid, v))
					break
				end
			end
		end
		if o.material and not pcall(function()
			return (Enum.Material :: any)[o.material]
		end) then
			table.insert(issues, ("terrain #%d material tidak dikenal: %s"):format(i, o.material))
		end
	end
	return issues
end

local function applyTerrain(t: any, ops: { any })
	for _, o in ops do
		local mat = o.material and (Enum.Material :: any)[o.material]
		if o.op == "Block" then
			t:FillBlock(o.cf, o.size, mat)
		elseif o.op == "Wedge" then
			t:FillWedge(o.cf, o.size, mat)
		elseif o.op == "Color" then
			t:SetMaterialColor(mat, o.color)
		elseif o.op == "Water" then
			t.WaterColor = o.color
			t.WaterTransparency = o.props.transparency
			t.WaterReflectance = o.props.reflectance
			t.WaterWaveSize = o.props.waveSize
			t.WaterWaveSpeed = o.props.waveSpeed
		end
	end
end

-- Jalur roket donasi: apakah kotak part (diperlebar radius) memuat salah satu titik di garis NukeLaunch → NukeTarget.
local function blocksNukePath(box: any): boolean
	local P = Layout.nukePath
	local a, b = Vector3.new(P.from[1], P.from[2], P.from[3]), Vector3.new(P.to[1], P.to[2], P.to[3])
	local r = P.radius
	local n = math.ceil((b - a).Magnitude)
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		if p.X > box.minX - r and p.X < box.maxX + r and p.Z > box.minZ - r and p.Z < box.maxZ + r and p.Y > box.minY - r and p.Y < box.maxY + r then
			return true
		end
	end
	return false
end

-- Part di dalam klon kit (layar arcade, lampu telepon umum) = isi kit, bukan bangunan kita.
local function inKit(inst: Instance, root: Instance): boolean
	local cur: Instance? = inst
	while cur and cur ~= root do
		if cur:GetAttribute("Kit") then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- Periksa pohon hasil build: nama, kembar, skrip, Anchored, area zona, area terlarang.
function MapGen.check(root: Instance): { string }
	local issues = {}
	-- zona lantai & batas boleh di bawah permukaan dan di bawah objek lama yang berdiri di lantai
	local isFloor = root.Name == "Ground" or root.Name == "Boundary"
	local function walk(inst: Instance)
		local names = {}
		for _, c in inst:GetChildren() do
			-- nama kembar hanya dilarang untuk objek map (part/model/folder); Texture/Decal/Attachment di dalam mesh boleh
			if c:IsA("BasePart") or c:IsA("Model") or c:IsA("Folder") then
				table.insert(names, c.Name)
			end
			if c:IsA("LuaSourceContainer") then
				table.insert(issues, "skrip dilarang: " .. c:GetFullName())
			end
			if c:IsA("BasePart") or c:IsA("Model") or c:IsA("Folder") then
				local why = Naming.problem(c.Name)
				if why then
					table.insert(issues, "nama '" .. c.Name .. "' (" .. why .. ") di " .. inst.Name)
				end
			end
			if c:IsA("BasePart") then
				if not c.Anchored then
					table.insert(issues, "tidak Anchored: " .. c.Name)
				end
				local box = aabb(c.CFrame, c.Size)
				for _, r in Layout.fixed do
					local allow = c:GetAttribute("AllowFixed") -- satu nama area atau beberapa dipisah koma
					if touches(c, r) and not (type(allow) == "string" and table.find(string.split(allow, ","), r.name)) then
						table.insert(issues, c.Name .. " menabrak area " .. r.name)
					end
				end
				if not isFloor then
					for _, r in Layout.standing do
						if touches(c, r) then
							table.insert(issues, c.Name .. " menabrak area " .. r.name)
						end
					end
					if box.minY < Layout.groundY - 0.01 and not c:GetAttribute("AllowBelowGround") then
						table.insert(issues, ("%s masuk ke lantai/terrain (dasar y %.2f < %d)"):format(c.Name, box.minY, Layout.groundY))
					end
				end
				if not isFloor and blocksNukePath(box) then
					table.insert(issues, c.Name .. " menutup jalur efek donasi")
				end
				-- D1 (Rencana_Workspace_R15.md §3): neon hanya garis tipis/titik, bukan panel (ukuran tengah ≤ 1 stud)
				if c.Material == Enum.Material.Neon and not inKit(c, root) then
					local s = { c.Size.X, c.Size.Y, c.Size.Z }
					table.sort(s)
					if s[2] > 1.001 then
						table.insert(issues, ("%s: panel neon %.1f×%.1f×%.1f (maks garis ≤ 1 stud)"):format(c.Name, c.Size.X, c.Size.Y, c.Size.Z))
					end
				end
			end
			walk(c)
		end
		for _, n in Naming.duplicates(names) do
			if inst:FindFirstChild(n) and not inst:FindFirstChild(n):IsA("GuiBase") then
				table.insert(issues, "nama kembar '" .. n .. "' di " .. inst.Name)
			end
		end
	end
	walk(root)
	-- zona (akar atau subfolder bernama zona) harus di dalam areanya
	local zoneFolders = if Layout.zones[root.Name] then { root } else root:GetChildren()
	for _, zf in zoneFolders do
		local area = Layout.zones[zf.Name]
		if area then
			for _, d in zf:GetDescendants() do
				if d:IsA("BasePart") and not inside(d, area) then
					table.insert(issues, d.Name .. " keluar dari area " .. area.name)
				end
			end
		end
	end
	return issues
end

-- P14 (Rencana_Workspace_R15.md §16): part COLLIDABLE yang memotong permukaan air di perairan renang (x < swimMaxX)
-- harus berdiri dari dasar laut (tiang, platform padat) — tidak boleh mengapung (kolong = avatar terjepit & terlempar).
function MapGen.checkWater(root: Instance): { string }
	local issues = {}
	local S = Layout.sea
	-- satu Model (dermaga, platform) dinilai utuh: boleh punya bagian di permukaan air kalau Model itu berdiri dari dasar laut
	local modelMin: { [Instance]: number } = {}
	local function minYOf(m: Instance): number
		if modelMin[m] == nil then
			local lo = math.huge
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					lo = math.min(lo, aabb(d.CFrame, d.Size).minY)
				end
			end
			modelMin[m] = lo
		end
		return modelMin[m]
	end
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide and p.Transparency < 1 then
			local box = aabb(p.CFrame, p.Size)
			local owner = p:FindFirstAncestorOfClass("Model")
			local lowest = if owner and owner:IsDescendantOf(root) then minYOf(owner) else box.minY
			if box.minX < S.swimMaxX and box.minY < S.surfaceY + 0.5 and box.maxY > S.surfaceY - 0.5 and lowest > S.floorY + 0.5 then
				table.insert(issues, ("%s mengapung di permukaan air renang (dasar y %.2f, harus dari dasar laut %d atau hiasan tembus)"):format(p.Name, box.minY, S.floorY))
			end
		end
	end
	return issues
end

-- P12: tiap blok Water harus didahului blok Air yang menutupinya, tanpa blok padat di antaranya.
local function covers(a: any, b: any): boolean
	return a.minX <= b.minX + 0.01 and a.maxX >= b.maxX - 0.01 and a.minY <= b.minY + 0.01 and a.maxY >= b.maxY - 0.01 and a.minZ <= b.minZ + 0.01 and a.maxZ >= b.maxZ - 0.01
end
local function overlap3(a: any, b: any): boolean
	return a.maxX > b.minX + 0.01 and a.minX < b.maxX - 0.01 and a.maxY > b.minY + 0.01 and a.minY < b.maxY - 0.01 and a.maxZ > b.minZ + 0.01 and a.minZ < b.maxZ - 0.01
end
function MapGen.checkWaterOrder(ops: { any }): { string }
	local issues = {}
	for i, o in ops do
		if o.op == "Block" and o.material == "Water" then
			local w = aabb(o.cf, o.size)
			local okCleared = false
			for j = i - 1, 1, -1 do
				local q = ops[j]
				if q.op == "Block" or q.op == "Wedge" then
					local qb = aabb(q.cf, q.size)
					if q.material == "Air" and covers(qb, w) then
						okCleared = true
						break
					elseif q.material ~= "Air" and q.material ~= "Water" and overlap3(qb, w) then
						break
					end
				end
			end
			if not okCleared then
				table.insert(issues, ("terrain #%d Water tanpa Air lebih dulu di atas voxel padat (P12)"):format(i))
			end
		end
	end
	return issues
end

-- Arah hadap kit (P8, Rencana_Workspace_R15.md §4): tiap kit harus terdaftar di KitFront; kit berarah wajib dipasang dengan
-- arah tujuan (Prefabs.facing / Prefabs.seatFacing), bukan yaw tebakan.
function MapGen.checkKits(uses: { any }): { string }
	local issues = {}
	for _, u in uses do
		local e = KitFront.kits[u.kit]
		if not e then
			table.insert(issues, ("kit '%s' (%s) belum diaudit arah depannya (KitFront)"):format(u.kit, u.name))
		elseif e.front ~= "any" and u.heading == nil then
			table.insert(issues, ("kit berarah '%s' (%s, depan %s) dipasang tanpa arah tujuan — pakai Prefabs.facing"):format(u.kit, u.name, e.front))
		end
	end
	return issues
end

function MapGen.build(zoneName: string, mode: string?, envIn: Env?)
	local env = envIn or defaultEnv()
	local out = env.out or print
	local fn = zones[zoneName]
	if not fn then
		error("MapGen: zona tidak dikenal '" .. tostring(zoneName) .. "'")
	end
	local kit = env.serverStorage:FindFirstChild("MapKit")
	local b = Builder.new(zoneName, kit)
	fn(b, Layout)
	local issues = MapGen.check(b.root)
	for _, k in b.missingKit do
		table.insert(issues, "kit tidak ada di ServerStorage.MapKit: " .. k)
	end
	for _, x in MapGen.checkKits(b.kitUses) do
		table.insert(issues, x)
	end
	for _, x in MapGen.checkWater(b.root) do
		table.insert(issues, x)
	end
	for _, x in MapGen.checkWaterOrder(b.terrainOps) do
		table.insert(issues, x)
	end
	for _, x in MapGen.checkTerrain(b.terrainOps) do
		table.insert(issues, x)
	end
	local report = { zone = zoneName, parts = b.parts, terrainOps = #b.terrainOps, issues = issues, applied = false }
	out(("MapGen %s %s | part %d | terrain %d operasi | masalah %d"):format(MapGen.version, zoneName, b.parts, #b.terrainOps, #issues))
	for i = 1, math.min(#issues, 15) do
		out("  - " .. issues[i])
	end
	local theme = themeOfZone(zoneName)
	if mode == "JALAN" and theme then
		b.root:Destroy()
		out(('MapGen GAGAL: zona %s = tema map "%s" (tidak dipasang ke Workspace.Map) — pakai G.themeMap("%s", "JALAN"). Tidak ada yang diubah.'):format(zoneName, theme, theme))
		return report
	end
	if mode ~= "JALAN" or #issues > 0 then
		b.root:Destroy()
		out(if mode == "JALAN" then "MapGen GAGAL: ada masalah, tidak ada yang diubah." else "MapGen CEK selesai: belum ada yang diubah.")
		return report
	end
	local rec = env.history and env.history:TryBeginRecording("MapGen_" .. zoneName)
	if #b.terrainOps > 0 then
		applyTerrain(env.terrain or env.workspace:FindFirstChildOfClass("Terrain"), b.terrainOps)
	end
	if #b.root:GetChildren() > 0 then
		local map = env.workspace:FindFirstChild("Map")
		if not map then
			map = Instance.new("Folder")
			map.Name = "Map"
			map.Parent = env.workspace
		end
		local old = map:FindFirstChild(zoneName)
		if old then
			-- Parent = nil (BUKAN Destroy): Ctrl+Z bisa mengembalikan zona lama. Destroy mengunci Parent → undo gagal
			-- ("The Parent property of … is locked", terlihat 30 Sep 20:36).
			old.Parent = nil
		end
		b.root.Parent = map
	else
		b.root:Destroy()
	end
	if rec then
		env.history:FinishRecording(rec, Enum.FinishRecordingOperation.Commit)
	end
	report.applied = true
	out(("MapGen SELESAI: %s dibangun (%d part, %d operasi terrain)."):format(zoneName, b.parts, #b.terrainOps))
	return report
end

-- ── Tema map ─────────────────────────────────────────────────────────────────────────────────────────────────────────

local function countClass(root: Instance, className: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA(className) then
			n += 1
		end
	end
	return n
end

-- Bangun dekor tema di memori + semua cek MapGen (akar masih bernama zona: MapGen.check memakai nama itu untuk area).
local function buildTheme(name: string, env: Env): (any, { string })
	local zone = MapGen.themeMaps[name]
	local b = Builder.new(zone, env.serverStorage:FindFirstChild("MapKit"))
	zones[zone](b, Layout)
	local issues = MapGen.check(b.root) -- termasuk "skrip dilarang"
	for _, k in b.missingKit do
		table.insert(issues, "kit tidak ada di ServerStorage.MapKit: " .. k)
	end
	for _, x in MapGen.checkKits(b.kitUses) do
		table.insert(issues, x)
	end
	if #b.terrainOps > 0 then
		table.insert(issues, ("tema tidak boleh mengubah terrain (%d operasi)"):format(#b.terrainOps))
	end
	return b, issues
end

-- Bandingkan dua pohon dekor (aset di place vs hasil kode) per instance: jalur relatif + kelas, lalu sifat part / teks.
-- Saudara bernama sama dibedakan sifatnya, BUKAN urutan anak (urutan GetChildren di Studio bisa beda dengan urutan dibuat;
-- terbukti 2 Okt 13:23: kartu bunting punya 2 SurfaceGui "TextGui" muka Front/Back → "BEDA 6" palsu).
local function treeDiff(a: Instance, b: Instance): { string }
	local function segment(d: Instance): string
		local ok, face = pcall(function()
			return (d :: any).Face
		end)
		if ok and typeof(face) == "EnumItem" then
			return d.Name .. "@" .. face.Name
		end
		return d.Name
	end
	local function keyed(root: Instance): { [string]: Instance }
		local m, seen = {}, {}
		for _, d in root:GetDescendants() do
			local parts, cur = {}, d
			while cur and cur ~= root do
				table.insert(parts, 1, segment(cur))
				cur = cur.Parent
			end
			local k = "." .. table.concat(parts, ".") .. "|" .. d.ClassName
			seen[k] = (seen[k] or 0) + 1
			m[k .. "#" .. seen[k]] = d
		end
		return m
	end
	local function near(x: number, y: number): boolean
		return math.abs(x - y) < 0.02
	end
	local function vEq(x: Vector3, y: Vector3): boolean
		return near(x.X, y.X) and near(x.Y, y.Y) and near(x.Z, y.Z)
	end
	local A, B = keyed(a), keyed(b)
	local diffs = {}
	for k, x in A do
		local y: any = B[k]
		if not y then
			table.insert(diffs, "hanya di aset: " .. k)
		elseif x:IsA("BasePart") then
			local p, q = x :: BasePart, y :: BasePart
			if not (vEq(p.CFrame.Position, q.CFrame.Position) and vEq(p.CFrame.LookVector, q.CFrame.LookVector) and vEq(p.CFrame.UpVector, q.CFrame.UpVector))
				or not vEq(p.Size, q.Size) or not vEq(Vector3.new(p.Color.R, p.Color.G, p.Color.B), Vector3.new(q.Color.R, q.Color.G, q.Color.B))
				or p.Material ~= q.Material or not near(p.Transparency, q.Transparency) or p.CanCollide ~= q.CanCollide then
				table.insert(diffs, "beda: " .. k)
			end
		elseif x:IsA("TextLabel") and (x :: TextLabel).Text ~= (y :: TextLabel).Text then
			table.insert(diffs, "teks beda: " .. k)
		end
	end
	for k in B do
		if not A[k] then
			table.insert(diffs, "hanya di kode: " .. k)
		end
	end
	table.sort(diffs)
	return diffs
end

local function themeList(): string
	local names = {}
	for n in MapGen.themeMaps do
		table.insert(names, n)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- Laporan semua tema: aset di ServerStorage.ThemeMap vs kode, sisa TAMPIL di Workspace.
local function themeReport(env: Env, out: (string) -> ())
	local dir = env.serverStorage:FindFirstChild(THEME_DIR)
	local shown = env.workspace:FindFirstChild(THEME_DIR)
	local rows = {}
	local names = {}
	for n in MapGen.themeMaps do
		table.insert(names, n)
	end
	if dir then
		for _, c in dir:GetChildren() do
			if not MapGen.themeMaps[c.Name] then
				table.insert(names, c.Name)
			end
		end
	end
	table.sort(names)
	for _, n in names do
		local asset = dir and dir:FindFirstChild(n)
		local row: any = { theme = n, known = MapGen.themeMaps[n] ~= nil, exists = asset ~= nil }
		if not row.known then
			out(("  %s: aset di ServerStorage.%s TIDAK dikenal kode (MapGen.themeMaps) — tidak bisa dibangun ulang"):format(n, THEME_DIR))
		elseif not asset then
			out(('  %s: BELUM dibangun → G.themeMap("%s", "JALAN")'):format(n, n))
		else
			row.parts = countClass(asset, "BasePart")
			row.scripts = countClass(asset, "LuaSourceContainer")
			local b = buildTheme(n, env)
			row.diffs = treeDiff(asset, b.root)
			b.root:Destroy()
			out(("  %s: aset %d part · skrip %d · dibangun %s · %s"):format(n, row.parts, row.scripts, tostring(asset:GetAttribute("MapGenVersion") or "?"),
				if #row.diffs == 0 then "cocok dengan kode " .. MapGen.version else ('BEDA %d (mis. %s) → G.themeMap("%s", "JALAN")'):format(#row.diffs, row.diffs[1], n)))
			if row.scripts > 0 then
				out("    ⚠ aset berisi skrip — server ThemeMap TIDAK akan memasangnya")
			end
		end
		table.insert(rows, row)
	end
	local left = {}
	if shown then
		for _, c in shown:GetChildren() do
			table.insert(left, c.Name)
		end
	end
	if #left > 0 then
		out(('  ⚠ masih TAMPIL di Workspace.%s: %s → G.themeMap("<tema>", "SIMPAN") sebelum Save/Publish'):format(THEME_DIR, table.concat(left, ", ")))
	end
	return rows, left
end

-- Tema map → ServerStorage.ThemeMap.<tema>. Mode: CEK | JALAN | TAMPIL | SIMPAN | DAFTAR (lihat kepala file).
function MapGen.themeMap(name: string?, mode: string?, envIn: Env?)
	local env = envIn or defaultEnv()
	local out = env.out or print
	if mode == "DAFTAR" then
		out(("MapGen %s themeMap DAFTAR | kode: %s"):format(MapGen.version, themeList()))
		local rows, left = themeReport(env, out)
		return { mode = "DAFTAR", rows = rows, shown = left }
	end
	if type(name) ~= "string" or not MapGen.themeMaps[name] then
		error(("MapGen.themeMap: tema tidak dikenal '%s' (ada: %s)"):format(tostring(name), themeList()))
	end
	local theme = name :: string
	local zone = MapGen.themeMaps[theme]
	local ss, ws = env.serverStorage, env.workspace
	local dir = ss:FindFirstChild(THEME_DIR)
	local shownDir = ws:FindFirstChild(THEME_DIR)
	local report: any = { theme = theme, zone = zone, mode = mode, applied = false, detached = {} }

	local function record(label: string, fn: () -> ())
		local history = env.history
		local rec = history and history:TryBeginRecording("MapGen_ThemeMap_" .. label)
		fn()
		if rec then
			history:FinishRecording(rec, Enum.FinishRecordingOperation.Commit)
		end
	end
	local function folder(parent: Instance, existing: Instance?): Instance
		if existing then
			return existing
		end
		local f = Instance.new("Folder")
		f.Name = THEME_DIR
		f.Parent = parent
		return f
	end

	if mode == "TAMPIL" or mode == "SIMPAN" then
		local fromDir, toParent = if mode == "TAMPIL" then dir else shownDir, if mode == "TAMPIL" then ws else ss
		local src = fromDir and fromDir:FindFirstChild(theme)
		local already = if mode == "TAMPIL" then shownDir and shownDir:FindFirstChild(theme) else dir and dir:FindFirstChild(theme)
		if already and not src then
			out(("MapGen themeMap %s: %s sudah di %s — tidak ada yang diubah."):format(mode, theme, if mode == "TAMPIL" then "Workspace" else "ServerStorage"))
			return report
		elseif not src then
			out(('MapGen themeMap %s GAGAL: %s tidak ada%s — tidak ada yang diubah.'):format(mode, theme,
				if mode == "TAMPIL" then (' di ServerStorage.%s (jalankan G.themeMap("%s", "JALAN"))'):format(THEME_DIR, theme) else " di Workspace." .. THEME_DIR))
			return report
		elseif already then
			out(("MapGen themeMap %s GAGAL: %s ada di Workspace DAN ServerStorage — hapus salah satu dulu. Tidak ada yang diubah."):format(mode, theme))
			return report
		end
		record(mode .. "_" .. theme, function()
			src.Parent = folder(toParent, if mode == "TAMPIL" then shownDir else dir)
			if mode == "SIMPAN" and shownDir and #shownDir:GetChildren() == 0 then
				shownDir.Parent = nil
			end
		end)
		report.applied = true
		out(if mode == "TAMPIL"
			then ('MapGen themeMap TAMPIL: %s di Workspace.%s (mode Edit). Selesai → G.themeMap("%s", "SIMPAN") sebelum Save/Publish.'):format(theme, THEME_DIR, theme)
			else ("MapGen themeMap SIMPAN: %s kembali ke ServerStorage.%s."):format(theme, THEME_DIR))
		return report
	end

	if mode ~= "CEK" and mode ~= "JALAN" then
		error("MapGen.themeMap: mode CEK | JALAN | TAMPIL | SIMPAN | DAFTAR")
	end
	local b, issues = buildTheme(theme, env)
	report.parts = b.parts
	report.issues = issues
	out(("MapGen %s themeMap %s (zona %s) | part %d | skrip %d | masalah %d"):format(MapGen.version, theme, zone, b.parts, countClass(b.root, "LuaSourceContainer"), #issues))
	for i = 1, math.min(#issues, 15) do
		out("  - " .. issues[i])
	end
	if mode ~= "JALAN" or #issues > 0 then
		b.root:Destroy()
		out(if mode == "JALAN" then "MapGen themeMap GAGAL: ada masalah, tidak ada yang diubah." else "MapGen themeMap CEK selesai: belum ada yang diubah.")
		return report
	end
	record("JALAN_" .. theme, function()
		local target = folder(ss, dir)
		local function detach(inst: Instance?, label: string)
			if inst then
				-- Parent = nil (BUKAN Destroy): Ctrl+Z bisa mengembalikan (pelajaran 30 Sep 20:36)
				inst.Parent = nil
				table.insert(report.detached, label)
			end
		end
		detach(target:FindFirstChild(theme), ("ServerStorage.%s.%s (versi lama)"):format(THEME_DIR, theme))
		detach(shownDir and shownDir:FindFirstChild(theme), ("Workspace.%s.%s (sisa TAMPIL)"):format(THEME_DIR, theme))
		local map = ws:FindFirstChild("Map")
		detach(map and map:FindFirstChild(zone), "Workspace.Map." .. zone)
		if shownDir and shownDir.Parent and #shownDir:GetChildren() == 0 then
			shownDir.Parent = nil
		end
		b.root.Name = theme
		b.root:SetAttribute("Zone", zone)
		b.root:SetAttribute("MapGenVersion", MapGen.version)
		b.root:SetAttribute("Parts", b.parts)
		b.root.Parent = target
	end)
	report.applied = true
	for _, d in report.detached do
		out("  dilepas (Ctrl+Z bisa): " .. d)
	end
	out(("MapGen themeMap SELESAI: ServerStorage.%s.%s dibangun (%d part)."):format(THEME_DIR, theme, b.parts))
	return report
end

-- Suasana senja + neon (Mood) ke Lighting. CEK = laporan nilai lama → baru; JALAN = terapkan (bisa Ctrl+Z).
-- Atmosphere & ColorCorrectionEffect yang ada dipakai ulang (GraphicsClient mencari Atmosphere); Bloom dibuat kalau belum ada.
function MapGen.lighting(mode: string?, lightingIn: any?, historyIn: any?, outIn: ((string) -> ())?)
	local L = lightingIn or game:GetService("Lighting")
	local out = outIn or print
	local function col(v: any): any
		return if type(v) == "table" then Color3.fromRGB(v[1], v[2], v[3]) else v
	end
	local function fmt(v: any): string
		if typeof(v) == "Color3" then
			return string.format("%d,%d,%d", math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
		end
		return if type(v) == "number" then string.format("%.3g", v) else tostring(v)
	end
	local changes = {}
	local function plan(target: any, label: string, props: { [string]: any })
		for k, v in props do
			if k ~= "Name" then
				local ok, old = pcall(function()
					return target[k]
				end)
				table.insert(changes, { target = target, key = k, value = col(v), label = label, old = if ok then old else nil })
			end
		end
	end
	plan(L, "Lighting", Mood.lighting)
	local atm = L:FindFirstChildOfClass("Atmosphere")
	local cc = L:FindFirstChildOfClass("ColorCorrectionEffect")
	local bloom = L:FindFirstChild(Mood.bloom.Name)
	if atm then
		plan(atm, "Atmosphere", Mood.atmosphere)
	end
	if cc then
		plan(cc, "ColorCorrection", Mood.colorCorrection)
	end
	if bloom then
		plan(bloom, "Bloom", Mood.bloom)
	end
	for _, c in changes do
		out(("  %s.%s: %s → %s"):format(c.label, c.key, fmt(c.old), fmt(c.value)))
	end
	out(("MapGen %s lighting | %d nilai | Atmosphere %s | ColorCorrection %s | Bloom %s"):format(
		MapGen.version, #changes, atm and "ada" or "DIBUAT", cc and "ada" or "DIBUAT", bloom and "ada" or "DIBUAT"))
	if mode ~= "JALAN" then
		out("MapGen lighting CEK selesai: belum ada yang diubah.")
		return { applied = false, changes = #changes }
	end
	local history = historyIn or game:GetService("ChangeHistoryService")
	local rec = history and history:TryBeginRecording("MapGen_Lighting")
	local function make(className: string, name: string, props: { [string]: any })
		local e = Instance.new(className)
		e.Name = name
		for k, v in props do
			if k ~= "Name" then
				(e :: any)[k] = col(v)
			end
		end
		e.Parent = L
	end
	if not atm then
		make("Atmosphere", "Atmosphere", Mood.atmosphere)
	end
	if not cc then
		make("ColorCorrectionEffect", "ColorCorrection", Mood.colorCorrection)
	end
	if not bloom then
		make("BloomEffect", Mood.bloom.Name, Mood.bloom)
	end
	local failed = {}
	for _, c in changes do
		local ok = pcall(function()
			c.target[c.key] = c.value
		end)
		if not ok then
			table.insert(failed, c.label .. "." .. c.key)
		end
	end
	if rec then
		history:FinishRecording(rec, Enum.FinishRecordingOperation.Commit)
	end
	out(("MapGen lighting SELESAI | gagal %d %s"):format(#failed, table.concat(failed, ", ")))
	return { applied = true, changes = #changes, failed = failed }
end

-- Pindahkan map baru keluar/masuk Workspace (supaya Publish di tengah rombak tetap memakai map lama).
function MapGen.draft(action: string, envIn: Env?)
	local env = envIn or defaultEnv()
	local out = env.out or print
	local from, to, name = env.workspace, env.serverStorage, "Map"
	if action == "TAMPIL" then
		from, to = env.serverStorage, env.workspace
		name = "MapDraft"
	elseif action ~= "SIMPAN" then
		error("MapGen.draft: SIMPAN atau TAMPIL")
	end
	local f = from:FindFirstChild(name)
	if not f then
		out("MapGen draft: tidak ada " .. name .. " di " .. from.Name)
		return false
	end
	f.Name = if action == "SIMPAN" then "MapDraft" else "Map"
	f.Parent = to
	out("MapGen draft: " .. action .. " OK → " .. to.Name .. "." .. f.Name)
	return true
end

return MapGen
