-- HITUNG + CEK ASET — tempel di Command Bar Studio (mode Edit). TIDAK mengubah apa pun.
-- Jalankan tiap habis Connect Rojo dan sebelum Publish (pengganti snippet hitung skrip lama).
-- Aturan = tools/checks/assets.luau (salinan berdiri sendiri; isi TOOLS/SKIP/MEMBERS/refs HARUS sama — dicek tes).
-- Adonis_Loader dilewati seluruhnya → modul Settings (DataStoreKey) tidak pernah dibaca.
local TOOLS = {
	{ path = "StarterPack/GlowStick", need = { "Handle" } },
	{ path = "StarterPack/Sign", need = { "Handle", "Handle/Part/SurfaceGui/TextLabel" } },
	{ path = "ServerStorage/WaterGun", need = { "Handle", "Part/Water" } },
	{ path = "ServerStorage/Flying Broom", need = { "Handle" } },
	{ path = "ServerStorage/Money Gun", need = { "Handle", "RemoteEvent" } },
}
local SKIP = {
	"ReplicatedStorage/CustomTween",
	"ReplicatedStorage/RagdollService",
	"ServerScriptService/Adonis_Loader",
	"StarterGui/DonationBigFX",
	"ReplicatedStorage/DonationFXConfig",
}
local MEMBERS = {
	Parent = true, Name = true, ClassName = true, Archivable = true, Source = true, Disabled = true, Enabled = true,
	RunContext = true, LinkedSource = true, Changed = true, Destroying = true, AncestryChanged = true, ChildAdded = true,
	ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, AttributeChanged = true,
}

local function pathOf(i)
	local parts = {}
	while i and i ~= game do
		table.insert(parts, 1, i.Name)
		i = i.Parent
	end
	return table.concat(parts, "/")
end
local function skipped(path)
	for _, p in ipairs(SKIP) do
		if path == p or string.sub(path, 1, #p + 1) == p .. "/" then
			return true
		end
	end
	return false
end
local function stripComments(src)
	local s = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	s = string.gsub(s, "%-%-[^\n]*", "")
	return s
end
local function refs(src)
	local s = stripComments(src)
	local out = {}
	local i = 1
	while true do
		local a, b = string.find(s, "%f[%w_]script%f[^%w_]", i)
		if a == nil or b == nil then
			break
		end
		local prev = string.sub(s, a - 1, a - 1)
		local code = not (prev == "/" or prev == "." or prev == ":" or prev == "-" or prev == '"' or prev == "'")
		local pos = b + 1
		local hops = 0
		while string.sub(s, pos, pos + 6) == ".Parent" and not string.match(string.sub(s, pos + 7, pos + 7), "[%w_]") do
			hops += 1
			pos += 7
		end
		local name = string.match(s, '^:WaitForChild%(%s*"([^"]+)"', pos)
			or string.match(s, "^:WaitForChild%(%s*'([^']+)'", pos)
		if name == nil and hops == 0 then
			name = string.match(s, "^%.([%a_][%w_]*)", pos)
				or string.match(s, '^%[%s*"([^"]+)"%s*%]', pos)
				or string.match(s, "^%[%s*'([^']+)'%s*%]", pos)
		end
		if code and name ~= nil and not MEMBERS[name] then
			table.insert(out, { hops = hops, name = name })
		end
		i = b + 1
	end
	return out
end
local function findPath(rel)
	local cur = game
	for part in string.gmatch(rel, "[^/]+") do
		if cur == game then
			local ok, svc = pcall(function()
				return game:GetService(part)
			end)
			cur = ok and svc or nil
		else
			cur = cur and cur:FindFirstChild(part)
		end
	end
	return cur
end
local function findRel(inst, rel)
	local cur = inst
	for part in string.gmatch(rel, "[^/]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	return cur
end

local n, scanned, missing = 0, 0, {}
for _, d in ipairs(game:GetDescendants()) do
	local ok, is = pcall(function()
		return d:IsA("LuaSourceContainer")
	end)
	if ok and is then
		n += 1
		local path = pathOf(d)
		if not skipped(path) then
			local okSrc, src = pcall(function()
				return d.Source
			end)
			if okSrc and type(src) == "string" then
				scanned += 1
				for _, ref in ipairs(refs(src)) do
					local base = d
					for _ = 1, ref.hops do
						base = base and base.Parent
					end
					if not (base and base:FindFirstChild(ref.name)) then
						table.insert(missing, path .. string.rep("/..", ref.hops) .. " tidak punya '" .. ref.name .. "'")
					end
				end
			end
		end
	end
end
for _, t in ipairs(TOOLS) do
	local tool = findPath(t.path)
	if not tool then
		table.insert(missing, t.path .. " (Tool) tidak ada")
	else
		for _, need in ipairs(t.need) do
			if not findRel(tool, need) then
				table.insert(missing, t.path .. " tidak punya '" .. need .. "' → tool tidak bisa dipakai")
			end
		end
	end
end
print("JUMLAH SKRIP:", n)
if #missing == 0 then
	print(("CEK ASET OK — %d tool lengkap · rujukan anak di %d skrip lengkap"):format(#TOOLS, scanned))
else
	for _, m in ipairs(missing) do
		warn("ASET HILANG: " .. m)
	end
	warn(("CEK ASET: %d aset hilang → jangan Publish, kirim Output ini"):format(#missing))
end
