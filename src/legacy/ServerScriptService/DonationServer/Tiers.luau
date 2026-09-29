-- ServerScriptService.DonationServer.Tiers — setelan Developer Product donasi yang diubah admin (Admin panel → Produk):
-- nama, partikel, kamera sinematik, efek besar, tampil/sembunyi, tambah/hapus produk baru.
-- Tanpa GetService: semua API Roblox lewat deps (lihat Tiers.new). Diuji Lune (dn16_test).
-- Rekaman store: { v = 1, rev, list = { { id, robux?, label?, fx?, cam?, big?, hidden?, custom? } }, retired = { id } }
--   fx/cam/big = false → OFF (beda dengan tidak ada = ikut bawaan). robux hanya disimpan untuk produk tambahan
--   (cadangan kalau harga Roblox gagal dibaca). retired = produk tambahan yang dihapus: strukNYA tetap diterima.
local Tiers = {}
Tiers.__index = Tiers

local FIELDS = { label = true, fx = true, cam = true, big = true, hidden = true }

local function isInt(v, lo, hi)
	return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

local function validField(field, value, cfg)
	if field == "label" then
		local len = type(value) == "string" and utf8.len(value)
		return len ~= nil and len ~= false and len >= 1 and len <= cfg.tierEdit.labelChars
	elseif field == "hidden" then
		return type(value) == "boolean"
	elseif value == false then
		return field == "fx" or field == "cam" or field == "big"
	elseif field == "fx" then
		return type(value) == "string" and cfg.effects[value] ~= nil
	elseif field == "cam" then
		return cfg.isCamMode(value)
	elseif field == "big" then
		return type(value) == "string" and cfg.isBig(value)
	end
	return false
end

-- Murni: kiriman tombol SIMPAN = { field = nilai } (1–5 field sah) → true/false.
function Tiers.validSave(value, cfg)
	if type(value) ~= "table" then
		return false
	end
	local n = 0
	for k, v in value do
		n += 1
		if n > 5 or not FIELDS[k] or not validField(k, v, cfg) then
			return false
		end
	end
	return n > 0
end

-- Murni: tier baru untuk produk tambahan — jeda/notif/partikel dari tier bawaan termahal yang harganya <= robux.
function Tiers.newTier(id, robux, defaults)
	local base = defaults[1]
	for _, d in defaults do
		if robux >= d.robux then
			base = d
		end
	end
	return {
		robux = robux,
		label = "Donate",
		productId = id,
		gap = base and base.gap or 3,
		notif = base and base.notif or 6,
		fx = base and base.fx,
		custom = true,
	}
end

-- Murni: tier bawaan + rekaman tersimpan (+ harga Roblox terbaru) → daftar tier baru & id pensiun.
function Tiers.merge(defaults, rec, cfg, prices)
	local out, byId = {}, {}
	for _, d in defaults do
		local t = table.clone(d)
		table.insert(out, t)
		byId[t.productId] = t
	end
	local retired = {}
	rec = type(rec) == "table" and rec or {}
	for _, e in type(rec.list) == "table" and rec.list or {} do
		if type(e) == "table" and isInt(e.id, 1, 1e15) then
			local t = byId[e.id]
			if not t and e.custom == true and isInt(e.robux, 1, 1e7) and #out < cfg.tierEdit.maxTiers then
				t = Tiers.newTier(e.id, e.robux, defaults)
				table.insert(out, t)
				byId[e.id] = t
			end
			if t then
				for field in FIELDS do
					local v = e[field]
					if v ~= nil and validField(field, v, cfg) then
						t[field] = v ~= false and v or nil
					end
				end
			end
		end
	end
	for _, id in type(rec.retired) == "table" and rec.retired or {} do
		if isInt(id, 1, 1e15) and not byId[id] then
			table.insert(retired, id)
		end
	end
	for _, t in out do
		local price = prices and prices[t.productId]
		if isInt(price, 1, 1e7) then
			t.robux = price
		end
	end
	return out, retired
end

