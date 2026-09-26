--!strict
-- Cek sintaks semua kode di repo (dipakai CI dan lokal):
--   lune run tools/checks/syntax
--
-- • Setiap .luau di src/ dan tools/ harus bisa dikompilasi Luau.
-- • Setiap .json di src/ (meta) dan default.project.json harus JSON valid.
-- Tidak butuh file place, jadi aman dijalankan di GitHub Actions.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ROOTS = { "src", "tools" }

local problems: { string } = {}
local counts = { luau = 0, json = 0 }

local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			if name ~= "out" and name ~= "node_modules" then
				walk(path)
			end
		elseif string.sub(name, -5) == ".luau" then
			counts.luau += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				table.insert(problems, `{path}: {err}`)
			end
		elseif string.sub(name, -5) == ".json" and string.sub(dir, 1, 3) == "src" then
			counts.json += 1
			local ok, err = pcall(serde.decode, "json", fs.readFile(path))
			if not ok then
				table.insert(problems, `{path}: JSON tidak valid: {err}`)
			end
		end
	end
end

for _, root in ROOTS do
	if fs.isDir(root) then
		walk(root)
	end
end

local ok, err = pcall(serde.decode, "json", fs.readFile("default.project.json"))
counts.json += 1
if not ok then
	table.insert(problems, `default.project.json: JSON tidak valid: {err}`)
end

if #problems > 0 then
	for _, m in problems do
		print("GAGAL: " .. m)
	end
	print(`{#problems} masalah`)
	process.exit(1)
end
print(`OK: {counts.luau} file .luau terkompilasi, {counts.json} file JSON valid.`)
