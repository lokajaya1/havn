-- MusicServer/Volume  (ModuleScript)  [FIX R5] dipindah dari init.server
-- Volume pribadi pemain. Store & kunci TETAP: MusicVolume / "Vol_<UserId>".

local DSS = game:GetService("DataStoreService")
local RS  = game:GetService("ReplicatedStorage")

local Shared = require(RS:WaitForChild("MusicShared"))
local VolDS  = DSS:GetDataStore("MusicVolume")

local Volume = {}
local timers = {}

-- DataStore bisa gagal sesaat walau API Services aktif. Diulang dulu sebelum
-- jatuh ke nilai bawaan, supaya setelan volume pemain tidak "hilang" sendiri.
function Volume.load(p)
	local ok, v = Shared.retry(3, function(i) return 0.5 * i end, VolDS.GetAsync, VolDS, "Vol_" .. p.UserId) -- [FIX R4]
	if ok and type(v) == "number" then return math.clamp(v, 0, 1) end
	return 0.7
end

-- [FIX M2] Volume hanya disimpan kalau pemain benar-benar menggesernya. Dulu:
-- load gagal → 0.7, lalu saat keluar SELALU SetAsync → setelan asli tertimpa.
local pendingVol = 0

local function writeVol(uid, vol)
	pendingVol += 1
	local ok = Shared.retry(3, function(i) return i end, VolDS.SetAsync, VolDS, "Vol_" .. uid, vol) -- [FIX R4]
	pendingVol -= 1
	return ok
end

-- d = data pemain ({ volume, volDirty }). Disimpan 5 dtk setelah geseran terakhir.
function Volume.saveLater(p, d)
	d.volDirty = true
	if timers[p] then task.cancel(timers[p]) end
	timers[p] = task.delay(5, function()
		timers[p] = nil
		local v = d.volume
		if writeVol(p.UserId, v) and d.volume == v then d.volDirty = false end
	end)
end

-- Pemain keluar: batalkan timer, tulis sekarang hanya kalau memang diubah.
function Volume.flush(p, d)
	if timers[p] then task.cancel(timers[p]); timers[p] = nil end
	if d.volDirty then task.spawn(writeVol, p.UserId, d.volume) end -- [FIX M2]
end

game:BindToClose(function()
	local t0 = os.clock()
	while pendingVol > 0 and os.clock() - t0 < 25 do task.wait(0.2) end
end)

return Volume
