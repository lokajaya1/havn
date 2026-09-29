-- DonationServer.Global — donasi tampil di SEMUA server lewat MessagingService.
-- Server asal: setelah donasi tersimpan (isNew, sekali per purchaseId) → satu pesan ke topik.
--   Pesan donatur SUDAH difilter di server asal (PublicChat + broadcast); server lain tidak bisa
--   memfilter ulang karena FilterStringAsync butuh pengirim ada di server itu (pola /global AN1).
-- Server penerima: pesan dari server sendiri dibuang (job), isi divalidasi, purchaseId kembar dibuang,
--   lalu masuk antrean pengumuman yang sama dengan `remote = true` (tanpa partikel & LiveScreen,
--   keduanya butuh karakter donatur di server ini).
-- Gagal kirim/terima hanya memengaruhi tampilan di server lain; data donasi sudah tersimpan.
-- Tes admin (item.test) dikirim sebagai v = 2: server versi lama (hanya kenal v = 1) mengabaikannya,
-- jadi donasi tes tidak pernah tampil sebagai donasi asli di sana.
-- Donasi luar (bagibagi, item.external) dikirim sebagai v = 3: robux = 0 + poin `gold` (bukan Rupiah), uid boleh 0
-- (nama bukan akun Roblox), tier efek boleh kosong (hanya notifikasi). Server versi lama mengabaikannya.
local Global = {}
Global.__index = Global

Global.VERSION = 1
Global.TEST_VERSION = 2
Global.EXTERNAL_VERSION = 3
local NAME_BYTES = 60
local EXTERNAL_NAME_BYTES = 200 -- nama bebas donatur luar (≤ 50 karakter UTF-8)
local ID_BYTES = 100
local MAX_ROBUX = 1e7

local function str(v, maxBytes)
	if type(v) == "string" and #v <= maxBytes and utf8.len(v) then
		return v
	end
	return nil
end

-- Murni: item pengumuman → data pesan.
function Global.encode(item, jobId)
	return {
		v = item.external and Global.EXTERNAL_VERSION or (item.test and Global.TEST_VERSION or Global.VERSION),
		test = item.test or nil,
		ext = item.external or nil,
		job = jobId,
		pid = item.purchaseId,
		uid = item.userId,
		name = item.name,
		display = item.displayName,
		robux = item.robux,
		t = item.tier,
		msg = item.message,
		gold = item.external and item.gold or nil,
	}
end

-- Murni: data pesan → item pengumuman, atau nil kalau tidak sah.
-- Tier dipilih dari harga tier (t) yang dikirim server asal, bukan dari robux (CurrencySpent bisa beda).
function Global.decode(data, cfg)
	if type(data) ~= "table" then
		return nil
	end
	local isExternal = data.v == Global.EXTERNAL_VERSION and data.ext == true
	local isTest
	if isExternal then
		isTest = data.test == true
	else
		isTest = data.v == Global.TEST_VERSION and data.test == true
		if data.v ~= Global.VERSION and not isTest then
			return nil
		end
	end
	local nameBytes = isExternal and EXTERNAL_NAME_BYTES or NAME_BYTES
	local job, pid = str(data.job, ID_BYTES), str(data.pid, ID_BYTES)
	local name, display = str(data.name, nameBytes), str(data.display, nameBytes)
	local msg = str(data.msg, cfg.message.maxBytes)
	local uid, robux, t = tonumber(data.uid), tonumber(data.robux), tonumber(data.t)
	if not (job and pid and name and display and msg and uid and robux) or (t == nil and not isExternal) then
		return nil
	end
	if uid % 1 ~= 0 or robux > MAX_ROBUX or robux % 1 ~= 0 then
		return nil
	end
	if isExternal then
		if uid < 0 or robux ~= 0 then
			return nil
		end
		local gold = data.gold
		if gold ~= nil and not (type(gold) == "number" and gold % 1 == 0 and gold >= 0 and gold <= 1e12) then
			return nil
		end
	elseif uid <= 0 or robux <= 0 then
		return nil
	end
	if (utf8.len(msg) or 0) > cfg.message.maxChars then
		return nil
	end
	local tier
	for _, candidate in cfg.tiers do
		if candidate.robux == t then
			tier = candidate
		end
	end
	if t ~= nil and not tier then
		return nil
	end
	return {
		job = job,
		purchaseId = pid,
		userId = uid,
		name = name,
		displayName = display,
		robux = robux,
		tier = tier and tier.robux,
		fxRobux = isExternal and tier and tier.robux or nil,
		message = msg,
		gold = isExternal and (tonumber(data.gold) or 0) or nil,
		gap = tier and tier.gap or cfg.bagibagi.gap,
		big = tier and tier.big,
		remote = true,
		external = isExternal or nil,
		test = isTest or nil,
	}
end

-- deps: { messaging, jobId, topic, cfg (DonationConfig), enqueue(item), task, warn }
function Global.new(deps)
	local self = setmetatable({}, Global)
	self.deps = deps
	self.cfg = deps.cfg.global
	self.seen = {} -- [purchaseId] = true
	self.order = {} -- purchaseId terlama di depan
	return self
end

-- true kalau purchaseId belum pernah terlihat (lalu diingat).
function Global:remember(pid)
	if self.seen[pid] then
		return false
	end
	self.seen[pid] = true
	table.insert(self.order, pid)
	while #self.order > self.cfg.recent do
		self.seen[table.remove(self.order, 1)] = nil
	end
	return true
end

-- Dipanggil server asal setelah donasi tersimpan. Tidak menunggu (task.spawn).
function Global:publish(item)
	if not self.cfg.enabled or (not item.external and item.robux < self.cfg.minRobux) then
		return
	end
	local d = self.deps
	local data = Global.encode(item, d.jobId)
	self:remember(item.purchaseId)
	d.task.spawn(function()
		local delays = self.cfg.retry
		for attempt = 0, #delays do
			local ok, err = pcall(d.messaging.PublishAsync, d.messaging, d.topic, data)
			if ok then
				return
			end
			if attempt == #delays then
				d.warn(("[Donation] kirim ke server lain gagal (%s): %s — hanya tampil di server ini"):format(item.name, tostring(err)))
				return
			end
			d.task.wait(delays[attempt + 1])
		end
	end)
end

function Global:onMessage(message)
	local item = Global.decode(type(message) == "table" and message.Data or nil, self.deps.cfg)
	if not item or item.job == self.deps.jobId then
		return
	end
	if not self:remember(item.purchaseId) then
		return
	end
	self.deps.enqueue(item)
end

-- Berlangganan topik; gagal (limit / layanan down) → coba ulang di latar, tidak mematikan DonationServer.
function Global:start()
	if not self.cfg.enabled then
		return
	end
	local d = self.deps
	d.task.spawn(function()
		local attempt = 0
		while true do
			local ok, conn = pcall(d.messaging.SubscribeAsync, d.messaging, d.topic, function(message)
				self:onMessage(message)
			end)
			if ok then
				self.connection = conn
				return
			end
			attempt += 1
			local delays = self.cfg.resubscribe
			local wait = delays[math.min(attempt, #delays)]
			d.warn(("[Donation] langganan donasi server lain gagal (%s), coba lagi %d dtk"):format(tostring(conn), wait))
			d.task.wait(wait)
		end
	end)
end

return Global
