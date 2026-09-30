--!strict
-- MapGen/Naming — aturan nama Workspace (domain murni). Lihat claude/Rencana_Workspace.md §3.
-- Nama sah: PascalCase Bahasa Inggris, dipisah "_", mis. "Container_Red_03", "Wall_North", "NeonSign_Arcade".

local Naming = {}

-- Nama bawaan Studio / nama kelas yang dilarang dipakai sebagai nama objek.
Naming.banned = {
	Part = true,
	Model = true,
	Union = true,
	UnionOperation = true,
	MeshPart = true,
	Folder = true,
	WedgePart = true,
	CornerWedgePart = true,
	TrussPart = true,
	NegateOperation = true,
	SpecialMesh = true,
	Script = true,
	LocalScript = true,
}

-- Mengembalikan alasan (string) kalau nama TIDAK sah, atau nil kalau sah.
function Naming.problem(name: string): string?
	if name == "" then
		return "kosong"
	end
	if Naming.banned[name] then
		return "nama bawaan Studio"
	end
	if string.sub(name, 1, 7) == "Meshes/" then
		return "nama mesh bawaan"
	end
	if not string.match(name, "^[A-Z][A-Za-z0-9]*$") then
		for piece in string.gmatch(name, "[^_]+") do
			if not string.match(piece, "^[A-Z0-9][A-Za-z0-9]*$") then
				return "bukan PascalCase_Dipisah_Garis_Bawah"
			end
		end
		if string.find(name, "__", 1, true) or string.sub(name, -1) == "_" or string.sub(name, 1, 1) == "_" then
			return "garis bawah ganda/di ujung"
		end
	end
	return nil
end

-- Nama kembar di satu induk (daftar nama anak) → daftar nama yang muncul > 1 kali.
function Naming.duplicates(names: { string }): { string }
	local seen: { [string]: number } = {}
	for _, n in names do
		seen[n] = (seen[n] or 0) + 1
	end
	local out = {}
	for n, c in seen do
		if c > 1 then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

-- Nama cadangan untuk isi mesh kit yang bernama generik ("Part" → "Piece_03").
function Naming.fallback(className: string, index: number): string
	local role = if className == "Model" or className == "Folder" then "Group" else "Piece"
	return string.format("%s_%02d", role, index)
end

return Naming
