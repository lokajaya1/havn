--!strict
-- Inventaris DataStore (READ-ONLY) lewat Open Cloud v2.
-- Pemakaian:  lune run tools/migrate/inventory <universeId> [universeId ...] [--ordered=A,B,C]
-- Key dibaca dari env ROBLOX_API_KEY (tidak pernah dicetak / disimpan).
-- Hasil: ringkasan di terminal + tools/migrate/out/inventory_<universe>.json (tanpa nilai data pemain).

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local DEFAULT_ORDERED = { "TopTimePlayed", "PlayerDonations_v1", "SaweriaScore_v1" }
local SAMPLES_PER_PATTERN = 3
local MIN_INTERVAL = 0.3 -- detik antar request (<= 200/menit; budget bersama game live)
local MAX_RETRY = 6
local OUT_DIR = "tools/migrate/out"

local BASE = "https://apis.roblox.com"
local override = process.env.ROBLOX_API_BASE
if override and override ~= "" then
	-- hanya untuk tes lokal; key tidak boleh dikirim ke host lain
	assert(string.match(override, "^http://127%.0%.0%.1:%d+$"), "ROBLOX_API_BASE hanya boleh http://127.0.0.1:<port>")
	BASE = override
end

local KEY = process.env.ROBLOX_API_KEY
if not KEY or KEY == "" then
	print('ROBLOX_API_KEY kosong. Jalankan dulu:  read -s "ROBLOX_API_KEY?API key: " && export ROBLOX_API_KEY')
	process.exit(1)
end

-- ---------- HTTP ----------
local lastAt = 0
local requestCount = 0

local function enc(s: string): string
	return net.urlEncode(s)
end

local function get(path: string, query: { [string]: string }?): (number, any)
	local attempt = 0
	while true do
		local wait = MIN_INTERVAL - (os.clock() - lastAt)
		if wait > 0 then
			task.wait(wait)
		end
		lastAt = os.clock()
		requestCount += 1
		local ok, res = pcall(net.request, {
			url = BASE .. path,
			method = "GET",
			query = query,
			headers = { ["x-api-key"] = KEY :: string, ["accept"] = "application/json" },
		})
		local status = if ok then res.statusCode else 0
		-- patch: retry-408-only
		local retryable = (not ok) or status == 408 or status == 429 or status >= 500
		if retryable and attempt < MAX_RETRY then
			attempt += 1
			local delay = 2 ^ attempt
			if ok and res.headers then
				local ra = tonumber(res.headers["retry-after"] or "")
				if ra and ra > 0 then
					delay = math.min(ra, 60)
				end
			end
			print(string.format("   ... %s, ulang %d/%d dalam %ds", if ok then "HTTP " .. status else "jaringan gagal", attempt, MAX_RETRY, delay))
			task.wait(delay)
		else
			if not ok then
				return 0, { error = tostring(res) }
			end
			local body: any = nil
			if res.body and res.body ~= "" then
				local okJ, decoded = pcall(serde.decode, "json" :: any, res.body)
				body = if okJ then decoded else { raw = string.sub(res.body, 1, 300) }
			end
			return status, body
		end
	end
end

local function errText(status: number, body: any): string
	local msg = ""
	if type(body) == "table" then
		msg = tostring(body.message or body.error or body.raw or "")
	end
	return string.format("HTTP %d %s", status, msg)
end

-- ---------- bentuk nilai (tanpa isi) ----------
local function isArray(t: { [any]: any }): (boolean, number)
	local n = 0
	for k in t do
		if type(k) ~= "number" then
			return false, 0
		end
		n += 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false, 0
		end
	end
	return true, n
end

local function shape(v: any, depth: number): string
	local tv = type(v)
	if v == nil then
		return "null"
	elseif tv ~= "table" then
		return tv
	end
	if depth >= 4 then
		return "{…}"
	end
	local arr, n = isArray(v)
	if arr then
		if n == 0 then
			return "[]"
		end
		return "[" .. shape(v[1], depth + 1) .. "]"
	end
	local keys = {}
	for k in v do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	-- kamus dinamis (kunci = userId / id aset / nama) → ringkas
	local numericKeys = 0
	for _, k in keys do
		if string.match(k, "^%d+$") then
			numericKeys += 1
		end
	end
	if #keys > 16 or (numericKeys > 0 and numericKeys == #keys) then
		local sample = v[keys[1]]
		if sample == nil then
			sample = v[tonumber(keys[1])]
		end
		local kind = if numericKeys == #keys then "<angka>" else "<teks>"
		return "{" .. kind .. ": " .. shape(sample, depth + 1) .. "}"
	end
	local parts = {}
	for _, k in keys do
		local child = v[k]
		if child == nil then
			child = v[tonumber(k)]
		end
		table.insert(parts, k .. ": " .. shape(child, depth + 1))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function pattern(id: string): string
	return (string.gsub(id, "%d+", "<n>"))
