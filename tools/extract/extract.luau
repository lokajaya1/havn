--!strict
-- Tahap 1 renovasi HAVN: pindahkan skrip APA ADANYA dari .rbxl ke src/legacy/.
--
-- Pakai (dari root repo):
--   lune run tools/extract/extract <path/ke/place.rbxl> [--force]
--
-- Menulis:
--   src/legacy/<Service>/...        sumber skrip, isi byte-per-byte sama dengan place
--   default.project.json             peta Rojo partially-managed (service TANPA $path)
--   tools/extract/manifest.json      daftar skrip terekstrak + md5 (dipakai verify)
--   tools/extract/report.md          ringkasan: terekstrak & ditinggal (dengan alasan)
--
-- Aturan (lihat README): skrip hanya diekstrak kalau semua leluhurnya Folder/service,
-- subtree-nya hanya berisi skrip, tidak ada nama kembar, dan namanya aman jadi nama file.
-- Selain itu skrip DITINGGAL di place (tetap jalan, tidak disentuh Rojo).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local OUT_ROOT = "src/legacy"
local PROJECT_NAME = "HAVN"

-- Service yang dipetakan. Workspace/ServerStorage/StarterPack/ReplicatedFirst sengaja
-- tidak: isinya aset (map, Tool), bukan kode lepas.
local SERVICES = {
	"ServerScriptService",
	"ReplicatedStorage",
	"StarterGui",
	"StarterPlayer",
}

-- Kelas wadah yang boleh dilewati (dipetakan dengan $className tanpa $path).
local CONTAINERS: { [string]: boolean } = {
	Folder = true,
	StarterPlayerScripts = true,
	StarterCharacterScripts = true,
}

local SCRIPT_SUFFIX: { [string]: string } = {
	Script = ".server.luau",
	LocalScript = ".client.luau",
	ModuleScript = ".luau",
}

type Entry = {
	path: string, -- path Explorer, dipisah "/"
	class: string,
	file: string, -- file sumber relatif root repo
	md5: string,
	disabled: boolean?,
}

type Skip = { path: string, reason: string }

local args = process.args
local placePath: string? = nil
local force = false
for _, a in args do
	if a == "--force" then
		force = true
	elseif placePath == nil then
		placePath = a
	end
end

if placePath == nil then
	print("Pakai: lune run tools/extract/extract <place.rbxl> [--force]")
	process.exit(1)
end
assert(placePath)

if fs.isDir(OUT_ROOT) and not force then
	print(`{OUT_ROOT}/ sudah ada. Hapus dulu atau jalankan dengan --force.`)
	process.exit(1)
end
if fs.isDir(OUT_ROOT) then
	fs.removeDir(OUT_ROOT)
end

local game = roblox.deserializePlace(fs.readFile(placePath))

local entries: { Entry } = {}
local skips: { Skip } = {}

local function isScript(i: any): boolean
	return SCRIPT_SUFFIX[i.ClassName] ~= nil
end

local function explorerPath(i: any): string
	local parts = {}
	while i and i ~= game do
		table.insert(parts, 1, i.Name)
		i = i.Parent
	end
	return table.concat(parts, "/")
end

