-- MusicServer/Playback  (ModuleScript)
-- Sound instance, antrian, vote skip, dan deteksi akhir lagu.
--
-- Prinsip deteksi akhir lagu:
--   Server TIDAK me-render audio. TimeLength / TimePosition / IsPlaying /
--   IsLoaded di server bernilai 0/false. Karena itu:
--     * Durasi -> laporan client selalu menang.
--     * Akhir  -> posisi playback nyata dari client, dengan watchdog jam
--                 dinding sebagai jaring pengaman.
--     * Ended  -> event per-mesin. Diabaikan selama masih ada client yang
--                 melaporkan posisi di tengah lagu.
--     * Lantai -> tidak ada jalur otomatis yang boleh memajukan antrian
--                 sebelum MIN_PLAY_TIME. Skip admin/vote menembus lantai.
--     * Gagal  -> :Play() diulang beberapa kali dulu sebelum lagu divonis
--                 tidak tersedia, karena HTTP 502/Timedout itu sementara.

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared  = require(RS:WaitForChild("MusicShared"))
local Library = require(script.Parent:WaitForChild("Library"))

local P = {}

-- ══ KONFIG ════════════════════════════════════════════════════════════════
local function num(key, default, min)
	local v = Shared[key]
	if type(v) ~= "number" then v = default end
	return (min and v < min) and min or v
end

local LOAD_TIMEOUT  = num("loadTimeout",  25, 8)
local END_GRACE     = num("endGrace",      3, 2)
local SPURIOUS_GAP  = num("spuriousGap",   2, 1.5)
local FADE_OUT      = num("fadeOut",       1, 0)
local MIN_PLAY_TIME = num("minPlayTime",   8, 3)
local MAX_RETRY     = num("maxLoadRetry",  2, 0)

local PROGRESS_TTL = 8    -- laporan posisi dianggap basi setelah ini
local HARD_TIMEOUT = 900  -- anti-macet total
local TICK         = 0.5
local MAX_DUR      = 1800   -- 30 menit, di atas ini pasti laporan ngawur

-- ══ STATE ═════════════════════════════════════════════════════════════════
local sound, soundPath
local queue                = {}
local nowPlaying, playing  = nil, false
local token, consumed      = 0, 0
local startClock           = 0
local duration, durSource  = 0, "?"
local serverDur    = 0
local repLen       = {}   -- userId -> durasi yang dilaporkan
local resumeUsed, retryUsed = 0, 0
local okMarked             = false
local endedConn, ancestryConn
local skipVotes            = {}
local transitioning        = false

local repPos, repFail = {}, {}   -- userId -> { pos, at } / true
local startLag        = 0        -- keterlambatan client vs jam server
local warnedAt        = 0

-- ══ UTIL ══════════════════════════════════════════════════════════════════
local function safeRead(obj, prop, default)
	if not obj then return default end
	local ok, v = pcall(function() return obj[prop] end)
	if ok and v ~= nil then return v end
	return default
end

local rawOf       = Shared.rawId
local normalizeId = Shared.assetId

local function buildPath(inst)
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local function isAdminPlayer(p)
	return p:GetAttribute("IsAdmin") == true
end

