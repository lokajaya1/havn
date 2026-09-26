--!strict
-- Salin + gabung DataStore dari universe lama ke universe baru sesuai rules.luau.
-- Hanya MEMBACA universe sumber. Tanpa opts.apply = uji kering (tidak ada tulis sama sekali).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Http = require("./http")
local Merge = require("./merge")

export type Options = {
	http: Http.Http,
	rules: any,
	source: string,
	target: string,
	apply: boolean,
	only: { [string]: boolean }?,
	limit: number?,
	outDir: string,
	stamp: string,
	log: (string) -> (),
}

type Counter = {
	source: number,
	skippedStudio: number,
	skippedEmpty: number,
	create: number,
	update: number,
	same: number,
	keptDiff: number,
	failed: number,
	notes: { string },
}

local enc = Http.enc

local function newCounter(): Counter
	return {
		source = 0,
		skippedStudio = 0,
		skippedEmpty = 0,
		create = 0,
		update = 0,
		same = 0,
		keptDiff = 0,
		failed = 0,
		notes = {},
	}
end

local function note(c: Counter, s: string)
	if #c.notes < 25 then
		table.insert(c.notes, s)
	end
end

local function stdBase(u: string, ds: string, scope: string): string
	return "/cloud/v2/universes/" .. u .. "/data-stores/" .. enc(ds) .. "/scopes/" .. enc(scope) .. "/entries"
end

local function entryPath(u: string, ds: string, scope: string, key: string): string
	local suffix = if string.find(key, "@", 1, true) then "@latest" else ""
	return stdBase(u, ds, scope) .. "/" .. enc(key) .. suffix
end

local function orderedBase(u: string, name: string): string
	return "/cloud/v2/universes/" .. u .. "/ordered-data-stores/" .. enc(name) .. "/scopes/global/entries"
end

-- Semua kunci (scope, key) di satu store. 404 = store belum ada = kosong.
local function listKeys(http: Http.Http, u: string, ds: string): ({ { scope: string, key: string } }?, string?)
	local out = {}
	local token: string? = nil
	repeat
		local q: { [string]: string } = { maxPageSize = "256" }
		if token then
			q.pageToken = token
		end
		local status, body = http:request("GET", stdBase(u, ds, "-"), q)
		if status == 404 then
			return out, nil
		elseif status ~= 200 then
			return nil, Http.errText(status, body)
		end
		for _, e in body.dataStoreEntries or {} do
			local rawId = e.id or ""
			local scope, key = string.match(rawId, "^([^/]+)/(.+)$")
			if not scope then
				scope = string.match(e.path or "", "/scopes/([^/]+)/entries/") or "global"
				key = rawId
			end
			table.insert(out, { scope = scope :: string, key = key :: string })
		end
		token = body.nextPageToken
		if token == "" then
			token = nil
		end
	until token == nil
	return out, nil
end

local function listOrdered(http: Http.Http, u: string, name: string): ({ [string]: number }?, { string }?, string?)
	local values: { [string]: number } = {}
	local order: { string } = {}
	local token: string? = nil
	repeat
		local q: { [string]: string } = { maxPageSize = "100" }
		if token then
			q.pageToken = token
		end
		local status, body = http:request("GET", orderedBase(u, name), q)
		if status == 404 then
			return values, order, nil
		elseif status ~= 200 then
			return nil, nil, Http.errText(status, body)
		end
		for _, e in body.orderedDataStoreEntries or {} do
			values[e.id] = tonumber(e.value) or 0
			table.insert(order, e.id)
		end
		token = body.nextPageToken
		if token == "" then
			token = nil
		end
	until token == nil
	return values, order, nil
end

local function nonEmpty(t: any): any
	if type(t) == "table" and next(t) ~= nil then
		return t
	end
	return nil
end

local function readJson(path: string): any
	if fs.isFile(path) then
		local ok, v = pcall(serde.decode, "json" :: any, fs.readFile(path))
		if ok then
			return v
		end
	end
	return nil
end

local Copy = {}

