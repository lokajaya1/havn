--!strict
-- ServerScriptService/ThemeMap/Rules (ModuleScript) — aturan MURNI tema map (themeMap, claude/Rencana_Tema.md):
-- validasi permintaan admin, jadwal mulai/selesai (WIB), tema efektif, rekaman DataStore + riwayat, jeda, dorong pemain.
-- Tanpa GetService / Instance / yield; waktu (`now`, detik UTC) selalu disuntik pemanggil.

local Rules = {}

export type Entry = { id: string, fromT: number?, untilT: number?, byName: string, at: number }
export type Record = {
	v: number,
	rev: number,
	id: string,
	fromT: number?,
	untilT: number?,
	by: number,
	byName: string,
	at: number,
	log: { Entry },
}

local DAY = 86400

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

local function shortText(v: any, max: number): boolean
	return type(v) == "string" and #v > 0 and #v <= max
end

local function hasKey(list: { any }, key: any): boolean
	for _, x in list do
		if x.key == key then
			return true
		end
	end
	return false
end

-- Permintaan dari remote: id dari daftar putih, kunci jadwal dari daftar. → true | false, "invalid"
function Rules.validate(cfg: any, id: any, startKey: any, endKey: any): (boolean, string?)
	if not (shortText(id, 32) and shortText(startKey, 16) and shortText(endKey, 16)) then
		return false, "invalid"
	end
	if not cfg.find(id) or not hasKey(cfg.starts, startKey) or not hasKey(cfg.ends, endKey) then
		return false, "invalid"
	end
	if id == cfg.default and (startKey ~= "now" or endKey ~= "none") then
		return false, "invalid" -- Default = kembali tanpa dekor sekarang, tanpa jadwal
	end
	return true, nil
end

-- Awal hari (00:00 zona utcOffset) yang memuat waktu t, dalam detik UTC.
function Rules.dayStart(t: number, utcOffset: number): number
	local off = utcOffset * 3600
	local localT = t + off
	return localT - (localT % DAY) - off
end

-- Jadwal → fromT (nil = sekarang), untilT (nil = tanpa batas, eksklusif).
--   now/tomorrow : sekarang / besok 00:00 zona
--   none/day/24h : tanpa batas / 00:00 sesudah hari mulai (= sampai 23:59 hari itu) / 24 jam sesudah mulai
function Rules.window(cfg: any, startKey: string, endKey: string, now: number): (number?, number?)
	local fromT: number? = nil
	if startKey == "tomorrow" then
		fromT = Rules.dayStart(now, cfg.utcOffset) + DAY
	end
	local begin = fromT or now
	local untilT: number? = nil
	if endKey == "day" then
		untilT = Rules.dayStart(begin, cfg.utcOffset) + DAY
	elseif endKey == "24h" then
		untilT = begin + DAY
	end
	return fromT, untilT
end

-- Rekaman dari DataStore (bisa rusak/lama) → bentuk aman, atau nil.
function Rules.sanitize(cfg: any, rec: any): Record?
	if type(rec) ~= "table" or not shortText(rec.id, 32) or not isInt(rec.rev, 0, 1e12) then
		return nil
	end
	local function time(v: any): number?
		return if isInt(v, 0, 1e11) then v else nil
	end
	local log = {}
	if type(rec.log) == "table" then
		for _, e in rec.log do
			if #log >= cfg.logMax then
				break
			end
			if type(e) == "table" and shortText(e.id, 32) and isInt(e.at, 0, 1e11) then
				table.insert(log, {
					id = e.id,
					fromT = time(e.fromT),
					untilT = time(e.untilT),
					byName = if shortText(e.byName, 64) then e.byName else "?",
					at = e.at,
				})
			end
		end
	end
	return {
		v = 1,
		rev = rec.rev,
		id = rec.id,
		fromT = time(rec.fromT),
		untilT = time(rec.untilT),
		by = if isInt(rec.by, 0, 1e13) then rec.by else 0,
		byName = if shortText(rec.byName, 64) then rec.byName else "?",
		at = time(rec.at) or 0,
		log = log,
	}
end

-- Tema yang harus terpasang sekarang. Rekaman kosong / tema tak dikenal / di luar jadwal → Default.
function Rules.effective(cfg: any, rec: Record?, now: number): string
	if not rec or not cfg.find(rec.id) then
		return cfg.default
	end
	if rec.fromT and now < rec.fromT then
		return cfg.default
	end
	if rec.untilT and now >= rec.untilT then
		return cfg.default
	end
	return rec.id
