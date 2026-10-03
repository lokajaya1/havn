--!strict
-- ReplicatedStorage/Modules/ToolRules (ModuleScript) — aturan MURNI tool (ruangan TOOLS, claude/Rencana_Tools.md).
-- Tanpa GetService / Instance / yield: jam & penjadwal DIOPER oleh pemanggil (os.clock, task.delay) → bisa dites
-- dengan jam palsu. Config = ReplicatedStorage.Config.Tools.

local ToolRules = {}

-- ── batas terima: token bucket ───────────────────────────────────────────────────────────────────────────────────
-- Penuh di awal (BURST token), terisi RATE token/dtk, maksimal BURST. take() = true kalau event boleh diproses.
export type Bucket = { rate: number, capacity: number, tokens: number, last: number? }

function ToolRules.bucket(rate: number, capacity: number): Bucket
	return { rate = rate, capacity = capacity, tokens = capacity, last = nil }
end

function ToolRules.take(b: Bucket, now: number): boolean
	local last = b.last
	if last ~= nil and now > last then
		b.tokens = math.min(b.capacity, b.tokens + (now - last) * b.rate)
	end
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

-- ── jeda terapkan: gate, nilai terakhir menang ───────────────────────────────────────────────────────────────────
-- push(v): kalau jeda sudah lewat → apply(v) langsung. Kalau belum → v disimpan dan apply dijadwalkan SEKALI di ujung
-- jeda; push berikutnya selama menunggu hanya mengganti nilai yang disimpan. Hasil: apply paling sering 1× per
-- `interval`, dan nilai push terakhir SELALU diterapkan (tidak pernah hilang).
-- clock = os.clock; later = task.delay (atau palsu di tes).
function ToolRules.gate(
	interval: number,
	apply: (any) -> (),
	clock: () -> number,
	later: (number, () -> ()) -> any
): (any) -> ()
	local last = -math.huge
	local scheduled = false
	local pending: any = nil
	local function flush()
		scheduled = false
		last = clock()
		local v = pending
		pending = nil
		apply(v)
	end
	return function(value: any)
		if scheduled then
			pending = value
			return
		end
		local now = clock()
		local wait = last + interval - now
		if wait <= 0 then
			last = now
			apply(value)
		else
			pending = value
			scheduled = true
			later(wait, flush)
		end
	end
end

-- ── validasi ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- Color3 sah: tipe Color3 dan R/G/B di 0–1 (NaN/inf/negatif ditolak). Color3 dari client bisa berisi apa saja.
function ToolRules.isColor(v: any): boolean
	if typeof(v) ~= "Color3" then
		return false
	end
	for _, c in { v.R, v.G, v.B } do
		if c ~= c or c < 0 or c > 1 then
			return false
		end
	end
	return true
end

-- Angka dari panel client → dipaksa ke rentang Config { MIN, MAX, STEP, DEFAULT }: bukan angka/NaN → DEFAULT,
-- di luar rentang → ujung terdekat, lalu dibulatkan ke kelipatan STEP terdekat dari MIN.
export type Range = { MIN: number, MAX: number, STEP: number, DEFAULT: number }

function ToolRules.choose(v: any, r: Range): number
	if type(v) ~= "number" or v ~= v then
		return r.DEFAULT
	end
	local n = math.clamp(v, r.MIN, r.MAX)
	n = r.MIN + math.floor((n - r.MIN) / r.STEP + 0.5) * r.STEP
	return math.min(n, r.MAX)
end

-- ── ToolGiver ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- rule = satu baris Config.GIVER.RULES. Boleh dapat: punya pass rule ATAU rank ≥ minRank.
export type GiverRule = { names: { string }, pass: string, minRank: number }

function ToolRules.eligible(rule: GiverRule, rank: number, hasVIP: boolean, hasVVIP: boolean): boolean
	local hasPass = (rule.pass == "VIP" and hasVIP) or (rule.pass == "VVIP" and hasVVIP)
	return hasPass or rank >= rule.minRank
end

-- Rank dari atribut Player (UnifiedRankManager): angka sah → angka itu; selain itu nil (belum dipasang).
function ToolRules.rankOf(attr: any): number?
	if type(attr) == "number" and attr == attr and attr >= 0 and attr <= 255 then
		return attr
	end
	return nil
end

return ToolRules
