-- ServerScriptService.DonationServer.Feed — daftar donasi HARI INI (WIB) untuk papan LIVE DONATIONS, lintas server dan
-- tahan restart. MemoryStore SortedMap per tanggal & jenis: `<memory>_<robux|gold>_<YYYYMMDD>` (+ _studio di Studio),
-- kunci = purchaseId, sortKey = waktu donasi, hilang sendiri setelah `ttl`. Hanya server asal yang menulis (sekali per
-- donasi, tanpa donasi TES); semua server membaca saat menyala & tiap `boards.every` detik (menyusulkan yang terlewat).
-- Tampil seketika tetap lewat Global. Tanpa GetService: API lewat deps. Diuji Lune (dn13_test L).
local Feed = {}
Feed.__index = Feed

local KINDS = { robux = true, gold = true }

local function isInt(v, lo, hi)
	return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

-- Murni: item pengumuman → nilai yang disimpan (ringkas; pesan sudah difilter server asal).
function Feed.pack(item, ts)
	return {
		u = item.userId,
		n = item.name,
		d = item.displayName,
		a = item.external and (item.gold or 0) or item.robux,
		m = item.message or "",
		t = ts,
	}
end

-- Murni: nilai tersimpan → kartu papan { pid, userId, name, display, amount, message, ts } atau nil kalau rusak.
function Feed.unpack(pid, v, cfg)
	if type(pid) ~= "string" or type(v) ~= "table" then
		return nil
	end
	if not (isInt(v.u, 0, 1e15) and type(v.n) == "string" and type(v.d) == "string" and isInt(v.a, 0, 1e12)
		and type(v.m) == "string" and type(v.t) == "number") then
		return nil
	end
	if #v.n > 60 or #v.d > 60 or (utf8.len(v.m) or math.huge) > cfg.message.maxChars then
		return nil
	end
	return { pid = pid, userId = v.u, name = v.n, display = v.d, amount = v.a, message = v.m, ts = v.t }
end

-- deps: { cfg (DonationConfig), memory (MemoryStoreService), descending (Enum.SortDirection.Descending), suffix,
--   now() (detik UTC), warn }
function Feed.new(deps)
	local self = setmetatable({}, Feed)
	self.deps = deps
	self.cfg = deps.cfg
	self.maps = {} -- [nama map] = SortedMap
	self.warned = {}
	return self
end

function Feed:map(kind, date)
	local F = self.cfg.feed
	local name = ("%s_%s_%s%s"):format(F.memory, kind, date, self.deps.suffix)
	if not self.maps[name] then
		self.maps[name] = self.deps.memory:GetSortedMap(name)
	end
	return self.maps[name]
end

function Feed:warnOnce(key, msg)
	if not self.warned[key] then
		self.warned[key] = true
		self.deps.warn(msg)
	end
end

function Feed:today()
	return self.cfg.dayKey(self.deps.now())
end

-- Server asal: simpan donasi (dipanggil sekali per donasi asli). Gagal → warn sekali, papan tetap jalan.
function Feed:record(item)
	if item.test or item.remote or type(item.purchaseId) ~= "string" then
		return false
	end
	local kind = item.external and "gold" or "robux"
	local ts = self.deps.now()
	local F = self.cfg.feed
	local ok, err = pcall(function()
		local m = self:map(kind, self.cfg.dayKey(ts))
		m:SetAsync(item.purchaseId, Feed.pack(item, ts), F.ttl, ts)
	end)
	if not ok then
		self:warnOnce("w" .. kind, "[Donation] feed harian gagal ditulis (papan tetap jalan): " .. tostring(err))
	else
		self.warned["w" .. kind] = nil
	end
	return ok
end

-- Semua server: kartu hari ini (terbaru di depan, maks cfg.feed.fetch) atau nil kalau gagal dibaca.
function Feed:read(kind)
	if not KINDS[kind] then
		return nil
	end
	local F = self.cfg.feed
	local ok, items = pcall(function()
		return self:map(kind, self:today()):GetRangeAsync(self.deps.descending, F.fetch)
	end)
	if not ok or type(items) ~= "table" then
		self:warnOnce("r" .. kind, "[Donation] feed harian gagal dibaca: " .. tostring(items))
		return nil
	end
	self.warned["r" .. kind] = nil
	local out = {}
	for _, it in items do
		local card = type(it) == "table" and Feed.unpack(it.key, it.value, self.cfg)
		if card then
			table.insert(out, card)
		end
	end
	table.sort(out, function(a, b)
		return a.ts > b.ts
	end)
	return out
end

return Feed
