-- MusicServer/RateLimit  (ModuleScript)  [FIX R5] dipindah dari init.server
-- Pembatas aksi remote per pemain + kuota laporan durasi + cek angka dari client.

local isAdmin = require(script.Parent:WaitForChild("Permissions")).isAdmin

local rateHits = {}

-- [FIX R4] Satu pembatas untuk semua aksi. everyone = true: admin juga dibatasi
-- (dulu SetLive & RequestState punya tabel jeda sendiri).
local function checkRate(p, action, cooldown, everyone)
	if isAdmin(p) and not everyone then return true end
	local key  = p.UserId .. "_" .. action
	local now  = os.clock()
	local last = rateHits[key]
	if last and (now - last) < cooldown then
		return false, ("Wait %ds"):format(math.ceil(cooldown - (now - last)))
	end
	rateHits[key] = now
	return true
end

task.spawn(function()
	while true do
		task.wait(300)
		local now = os.clock()
		for k, t in pairs(rateHits) do
			if (now - t) > 120 then rateHits[k] = nil end
		end
	end
end)

-- [FIX M3] Angka dari client wajib angka sungguhan: NaN lolos math.clamp.
local function isNum(v) return type(v) == "number" and v == v end

-- [FIX M3] ReportDuration: kuota token per pemain (5 token, terisi 1/dtk).
-- Laporan sah: posisi tiap 3 dtk + durasi sekali + gagal ≤2 → tidak pernah habis.
-- Spam dibuang supaya tidak memicu SongDuration ke semua pemain.
local reportBucket = {}
local function allowReport(p)
	local now = os.clock()
	local b = reportBucket[p]
	if not b then b = { tokens = 5, at = now }; reportBucket[p] = b end
	b.tokens = math.min(5, b.tokens + (now - b.at))
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

-- Pemain keluar: buang semua jejak jeda & kuotanya.
local function forget(p)
	reportBucket[p] = nil
	local prefix = p.UserId .. "_"
	for k in pairs(rateHits) do
		if k:sub(1, #prefix) == prefix then rateHits[k] = nil end
	end
end

return {
	check       = checkRate,
	isNum       = isNum,
	allowReport = allowReport,
	forget      = forget,
}