-- Nama harus bisa jadi nama file di Mac/Windows dan tidak disalahartikan Rojo.
local function nameProblem(name: string): string?
	if name == "" then
		return "nama kosong"
	end
	if string.find(name, '[/\\:%*%?"<>|%c]') then
		return "nama berisi karakter yang tidak boleh di nama file"
	end
	if string.sub(name, 1, 1) == "." or string.sub(name, -1) == "." or string.sub(name, -1) == " " then
		return "nama diawali titik atau diakhiri titik/spasi"
	end
	local lower = string.lower(name)
	if lower == "init" or string.match(lower, "^init%.") then
		return "nama 'init' punya arti khusus di Rojo"
	end
	for _, suf in { ".server", ".client", ".meta", ".lua", ".luau", ".json", ".model", ".project", ".txt", ".csv", ".rbxm", ".rbxmx", ".toml", ".plugin", ".local" } do
		if string.sub(lower, -#suf) == suf then
			return `nama berakhiran '{suf}' disalahartikan Rojo`
		end
	end
	return nil
end

-- Nama kembar (tanpa beda huruf besar/kecil: disk Mac case-insensitive).
local function duplicateNames(parent: any): { [string]: boolean }
	local seen, dup = {}, {}
	for _, c in parent:GetChildren() do
		local k = string.lower(c.Name)
		if seen[k] then
			dup[k] = true
		end
		seen[k] = true
	end
	return dup
end

local function countScripts(i: any): number
	local n = if isScript(i) then 1 else 0
	for _, d in i:GetDescendants() do
		if isScript(d) then
			n += 1
		end
	end
	return n
end

-- Kenapa subtree ini TIDAK bisa diserahkan penuh ke Rojo ($path)? nil = bersih.
-- Bersih = hanya skrip (dan Folder bila allowFolders) di dalamnya, tanpa nama kembar,
-- tanpa folder kosong, semua nama aman.
local function subtreeProblem(i: any, allowFolders: boolean): string?
	local np = nameProblem(i.Name)
	if np then
		return `{np} ({explorerPath(i)})`
	end
	if i.ClassName == "Folder" and #i:GetChildren() == 0 then
		return `folder kosong tidak tersimpan di git ({explorerPath(i)})`
	end
	local dup = duplicateNames(i)
	if next(dup) then
		return `ada anak bernama kembar di {explorerPath(i)}`
	end
	for _, c in i:GetChildren() do
		if isScript(c) or (allowFolders and c.ClassName == "Folder") then
			local p = subtreeProblem(c, allowFolders)
			if p then
				return p
			end
		else
			return `berisi {c.ClassName} '{c.Name}' (bukan skrip)`
		end
	end
	return nil
end

local function writeJson(path: string, value: any)
	fs.writeFile(path, serde.encode("json", value, true) .. "\n")
end

local function recordScript(s: any, file: string)
	local src: string = s.Source
	local e: Entry = {
		path = explorerPath(s),
		class = s.ClassName,
		file = file,
		md5 = serde.hash("md5", src),
	}
	if s.ClassName ~= "ModuleScript" and s.Disabled then
		e.disabled = true
	end
	table.insert(entries, e)
end

local function scriptMeta(s: any): { [string]: any }?
	if s.ClassName ~= "ModuleScript" and s.Disabled then
		return { properties = { Disabled = true } }
	end
	return nil
end

local emitFolder: (any, string) -> string

-- Tulis skrip (bisa punya anak skrip) ke dir; kembalikan path relatif untuk $path.
local function emitScript(s: any, dir: string): string
	local suffix = SCRIPT_SUFFIX[s.ClassName]
	local children = s:GetChildren()
	if #children == 0 then
		local file = `{dir}/{s.Name}{suffix}`
		fs.writeFile(file, s.Source)
		local meta = scriptMeta(s)
		if meta then
			writeJson(`{dir}/{s.Name}.meta.json`, meta)
		end
		recordScript(s, file)
		return file
	end
	local sub = `{dir}/{s.Name}`
	fs.writeDir(sub)
	local initFile = `{sub}/init{suffix}`
	fs.writeFile(initFile, s.Source)
	local meta = scriptMeta(s)
	if meta then
		writeJson(`{sub}/init.meta.json`, meta)
	end
	recordScript(s, initFile)
	for _, c in children do
		if isScript(c) then
			emitScript(c, sub)
		else
			emitFolder(c, sub)
		end
	end
	return sub
end

function emitFolder(f: any, dir: string): string
	local sub = `{dir}/{f.Name}`
	fs.writeDir(sub)
	for _, c in f:GetChildren() do
		if isScript(c) then
			emitScript(c, sub)
		else
			emitFolder(c, sub)
		end
	end
	return sub
end

local function skipAll(i: any, reason: string)
	if isScript(i) then
		table.insert(skips, { path = explorerPath(i), reason = reason })
	end
	for _, d in i:GetDescendants() do
		if isScript(d) then
			table.insert(skips, { path = explorerPath(d), reason = reason })
		end
	end
end

-- Petakan anak-anak sebuah wadah. Kembalikan node proyek Rojo, atau nil bila tak ada yang diekstrak.
local function mapContainer(container: any, dir: string, node: { [string]: any }): boolean
	local any = false
	local dup = duplicateNames(container)
	for _, c in container:GetChildren() do
		if countScripts(c) == 0 then
			continue
		end
		if dup[string.lower(c.Name)] then
			skipAll(c, `nama '{c.Name}' kembar dengan saudaranya di {explorerPath(container)}`)
			continue
		end
		local np = nameProblem(c.Name)
		if np then
			skipAll(c, np)
			continue
		end
		if isScript(c) then
			local p = subtreeProblem(c, true)
			if p then
				skipAll(c, p)
			else
				fs.writeDir(dir)
				node[c.Name] = { ["$path"] = emitScript(c, dir) }
				any = true
			end
		elseif CONTAINERS[c.ClassName] then
			local clean = c.ClassName == "Folder" and subtreeProblem(c, true) == nil
			if clean then
				fs.writeDir(dir)
				node[c.Name] = { ["$path"] = emitFolder(c, dir) }
				any = true
			else
				local child = { ["$className"] = c.ClassName }
				if mapContainer(c, `{dir}/{c.Name}`, child) then
					node[c.Name] = child
					any = true
				end
			end
		else
			skipAll(c, `di dalam {c.ClassName} '{explorerPath(c)}'`)
		end
	end
	return any
end

local tree: { [string]: any } = { ["$className"] = "DataModel" }
for _, svcName in SERVICES do
	local svc = game:GetService(svcName)
	local node = { ["$className"] = svcName }
	if mapContainer(svc, `{OUT_ROOT}/{svcName}`, node) then
		tree[svcName] = node
	end
end

-- Skrip di service yang tidak dipetakan juga dicatat sebagai ditinggal.
for _, svc in game:GetChildren() do
	if table.find(SERVICES, svc.ClassName) == nil then
		for _, d in svc:GetDescendants() do
			if isScript(d) then
				table.insert(skips, { path = explorerPath(d), reason = `{svc.ClassName}: aset/map, Tahap 1 tidak dipetakan` })
			end
		end
	end
end

table.sort(entries, function(a, b)
	return a.path < b.path
end)
table.sort(skips, function(a, b)
	return a.path < b.path
end)

writeJson("default.project.json", { name = PROJECT_NAME, tree = tree })
writeJson("tools/extract/manifest.json", {
	source = placePath,
	sourceMd5 = serde.hash("md5", fs.readFile(placePath)),
	scripts = entries,
})

-- Laporan
local total = #entries + #skips
local byReason: { [string]: number } = {}
for _, s in skips do
	local key = string.gsub(s.reason, "'.-'", "'…'")
	byReason[key] = (byReason[key] or 0) + 1
end
local reasons = {}
for k, v in byReason do
	table.insert(reasons, { k = k, v = v })
end
table.sort(reasons, function(a, b)
	return a.v > b.v
end)

local lines = {
	"# Laporan ekstraksi Tahap 1",
	"",
	`Sumber: \`{placePath}\` (md5 {serde.hash("md5", fs.readFile(placePath))})`,
	"",
	`Total skrip: **{total}** · diekstrak ke \`{OUT_ROOT}/\`: **{#entries}** · ditinggal di place: **{#skips}**`,
	"",
	"## Alasan ditinggal",
	"| Jumlah | Alasan |",
	"|---|---|",
}
for _, r in reasons do
	table.insert(lines, `| {r.v} | {r.k} |`)
end
table.insert(lines, "")
table.insert(lines, "## Diekstrak")
table.insert(lines, "| Explorer | File | Disabled |")
table.insert(lines, "|---|---|---|")
for _, e in entries do
	table.insert(lines, `| {e.path} | \`{e.file}\` | {if e.disabled then "ya" else ""} |`)
end
table.insert(lines, "")
table.insert(lines, "## Ditinggal di place")
table.insert(lines, "| Explorer | Alasan |")
table.insert(lines, "|---|---|")
for _, s in skips do
	table.insert(lines, `| {s.path} | {s.reason} |`)
end
fs.writeFile("tools/extract/report.md", table.concat(lines, "\n") .. "\n")

print(`Total skrip {total}: diekstrak {#entries}, ditinggal {#skips}.`)
print("Tulis: default.project.json, tools/extract/manifest.json, tools/extract/report.md")
print("Berikutnya: lune run tools/extract/verify " .. placePath)