-- deps: { cfg (DonationConfig), store (DataStore), messaging, jobId, suffix, products() → { [id] = { price, name } },
--   isForeign(id), register(id), publish(tiers), filter(text, userId), isEditor(player), clock(), task, warn, print }
function Tiers.new(deps)
	local self = setmetatable({}, Tiers)
	self.deps = deps
	self.cfg = deps.cfg
	self.rec = { v = 1, rev = 0, list = {}, retired = {} }
	self.prices = {}
	self.ready = false
	self.registered = {}
	self.last = {} -- [Player] = clock
	return self
end

function Tiers:apply()
	local tiers, retired = Tiers.merge(self.cfg.defaultTiers, self.rec, self.cfg, self.prices)
	self.cfg.applyTiers(tiers)
	for _, t in tiers do
		self:registerOnce(t.productId)
	end
	for _, id in retired do
		self:registerOnce(id)
	end
	self.deps.publish(self.cfg.tiers)
end

function Tiers:registerOnce(id)
	if not self.registered[id] then
		self.registered[id] = true
		self.deps.register(id)
	end
end

-- Baca rekaman (coba 3×). Gagal → tetap tier bawaan & perubahan ditolak (tidak menimpa rekaman yang tidak terbaca).
function Tiers:load()
	local d, E = self.deps, self.cfg.tierEdit
	for attempt = 1, 3 do
		local ok, rec = pcall(d.store.GetAsync, d.store, E.key)
		if ok then
			if type(rec) == "table" then
				rec.list = type(rec.list) == "table" and rec.list or {}
				rec.retired = type(rec.retired) == "table" and rec.retired or {}
				rec.rev = isInt(rec.rev, 0, 1e12) and rec.rev or 0
				self.rec = rec
			end
			self.ready = true
			self:apply()
			return true
		end
		d.warn(("[Donation] setelan produk gagal dibaca (%d/3): %s"):format(attempt, tostring(rec)))
		if attempt < 3 then
			d.task.wait(5)
		end
	end
	self:apply()
	return false
end

-- Harga terbaru dari Roblox (Creator Hub). Hanya di memori; produk tambahan ikut disimpan di rekaman berikutnya.
function Tiers:refreshPrices()
	local ok, map = pcall(self.deps.products)
	if not ok or type(map) ~= "table" then
		self.deps.warn("[Donation] daftar Developer Product gagal dibaca: " .. tostring(map))
		return false
	end
	local found, total = 0, 0
	for _, t in self.cfg.defaultTiers do
		total += 1
		found += map[t.productId] and 1 or 0
	end
	self.prices = {}
	for id, info in map do
		self.prices[id] = info.price
	end
	for _, e in self.rec.list do
		if e.custom and map[e.id] and isInt(map[e.id].price, 1, 1e7) then
			e.robux = map[e.id].price
		end
	end
	self.deps.print(("[Donation] harga produk dibaca: %d/%d produk bawaan cocok"):format(found, total))
	self:apply()
	return true
end

local function entryFor(rec, id)
	for _, e in rec.list do
		if e.id == id then
			return e
		end
	end
	local e = { id = id }
	table.insert(rec.list, e)
	return e
end

