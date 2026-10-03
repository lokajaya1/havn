--!strict
-- tools/checks/assets.luau — aturan ASET WAJIB (murni, tanpa API Lune/Roblox).
-- Dipakai tools/checks/place. Salinan berdiri sendiri untuk Command Bar: tools/checks/studio/cek_aset.luau (isi aturan HARUS sama).
--
-- Kenapa: aset non-skrip milik Studio (Value, Handle, partikel) bisa hilang tanpa terlihat — skripnya tetap identik dengan repo,
-- jadi cek skrip biasa lolos. Kejadian WORLD (3 Okt): 30 Value carry + isi GlowStick/WaterGun/Flying Broom hilang (claude/Rencana_Tools.md T0).

local Assets = {}

-- Tool: bagian yang WAJIB ada (jalur relatif dari Tool). Tool tanpa Handle (RequiresHandle) tidak bisa dipakai.
Assets.TOOLS = {
	{ path = "StarterPack/GlowStick", need = { "Handle" } },
	{ path = "StarterPack/Sign", need = { "Handle", "Handle/Part/SurfaceGui/TextLabel" } },
	{ path = "ServerStorage/WaterGun", need = { "Handle", "Part/Water" } },
	{ path = "ServerStorage/Flying Broom", need = { "Handle" } },
	{ path = "ServerStorage/Money Gun", need = { "Handle", "RemoteEvent" } },
}

-- Skrip yang tidak dipindai rujukannya: library contoh yang tidak pernah di-require (0 pemakai) + vendor/luar repo
-- (Command Bar memindai semua skrip di place; Adonis_Loader dilewati SELURUHNYA → Settings tidak pernah dibaca).
Assets.SKIP = {
	"ReplicatedStorage/CustomTween",
	"ReplicatedStorage/RagdollService",
	"ServerScriptService/Adonis_Loader",
	"StarterGui/DonationBigFX",
	"ReplicatedStorage/DonationFXConfig",
}

-- Anggota LuaSourceContainer/Instance — bukan anak (script.Name, script.Parent, …).
Assets.MEMBERS = {
	Parent = true, Name = true, ClassName = true, Archivable = true, Source = true, Disabled = true, Enabled = true,
	RunContext = true, LinkedSource = true, Changed = true, Destroying = true, AncestryChanged = true, ChildAdded = true,
	ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, AttributeChanged = true,
}

function Assets.skipped(path: string): boolean
	for _, p in Assets.SKIP do
		if path == p or string.sub(path, 1, #p + 1) == p .. "/" then
			return true
		end
	end
	return false
end

function Assets.stripComments(src: string): string
	local s = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	s = string.gsub(s, "%-%-[^\n]*", "")
	return s
end

export type Ref = { hops: number, name: string }

-- Rujukan anak yang PASTI wajib ada (tanpa FindFirstChild):
--   script.X · script["X"] · script:WaitForChild("X") · script.Parent…:WaitForChild("X")
-- `script.Parent.X` (titik) TIDAK dihitung: bisa properti/event induknya (mis. RemoteEvent.OnServerEvent).
function Assets.refs(src: string): { Ref }
	local s = Assets.stripComments(src)
	local out: { Ref } = {}
	local i = 1
	while true do
		local a, b = string.find(s, "%f[%w_]script%f[^%w_]", i)
		if a == nil or b == nil then
			break
		end
		-- bukan kode: bagian URL/teks ("https://script.google.com", "script.X" di dalam string)
		local prev = string.sub(s, a - 1, a - 1)
		local code = not (prev == "/" or prev == "." or prev == ":" or prev == "-" or prev == '"' or prev == "'")
		local pos = b + 1
		local hops = 0
		while string.sub(s, pos, pos + 6) == ".Parent" and not string.match(string.sub(s, pos + 7, pos + 7), "[%w_]") do
			hops += 1
			pos += 7
		end
		local name: string? = string.match(s, '^:WaitForChild%(%s*"([^"]+)"', pos)
			or string.match(s, "^:WaitForChild%(%s*'([^']+)'", pos)
		if name == nil and hops == 0 then
			name = string.match(s, "^%.([%a_][%w_]*)", pos)
				or string.match(s, '^%[%s*"([^"]+)"%s*%]', pos)
				or string.match(s, "^%[%s*'([^']+)'%s*%]", pos)
		end
		if code and name ~= nil and not Assets.MEMBERS[name] then
			table.insert(out, { hops = hops, name = name })
		end
		i = b + 1
	end
	return out
end

return Assets
