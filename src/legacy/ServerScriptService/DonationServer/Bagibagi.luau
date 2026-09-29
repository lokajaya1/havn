-- DonationServer.Bagibagi — donasi luar dari bagibagi.co lewat jembatan Google Apps Script
-- (tools/bagibagi-bridge/Code.gs; GET ?key=<Secret>&after=<baris> → { ok, next, items }).
-- Hanya SATU server yang menarik (pemimpin = kunci MemoryStore berumur `lease` detik), lalu donasi
-- diumumkan di server itu dan disiarkan ke server lain lewat Global (v3, tanpa nominal).
-- Anti dobel: `cursor` (baris terakhir) + `ids` (ID donasi terakhir) di DataStore diperbarui dalam SATU
-- UpdateAsync sebelum pengumuman → webhook yang terkirim dua kali / pemimpin berganti tidak mengulang.
-- Tarikan pertama tanpa cursor hanya mencatat titik mulai (riwayat lama tidak diumumkan).
-- Nama & pesan bebas dari donatur difilter (PublicChat, broadcast) atas nama pemain di server ini;
-- tanpa pemain / filter gagal → "Seseorang" & tanpa pesan (fail-closed). Nominal Rupiah tidak ditampilkan.
local Bagibagi = {}
Bagibagi.__index = Bagibagi

local MAX_ITEMS = 50
local NAME_CHARS = 50
local FALLBACK_NAME = "Seseorang"

local function trim(s)
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function cutChars(s, n)
	local len = utf8.len(s)
	if not len then
		return nil
	end
	if len <= n then
		return s
	end
	return string.sub(s, 1, utf8.offset(s, n + 1) - 1)
end

local function isInt(v, min, max)
	return type(v) == "number" and v == v and v % 1 == 0 and v >= min and v <= max
end

-- Murni: nominal Rupiah → t (harga tier Robux yang efeknya dipakai) atau nil (notifikasi saja).
function Bagibagi.tierFor(rp, list)
	local best
	for _, entry in list do
		if rp >= entry.rp and (not best or entry.rp > best.rp) then
			best = entry
		end
	end
	return best and best.t
end

-- Murni: jawaban jembatan (sudah JSONDecode) → { next, items } tervalidasi & urut baris, atau nil.
function Bagibagi.parse(data)
	if type(data) ~= "table" or data.ok ~= true or not isInt(data.next, 0, 1e9) then
		return nil
	end
	local items = {}
	if type(data.items) == "table" then
		for i, it in data.items do
			if i > MAX_ITEMS then
				break
			end
			if
				type(it) == "table"
				and isInt(it.row, 1, 1e9)
				and type(it.id) == "string"
				and #it.id > 0
				and #it.id <= 100
				and type(it.name) == "string"
				and #it.name <= 400
				and isInt(it.amount, 0, 1e12)
				and type(it.message) == "string"
				and #it.message <= 2000
			then
				table.insert(items, {
					row = it.row,
					id = it.id,
					name = it.name,
					amount = it.amount,
					message = it.message,
					test = it.test == true,
				})
			end
		end
	end
	table.sort(items, function(a, b)
		return a.row < b.row
	end)
	return { next = data.next, items = items }
end

-- deps: { cfg (DonationConfig), http (HttpService), store (DataStore), memory (MemoryStore SortedMap),
--         jobId, players (Players), filter(text, fromUserId) → string?, enqueue(item), publish(item),
--         task, warn, print }
function Bagibagi.new(deps)
	local self = setmetatable({}, Bagibagi)
	self.deps = deps
	self.cfg = deps.cfg.bagibagi
	self.warned = {} -- [jenis] = true (warn sekali sampai pulih)
	self.uidCache = {} -- [nama] = userId | false
	self.leader = false
	return self
end

function Bagibagi:warnOnce(kind, text)
	if not self.warned[kind] then
		self.warned[kind] = true
		self.deps.warn("[Donation] bagibagi: " .. text)
	end
end

function Bagibagi:isLeader()
	local d, jobId = self.deps, self.deps.jobId
	local ok, v = pcall(function()
		return d.memory:UpdateAsync("leader", function(old)
			if old == nil or (type(old) == "table" and old.job == jobId) then
				return { job = jobId }
			end
			return nil
		end, self.cfg.lease)
	end)
	local now = ok and type(v) == "table" and v.job == jobId
	if now and not self.leader then
		d.print("[Donation] bagibagi: server ini menarik donasi")
	end
	self.leader = now
	return now
end