-- Perubahan dari Admin panel. op: "save" (id, nil, { field = nilai }) = tombol SIMPAN | "set" (id, field, value) |
-- "add" (id) | "remove" (id) | "prices".
-- → true | false, alasan ("invalid" | "cooldown" | "rank" | "notready" | "notfound" | "foreign" | "exists" | "full" | "filter" | "api")
function Tiers:edit(player, op, id, field, value)
	local d, E = self.deps, self.cfg.tierEdit
	if type(op) ~= "string" or (op ~= "prices" and not isInt(id, 1, 1e15)) then
		return false, "invalid"
	end
	if op == "set" and not (FIELDS[field] and validField(field, value, self.cfg)) then
		return false, "invalid"
	end
	if op == "save" and not Tiers.validSave(value, self.cfg) then
		return false, "invalid"
	end
	local now = d.clock()
	if self.last[player] and now - self.last[player] < E.cooldown then
		return false, "cooldown"
	end
	self.last[player] = now
	if not d.isEditor(player) then
		return false, "rank"
	end
	if not self.ready then
		return false, "notready"
	end
	local known = self.cfg.tierForProduct(id)
	if op == "set" then
		if not known then
			return false, "notfound"
		end
		if field == "label" then
			value = d.filter(value, player.UserId)
			if not value then
				return false, "filter"
			end
		end
		entryFor(self.rec, id)[field] = value
	elseif op == "save" then
		if not known then
			return false, "notfound"
		end
		local changes = table.clone(value)
		if changes.label ~= nil then
			changes.label = d.filter(changes.label, player.UserId)
			if not changes.label then
				return false, "filter"
			end
		end
		local e = entryFor(self.rec, id)
		for k, v in changes do
			e[k] = v
		end
		field, value = "", ""
		for k, v in changes do
			value ..= ("%s=%s "):format(k, tostring(v))
		end
	elseif op == "add" then
		if known then
			return false, "exists"
		end
		if #self.cfg.tiers >= E.maxTiers then
			return false, "full"
		end
		if d.isForeign(id) then
			return false, "foreign"
		end
		local ok, map = pcall(d.products)
		if not ok or type(map) ~= "table" then
			return false, "api"
		end
		local info = map[id]
		if not info or not isInt(info.price, 1, 1e7) then
			return false, "notfound"
		end
		for id2, info2 in map do
			self.prices[id2] = info2.price
		end
		local name = string.sub(tostring(info.name or ""), 1, 60)
		local len = utf8.len(name)
		if len and len > E.labelChars then
			name = string.sub(name, 1, utf8.offset(name, E.labelChars + 1) - 1)
		end
		local label = (len and name ~= "" and d.filter(name, player.UserId)) or "Donate"
		for i, r in self.rec.retired do
			if r == id then
				table.remove(self.rec.retired, i)
				break
			end
		end
		local e = entryFor(self.rec, id)
		e.custom, e.robux, e.label = true, info.price, label
	elseif op == "remove" then
		if not (known and known.custom) then
			return false, known and "invalid" or "notfound"
		end
		for i, e in self.rec.list do
			if e.id == id then
				table.remove(self.rec.list, i)
				break
			end
		end
		table.insert(self.rec.retired, id)
	elseif op == "prices" then
		if self:refreshPrices() then
			return true
		end
		return false, "api"
	else
		return false, "invalid"
	end
	self:apply()
	self:saveSoon()
	d.print(("[Donation] setelan produk oleh %s: %s %s %s %s"):format(player.Name, op, tostring(id), tostring(field or ""),
		tostring(value == nil and "" or value)))
	return true
end

function Tiers:saveSoon()
	self.dirty = true
	if self.saving then
		return
	end
	self.saving = true
	self.deps.task.delay(self.cfg.tierEdit.saveDelay, function()
		self:save()
	end)
end

function Tiers:save()
	local d, E = self.deps, self.cfg.tierEdit
	self.dirty = false
	local ok, err = pcall(d.store.UpdateAsync, d.store, E.key, function(old)
		local rev = math.max(type(old) == "table" and tonumber(old.rev) or 0, self.rec.rev) + 1
		self.rec.rev = rev
		return self.rec
	end)
	self.saving = false
	if not ok then
		d.warn("[Donation] setelan produk gagal disimpan, dicoba lagi: " .. tostring(err))
		self:saveSoon()
		return false
	end
	if self.dirty then
		self:saveSoon() -- ada perubahan selama menyimpan
	end
	pcall(d.messaging.PublishAsync, d.messaging, E.topic .. d.suffix, { job = d.jobId, rev = self.rec.rev })
	return true
end

-- Server lain menyimpan → baca ulang (kecuali perubahan server ini sendiri belum tersimpan).
function Tiers:onRemote(data)
	local d, E = self.deps, self.cfg.tierEdit
	if type(data) ~= "table" or data.job == d.jobId or self.dirty or self.saving then
		return
	end
	local ok, rec = pcall(d.store.GetAsync, d.store, E.key)
	if ok and type(rec) == "table" and isInt(rec.rev, 0, 1e12) and rec.rev > self.rec.rev then
		rec.list = type(rec.list) == "table" and rec.list or {}
		rec.retired = type(rec.retired) == "table" and rec.retired or {}
		self.rec = rec
		self.ready = true
		self:apply()
	end
end

function Tiers:start()
	local d, E = self.deps, self.cfg.tierEdit
	pcall(d.messaging.SubscribeAsync, d.messaging, E.topic .. d.suffix, function(msg)
		self:onRemote(msg and msg.Data)
	end)
	self:load()
	self:refreshPrices()
end

return Tiers