end

-- ---------- standard data stores ----------
local function listDataStores(u: string): ({ any }?, string?)
	local out = {}
	local token: string? = nil
	repeat
		local q: { [string]: string } = { maxPageSize = "100", showDeleted = "true" }
		if token then
			q.pageToken = token
		end
		local status, body = get("/cloud/v2/universes/" .. u .. "/data-stores", q)
		if status ~= 200 then
			return nil, errText(status, body)
		end
		for _, ds in body.dataStores or {} do
			table.insert(out, ds)
		end
		token = body.nextPageToken
		if token == "" then
			token = nil
		end
	until token == nil
	return out, nil
end

local function listEntries(u: string, ds: string): ({ { id: string, scope: string } }?, string?)
	local out = {}
	local token: string? = nil
	repeat
		local q: { [string]: string } = { maxPageSize = "256" }
		if token then
			q.pageToken = token
		end
		local status, body = get("/cloud/v2/universes/" .. u .. "/data-stores/" .. enc(ds) .. "/scopes/-/entries", q)
		if status ~= 200 then
			return nil, errText(status, body)
		end
		for _, e in body.dataStoreEntries or {} do
			-- patch: wildcard-id-split
			-- dengan scope "-", id berbentuk "<scope>/<key>"
			local rawId = e.id or ""
			local scope, key = string.match(rawId, "^([^/]+)/(.+)$")
			if not scope then
				scope = string.match(e.path or "", "/scopes/([^/]+)/entries/") or "global"
				key = rawId
			end
			table.insert(out, { id = key :: string, scope = scope :: string })
		end
		token = body.nextPageToken
		if token == "" then
			token = nil
		end
	until token == nil
	return out, nil
end

local function getEntry(u: string, ds: string, scope: string, id: string): (any?, string?)
	local status, body = get(
		"/cloud/v2/universes/" .. u .. "/data-stores/" .. enc(ds) .. "/scopes/" .. enc(scope) .. "/entries/" .. enc(id)
			-- kunci berisi "@" dianggap revisi kecuali diakhiri @latest
			.. (if string.find(id, "@", 1, true) then "@latest" else "")
	)
	if status ~= 200 then
		return nil, errText(status, body)
	end
	return body, nil
end

-- ---------- ordered data stores ----------
local function scanOrdered(u: string, name: string): { [string]: any }
	local count, minV, maxV = 0, math.huge, -math.huge
	local samples = {}
	local token: string? = nil
	repeat
		local q: { [string]: string } = { maxPageSize = "100" }
		if token then
			q.pageToken = token
		end
		local status, body = get("/cloud/v2/universes/" .. u .. "/ordered-data-stores/" .. enc(name) .. "/scopes/global/entries", q)
		if status ~= 200 then
			return { name = name, error = errText(status, body) }
		end
		for _, e in body.orderedDataStoreEntries or {} do
			count += 1
			local v = tonumber(e.value) or 0
			minV, maxV = math.min(minV, v), math.max(maxV, v)
			if #samples < 5 then
				table.insert(samples, e.id)
			end
		end
		token = body.nextPageToken
		if token == "" then
			token = nil
		end
	until token == nil
	return {
		name = name,
		count = count,
		min = if count > 0 then minV else nil,
		max = if count > 0 then maxV else nil,
		keyPatterns = (function()
			local p = {}
			for _, id in samples do
				p[pattern(id)] = true
			end
			local l = {}
			for k in p do
				table.insert(l, k)
			end
			table.sort(l)
			return l
		end)(),
	}
end

-- ---------- main ----------
local universes: { string } = {}
local ordered = DEFAULT_ORDERED
local only: { [string]: boolean }? = nil
for _, a in process.args do
	local o = string.match(a, "^%-%-ordered=(.*)$")
	local onlyArg = string.match(a, "^%-%-only=(.*)$")
	if onlyArg then
		local set: { [string]: boolean } = {}
		for n in string.gmatch(onlyArg, "[^,]+") do
			set[n] = true
		end
		only = set
	elseif o then
		ordered = {}
		for n in string.gmatch(o, "[^,]+") do
			table.insert(ordered, n)
		end
	elseif string.match(a, "^%d+$") then
		table.insert(universes, a)
	else
		print("Argumen tidak dikenal: " .. a)
		process.exit(1)
	end
