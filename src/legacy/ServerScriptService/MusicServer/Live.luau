-- MusicServer/Live  (ModuleScript)
-- [FIX L1] SIARAN LIVE — sisi DJ (stasiun).
-- Satu server bisa menjadi stasiun: lagu yang diputar di server ini dicatat di
-- MemoryStore (sumber kebenaran, dengan lease) dan diumumkan lewat
-- MessagingService. Hanya SATU siaran dalam satu waktu. Kalau server stasiun
-- mati tanpa sempat berhenti, lease habis sendiri dalam LEASE detik.
-- L1: server lain baru MENCATAT pesan + selisih jam (bukti untuk L2).

local MSS = game:GetService("MemoryStoreService")
local Msg = game:GetService("MessagingService")

local Live = {}

local MAP_NAME = "MusicLive"
local KEY      = "state"
local TOPIC    = "MusicLive"
local LEASE    = 30   -- detik
local RENEW    = 10   -- detik; perpanjang lease selama siaran
local MAX_MISS = 3    -- gagal perpanjang berturut-turut → berhenti

local map   = MSS:GetHashMap(MAP_NAME)
local jobId = (game.JobId ~= "" and game.JobId) or ("studio-" .. game:GetService("HttpService"):GenerateGUID(false)) -- [FIX L1c] unik tiap sesi Studio

local active = false
local djName, djId
local ver    = 0
local current          -- { song = {...}, startedAtMs = n }
local listeners = {}   -- fn(state) saat status siaran server ini berubah
local remoteFns = {}   -- fn(msg) saat pesan dari server lain datang

local function nowMs() return DateTime.now().UnixTimestampMillis end

local function slim(song)
	if type(song) ~= "table" then return nil end
	return {
		Id = song.Id, RawId = song.RawId, Name = song.Name,
		AudioCreator = song.AudioCreator, creatorType = song.creatorType,
		thumbnailUrl = song.thumbnailUrl, Requester = song.Requester,
	}
end

local function buildState()
	return {
		jobId = jobId, dj = djName, djId = djId, ver = ver,
		song = current and current.song or nil,
		startedAtMs = current and current.startedAtMs or nil,
	}
end

-- Tulis status kalau kunci kosong/kedaluwarsa atau milik server ini.
-- Hasil: true | false, namaDjLain | false, nil, galat
local function claim()
	local busyBy
	local ok, res = pcall(function()
		return map:UpdateAsync(KEY, function(old)
			if type(old) == "table" and old.jobId ~= jobId then
				busyBy = old.dj or "?"
				return nil
			end
			return buildState()
		end, LEASE)
	end)
	if not ok then return false, nil, res end
	if res == nil then return false, busyBy end
	return true
end

local function publish(kind)
	local payload = {
		type = kind, jobId = jobId, dj = djName, ver = ver, sentAtMs = nowMs(),
		songId = current and current.song and current.song.Id or nil,
		startedAtMs = current and current.startedAtMs or nil,
	}
	local ok, err = pcall(Msg.PublishAsync, Msg, TOPIC, payload)
	if not ok then warn("[Live] PublishAsync gagal:", err) end
end

local function changed()
	local st = Live.state()
	for _, fn in ipairs(listeners) do task.spawn(fn, st) end
end

-- [FIX L2] SISI PENDENGAR. Server yang tidak siaran membaca status di MemoryStore
-- (saat ada pesan + tiap POLL detik). Ada siaran milik server lain → ikut;
-- status hilang (DJ berhenti / lease habis) → kembali ke musik server ini.
local POLL = 10
local following, followKey, followDj = false, nil, nil
local followFns = {}   -- fn(state) ikut lagu siaran | fn(nil) berhenti ikut

function Live.isFollowing() return following end
function Live.onFollow(fn) table.insert(followFns, fn) end

local function syncFollower()
	if active then return end
	local ok, st = pcall(map.GetAsync, map, KEY)
	if not ok then return end
	if type(st) == "table" and st.jobId ~= jobId then
		local key = tostring(st.jobId) .. ":" .. tostring(st.ver)
		if key == followKey then return end
		followKey = key
		local first = not following
		following, followDj = true, st.dj
		local lag = st.startedAtMs and (nowMs() - st.startedAtMs) or 0
		print(("[Live] ikut siaran DJ %s | lagu %s | mulai di detik %.1f")
			:format(tostring(st.dj), tostring(st.song and st.song.Name), lag / 1000))
		for _, fn in ipairs(followFns) do task.spawn(fn, st) end
		if first then changed() end
	elseif following then
		following, followKey, followDj = false, nil, nil
		print("[Live] siaran selesai, kembali ke musik server ini")
		for _, fn in ipairs(followFns) do task.spawn(fn, nil) end
		changed()
	end
