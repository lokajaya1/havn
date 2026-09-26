--!strict
-- Verifikasi hasil Tahap 1 (jalankan setelah extract, dari root repo):
--   lune run tools/extract/verify <path/ke/place.rbxl>
--
-- Membuktikan, tanpa membuka Studio:
--   1. Tiap file di src/legacy masih sama dengan md5 di manifest (tidak ada yang ter-format/ter-edit).
--   2. `rojo build` menghasilkan skrip yang IDENTIK dengan place: kelas, isi, Disabled.
--   3. Di bawah setiap node $path, anak-anaknya di place == anak-anaknya di build
--      → Rojo tidak akan MENGHAPUS apa pun saat Connect.
--   4. Tiap node punya tepat satu pasangan (nama+kelas) di place → Rojo memakai instance
--      yang ada, tidak membuat skrip dobel.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local BUILD_DIR = "tools/extract/out"
local BUILD = BUILD_DIR .. "/build.rbxl"

local placePath = process.args[1]
if placePath == nil then
	print("Pakai: lune run tools/extract/verify <place.rbxl>")
	process.exit(1)
end

local problems: { string } = {}
local function fail(msg: string)
	table.insert(problems, msg)
end

local manifest = serde.decode("json", fs.readFile("tools/extract/manifest.json"))
local placeBytes = fs.readFile(placePath)
if serde.hash("md5", placeBytes) ~= manifest.sourceMd5 then
	fail("place yang diberikan BERBEDA dengan place saat extract (md5 tidak sama)")
end

-- 1. File masih sesuai manifest
for _, e in manifest.scripts do
	if not fs.isFile(e.file) then
		fail(`file hilang: {e.file}`)
	elseif serde.hash("md5", fs.readFile(e.file)) ~= e.md5 then
		fail(`isi file berubah sejak extract: {e.file}`)
	end
end

-- 2. Build
fs.writeDir(BUILD_DIR)
local r = process.exec("rojo", { "build", "default.project.json", "-o", BUILD })
if not r.ok then
	print(r.stdout, r.stderr)
	print("GAGAL: rojo build error")
	process.exit(1)
end

local place = roblox.deserializePlace(placeBytes)
local built = roblox.deserializePlace(fs.readFile(BUILD))

local function isScript(i: any): boolean
	return i.ClassName == "Script" or i.ClassName == "LocalScript" or i.ClassName == "ModuleScript"
end

local function pathOf(i: any, root: any): string
	local parts = {}
	while i and i ~= root do
		table.insert(parts, 1, i.Name)
		i = i.Parent
	end
	return table.concat(parts, "/")
end

-- Satu-satunya anak dengan nama+kelas itu; error kalau 0 atau >1.
local function uniqueChild(parent: any, name: string, class: string): (any?, string?)
	local found, n = nil, 0
	for _, c in parent:GetChildren() do
		if c.Name == name and c.ClassName == class then
			found = c
			n += 1
		end
	end
	if n == 1 then
		return found, nil
	end
	return nil, if n == 0 then "tidak ada" else `{n} kembar`
end

local manifestByPath: { [string]: any } = {}
for _, e in manifest.scripts do
	manifestByPath[e.path] = e
end

-- Node $path (dikelola penuh oleh Rojo) dari project file
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
	local cur = p
	while true do
		if managed[cur] then
			return true
		end
		local parent = string.match(cur, "^(.*)/[^/]*$")
		if parent == nil then
			return false
		end
		cur = parent
	end
end

local builtScripts = 0
local function walk(b: any, o: any)
	for _, bc in b:GetChildren() do
		local p = pathOf(bc, built)
		local oc, why = uniqueChild(o, bc.Name, bc.ClassName)
		if oc == nil then
			fail(`{p} ({bc.ClassName}): pasangan di place {why}`)
			continue
		end
		if isScript(bc) then
			builtScripts += 1
			local e = manifestByPath[p]
			if e == nil then
				fail(`{p}: ada di build tapi tidak di manifest`)
			end
			if bc.Source ~= oc.Source then
				fail(`{p}: isi berbeda dengan place`)
			end
			if bc.ClassName ~= "ModuleScript" and bc.Disabled ~= oc.Disabled then
				fail(`{p}: Disabled build={bc.Disabled} place={oc.Disabled}`)
			end
			if bc.ClassName == "Script" and bc.RunContext ~= oc.RunContext then
				fail(`{p}: RunContext berbeda`)
			end
		end
		if underManaged(p) then
			-- Rojo akan menghapus anak di place yang tidak ada di build
			for _, occ in oc:GetChildren() do
				if uniqueChild(bc, occ.Name, occ.ClassName) == nil then
					fail(`{p}: Rojo akan MENGHAPUS '{occ.Name}' ({occ.ClassName})`)
				end
			end
		end
		walk(bc, oc)
	end
end

for _, svc in built:GetChildren() do
	local osvc = place:FindFirstChildOfClass(svc.ClassName)
	if osvc == nil then
		fail(`service {svc.ClassName} tidak ada di place`)
	else
		walk(svc, osvc)
	end
end

if builtScripts ~= #manifest.scripts then
	fail(`jumlah skrip di build {builtScripts} ≠ manifest {#manifest.scripts}`)
end

if #problems == 0 then
	print(`OK: {builtScripts} skrip identik dengan place, 0 akan dihapus, 0 dobel.`)
else
	for _, m in problems do
		print("BEDA: " .. m)
	end
	print(`GAGAL: {#problems} beda`)
	process.exit(1)
end
