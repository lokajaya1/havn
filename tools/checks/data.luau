-- tools/checks/data.luau — jalankan: lune run tools/checks/data [folder-repo]
-- Ruangan DATA-STUDIO (claude/Rencana_DataStudio.md). Play di Studio memakai DataStore & topik
-- MessagingService universe LIVE yang sama, jadi tiap nama harus terpisah di Studio:
--   * kode baru  : lewat ReplicatedStorage/Config/StudioData (StudioData.name(nama, RunService:IsStudio()))
--   * kode lama  : akhiran _studio yang sudah terbukti (Likesystem, RoleManagerServer, ThemeColor, ...)
--   * MemoryStore: tidak perlu (Studio sudah dipisah Roblox), tetap didaftar di sini
-- Cek ini menjaga DAFTAR pemakai di bawah. File baru yang memanggil API itu, atau jumlah panggilan yang
-- berubah, membuat cek GAGAL sampai diperiksa lalu didaftarkan (sesudah namanya lewat StudioData).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ROOT = process.args[1] or "."

-- Pola panggilan (setelah komentar & isi string dibuang).
local CALLS = {
	GetDataStore = "[:%.]GetDataStore%s*[%(,]",
	GetOrderedDataStore = "[:%.]GetOrderedDataStore%s*[%(,]",
	GetGlobalDataStore = "[:%.]GetGlobalDataStore%s*[%(,]",
	GetSortedMap = "[:%.]GetSortedMap%s*[%(,]",
	GetHashMap = "[:%.]GetHashMap%s*[%(,]",
	GetQueue = "[:%.]GetQueue%s*[%(,]",
	PublishAsync = "[:%.]PublishAsync%s*[%(,]",
	SubscribeAsync = "[:%.]SubscribeAsync%s*[%(,]",
}
local HELPER = "StudioData%.name%s*%("

-- cara: "StudioData" (helper = jumlah StudioData.name minimal), "lama" (wajib ada IsStudio()),
-- "dari pemanggil" (nama/akhiran diberikan skrip lain), "MemoryStore" (Studio terpisah).
local DAFTAR = {
	["src/legacy/ServerScriptService/ShopServer.server.luau"] = {
		calls = { GetDataStore = 1, PublishAsync = 2, SubscribeAsync = 1 },
		cara = "StudioData",
		helper = 2,
	},
	["src/legacy/ServerScriptService/ReceiptHandler.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "StudioData",
		helper = 1,
	},
	["src/legacy/ServerScriptService/Misc/DanceHandler/Favorites.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "StudioData",
		helper = 1,
	},
	["src/legacy/ServerScriptService/FavoritePrompt.server.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "StudioData",
		helper = 1,
	},
	["src/legacy/ServerScriptService/MusicServer/Library.luau"] = {
		calls = { GetDataStore = 3 },
		cara = "StudioData",
		helper = 2,
		catatan = "+ library live dibaca (salinan awal Studio)",
	},
	["src/legacy/ServerScriptService/MusicServer/Volume.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "StudioData",
		helper = 1,
	},
	["src/legacy/ServerScriptService/MusicServer/Live.luau"] = {
		calls = { GetHashMap = 1, PublishAsync = 1, SubscribeAsync = 1 },
		cara = "StudioData",
		helper = 1,
		catatan = "+ MemoryStore MusicLive",
	},
	["src/legacy/ServerScriptService/AnnouncementHandler.server.luau"] = {
		calls = { PublishAsync = 1, SubscribeAsync = 1 },
		cara = "StudioData",
		helper = 1,
	},
	["src/legacy/ServerScriptService/Communityinfoservice.server.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "lama",
	},
	["src/legacy/ServerScriptService/Likesystem.server.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "lama",
	},
	["src/legacy/ServerScriptService/RoleManagerServer.server.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "lama",
	},
	["src/legacy/Workspace/TimePlayedLeaderboard/TimePlayedClass.server.luau"] = {
		calls = { GetDataStore = 1, GetOrderedDataStore = 1 },
		cara = "lama",
	},
	["src/server/ThemeColor/init.server.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "lama",
	},
	["src/server/ThemeMap/init.server.luau"] = {
		calls = { GetDataStore = 1 },
		cara = "lama",
	},
	["src/server/ThemeMap/Service.luau"] = {
		calls = { PublishAsync = 1, SubscribeAsync = 1 },
		cara = "dari pemanggil",
		catatan = "topik dari ThemeMap/init",
	},
	["src/legacy/ServerScriptService/DonationServer/init.server.luau"] = {
		calls = { GetDataStore = 3, GetOrderedDataStore = 2, GetSortedMap = 1 },
		cara = "lama",
		catatan = "+ papan baca live (studioReadsLive)",
	},
	["src/legacy/ServerScriptService/DonationServer/Global.luau"] = {
		calls = { PublishAsync = 1, SubscribeAsync = 1 },
		cara = "dari pemanggil",
		catatan = "topik dari DonationServer/init",
	},
	["src/legacy/ServerScriptService/DonationServer/Tiers.luau"] = {
		calls = { PublishAsync = 1, SubscribeAsync = 1 },
		cara = "dari pemanggil",
		catatan = "akhiran dari DonationServer/init",
	},
	["src/legacy/ServerScriptService/DonationServer/Feed.luau"] = {
		calls = { GetSortedMap = 1 },
		cara = "MemoryStore",
	},
	["src/server/ServerList.server.luau"] = {
		calls = { GetSortedMap = 1 },
		cara = "MemoryStore",
	},
}