-- GET ke jembatan; after = nil → titik mulai. → { next, items } atau nil.
function Bagibagi:request(after)
	local d, cfg = self.deps, self.cfg
	local ok, res = pcall(function()
		local url = d.http:GetSecret(cfg.secret):AddPrefix(cfg.url .. "?key=")
		if after then
			url = url:AddSuffix("&after=" .. after)
		end
		return d.http:RequestAsync({ Url = url, Method = "GET" })
	end)
	if not ok then
		self:warnOnce("request", "permintaan gagal (" .. tostring(res) .. ") — cek Secret '" .. cfg.secret .. "'")
		return nil
	end
	if not res.Success then
		self:warnOnce("http", "HTTP " .. tostring(res.StatusCode))
		return nil
	end
	local okJ, data = pcall(d.http.JSONDecode, d.http, res.Body)
	local parsed = okJ and Bagibagi.parse(data)
	if not parsed then
		self:warnOnce("reply", "jawaban jembatan tidak sah (" .. string.sub(tostring(res.Body), 1, 80) .. ")")
		return nil
	end
	self.warned.request, self.warned.http, self.warned.reply = nil, nil, nil
	return parsed
end

function Bagibagi:userIdFor(name)
	if self.uidCache[name] ~= nil then
		return self.uidCache[name] or 0
	end
	local uid = false
	if #name >= 3 and #name <= 20 and string.match(name, "^[%w_]+$") then
		local ok, id = pcall(self.deps.players.GetUserIdFromNameAsync, self.deps.players, name)
		if ok and type(id) == "number" and id > 0 then
			uid = id
		end
	end
	self.uidCache[name] = uid
	return uid or 0
end

function Bagibagi:announce(it)
	local d, cfg = self.deps, self.deps.cfg
	local from = d.players:GetPlayers()[1]
	local rawName = cutChars(trim(it.name), NAME_CHARS) or ""
	local name = (from and rawName ~= "" and d.filter(rawName, from.UserId)) or FALLBACK_NAME
	local message = ""
	local rawMsg = cutChars(trim(it.message), cfg.message.maxChars) or ""
	if from and rawMsg ~= "" then
		message = d.filter(rawMsg, from.UserId) or ""
	end
	local t = Bagibagi.tierFor(it.amount, self.cfg.tiers)
	local tier
	for _, candidate in cfg.tiers do
		if candidate.robux == t then
			tier = candidate
		end
	end
	local item = {
		displayName = name,
		name = name,
		userId = rawName ~= "" and self:userIdFor(rawName) or 0,
		robux = 0, -- nominal tidak ditampilkan
		message = message,
		gap = tier and tier.gap or self.cfg.gap,
		big = tier and tier.big,
		tier = tier and tier.robux,
		fxRobux = tier and tier.robux,
		purchaseId = "bb-" .. it.id .. (it.test and ("-" .. it.row) or ""),
		external = true,
		test = it.test or nil,
	}
	d.print(("[Donation] bagibagi%s: %s%s"):format(it.test and " (tes)" or "", name, tier and (" | efek " .. tier.robux) or ""))
	d.enqueue(item)
	d.publish(item)
end

function Bagibagi:pollOnce()
	local d = self.deps
	local okS, state = pcall(d.store.GetAsync, d.store, "state")
	if not okS then
		self:warnOnce("store", "DataStore gagal dibaca (" .. tostring(state) .. ")")
		return
	end
	if type(state) ~= "table" or not isInt(state.cursor, 0, 1e9) then
		local first = self:request(nil)
		if first then
			pcall(d.store.UpdateAsync, d.store, "state", function(old)
				if type(old) == "table" and isInt(old.cursor, 0, 1e9) then
					return nil
				end
				return { cursor = first.next, ids = {} }
			end)
			d.print("[Donation] bagibagi: mulai dari baris " .. first.next .. " (riwayat lama tidak diumumkan)")
		end
		return
	end
	local res = self:request(state.cursor)
	if not res then
		return
	end
	for _, it in res.items do
		local fresh = false
		local okU, err = pcall(d.store.UpdateAsync, d.store, "state", function(old)
			old = type(old) == "table" and old or {}
			if it.row <= (tonumber(old.cursor) or 0) then
				fresh = false
				return nil
			end
			local ids = type(old.ids) == "table" and old.ids or {}
			local dup = false
			if not it.test then
				for _, x in ids do
					if x == it.id then
						dup = true
					end
				end
				if not dup then
					table.insert(ids, it.id)
					while #ids > self.cfg.keepIds do
						table.remove(ids, 1)
					end
				end
			end
			fresh = not dup
			return { cursor = it.row, ids = ids }
		end)
		if not okU then
			self:warnOnce("store", "DataStore gagal ditulis (" .. tostring(err) .. "), dicoba lagi")
			return
		end
		self.warned.store = nil
		if fresh then
			self:announce(it)
		end
	end
end

function Bagibagi:start()
	if not self.cfg.enabled then
		return
	end
	local d = self.deps
	d.task.spawn(function()
		while true do
			if self:isLeader() then
				local ok, err = pcall(self.pollOnce, self)
				if not ok then
					self:warnOnce("poll", "gagal (" .. tostring(err) .. ")")
				end
			end
			d.task.wait(self.cfg.poll)
		end
	end)
end

return Bagibagi