local function countKeys(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

local function resetReports()
	repPos, repFail, repLen = {}, {}, {}
	startLag, warnedAt      = 0, 0
	serverDur               = 0
end

-- Posisi playback terbaik yang diketahui, diekstrapolasi dari laporan terakhir.
local function bestPos()
	local now, best = os.clock(), nil
	for _, r in pairs(repPos) do
		local age = now - r.at
		if age <= PROGRESS_TTL then
			local est = r.pos + age
			if not best or est > best then best = est end
		end
	end
	return best
end

-- Durasi dari client memakai NILAI TENGAH dari semua laporan, bukan yang
-- terbesar. Satu client rusak (atau iseng) yang melaporkan durasi ngawur tidak
-- bisa menyandera antrian selama ada pendengar lain yang normal.
local function clientDuration()
	local vals = {}
	for _, len in pairs(repLen) do table.insert(vals, len) end
	if #vals == 0 then return 0 end
	table.sort(vals)
	-- [FIX 2c2] median ATAS: dengan 2 pelapor, satu laporan pendek palsu tidak bisa memaksa skip
	return vals[math.floor(#vals / 2) + 1]
end

local function recomputeDuration()
	local cd = clientDuration()
	local d  = (cd > 1) and cd or serverDur
	if d <= 1 or math.abs(d - duration) <= 0.5 then return end
	duration  = d
	durSource = (cd > 1) and "client" or "server"
	Shared.all("SongDuration", d)
end

-- ══ ANTRIAN ═══════════════════════════════════════════════════════════════
function P.queue()     return queue end
function P.queueSize() return #queue end
function P.queueFull() return #queue >= Shared.maxGlobalQueue end

function P.queueContains(songId)
	local id = tostring(songId)
	for _, q in ipairs(queue) do
		if q.Id == id then return true end
	end
	return false
end

function P.queueCountBy(userId)
	local n = 0
	for _, q in ipairs(queue) do
		if q.RequesterId == userId then n += 1 end
	end
	return n
end

function P.queueIds()
	local ids = {}
	if nowPlaying then ids[nowPlaying.Id] = "sedangDiputar" end
	for _, q in ipairs(queue) do ids[q.Id] = "diAntrian" end
	return ids
end

function P.broadcastQueue() Shared.all("QueueUpdate", queue) end
function P.broadcastIds()   Shared.all("QueueIds", P.queueIds()) end

-- priority = premium: menyalip non-premium, FIFO di dalam kelompoknya sendiri.
function P.enqueue(entry, priority, isPremiumFn)
	if not priority then
		table.insert(queue, entry)
		return
	end
	local byName = {}
	for _, pl in ipairs(Players:GetPlayers()) do byName[pl.Name] = pl end

	local pos = 1
	for i, q in ipairs(queue) do
		local qp = byName[q.Requester]
		if qp and isPremiumFn(qp) then pos = i + 1 else break end
	end
	table.insert(queue, pos, entry)
end

-- Hapus by index tapi diverifikasi dengan Id: isi antrian bisa bergeser antara
-- client merender dan server menerima.
function P.removeFromQueue(idx, expectId)
	if type(idx) ~= "number" or idx < 1 or idx > #queue then return nil end
	if expectId and queue[idx].Id ~= tostring(expectId) then
		local found
		for i, q in ipairs(queue) do
			if q.Id == tostring(expectId) then found = i; break end
		end
		if not found then return nil end
		idx = found
	end
	return table.remove(queue, idx)
end

function P.removeFromQueueById(songId)
	local id = tostring(songId)
	for i = #queue, 1, -1 do
		if queue[i].Id == id then table.remove(queue, i) end
	end
end

-- ══ INSTANCE SOUND ════════════════════════════════════════════════════════
local function stagePart()
	local stage = workspace:FindFirstChild(Shared.stageName)
	if stage and stage:IsA("BasePart") then return stage end
	if stage then stage:Destroy() end
	stage = Instance.new("Part")
	stage.Name         = Shared.stageName
	stage.Anchored     = true
	stage.CanCollide   = false
	stage.CanQuery     = false
	stage.CanTouch     = false
	stage.Transparency = 1
	stage.Size         = Vector3.new(1, 1, 1)
	stage.Position     = Vector3.new(0, 5, 0)
	stage.Parent       = workspace
	return stage
end

-- Hanya nama persis Shared.soundName di lokasi yang kita kontrol, supaya tidak
-- nyangkut ke ambient/sfx milik sistem lain.
local function findOrMake()
	local stage = workspace:FindFirstChild(Shared.stageName)
	if stage then
		local s = stage:FindFirstChild(Shared.soundName)
		if s and s:IsA("Sound") then return s end
	end
	local direct = workspace:FindFirstChild(Shared.soundName)
	if direct and direct:IsA("Sound") then return direct end
	local ss = SoundService:FindFirstChild(Shared.soundName)
	if ss and ss:IsA("Sound") then return ss end

	local s = Instance.new("Sound")
	s.Name   = Shared.soundName
	s.Looped = false
	s.Volume = Shared.defaultVolume
	s.Parent = stagePart()
	return s
end

function P.applySpatial(cfg)
	if not sound then return end
	pcall(function() sound.Volume = math.clamp(cfg.volume or 1, 0, 1) end)
	if sound.Parent and sound.Parent:IsA("BasePart") then
		pcall(function() sound.RollOffMinDistance = cfg.min  or 10    end)
		pcall(function() sound.RollOffMaxDistance = cfg.max  or 10000 end)
		pcall(function() sound.EmitterSize        = cfg.size or 100   end)
		pcall(function() sound.RollOffMode        = Enum.RollOffMode.Linear end)
	end
end

function P.applyLoudness() Shared.applyLoudness(sound) end

function P.init()
	sound = findOrMake()
	sound.Looped = false
	sound.Volume = Shared.defaultVolume
	soundPath = buildPath(sound)
	P.applyLoudness()

	if ancestryConn then ancestryConn:Disconnect() end
	ancestryConn = sound.AncestryChanged:Connect(function()
		if sound.Parent then return end
		task.delay(1, function()
			P.init()
			P.applyMode(Shared.spatial.mode)
		end)
	end)
end

-- mode "global" -> parent ke workspace root (bukan SoundService): tetap
-- non-positional, tanpa kelakuan aneh Sound di bawah SoundService.
function P.applyMode(mode)
	if not sound or not sound.Parent then P.init() end
	local target = (mode == "global") and workspace or stagePart()
	if sound.Parent ~= target then sound.Parent = target end
	P.applySpatial(Shared.spatial)
	soundPath = buildPath(sound)
	Shared.all("SoundLocation", soundPath)
end

function P.setGlobalVolume(v)
	v = math.clamp(v or Shared.defaultVolume, 0, 1)
	pcall(function() sound.Volume = v end)
	Shared.all("GlobalVolumeUpdate", v)
end

-- ══ GETTER ════════════════════════════════════════════════════════════════
function P.isPlaying() return playing end
function P.current()   return nowPlaying end
function P.path()      return soundPath or "" end

-- Untuk player yang baru join: pakai posisi client kalau ada, karena jam server
-- bisa lebih maju dari audio yang sebenarnya berbunyi.
function P.elapsed()
	if not playing or startClock == 0 then return 0 end
	local pos = bestPos()
	if pos then return math.max(0, pos) end
	return math.max(0, os.clock() - startClock)
end

function P.votesNeeded()
	local n = #Players:GetPlayers()
	return n <= 1 and 1 or math.ceil(n / 2)
end

function P.votes() return { current = #skipVotes, required = P.votesNeeded() } end

-- ══ PERPINDAHAN LAGU ══════════════════════════════════════════════════════
-- Lagu pendek tetap boleh selesai wajar.
local function floorTime()
	if duration > 1 then return math.min(MIN_PLAY_TIME, math.max(1, duration - 1)) end
	return MIN_PLAY_TIME
end

-- Satu-satunya pintu "lagu selesai -> lagu berikutnya". Dedup lewat token,
-- jadi pemicu dari lagu lama tidak bisa meng-skip lagu yang sedang jalan.
local function advance(tk, reason, manual)
	if transitioning  then return end
	if tk ~= token    then return end
	if consumed == tk then return end
	if not playing    then return end

	local el = os.clock() - startClock
	if not manual and el < floorTime() then
		warn(("[Music] advance ditolak (%s): baru %.1fs, lantai %.1fs — %s")
			:format(reason, el, floorTime(), tostring(nowPlaying and nowPlaying.Name)))
		return
	end

	consumed = tk
	print(("[Music] lanjut | %s | elapsed %.1fs | durasi %.1fs (%s) | lag %.1fs | pelapor %d")
		:format(reason, el, duration, durSource, startLag, countKeys(repPos)))
	P.next()
end

-- Laporan dari client: durasi asli, posisi playback, atau tanda gagal load.
-- SIGNATURE: (player, data).
function P.report(player, data)
	if type(data) ~= "table" then return end
	if not playing or not nowPlaying then return end

	local id = rawOf(data.id)
	if not id or id ~= rawOf(nowPlaying.Id) then return end

	local uid = (typeof(player) == "Instance" and player.UserId) or 0
	local el  = os.clock() - startClock

	-- [FIX 2c2] abaikan durasi yang jauh lebih pendek dari durasi yang diketahui server
	if type(data.len) == "number" and data.len > 1 and data.len < MAX_DUR
		and not (serverDur > 1 and data.len < serverDur - 2) then
		repLen[uid] = data.len
		if not okMarked then okMarked = true; pcall(Library.markOk, nowPlaying) end
		recomputeDuration()
	end

	-- Posisi tidak boleh melampaui waktu yang benar-benar sudah berjalan di
	-- server. Tanpa cek ini, satu client bisa mengirim pos = durasi dan
	-- memaksa lagu ter-skip untuk semua orang.
	if type(data.pos) == "number" and data.pos >= 0 and data.pos <= el + 5 then
		repPos[uid]  = { pos = data.pos, at = os.clock() }
		repFail[uid] = nil
		if not okMarked then okMarked = true; pcall(Library.markOk, nowPlaying) end
		local lag = el - data.pos
		if lag > startLag and lag < 120 then startLag = lag end
	end

	if data.failed == true then repFail[uid] = true end
end

local function tryResume(el)
	if resumeUsed >= 2 then return end
	resumeUsed += 1
	pcall(function()
		sound.TimePosition = math.max(0, math.min(el, math.max(0, duration - 0.5)))
		sound:Play()
	end)
end

-- Butuh konfirmasi lebih dari satu pendengar: satu client yang kena throttle
-- atau koneksi jelek tidak boleh mem-blacklist lagu.
local function failConfirmed()
	local need = math.min(2, math.max(1, #Players:GetPlayers()))
	return countKeys(repFail) >= need
end

-- Ulangi :Play() lagu YANG SAMA. JANGAN set SoundId = "" (itu yang memicu
-- 'Failed to load sound http://www.roblox.com/asset/?id=').
local function replayCurrent(tk)
	if tk ~= token or not nowPlaying then return end
	local id = normalizeId(nowPlaying.Id)
	if not id then return end
	pcall(function()
		sound:Stop()
		sound.TimePosition = 0
		sound.SoundId      = id
		sound:Play()
	end)
	startClock = os.clock()
	resumeUsed = 0
	resetReports()
	duration, durSource = 0, "?"
	Shared.all("SongRetry",  { name = nowPlaying.Name or "?", attempt = retryUsed })
	Shared.all("NowPlaying", nowPlaying)
	if P.onSongStart then task.spawn(P.onSongStart, nowPlaying) end -- [FIX L1]
	warn(("[Music] retry #%d memuat: %s (%s)")
		:format(retryUsed, tostring(nowPlaying.Name), tostring(nowPlaying.RawId or id)))
end

local function markUnavailable(tk, song)
	warn("[Music] gagal dimuat (dikonfirmasi", countKeys(repFail), "client):",
		song.Name, "| ID:", song.RawId or "?")
	Shared.all("SongUnavailable", { name = song.Name or "?", id = song.Id or "" })
	pcall(function() sound:Stop() end)

	if Library.markFail(song) then
		P.removeFromQueueById(song.Id)
		Library.broadcast()
		P.broadcastQueue()
		P.broadcastIds()
		Library.saveNow()
		local note = '"' .. (song.Name or "?") .. '" marked unavailable (failed twice). Data is kept.'
		Shared.filtered(isAdminPlayer, "SongAutoRemoved", note)
	end
	advance(tk, "gagal load", true)
end

local function watchdog(tk, song)
	local loadDeadline = os.clock() + LOAD_TIMEOUT

	while true do
		task.wait(TICK)
		if tk ~= token or not playing then return end

		local d = safeRead(sound, "TimeLength", 0)
		if type(d) == "number" and d > serverDur and d < MAX_DUR then serverDur = d end
		recomputeDuration()

		local el  = os.clock() - startClock
		local pos = bestPos()

		if duration > 1 then
			if pos and pos >= duration - 0.3 then
				advance(tk, "posisi client mencapai akhir")
				return
			end
			if el >= duration + startLag + END_GRACE then
				advance(tk, "watchdog jam dinding")
				return
			end

		elseif os.clock() >= loadDeadline then
			if pos then
				-- Ada client yang jelas sedang memutar: jangan hakimi.
			elseif #Players:GetPlayers() == 0 then
				-- Tidak ada pendengar: tunda penilaian, JANGAN matikan watchdog.
				loadDeadline = os.clock() + LOAD_TIMEOUT
			elseif failConfirmed() then
				if retryUsed < MAX_RETRY then
					retryUsed += 1
					replayCurrent(tk)
					loadDeadline = os.clock() + LOAD_TIMEOUT
				else
					markUnavailable(tk, song)
					return
				end
			elseif os.clock() - warnedAt > 30 then
				warnedAt = os.clock()
				warn("[Music] durasi tak diketahui & tak ada laporan client:", song.Name)
			end
		end

		-- Jaring pengaman terakhir; ikut memanjang untuk lagu/mix yang panjang.
		local hardLimit = (duration > 1) and (duration + 180) or HARD_TIMEOUT
		if el > hardLimit then
			advance(tk, "hard timeout", true)
			return
		end
	end
end

-- Ended di server = event per-mesin, bukan bukti audio pemain sudah habis.
local function onEnded(tk)
	if tk ~= token or not playing then return end
	local el  = os.clock() - startClock
	local pos = bestPos()

	if pos and duration > 1 and pos < duration - SPURIOUS_GAP then
		warn(("[Music] Ended server diabaikan: client masih di %.1fs / %.1fs"):format(pos, duration))
		tryResume(el)
		return
	end

	if duration <= 1 then
		if el < MIN_PLAY_TIME or pos then
			warn(("[Music] Ended server di %.1fs, durasi belum diketahui -> diabaikan"):format(el))
			tryResume(el)
			return
		end
		advance(tk, "Ended server tanpa durasi")
		return
	end

	if el < duration - SPURIOUS_GAP then
		warn(("[Music] Ended kepagian (%.1fs / %.1fs), coba resume"):format(el, duration))
		tryResume(el)
		return
	end

	advance(tk, "Sound.Ended")
end

-- [FIX A1] AUTO PLAY. Antrian kosong → lagu acak dari library global.
-- Tidak mengulang RECENT_MAX lagu terakhir (kalau library kecil, aturan ini
-- dilonggarkan), melewati lagu `unavailable`, dan tidak jalan tanpa pemain.
-- Lagu pemain selalu didahulukan karena hanya dipakai saat antrian kosong.
local RECENT_MAX = 20
local recent = {}

local function remember(id)
	if not id then return end
	for i = #recent, 1, -1 do
		if recent[i] == id then table.remove(recent, i) end
	end
	table.insert(recent, 1, id)
	if #recent > RECENT_MAX then table.remove(recent) end
end

local function pickAuto()
	if not (Shared.spatial and Shared.spatial.autoplay) then return nil end
	if #Players:GetPlayers() == 0 then return nil end
	local skip = {}
	for _, id in ipairs(recent) do skip[id] = true end
	local fresh, any = {}, {}
	for _, s in ipairs(Library.all()) do
		if not s.unavailable and s.Id then
			table.insert(any, s)
			if not skip[s.Id] then table.insert(fresh, s) end
		end
	end
	local pool = (#fresh > 0) and fresh or any
	if #pool == 0 then return nil end
	local s = pool[math.random(#pool)]
	return {
		Name = s.Name, Id = s.Id, RawId = s.RawId or rawOf(s.Id),
		thumbnailUrl = s.thumbnailUrl or "",
		creatorType = s.creatorType, AudioCreator = s.AudioCreator,
		Requester = "Auto play", RequesterId = 0,
		LibOwner = s.Requester, auto = true,
	}
end
function P.play(song)
	if not song or not song.Id then
		playing = false; task.defer(P.next); return
	end
	local id = normalizeId(song.Id)
	if not id then
		playing = false; task.defer(P.next); return
	end

	-- Lagu yang sudah ditandai tidak tersedia: lewati, jangan bikin macet.
	local _, libSong = Library.find(song.Id)
	if libSong and libSong.unavailable then
		warn("[Music] lewati lagu unavailable:", song.Name)
		Shared.all("SongUnavailable", { name = song.Name or "?", id = song.Id })
		playing = false; task.defer(P.next); return
	end

	if not sound or not sound.Parent then P.init() end

	token     += 1
	local tk   = token
	nowPlaying = song
	remember(song.Id) -- [FIX A1]
	playing    = true
	skipVotes  = {}
	startClock = os.clock()
	resumeUsed = 0
	retryUsed  = 0
	okMarked   = false
	duration, durSource = 0, "?"
	resetReports()

	if endedConn then endedConn:Disconnect(); endedConn = nil end

	local ok = pcall(function()
		sound:Stop()
		sound.TimePosition = 0
		sound.SoundId      = id
		sound:Play()
	end)
	if not ok then
		playing = false; task.defer(P.next); return
	end

	P.applyLoudness()
	endedConn = sound.Ended:Connect(function() onEnded(tk) end)

	Shared.all("NowPlaying", song)
	if P.onSongStart then task.spawn(P.onSongStart, song) end -- [FIX L1] lapor ke siaran live
	Shared.all("SkipVoteUpdate", P.votes())
	P.broadcastIds()

	print(("[Music] play: %s (%s)"):format(tostring(song.Name), tostring(song.RawId or song.Id)))
	task.spawn(watchdog, tk, song)
end

function P.next()
	playing    = false
	nowPlaying = nil
	duration, durSource = 0, "?"
	resetReports()

	local song = table.remove(queue, 1) or pickAuto() -- [FIX A1] antrian kosong → auto play
	if song then
		P.broadcastQueue()
		P.play(song)
	else
		skipVotes = {}
		if endedConn then endedConn:Disconnect(); endedConn = nil end
		pcall(function() sound:Stop() end)
		Shared.all("NowPlaying",     { Name = "No song playing", Requester = "" })
		Shared.all("SkipVoteUpdate", P.votes())
		Shared.all("SongStopped",    true)
		if P.onSongStart then task.spawn(P.onSongStart, nil) end -- [FIX L1]
		P.broadcastIds()
	end
end

-- Skip halus: client fade-out dulu, baru ganti lagu. `consumed` dikunci ke
-- token sekarang supaya Ended/watchdog yang fire barengan tidak double-skip.
function P.skip()
	if transitioning then return end
	if not playing then P.next(); return end
	transitioning = true
	consumed      = token
	print("[Music] skip manual")
	Shared.all("MusicFade", { to = 0, dur = FADE_OUT })
	task.delay(FADE_OUT, function()
		transitioning = false
		pcall(function() sound:Stop() end)
		P.next()
	end)
end

function P.voteSkip(p)
	if not playing then return Shared.to(p, "SkipError", "Nothing is playing") end
	if table.find(skipVotes, p) then return Shared.to(p, "SkipError", "Already voted") end
	table.insert(skipVotes, p)
	local state = P.votes()
	Shared.all("SkipVoteUpdate", state)
	if state.current >= state.required then
		skipVotes = {}
		P.skip()
	end
end

function P.clearVote(p)
	repPos[p.UserId]  = nil
	repFail[p.UserId] = nil
	repLen[p.UserId]  = nil
	for i = #skipVotes, 1, -1 do
		if skipVotes[i] == p then
			table.remove(skipVotes, i)
			Shared.all("SkipVoteUpdate", P.votes())
			return
		end
	end
end

function P.resetVotes() skipVotes = {} end

return P