function Copy.run(opts: Options): { [string]: any }
	assert(opts.source ~= opts.target, "sumber dan target tidak boleh sama")
	local http, S, T, log = opts.http, opts.source, opts.target, opts.log
	local report: { [string]: any } = {
		mode = if opts.apply then "APPLY" else "UJI-KERING",
		source = S,
		target = T,
		stamp = opts.stamp,
		rules = {},
	}
	local backupPath = opts.outDir .. "/backup_" .. T .. "_" .. opts.stamp .. ".json"
	local backups = {}
	local ledgerPath = opts.outDir .. "/ledger_" .. T .. ".json"
	local ledger = readJson(ledgerPath) or {}

	local function backup(entry: { [string]: any })
		table.insert(backups, entry)
		fs.writeFile(backupPath, serde.encode("json", backups, true))
	end

	-- ---------- standard ----------
	for _, rule in opts.rules.standard do
		if opts.only and not opts.only[rule.name] then
			continue
		end
		local c = newCounter()
		report.rules[rule.name] = c
		local scope = rule.scope or "global"
		local strategy = Merge.strategies[rule.merge]
		assert(strategy, "strategi tidak dikenal: " .. rule.merge)
		log(string.format("\n[%s] %s → %s (%s)", rule.name, rule.from, rule.to, rule.merge))

		local srcKeys, e1 = listKeys(http, S, rule.from)
		local dstKeys, e2 = listKeys(http, T, rule.to)
		if not srcKeys or not dstKeys then
			c.failed += 1
			note(c, "list gagal: " .. tostring(e1 or e2))
			log("  GAGAL list: " .. tostring(e1 or e2))
			continue
		end
		local existing: { [string]: boolean } = {}
		for _, k in dstKeys do
			if k.scope == scope then
				existing[k.key] = true
			end
		end

		local processed = 0
		for _, k in srcKeys do
			if k.scope ~= scope then
				continue
			end
			if rule.key and k.key ~= rule.key then
				continue
			end
			if rule.prefix and string.sub(k.key, 1, #rule.prefix) ~= rule.prefix then
				continue
			end
			if opts.limit and processed >= opts.limit then
				break
			end
			processed += 1
			c.source += 1
			if processed % 250 == 0 then
				log(string.format("  … %d kunci", processed))
			end
			if Merge.isStudioKey(k.key) then
				c.skippedStudio += 1
				continue
			end

			local st, src = http:request("GET", entryPath(S, rule.from, scope, k.key))
			if st ~= 200 then
				c.failed += 1
				note(c, k.key .. ": baca sumber " .. Http.errText(st, src))
				continue
			end
			local oldValue = src.value

			if not existing[k.key] then
				if rule.skipEmpty and Merge.isEmpty(oldValue) then
					c.skippedEmpty += 1
					continue
				end
				if opts.apply then
					local body = { value = oldValue, users = nonEmpty(src.users), attributes = nonEmpty(src.attributes) }
					local cs, cb = http:request("POST", stdBase(T, rule.to, scope), { id = k.key }, body)
					if cs == 200 or cs == 201 then
						c.create += 1
					else
						c.failed += 1
						note(c, k.key .. ": buat " .. Http.errText(cs, cb))
					end
				else
					c.create += 1
				end
				continue
			end

			local ts, dst = http:request("GET", entryPath(T, rule.to, scope, k.key))
			if ts ~= 200 then
				c.failed += 1
				note(c, k.key .. ": baca target " .. Http.errText(ts, dst))
				continue
			end
			local merged = strategy(oldValue, dst.value)
			if Merge.equal(merged, dst.value) then
				-- "tetap" = nilai lama dibuang karena game baru punya nilai lain (perlu dilihat manusia)
				local lossy = rule.merge == "keepTarget"
					or (rule.merge == "adonis" and not (Merge.isArray(oldValue) and Merge.isArray(dst.value)))
				if lossy and not Merge.equal(oldValue, dst.value) then
					c.keptDiff += 1
					note(c, k.key .. ": nilai game baru dipertahankan")
				else
					c.same += 1
				end
				continue
			end
			if string.find(k.key, "@", 1, true) then
				c.failed += 1
				note(c, k.key .. ": kunci ber-@ tidak bisa di-update lewat API")
				continue
			end
			if opts.apply then
				backup({
					rule = rule.name,
					store = rule.to,
					scope = scope,
					key = k.key,
					value = dst.value,
					users = dst.users,
					attributes = dst.attributes,
				})
				local body = {
					value = merged,
					etag = dst.etag,
					users = nonEmpty(dst.users),
					attributes = nonEmpty(dst.attributes),
				}
				local us, ub = http:request("PATCH", entryPath(T, rule.to, scope, k.key), nil, body)
				if us == 200 then
					c.update += 1
				else
					c.failed += 1
					note(c, k.key .. ": update " .. Http.errText(us, ub))
				end
			else
				c.update += 1
			end
		end
	end

	-- ---------- ordered ----------
	for _, rule in opts.rules.ordered do
		if opts.only and not opts.only[rule.name] then
			continue
		end
		local c = newCounter()
		report.rules[rule.name] = c
		log(string.format("\n[%s] ordered %s → %s (%s)", rule.name, rule.from, rule.to, rule.merge))
		local srcValues, srcOrder, e1 = listOrdered(http, S, rule.from)
		local dstValues, _, e2 = listOrdered(http, T, rule.to)
		if not srcValues or not srcOrder or not dstValues then
			c.failed += 1
			note(c, "list gagal: " .. tostring(e1 or e2))
			log("  GAGAL list: " .. tostring(e1 or e2))
			continue
		end
		local applied = ledger[rule.name] or {}
		ledger[rule.name] = applied
		local processed = 0
		for _, key in srcOrder do
			if opts.limit and processed >= opts.limit then
				break
			end
			processed += 1
			c.source += 1
			if Merge.isStudioKey(key) then
				c.skippedStudio += 1
				continue
			end
			local oldValue = srcValues[key]
			local current = dstValues[key]
			local newValue: number?, newLedger: number? = nil, nil
			if rule.merge == "sumLedger" then
				newValue, newLedger = Merge.sumLedger(oldValue, current, applied[key])
			elseif current == nil then
				newValue = oldValue
			end
			if newValue == nil then
				if current ~= nil and current ~= oldValue and rule.merge ~= "sumLedger" then
					c.keptDiff += 1
				else
					c.same += 1
				end
				continue
			end
			local isCreate = current == nil
			if opts.apply then
				local st, body
				if isCreate then
					st, body = http:request("POST", orderedBase(T, rule.to), { id = key }, { value = newValue })
					if st == 400 then
						-- sudah dibuat server game di antara list dan tulis: pakai PATCH absolut
						st, body = http:request(
							"PATCH",
							orderedBase(T, rule.to) .. "/" .. enc(key),
							{ allowMissing = "true" },
							{ value = newValue }
						)
					end
				else
					backup({ rule = rule.name, store = rule.to, ordered = true, key = key, value = current })
					st, body = http:request(
						"PATCH",
						orderedBase(T, rule.to) .. "/" .. enc(key),
						{ allowMissing = "true" },
						{ value = newValue }
					)
				end
				if st == 200 or st == 201 then
					if isCreate then
						c.create += 1
					else
						c.update += 1
					end
					if newLedger then
						applied[key] = newLedger
						fs.writeFile(ledgerPath, serde.encode("json", ledger, true))
					end
				else
					c.failed += 1
					note(c, key .. ": tulis " .. Http.errText(st, body))
				end
			elseif isCreate then
				c.create += 1
			else
				c.update += 1
			end
		end
	end

	report.requests = http.count
	report.writes = http.writes
	if #backups > 0 then
		report.backupFile = backupPath
	end
	return report
end

function Copy.summary(report: { [string]: any }): string
	local lines = {
		string.format("\n=== %s  %s → %s ===", report.mode, report.source, report.target),
		string.format(
			"%-16s %7s %7s %7s %7s %7s %7s %7s %7s",
			"aturan",
			"sumber",
			"studio",
			"kosong",
			"buat",
			"gabung",
			"sama",
			"tetap",
			"GAGAL"
		),
	}
	local names = {}
	for name in report.rules do
		table.insert(names, name)
	end
	table.sort(names)
	local failed = 0
	for _, name in names do
		local c = report.rules[name]
		failed += c.failed
		table.insert(
			lines,
			string.format(
				"%-16s %7d %7d %7d %7d %7d %7d %7d %7d",
				name,
				c.source,
				c.skippedStudio,
				c.skippedEmpty,
				c.create,
				c.update,
				c.same,
				c.keptDiff,
				c.failed
			)
		)
		for _, n in c.notes do
			table.insert(lines, "    · " .. n)
		end
	end
	table.insert(
		lines,
		string.format("Request: %d (tulis: %d). Total GAGAL: %d", report.requests, report.writes, failed)
	)
	return table.concat(lines, "\n")
end

return Copy
