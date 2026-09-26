--!strict
-- Tes alat migrasi: unit (lib/merge) + end-to-end melawan server Open Cloud tiruan lokal.
-- Pemakaian: lune run tools/migrate/test   → harus diakhiri "SEMUA PASS".
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Copy = require("./lib/copy")
local Http = require("./lib/http")
local Merge = require("./lib/merge")
local rules = require("./rules")

local pass, fail = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		pass += 1
	else
		fail += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  → " .. Merge.canon(detail) else ""))
	end
end
local eq = Merge.equal

-- ---------------- unit: merge ----------------
local s = Merge.strategies
check("keepTarget baru kosong", eq(s.keepTarget(1, nil), 1))
check("keepTarget pertahankan baru", eq(s.keepTarget(1, 2), 2))
check("orBool", s.orBool(false, true) == true and s.orBool(true, false) == true and s.orBool(false, false) == false)
check("unionList", eq(s.unionList({ "A", "B" }, { "B", "C" }), { "A", "B", "C" }))
check("unionById", eq(s.unionById({ { Id = "1", n = 1 } }, { { Id = "1", n = 2 }, { Id = "2" } }), { { Id = "1", n = 1 }, { Id = "2" } }))
check(
	"shop gamepass true menang + riwayat gabung",
	eq(
		s.shop(
			{ Gamepasses = { Commands = true, VIP = false }, GiftHistory = {}, Purchases = { "p1" } },
			{ Gamepasses = { VIP = true }, GiftHistory = { "g" }, Purchases = { "p2" } }
		),
		{ Gamepasses = { Commands = true, VIP = true }, GiftHistory = { "g" }, Purchases = { "p1", "p2" } }
	)
)
check(
	"likes",
	eq(
		s.likes({ given = { 1, 2 }, likes = 5, updated = 100 }, { given = { 2, 3 }, likes = 2, updated = 200 }),
		{ given = { 1, 2, 3 }, likes = 5, updated = 200 }
	)
)
check("adonis daftar digabung", eq(s.adonis({ { User = "x" } }, { { User = "y" } }), { { User = "x" }, { User = "y" } }))
check("adonis nilai baru dipertahankan", eq(s.adonis("lama", "baru"), "baru"))
check("isEmpty default shop", Merge.isEmpty({ Gamepasses = {}, GiftHistory = {}, Purchases = {} }))
check("isEmpty bukan", not Merge.isEmpty({ Gamepasses = { Commands = true } }) and not Merge.isEmpty(false))
check("studio key", Merge.isStudioKey("-1") and Merge.isStudioKey("fav_-3") and not Merge.isStudioKey("fav_12"))
local v1, l1 = Merge.sumLedger(100, 7, nil)
local v2 = Merge.sumLedger(100, 107, 100)
local v3, l3 = Merge.sumLedger(130, 107, 100)
check("sumLedger", v1 == 107 and l1 == 100 and v2 == nil and v3 == 137 and l3 == 130)
check("canon urutan kunci stabil", Merge.canon({ b = 1, a = 2 }) == Merge.canon({ a = 2, b = 1 }))

-- ---------------- server tiruan ----------------
type Entry = { value: any, users: any, attributes: any, rev: number }
local db: { [string]: any } = {}
local writes: { [string]: number } = {}
local inject408 = 1

local function uni(u: string)
	db[u] = db[u] or { std = {}, ord = {} }
	return db[u]
end
local function putStd(u: string, ds: string, scope: string, key: string, value: any, users: any?)
	local st = uni(u).std
	st[ds] = st[ds] or {}
	st[ds][scope] = st[ds][scope] or {}
	st[ds][scope][key] = { value = value, users = users, attributes = nil, rev = 1 }
end
local function getStd(u: string, ds: string, scope: string, key: string): Entry?
	local st = uni(u).std[ds]
	return st and st[scope] and st[scope][key]
end
local function putOrd(u: string, name: string, key: string, value: number)
	local o = uni(u).ord
	o[name] = o[name] or {}
	o[name][key] = value
end

local function reply(status: number, body: any)
	return { status = status, headers = { ["content-type"] = "application/json" }, body = serde.encode("json", body) }
end

local function sortedKeys(t: { [string]: any }): { string }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

