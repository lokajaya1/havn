--!strict
-- Aturan gabung data lama (old) ke data game baru (new). MURNI: tanpa I/O.
-- Setiap strategi: (old, new|nil) -> nilai hasil. new == nil = kunci belum ada di game baru.

local Merge = {}

-- JSON kanonik (kunci diurutkan) untuk membandingkan / menghapus duplikat.
local function canon(v: any): string
	local t = type(v)
	if t == "table" then
		local n = #v
		local count = 0
		for _ in v do
			count += 1
		end
		if count == n then
			local parts = table.create(n)
			for i = 1, n do
				parts[i] = canon(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in v do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			local child = v[k]
			if child == nil then
				child = v[tonumber(k)]
			end
			table.insert(parts, string.format("%q", k) .. ":" .. canon(child))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end
Merge.canon = canon

function Merge.equal(a: any, b: any): boolean
	return canon(a) == canon(b)
end

local function isArray(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	local count = 0
	for _ in v do
		count += 1
	end
	return count == #v
end
Merge.isArray = isArray

-- {} atau tabel yang semua isinya tabel kosong (mis. ShopData default).
function Merge.isEmpty(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for _, x in v do
		if not (type(x) == "table" and Merge.isEmpty(x)) then
			return false
		end
	end
	return true
end

local function unionBy(a: any, b: any, keyOf: (any) -> string): any
	local out, seen = {}, {}
	for _, list in { a, b } do
		if type(list) == "table" then
			for _, item in ipairs(list) do
				local k = keyOf(item)
				if not seen[k] then
					seen[k] = true
					table.insert(out, item)
				end
			end
		end
	end
	return out
end

local function byId(item: any): string
	if type(item) == "table" and item.Id ~= nil then
		return "id:" .. tostring(item.Id)
	end
	return canon(item)
end

local function copyTable(t: { [any]: any }): { [any]: any }
	local out = {}
	for k, v in t do
		out[k] = v
	end
	return out
end

local strategies: { [string]: (any, any) -> any } = {}

-- Nilai di game baru dipertahankan; data lama hanya mengisi yang belum ada.
strategies.keepTarget = function(old, new)
	if new == nil then
		return old
	end
	return new
end

strategies.orBool = function(old, new)
	if new == nil then
		return old
	end
	return old == true or new == true
end

strategies.unionList = function(old, new)
	if new == nil then
		return old
	end
	if not (isArray(old) and isArray(new)) then
		return new
	end
	return unionBy(old, new, canon)
end

strategies.unionById = function(old, new)
	if new == nil then
		return old
	end
	if not (isArray(old) and isArray(new)) then
		return new
	end
	return unionBy(old, new, byId)
end

-- ShopData: lama jadi dasar; gamepass digabung (true menang); riwayat digabung.
strategies.shop = function(old, new)
	if new == nil then
		return old
	end
	if type(old) ~= "table" or type(new) ~= "table" then
		return new
	end
	local out = copyTable(old)
	for k, v in new do
		if out[k] == nil then
			out[k] = v
		end
	end
	local gpOld, gpNew = old.Gamepasses, new.Gamepasses
	if isArray(gpOld) and isArray(gpNew) then
		out.Gamepasses = unionBy(gpOld, gpNew, canon)
	elseif type(gpOld) == "table" or type(gpNew) == "table" then
		local gp = {}
		for _, src in { gpOld, gpNew } do
			if type(src) == "table" then
				for k, v in src do
					if gp[k] == nil or v == true then
						gp[k] = v
					end
				end
			end
		end
		out.Gamepasses = gp
	end
	for _, field in { "GiftHistory", "Purchases" } do
		if isArray(old[field]) and isArray(new[field]) then
			out[field] = unionBy(old[field], new[field], canon)
		end
	end
	return out
end

-- AvatarLikes: daftar yang di-like digabung, angka pakai yang terbesar.
strategies.likes = function(old, new)
	if new == nil then
		return old
	end
	if type(old) ~= "table" or type(new) ~= "table" then
		return new
	end
	local out = copyTable(old)
	for k, v in new do
		if out[k] == nil then
			out[k] = v
		end
	end
	if isArray(old.given) and isArray(new.given) then
		out.given = unionBy(old.given, new.given, canon)
	end
	for _, field in { "likes", "updated" } do
		local a, b = old[field], new[field]
		if type(a) == "number" and type(b) == "number" then
			out[field] = math.max(a, b)
		end
	end
	return out
end

-- Adonis: daftar (ban, log) digabung; nilai lain milik game baru dipertahankan.
strategies.adonis = function(old, new)
	if new == nil then
		return old
	end
	if isArray(old) and isArray(new) then
		return unionBy(old, new, canon)
	end
	return new
end

Merge.strategies = strategies

-- Waktu main: tambahkan selisih sejak migrasi terakhir (ledger) supaya tidak dobel.
-- Kembalikan (nilaiTarget, nilaiLedgerBaru) atau nil kalau tidak ada yang perlu ditulis.
function Merge.sumLedger(oldValue: number, targetValue: number?, applied: number?): (number?, number?)
	local delta = oldValue - (applied or 0)
	if delta <= 0 then
		return nil, nil
	end
	return (targetValue or 0) + delta, oldValue
end

-- Id pemain negatif = pemain uji Studio.
function Merge.isStudioKey(key: string): boolean
	return string.match(key, "%-%d+$") ~= nil
end

return Merge