end
Live.syncNow = syncFollower

function Live.state() -- [FIX L2] + following
	return { active = active, dj = active and djName or followDj, here = active, following = following }
end

function Live.isActive() return active end
function Live.onChange(fn) table.insert(listeners, fn) end
function Live.onRemote(fn) table.insert(remoteFns, fn) end

local function setCurrent(song, elapsed)
	if song then
		current = { song = slim(song), startedAtMs = nowMs() - math.floor((tonumber(elapsed) or 0) * 1000) }
	else
		current = nil
	end
end

-- YIELDS. Mulai siaran dari server ini.
function Live.start(p, song, elapsed)
	if active then return false, "Live is already running on this server" end
	djName, djId = p.Name, p.UserId
	setCurrent(song, elapsed)
	ver += 1
	local ok, busy, err = claim()
	if not ok then
		djName, djId, current = nil, nil, nil
		if busy then return false, "Live is in use by " .. tostring(busy) end
		warn("[Live] gagal memulai siaran:", err)
		return false, "Live failed to start, try again"
	end
	active = true
	print(("[Live] siaran DIMULAI oleh %s | server %s"):format(djName, string.sub(jobId, 1, 8)))
	publish("start")
	changed()

	task.spawn(function()
		local miss = 0
		while active do
			task.wait(RENEW)
			if not active then break end
			local okR, busyR = claim()
			if okR then
				miss = 0
			elseif busyR then
				warn("[Live] lease diambil server lain (" .. tostring(busyR) .. "), siaran berhenti")
				Live.stop("lease hilang", true)
				break
			else
				miss += 1
				if miss >= MAX_MISS then
					warn("[Live] MemoryStore gagal " .. miss .. "x, siaran berhenti")
					Live.stop("MemoryStore gagal", true)
					break
				end
			end
		end
	end)
	return true
end

-- YIELDS. Hentikan siaran server ini (tidak berbuat apa-apa kalau tidak siaran).
function Live.stop(reason, skipRemove)
	if not active then return end
	active = false
	ver += 1
	if not skipRemove then
		local ok, old = pcall(map.GetAsync, map, KEY)
		if ok and type(old) == "table" and old.jobId == jobId then
			pcall(map.RemoveAsync, map, KEY)
		end
	end
	publish("stop")
	print(("[Live] siaran BERHENTI (%s)"):format(tostring(reason)))
	djName, djId, current = nil, nil, nil
	changed()
end

-- Dipanggil Playback setiap lagu mulai / diulang / berhenti.
function Live.songChanged(song, elapsed)
	if not active then return end
	setCurrent(song, elapsed)
	ver += 1
	task.spawn(function()
		claim()
		publish(song and "song" or "idle")
	end)
end

function Live.playerLeft(p)
	if active and p.UserId == djId then
		task.spawn(Live.stop, "DJ keluar")
	end
end

game:BindToClose(function()
	if active then Live.stop("server ditutup") end
end)

-- Pesan dari server lain. L1: hanya dicatat (selisih jam + latensi).
task.spawn(function()
	local ok, err = pcall(function()
		Msg:SubscribeAsync(TOPIC, function(m)
			local d = m and m.Data
			if type(d) ~= "table" or d.jobId == jobId then return end
			local lag = nowMs() - (tonumber(d.sentAtMs) or nowMs())
			print(("[Live] pesan '%s' dari server %s (DJ %s) | selisih jam+latensi %d ms")
				:format(tostring(d.type), string.sub(tostring(d.jobId), 1, 8), tostring(d.dj), lag))
			for _, fn in ipairs(remoteFns) do task.spawn(fn, d) end
			task.spawn(syncFollower) -- [FIX L2]
		end)
	end)
	if not ok then warn("[Live] SubscribeAsync gagal:", err) end
end)

-- [FIX L2] Cadangan pesan yang hilang + server baru yang lahir di tengah siaran.
task.spawn(function()
	task.wait(3)
	while true do
		syncFollower()
		task.wait(POLL)
	end
end)

return Live