-- Buang komentar & isi string (supaya teks seperti "PublishAsync gagal" tidak terhitung).
local function codeOnly(src: string): string
	local out = {}
	local i, n = 1, #src
	local function longBracket(at: number): number?
		local eq = string.match(src, "^%[(=*)%[", at)
		if eq == nil then
			return nil
		end
		local close = "]" .. eq .. "]"
		local stop = string.find(src, close, at + #eq + 2, true)
		return if stop then stop + #close - 1 else n
	end
	while i <= n do
		local c = string.sub(src, i, i)
		local two = string.sub(src, i, i + 1)
		if two == "--" then
			local stop = longBracket(i + 2)
			if stop then
				i = stop + 1
			else
				local nl = string.find(src, "\n", i, true)
				i = if nl then nl else n + 1
			end
		elseif c == "\"" or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c then
					break
				else
					j += 1
				end
			end
			table.insert(out, c .. c)
			i = j + 1
		elseif c == "[" and longBracket(i) then
			i = (longBracket(i) :: number) + 1
			table.insert(out, "\"\"")
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

local function count(code: string, pat: string): number
	local k = 0
	for _ in string.gmatch(code, pat) do
		k += 1
	end
	return k
end

local function walk(dir: string, list: { string })
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			walk(p, list)
		elseif string.match(name, "%.luau?$") then
			table.insert(list, p)
		end
	end
end

local files = {}
walk(ROOT .. "/src", files)
table.sort(files)

local fails = {}
local seen = {}
for _, full in files do
	local rel = string.sub(full, #ROOT + 2)
	local code = codeOnly(fs.readFile(full))
	local found = {}
	local any = false
	for kind, pat in CALLS do
		local k = count(code, pat)
		if k > 0 then
			found[kind] = k
			any = true
		end
	end
	local entry = DAFTAR[rel]
	if any and not entry then
		local parts = {}
		for kind, k in found do
			table.insert(parts, kind .. "×" .. k)
		end
		table.sort(parts)
		table.insert(fails, ("%s: pemakai BARU (%s) — nama wajib lewat StudioData.name, lalu daftarkan di tools/checks/data.luau")
			:format(rel, table.concat(parts, ", ")))
	elseif entry then
		seen[rel] = true
		for kind in CALLS do
			local want = entry.calls[kind] or 0
			local got = found[kind] or 0
			if want ~= got then
				table.insert(fails, ("%s: %s %d kali (daftar %d) — periksa _studio lalu perbarui daftar"):format(rel, kind, got, want))
			end
		end
		if entry.cara == "StudioData" then
			local h = count(code, HELPER)
			if h < (entry.helper or 1) then
				table.insert(fails, ("%s: StudioData.name dipakai %d kali (minimal %d)"):format(rel, h, entry.helper or 1))
			end
		elseif entry.cara == "lama" then
			if not string.find(code, "IsStudio%s*%(") then
				table.insert(fails, ("%s: cara lama tanpa IsStudio() — akhiran _studio hilang?"):format(rel))
			end
		end
	end
end
for rel in DAFTAR do
	if not seen[rel] then
		table.insert(fails, ("%s: ada di daftar tapi tidak ditemukan / tidak lagi memanggil API (perbarui daftar)"):format(rel))
	end
end

-- Helper sendiri: live = nama PERSIS, Studio = + _studio.
local helperPath = ROOT .. "/src/legacy/ReplicatedStorage/Config/StudioData.luau"
if not fs.isFile(helperPath) then
	table.insert(fails, "Config/StudioData.luau tidak ada")
else
	local ok, StudioData = pcall(function()
		return luau.load(fs.readFile(helperPath), { debugName = "StudioData" })()
	end)
	if not ok then
		table.insert(fails, "Config/StudioData.luau gagal dimuat: " .. tostring(StudioData))
	elseif StudioData.name("ShopData", false) ~= "ShopData" or StudioData.name("ShopData", true) ~= "ShopData_studio" then
		table.insert(fails, "Config/StudioData.name tidak sesuai aturan (live persis, Studio + _studio)")
	end
end

table.sort(fails)
if #fails > 0 then
	print(("GAGAL: %d masalah store/topik Studio (DATA-STUDIO):"):format(#fails))
	for _, l in fails do
		print("  " .. l)
	end
	process.exit(1)
end
local n = 0
for _ in DAFTAR do
	n += 1
end
print(("OK: %d file pemakai DataStore/Messaging/MemoryStore cocok dengan daftar DATA-STUDIO"):format(n))