end

-- Rekaman baru di atas rekaman lama (UpdateAsync): rev naik dari yang TERBESAR (lama vs yang diketahui server ini),
-- riwayat terbaru di depan, maks cfg.logMax.
function Rules.nextRecord(cfg: any, old: Record?, knownRev: number, id: string, fromT: number?, untilT: number?, by: number, byName: string, now: number): Record
	local rev = math.max(if old then old.rev else 0, knownRev) + 1
	local log: { Entry } = { { id = id, fromT = fromT, untilT = untilT, byName = byName, at = now } }
	if old then
		for _, e in old.log do
			if #log >= cfg.logMax then
				break
			end
			table.insert(log, e)
		end
	end
	return { v = 1, rev = rev, id = id, fromT = fromT, untilT = untilT, by = by, byName = byName, at = now, log = log }
end

-- Jeda: per admin (cfg.cooldown.admin) dan antar-pergantian di server ini (cfg.cooldown.server). clock = os.clock.
-- → true | false, "cooldown", sisa detik (dibulatkan ke atas)
function Rules.cooldown(cfg: any, lastAdmin: number?, lastServer: number?, clock: number): (boolean, string?, number?)
	local waitFor = 0
	if lastAdmin then
		waitFor = math.max(waitFor, cfg.cooldown.admin - (clock - lastAdmin))
	end
	if lastServer then
		waitFor = math.max(waitFor, cfg.cooldown.server - (clock - lastServer))
	end
	if waitFor > 0 then
		return false, "cooldown", math.ceil(waitFor)
	end
	return true, nil, nil
end

export type Box = { minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number }

-- Pemain di dalam kotak part padat tema (diperlebar push.margin mendatar, push.vertical tegak) → titik baru di tepi
-- terdekat + push.out (y tetap). Diulang maks 4× (kotak bertumpuk, mis. 3 tingkat kue). → x, z baru, atau nil = aman.
function Rules.pushOut(boxes: { Box }, x: number, y: number, z: number, push: any): (number?, number?)
	local m, out, vert = push.margin, push.out, push.vertical
	local moved = false
	for _ = 1, 4 do
		local hit: Box? = nil
		for _, b in boxes do
			if x > b.minX - m and x < b.maxX + m and z > b.minZ - m and z < b.maxZ + m and y > b.minY - vert and y < b.maxY + vert then
				hit = b
				break
			end
		end
		if not hit then
			break
		end
		local h = hit :: Box
		-- urutan seri: selatan (+Z, arah spawn) lebih dulu
		local opts = {
			{ d = h.maxZ + out - z, x = x, z = h.maxZ + out },
			{ d = z - (h.minZ - out), x = x, z = h.minZ - out },
			{ d = h.maxX + out - x, x = h.maxX + out, z = z },
			{ d = x - (h.minX - out), x = h.minX - out, z = z },
		}
		local best = opts[1]
		for i = 2, 4 do
			if opts[i].d < best.d then
				best = opts[i]
			end
		end
		x, z, moved = best.x, best.z, true
	end
	if moved then
		return x, z
	end
	return nil, nil
end

-- "02 Okt 13:40 WIB" (Roblox os.date hanya "*t"/"!*t").
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des" }
function Rules.fmt(t: number?, utcOffset: number): string
	if not t then
		return "-"
	end
	local d = os.date("!*t", math.floor(t + utcOffset * 3600)) :: any
	return ("%02d %s %02d:%02d WIB"):format(d.day, MONTHS[d.month], d.hour, d.min)
end

-- Baris log server: "Birthday ← Default oleh lokk123458 (8649461014) | mulai sekarang | selesai 03 Okt 00:00 WIB"
function Rules.describe(cfg: any, rec: Record, previous: string): string
	return ("%s ← %s oleh %s (%d) | mulai %s | selesai %s"):format(
		rec.id,
		previous,
		rec.byName,
		rec.by,
		if rec.fromT then Rules.fmt(rec.fromT, cfg.utcOffset) else "sekarang",
		if rec.untilT then Rules.fmt(rec.untilT, cfg.utcOffset) else "tanpa batas"
	)
end

return Rules