local function page(items: { any }, q: { [string]: string }, size: number): ({ any }, string?)
	local start = tonumber(q.pageToken or "1") or 1
	local out = {}
	for i = start, math.min(#items, start + size - 1) do
		table.insert(out, items[i])
	end
	local nextToken = if start + size <= #items then tostring(start + size) else nil
	return out, nextToken
end

local function handler(req: any)
	local seg = {}
	for part in string.gmatch(req.path, "[^/]+") do
		table.insert(seg, net.urlDecode(part))
	end
	local q = req.query or {}
	local body = if req.body and req.body ~= "" then serde.decode("json", req.body) else nil
	-- cloud v2 universes {u} <kind> {name} scopes {scope} entries [key]
	local u, kind, name, scope, key = seg[4], seg[5], seg[6], seg[8], seg[10]
	if req.method ~= "GET" then
		writes[u] = (writes[u] or 0) + 1
	end
	if kind == "data-stores" then
		local store = uni(u).std[name]
		if key == nil and req.method == "GET" then
			if not store then
				return reply(404, { message = "not found" })
			end
			local items = {}
			for _, sc in sortedKeys(store) do
				if scope == "-" or scope == sc then
					for _, k in sortedKeys(store[sc]) do
						table.insert(items, { id = sc .. "/" .. k, path = "x/scopes/" .. sc .. "/entries/" .. k })
					end
				end
			end
			local p, nt = page(items, q, 2)
			return reply(200, { dataStoreEntries = p, nextPageToken = nt })
		elseif key == nil and req.method == "POST" then
			if getStd(u, name, scope, q.id) then
				return reply(400, { message = "exists" })
			end
			putStd(u, name, scope, q.id, body.value, body.users)
			return reply(200, { id = q.id })
		end
		if string.find(key, "@", 1, true) then
			local base, rev = string.match(key, "^(.*)@([^@]*)$")
			if rev ~= "latest" then
				return reply(403, { message = "missing scope universe-datastores.versions:read." })
			end
			key = base
		end
		local e = getStd(u, name, scope, key)
		if req.method == "GET" then
			if inject408 > 0 then
				inject408 -= 1
				return { status = 408, body = "<html>408</html>" }
			end
			if not e then
				return reply(404, { message = "Entry not found." })
			end
			return reply(200, { value = e.value, users = e.users, attributes = e.attributes, etag = tostring(e.rev) })
		elseif req.method == "PATCH" then
			if e and body.etag and body.etag ~= tostring(e.rev) then
				return reply(412, { message = "etag mismatch" })
			end
			if not e and q.allowMissing ~= "true" then
				return reply(404, { message = "Entry not found." })
			end
			local rev = if e then e.rev + 1 else 1
			uni(u).std[name][scope][key] = { value = body.value, users = body.users, attributes = body.attributes, rev = rev }
			return reply(200, { value = body.value })
		end
	elseif kind == "ordered-data-stores" then
		local store = uni(u).ord[name]
		if key == nil and req.method == "GET" then
			if not store then
				return reply(404, { message = "not found" })
			end
			local items = {}
			for _, k in sortedKeys(store) do
				table.insert(items, { id = k, value = store[k] })
			end
			local p, nt = page(items, q, 2)
			return reply(200, { orderedDataStoreEntries = p, nextPageToken = nt })
		elseif key == nil and req.method == "POST" then
			if store and store[q.id] ~= nil then
				return reply(400, { message = "exists" })
			end
			putOrd(u, name, q.id, body.value)
			return reply(200, { id = q.id, value = body.value })
		elseif req.method == "PATCH" then
			if not (store and store[key] ~= nil) and q.allowMissing ~= "true" then
				return reply(404, { message = "not found" })
			end
			putOrd(u, name, key, body.value)
			return reply(200, { id = key, value = body.value })
		end
	end
	return reply(404, { message = "no route " .. req.path })
end

-- ---------------- data uji ----------------
local S, T = rules.source, rules.target
putStd(S, "ShopData", "global", "10", { Gamepasses = { Commands = true }, GiftHistory = {}, Purchases = {} })
putStd(S, "ShopData", "global", "11", { Gamepasses = {}, GiftHistory = {}, Purchases = {} })
putStd(S, "ShopData", "global", "-1", { Gamepasses = { Commands = true }, GiftHistory = {}, Purchases = {} })
putStd(S, "ShopData", "global", "12", { Gamepasses = {}, GiftHistory = {}, Purchases = { "p1" } })
putStd(T, "ShopData", "global", "12", { Gamepasses = { VIP = true }, GiftHistory = {}, Purchases = { "p2" } }, { "users/12" })
putStd(S, "DanceFavorites_v2", "global", "favorites_10", { "A", "B" })
putStd(S, "DanceFavorites_v2", "global", "favorites_11", {})
putStd(T, "DanceFavorites", "global", "favorites_10", { "B", "C" })
putStd(S, "FavoritePrompted_V1", "global", "fav_10", true)
putStd(S, "FavoritePrompted_V1", "global", "fav_11", false)
putStd(T, "FavoritePrompted", "global", "fav_11", true)
putStd(S, "PlayerMusicVolume_v2", "global", "Vol_10", 0.5)
putStd(S, "PlayerMusicVolume_v2", "global", "Vol_11", 0.2)
putStd(S, "PlayerMusicVolume_v2", "global", "MyLib_10", { { Id = "1" } })
putStd(S, "PlayerMusicVolume_v2", "global", "MyLib_11", {})
putStd(T, "MusicVolume", "global", "Vol_10", 0.9)
putStd(T, "MusicFavorites", "global", "MyLib_10", { { Id = "2" } })
putStd(S, "SharedMusicLibrary_v2", "global", "GlobalLib", { { Id = "a" }, { Id = "b" } })
putStd(T, "MusicLibrary", "global", "GlobalLib", { { Id = "b" }, { Id = "c" } })
putStd(S, "AvatarLikes_v1", "global", "u_10", { given = { 1, 2 }, likes = 5, updated = 100 })
putStd(T, "AvatarLikes", "global", "u_10", { given = { 2, 3 }, likes = 2, updated = 200 })
putStd(S, "CommunityPref", "global", "u_10", true)
putStd(S, "AdminTitleData_v1", "global", "10", { title = "VIP", colorHex = "FF0000" })
putStd(S, "Adonis_1", "Adonis", "K1", { { User = "x" } })
putStd(S, "Adonis_1", "Adonis", "K2", "lama")
putStd(S, "Adonis_1", "Adonis", "K3", { a = 1 })
putStd(S, "Adonis_1", "global", "G", "abaikan")
putStd(T, "AdonisData", "Adonis", "K1", { { User = "y" } })
putStd(T, "AdonisData", "Adonis", "K2", "baru")
putStd(S, "DonationData_v1", "global", "10", { total = 5 })
putStd(S, "Donation Board v4", "global", "donationboard@donations", { ["10"] = { UserId = 10 } })
putOrd(S, "TopTimePlayed", "TimePlayed10", 100)
putOrd(S, "TopTimePlayed", "TimePlayed11", 50)
putOrd(S, "TopTimePlayed", "TimePlayed-1", 5)
putOrd(T, "TopTimePlayed", "TimePlayed10", 7)
putOrd(S, "PlayerDonations_v1", "10", 5)

-- ---------------- jalankan ----------------
local PORT = 18791
local server = net.serve(PORT, handler)
local OUT = "tools/migrate/out/_test"
if fs.isDir(OUT) then
	fs.removeDir(OUT)
end
fs.writeDir(OUT)

local quiet = function(_: string) end
local function run(apply: boolean)
	local http = Http.new("http://127.0.0.1:" .. PORT, "TESTKEY", 0, quiet)
	return Copy.run({
		http = http,
		rules = rules,
		source = S,
		target = T,
		apply = apply,
		outDir = OUT,
		stamp = "t" .. tostring(os.clock()),
		log = quiet,
	})
end

local dry = run(false)
check("uji kering: 0 tulis", (writes[S] or 0) == 0 and (writes[T] or 0) == 0, writes)
check("uji kering: rencana shop", dry.rules.shop.create == 1 and dry.rules.shop.update == 1 and dry.rules.shop.skippedEmpty == 1)

local r1 = run(true)
check("apply: sumber tidak pernah ditulis", (writes[S] or 0) == 0, writes)
local function val(ds, key, scope: string?)
	local e = getStd(T, ds, scope or "global", key)
	return e and e.value
end
check("shop 10 dibuat", eq(val("ShopData", "10"), { Gamepasses = { Commands = true }, GiftHistory = {}, Purchases = {} }))
check("shop 11 kosong dilewati", val("ShopData", "11") == nil)
check("shop -1 studio dilewati", val("ShopData", "-1") == nil)
check(
	"shop 12 digabung",
	eq(val("ShopData", "12"), { Gamepasses = { VIP = true }, GiftHistory = {}, Purchases = { "p1", "p2" } }),
	val("ShopData", "12")
)
check("shop 12 users tetap", eq((getStd(T, "ShopData", "global", "12") :: any).users, { "users/12" }))
check("dance gabung", eq(val("DanceFavorites", "favorites_10"), { "A", "B", "C" }))
check("dance kosong dilewati", val("DanceFavorites", "favorites_11") == nil)
check("favPrompt", val("FavoritePrompted", "fav_10") == true and val("FavoritePrompted", "fav_11") == true)
check("volume: setelan baru dipertahankan", val("MusicVolume", "Vol_10") == 0.9 and val("MusicVolume", "Vol_11") == 0.2)
check("volume tidak masuk MusicFavorites", val("MusicFavorites", "Vol_10") == nil)
check("musicFav gabung per Id", eq(val("MusicFavorites", "MyLib_10"), { { Id = "1" }, { Id = "2" } }))
check("musicLib gabung", eq(val("MusicLibrary", "GlobalLib"), { { Id = "a" }, { Id = "b" }, { Id = "c" } }))
check("likes", eq(val("AvatarLikes", "u_10"), { given = { 1, 2, 3 }, likes = 5, updated = 200 }))
check("community", val("CommunityPref", "u_10") == true)
check("titles", eq(val("AdminTitles", "10"), { title = "VIP", colorHex = "FF0000" }))
check("adonis list gabung", eq(val("AdonisData", "K1", "Adonis"), { { User = "x" }, { User = "y" } }))
check("adonis nilai baru tetap", val("AdonisData", "K2", "Adonis") == "baru")
check("adonis kunci baru dibuat", eq(val("AdonisData", "K3", "Adonis"), { a = 1 }))
check("adonis scope global diabaikan", getStd(T, "AdonisData", "global", "G") == nil)
check("donationData", eq(val("DonationData_v1", "10"), { total = 5 }))
check("donation board kunci @", eq(val("Donation Board v4", "donationboard@donations"), { ["10"] = { UserId = 10 } }))
local ordT = db[T].ord
check("timePlayed dijumlah", ordT.TopTimePlayed.TimePlayed10 == 107 and ordT.TopTimePlayed.TimePlayed11 == 50, ordT.TopTimePlayed)
check("timePlayed studio dilewati", ordT.TopTimePlayed["TimePlayed-1"] == nil)
check("donationsOrdered", ordT.PlayerDonations_v1 and ordT.PlayerDonations_v1["10"] == 5)
local totalFailed = 0
for _, c in r1.rules do
	totalFailed += c.failed
end
check("apply: 0 gagal (termasuk ulang 408)", totalFailed == 0, r1.rules)
check("cadangan ditulis", r1.backupFile ~= nil and fs.isFile(r1.backupFile))

local before = writes[T] or 0
local r2 = run(true)
check("jalan ulang: 0 tulis (idempoten)", (writes[T] or 0) == before, { before = before, after = writes[T] })
check("jalan ulang: waktu main tidak dobel", ordT.TopTimePlayed.TimePlayed10 == 107)
check("jalan ulang: shop sama", r2.rules.shop.same >= 2)

putOrd(S, "TopTimePlayed", "TimePlayed10", 130)
before = writes[T] or 0
run(true)
check("sinkron akhir: hanya selisih", ordT.TopTimePlayed.TimePlayed10 == 137 and (writes[T] or 0) == before + 1)

server.stop()
fs.removeDir(OUT)
print(string.format("\n%d PASS, %d FAIL", pass, fail))
if fail == 0 then
	print("SEMUA PASS")
end
process.exit(if fail == 0 then 0 else 1)