end
if #universes == 0 then
	print("Pemakaian: lune run tools/migrate/inventory <universeId> [universeId ...] [--ordered=A,B]")
	process.exit(1)
end

if not fs.isDir(OUT_DIR) then
	fs.writeDir(OUT_DIR)
end

local exitCode = 0
for _, u in universes do
	print(string.format("\n=== Universe %s ===", u))
	local report: { [string]: any } = { universe = u, generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"), dataStores = {}, ordered = {} }
	local stores, err = listDataStores(u)
	if not stores then
		print("  GAGAL list data stores: " .. tostring(err))
		report.error = err
		exitCode = 1
	else
		table.sort(stores, function(a, b)
			return a.id < b.id
		end)
		print(string.format("  %d data store (standard)", #stores))
		for _, ds in stores do
			if only and not only[ds.id] then
				continue
			end
			local info: { [string]: any } = { id = ds.id, state = ds.state, createTime = ds.createTime }
			if ds.state == "DELETED" then
				print(string.format("  - %-28s DELETED (expire %s) → dilewati", ds.id, tostring(ds.expireTime)))
			else
				local entries, e2 = listEntries(u, ds.id)
				if not entries then
					info.error = e2
					print(string.format("  - %-28s GAGAL list entries: %s", ds.id, tostring(e2)))
					exitCode = 1
				else
					local scopes, pats, order = {}, {}, {}
					for _, en in entries do
						scopes[en.scope] = (scopes[en.scope] or 0) + 1
						local p = pattern(en.id)
						if not pats[p] then
							pats[p] = { count = 0, samples = {} }
							table.insert(order, p)
						end
						pats[p].count += 1
						if #pats[p].samples < SAMPLES_PER_PATTERN then
							table.insert(pats[p].samples, en)
						end
					end
					table.sort(order, function(a, b)
						return pats[a].count > pats[b].count
					end)
					info.count = #entries
					info.scopes = scopes
					info.patterns = {}
					local scopeList = {}
					for s, n in scopes do
						table.insert(scopeList, s .. "=" .. n)
					end
					table.sort(scopeList)
					print(string.format("  - %-28s %6d entri  scope[%s]", ds.id, #entries, table.concat(scopeList, ",")))
					for i, p in order do
						if i > 8 then
							print(string.format("      … %d pola lain", #order - 8))
							break
						end
						local shapes, withUsers, attrKeys, maxBytes = {}, 0, {}, 0
						for _, s in pats[p].samples do
							local entry, e3 = getEntry(u, ds.id, s.scope, s.id)
							if entry then
								local sh = shape(entry.value, 0)
								shapes[sh] = (shapes[sh] or 0) + 1
								if entry.users and #entry.users > 0 then
									withUsers += 1
								end
								if type(entry.attributes) == "table" then
									for k in entry.attributes do
										attrKeys[k] = true
									end
								end
								maxBytes = math.max(maxBytes, #serde.encode("json", entry.value))
							else
								shapes["(GAGAL " .. tostring(e3) .. ")"] = (shapes["(GAGAL " .. tostring(e3) .. ")"] or 0) + 1
							end
						end
						local shapeList, attrList = {}, {}
						for sh in shapes do
							table.insert(shapeList, sh)
						end
						for k in attrKeys do
							table.insert(attrList, k)
						end
						table.sort(shapeList)
						table.sort(attrList)
						table.insert(info.patterns, {
							pattern = p,
							count = pats[p].count,
							shapes = shapeList,
							sampledWithUsers = withUsers,
							sampled = #pats[p].samples,
							attributeKeys = attrList,
							maxSampleBytes = maxBytes,
						})
						print(string.format("      %-22s %6d  users:%d/%d  %s", p, pats[p].count, withUsers, #pats[p].samples, table.concat(shapeList, " | ")))
					end
				end
			end
			table.insert(report.dataStores, info)
		end
	end
	print("  Ordered data store (nama harus diketahui; tidak ada API list):")
	for _, name in ordered do
		if only and not only[name] then
			continue
		end
		local r = scanOrdered(u, name)
		table.insert(report.ordered, r)
		if r.error then
			print(string.format("  - %-28s %s", name, r.error))
		else
			print(string.format("  - %-28s %6d entri  min=%s max=%s  pola[%s]", name, r.count, tostring(r.min), tostring(r.max), table.concat(r.keyPatterns, ",")))
		end
	end
	local path = OUT_DIR .. "/inventory_" .. u .. (if only then "_only" else "") .. ".json"
	fs.writeFile(path, serde.encode("json", report, true))
	print("  → " .. path)
end
print(string.format("\nSelesai. %d request. Tidak ada yang ditulis ke Roblox.", requestCount))
process.exit(exitCode)
