--!strict
-- Cek "aman di-Connect" terhadap file place (LOKAL saja; file .rbxl tidak boleh di-commit):
--   lune run tools/checks/place <path/ke/place.rbxl>
--
-- Mensimulasikan apa yang akan dilakukan plugin Rojo saat Connect, memakai `rojo build`:
--   GAGAL  • node yang pasangannya di place ambigu (>1 instance nama+kelas sama) → risiko salinan/salah tempel
--          • instance di place yang akan DIHAPUS Rojo (ada di bawah node $path tapi tidak ada di repo)
--   INFO   • BARU   : instance yang akan DITAMBAH Rojo (wajar untuk file baru)
--          • DIUBAH : skrip yang isinya beda dengan place (harus persis file yang memang kamu ubah)
-- Aturan Rojo 7.7 yang dipakai: pasangan dicari lewat Nama+ClassName (plugin hydrate.lua), node dengan
-- $path menghapus anak yang tidak dikenal, node tanpa $path tidak.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

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
local function collect(node: any, prefix: string?)
	for k, v in node do
		if string.sub(k, 1, 1) ~= "$" and type(v) == "table" then
			local p = if prefix then `{prefix}/{k}` else k
			if v["$path"] then
				managed[p] = true
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
		if fileBacked and bc.Source ~= oc.Source then
			table.insert(changed, p)
		end
		if underManaged(p) then
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

for _, m in added do
	print("BARU   : " .. m)
end
for _, m in changed do
	print("DIUBAH : " .. m)
end
for _, m in failures do
	print("GAGAL  : " .. m)
end
print(`Ringkasan: {scripts} skrip dikelola repo · {#changed} diubah · {#added} baru · {#failures} masalah`)
if #failures > 0 then
	process.exit(1)
end
