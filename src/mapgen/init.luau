--!strict
-- ServerStorage/MapGen (ModuleScript) — alat STUDIO untuk membangun map dari kode (tidak pernah di-require game).
-- Command Bar (mode Edit):
--   local G = require(game.ServerStorage.MapGen:Clone())   -- :Clone() = hindari cache require Command Bar
--   G.build("Blockout", "CEK")     → laporan saja, tidak mengubah apa pun
--   G.build("Blockout", "JALAN")   → ganti Workspace.Map.<zona> (bisa Ctrl+Z)
--   G.draft("SIMPAN") / G.draft("TAMPIL")  → pindah Workspace.Map ↔ ServerStorage.MapDraft (sebelum Publish)

local Builder = require(script.Builder)
local Naming = require(script.Naming)
local Layout = require(script.Layout)

local zones: { [string]: (any, any) -> () } = {
	Blockout = require(script.Zones.Blockout),
	Terrain = require(script.Zones.Terrain),
}

local MapGen = { version = "R2", layout = Layout }

type Env = { workspace: Instance, serverStorage: Instance, history: any?, terrain: any?, out: ((string) -> ())? }

local function defaultEnv(): Env
	return {
		workspace = workspace,
		serverStorage = game:GetService("ServerStorage"),
		history = game:GetService("ChangeHistoryService"),
	}
end

local function inside(p: BasePart, a: any): boolean
	local pos, s = p.CFrame.Position, p.Size
	return pos.X - s.X / 2 >= a.minX - 0.01 and pos.X + s.X / 2 <= a.maxX + 0.01 and pos.Z - s.Z / 2 >= a.minZ - 0.01 and pos.Z + s.Z / 2 <= a.maxZ + 0.01
end

local function touches(p: BasePart, a: any): boolean
	local pos, s = p.CFrame.Position, p.Size
	return pos.X + s.X / 2 > a.minX and pos.X - s.X / 2 < a.maxX and pos.Z + s.Z / 2 > a.minZ and pos.Z - s.Z / 2 < a.maxZ
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
	return { minX = p.X - e.X, maxX = p.X + e.X, minZ = p.Z - e.Z, maxZ = p.Z + e.Z }
end

local function overlap(a: any, b: any): boolean
	return a.maxX > b.minX + 0.01 and a.minX < b.maxX - 0.01 and a.maxZ > b.minZ + 0.01 and a.minZ < b.maxZ - 0.01
end

-- Periksa operasi terrain: di dalam batas map, tidak menyentuh DJ STAGE / lubang lantai dansa, material sah.
function MapGen.checkTerrain(ops: { any }): { string }
	local issues = {}
	local B = Layout.boundary
	for i, o in ops do
		if o.op == "Block" or o.op == "Wedge" then
			local box = aabb(o.cf, o.size)
			if box.minX < B.minX - 0.01 or box.maxX > B.maxX + 0.01 or box.minZ < B.minZ - 0.01 or box.maxZ > B.maxZ + 0.01 then
				table.insert(issues, ("terrain #%d (%s) keluar batas map"):format(i, o.material))
			end
			for _, r in { Layout.reserved[1], Layout.danceFloorPit } do
				if overlap(box, r) then
					table.insert(issues, ("terrain #%d (%s) menyentuh %s"):format(i, o.material, r.name))
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

-- Periksa pohon hasil build: nama, kembar, skrip, Anchored, area zona, area terlarang.
function MapGen.check(root: Instance): { string }
	local issues = {}
	local function walk(inst: Instance)
		local names = {}
		for _, c in inst:GetChildren() do
			table.insert(names, c.Name)
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
				for _, r in Layout.reserved do
					if touches(c, r) then
						table.insert(issues, c.Name .. " menabrak area " .. r.name)
					end
				end
				if touches(c, Layout.nukeCorridor) then
					table.insert(issues, c.Name .. " menutup jalur efek donasi")
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
	-- setiap subfolder bernama zona harus di dalam areanya
	for _, zf in root:GetChildren() do
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
	for _, x in MapGen.checkTerrain(b.terrainOps) do
		table.insert(issues, x)
	end
	local report = { zone = zoneName, parts = b.parts, terrainOps = #b.terrainOps, issues = issues, applied = false }
	out(("MapGen %s %s | part %d | terrain %d operasi | masalah %d"):format(MapGen.version, zoneName, b.parts, #b.terrainOps, #issues))
	for i = 1, math.min(#issues, 15) do
		out("  - " .. issues[i])
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
			old:Destroy()
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
