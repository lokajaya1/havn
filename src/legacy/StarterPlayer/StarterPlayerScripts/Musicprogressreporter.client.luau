-- StarterPlayer > StarterPlayerScripts > MusicProgressReporter  (LocalScript)
--
-- Server tidak me-render audio, jadi TimeLength / TimePosition / IsPlaying /
-- IsLoaded di sana tidak bisa dipercaya (semuanya "Not Replicated" dan
-- bernilai 0 selama aset belum loaded). Script ini mengirim kebenaran dari
-- mesin yang BENAR-BENAR memutar audio:
--
--   { id = "<rawId>", len = <TimeLength> }                 -- sekali, saat loaded
--   { id = "<rawId>", pos = <TimePosition>, len = <..> }   -- heartbeat tiap 3s
--   { id = "<rawId>", done = true }                        -- Ended di client
--   { id = "<rawId>", failed = true }                      -- gagal load
--
-- Playback.lua v3 memakai `pos` dan `done` untuk memutuskan akhir lagu, jadi
-- tanpa script ini server jatuh ke mode aman (menahan lagu, bukan nge-skip).
-- Script ini berdiri sendiri: tidak perlu mengubah MusicClient.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Shared = require(RS:WaitForChild("MusicShared"))
local remote = Shared.remote

-- ══ KONFIG ════════════════════════════════════════════════════════════════
local REPORT_EVERY   = 3    -- detik antar heartbeat posisi
local LOAD_TIMEOUT   = 12   -- setelah ini, kalau belum loaded -> lapor failed
local RESET_POSITION = true -- paksa TimePosition benar saat lagu ganti
-- (TimePosition tidak replikasi; kalau nilai lama
--  lagu sebelumnya tertinggal, audio bisa mulai di
--  dekat ujung lalu langsung Ended)

-- ══ UTIL ══════════════════════════════════════════════════════════════════
local soundPath
local session = 0

local function resolvePath(path)
	if not path or path == "" then return nil end
	local cur = game
	for part in tostring(path):gmatch("[^%.]+") do
		if cur == game then
			local ok, svc = pcall(function() return game:GetService(part) end)
			cur = (ok and svc) or game:FindFirstChild(part)
		else
			cur = cur:FindFirstChild(part)
		end
		if not cur then return nil end
	end
	return cur
end

local function findSound()
	local s = resolvePath(soundPath)
	if s and s:IsA("Sound") then return s end

	local stage = workspace:FindFirstChild(Shared.stageName)
	if stage then
		local x = stage:FindFirstChild(Shared.soundName)
		if x and x:IsA("Sound") then return x end
	end
	local direct = workspace:FindFirstChild(Shared.soundName)
	if direct and direct:IsA("Sound") then return direct end
	local ss = game:GetService("SoundService"):FindFirstChild(Shared.soundName)
	if ss and ss:IsA("Sound") then return ss end
	return nil
end

local function send(payload)
	pcall(function() remote:FireServer("ReportDuration", payload) end)
end

local function rawOf(v) return tostring(v or ""):match("%d+") end

-- ══ TRACKER PER LAGU ══════════════════════════════════════════════════════
local function track(np)
	session += 1
	local mine  = session
	local rawId = rawOf(np and np.Id)
	if not rawId then return end

	task.spawn(function()
		local t0 = os.clock()
		local sound

		-- Tunggu instance Sound ada DAN SoundId-nya sudah lagu ini.
		while session == mine do
			sound = findSound()
			if sound and rawOf(sound.SoundId) == rawId then break end
			if os.clock() - t0 > 20 then return end
			task.wait(0.25)
		end
		if session ~= mine or not sound then return end

		if RESET_POSITION then
			local target = tonumber(np.Elapsed) or 0
			pcall(function()
				if math.abs((sound.TimePosition or 0) - target) > 3 then
					sound.TimePosition = target
				end
			end)
		end

		local sentLen, sentFail, sentDone = false, false, false

		local endedConn = sound.Ended:Connect(function()
			if session ~= mine or sentDone then return end
			if rawOf(sound.SoundId) ~= rawId then return end
			sentDone = true
			send({ id = rawId, done = true, pos = sound.TimePosition, len = sound.TimeLength })
		end)

		local lastReport = 0
		while session == mine do
			task.wait(0.5)
			if session ~= mine then break end
			if rawOf(sound.SoundId) ~= rawId then break end

			local len = sound.TimeLength
			local loaded = sound.IsLoaded and type(len) == "number" and len > 1

			if loaded and not sentLen then
				sentLen = true
				send({ id = rawId, len = len })
			end

			if not loaded and not sentFail and (os.clock() - t0) > LOAD_TIMEOUT then
				sentFail = true
				send({ id = rawId, failed = true })
			end

			if loaded and sound.IsPlaying and (os.clock() - lastReport) >= REPORT_EVERY then
				lastReport = os.clock()
				send({ id = rawId, pos = sound.TimePosition, len = len })
			end
		end

		if endedConn then endedConn:Disconnect() end
	end)
end

-- ══ LISTENER ══════════════════════════════════════════════════════════════
remote.OnClientEvent:Connect(function(action, data)
	if action == "SoundLocation" then
		soundPath = data
	elseif action == "NowPlaying" then
		if type(data) == "table" and data.Id then
			track(data)
		else
			session += 1 -- berhenti melapor
		end
	elseif action == "SongStopped" then
		session += 1
	end
end)

-- Minta state awal (aman kalau MusicClient juga melakukannya).
task.delay(2, function()
	pcall(function() remote:FireServer("RequestState") end)
end)