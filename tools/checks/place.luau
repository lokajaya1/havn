--!strict
-- Cek "aman di-Connect" terhadap file place (LOKAL saja; file .rbxl tidak boleh di-commit):
--   lune run tools/checks/place <path/ke/place.rbxl>
--
-- Mensimulasikan apa yang akan dilakukan plugin Rojo saat Connect, memakai `rojo build`:
--   GAGAL  • node yang pasangannya di place ambigu (>1 instance nama+kelas sama) → risiko salinan/salah tempel
--          • instance di place yang akan DIHAPUS Rojo (ada di bawah node $path tapi tidak ada di repo;
--            node "$ignoreUnknownInstances": true dikecualikan — Rojo membiarkan anak yang tidak dikenal)
--          • ASET WAJIB: aset non-skrip yang dibutuhkan skrip/tool tapi tidak ada di place MAUPUN di repo
--            (aturan di tools/checks/assets.luau: Tool tanpa Handle/bagian wajib, rujukan script.X / script["X"] /
--            :WaitForChild("X") yang anaknya tidak ada) → contoh: 30 Value carry + isi 3 tool yang hilang sesudah WORLD
--   INFO   • BARU   : instance yang akan DITAMBAH Rojo (wajar untuk file baru)
--          • DIUBAH : skrip yang isinya beda dengan place (harus persis file yang memang kamu ubah)
-- Aturan Rojo 7.7 yang dipakai: pasangan dicari lewat Nama+ClassName (plugin hydrate.lua), node dengan
-- $path menghapus anak yang tidak dikenal, node tanpa $path tidak.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Assets = require("./assets")

local placePath = process.args[1]
if placePath == nil then
	print("Pakai: lune run tools/checks/place <place.rbxl>")
	process.exit(1)
end

local OUT = "tools/checks/out"
fs.writeDir(OUT)
local r = process.exec("rojo", { "build", "default.project.json", "-o", OUT .. "/build.rbxl" })
if not r.ok then
	print(r.stdout, r.stderr)
	print("GAGAL: rojo build")
	process.exit(1)
end

local built = roblox.deserializePlace(fs.readFile(OUT .. "/build.rbxl"))
local place = roblox.deserializePlace(fs.readFile(placePath))

local project = serde.decode("json", fs.readFile("default.project.json"))
local managed: { [string]: boolean } = {}
local keepUnknown: { [string]: boolean } = {}
local function collect(node: any, prefix: string?)
	for k, v in node do
		if string.sub(k, 1, 1) ~= "$" and type(v) == "table" then
			local p = if prefix then `{prefix}/{k}` else k
			if v["$path"] then
				managed[p] = true
			end
			if v["$ignoreUnknownInstances"] == true then
				keepUnknown[p] = true
			end
			collect(v, p)
		end
	end
end
collect(project.tree, nil)

local function underManaged(p: string): boolean
	local cur: string? = p
	while cur do
		if managed[cur] then
			return true
		end
		cur = string.match(cur, "^(.*)/[^/]*$")
	end
	return false
end

local function pathOf(i: any, root: any): string
	local parts = {}
	while i and i ~= root do
		table.insert(parts, 1, i.Name)
		i = i.Parent
	end
	return table.concat(parts, "/")
end

local function isScript(i: any): boolean
	return i:IsA("LuaSourceContainer")
end

local failures, added, changed = {}, {}, {}
local scripts = 0
local pairOf: { [any]: any } = {} -- instance build → pasangannya di place

local function walk(b: any, o: any)
	for _, bc in b:GetChildren() do
		local p = pathOf(bc, built)
		local candidates = {}
		for _, oc in o:GetChildren() do
			if oc.Name == bc.Name and oc.ClassName == bc.ClassName then
				table.insert(candidates, oc)
			end
		end
		-- Skrip dari node `$className` tanpa $path hanya penanda jalur: Rojo tidak menyentuh Source-nya.
		local fileBacked = isScript(bc) and underManaged(p)
		if fileBacked then
			scripts += 1
		end
		if #candidates == 0 then
			table.insert(added, `{p} ({bc.ClassName})`)
			continue
		elseif #candidates > 1 then
			table.insert(failures, `{p}: {#candidates} instance kembar di place (ambigu)`)
			continue
		end
		local oc = candidates[1]
		pairOf[bc] = oc
		if fileBacked and bc.Source ~= oc.Source then
			table.insert(changed, p)
		end
		if underManaged(p) and not keepUnknown[p] then
			for _, occ in oc:GetChildren() do
				local keep = false
				for _, bcc in bc:GetChildren() do
					if bcc.Name == occ.Name and bcc.ClassName == occ.ClassName then
						keep = true
						break
					end
				end
				if not keep then
					table.insert(failures, `{p}: Rojo akan MENGHAPUS '{occ.Name}' ({occ.ClassName})`)
				end
			end
		end
		walk(bc, oc)
	end
end

for _, svc in built:GetChildren() do
	local osvc = place:FindFirstChildOfClass(svc.ClassName)
	if osvc == nil then
		table.insert(failures, `service {svc.ClassName} tidak ada di place`)
	else
		walk(svc, osvc)
	end
end

-- ── ASET WAJIB ───────────────────────────────────────────────────────────────────────────────────────────────────
local function findPath(root: any, rel: string): any
	local cur = root
	for part in string.gmatch(rel, "[^/]+") do
		if cur == nil then
			return nil
		end
		if cur == root then
			cur = cur:FindFirstChildOfClass(part) or cur:FindFirstChild(part)
		else
			cur = cur:FindFirstChild(part)
		end
	end
	return cur
end
local function findRel(inst: any, rel: string): any
	local cur = inst
	for part in string.gmatch(rel, "[^/]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	return cur
end
local asetHilang = 0
local function aset(msg: string)
	asetHilang += 1
	table.insert(failures, "ASET WAJIB: " .. msg)
end
for _, t in Assets.TOOLS do
	local p, b = findPath(place, t.path), findPath(built, t.path)
	if p == nil and b == nil then
		aset(`{t.path} (Tool) tidak ada`)
	else
		for _, need in t.need do
			if not ((p and findRel(p, need)) or (b and findRel(b, need))) then
				aset(`{t.path} tidak punya '{need}' → tool tidak bisa dipakai`)
			end
		end
	end
end
for _, bc in built:GetDescendants() do
	if isScript(bc) then
		local path = pathOf(bc, built)
		if not Assets.skipped(path) then
			for _, ref in Assets.refs(bc.Source) do
				local bBase, pBase = bc, pairOf[bc]
				for _ = 1, ref.hops do
					bBase = bBase and bBase.Parent
					pBase = pBase and pBase.Parent
				end
				if not ((bBase and bBase:FindFirstChild(ref.name)) or (pBase and pBase:FindFirstChild(ref.name))) then
					aset(`{path}{string.rep("/..", ref.hops)} tidak punya '{ref.name}' (dirujuk skrip ini)`)
				end
			end
		end
	end
end

for _, m in added do
	print("BARU   : " .. m)
end
for _, m in changed do
	print("DIUBAH : " .. m)
end
for _, m in failures do
	print("GAGAL  : " .. m)
end
print(`Ringkasan: {scripts} skrip dikelola repo · {#changed} diubah · {#added} baru · {#failures} masalah ({asetHilang} aset wajib hilang)`)
if #failures > 0 then
	process.exit(1)
end
