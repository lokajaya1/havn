-- DancePlayer — ServerScriptService > Misc (ModuleScript, khusus server)
-- Memutar, mengganti, mengubah speed, dan menghentikan dance satu karakter.
-- Track TIDAK dimuat di sini: DanceHandler memberikan track dari cache LRU
-- miliknya (yang sudah ditunggu sampai termuat), jadi satu dance = satu track
-- per karakter. Menggantikan SmoothDanceHelper + SmoothDanceManager.
--
-- Satu "slot" per pemain: { current = track yang terakhir diputar, speedConn }.

local RunService = game:GetService("RunService")

local DancePlayer = {}

-- Tween speed bawaan saat dance yang sama diminta lagi lewat play().
DancePlayer.SAME_TRACK_SPEED_TIME = 0.15

function DancePlayer.newSlot()
	return { current = nil, speedConn = nil }
end

local function stopSpeedTween(slot)
	if slot.speedConn then
		slot.speedConn:Disconnect()
		slot.speedConn = nil
	end
end

-- Ubah speed track yang sedang main; smoothTime > 0 = cosine ease per Heartbeat.
-- false kalau tidak ada dance yang main.
function DancePlayer.setSpeed(slot, newSpeed, smoothTime)
	local track = slot.current
	if not track or not track.IsPlaying then return false end

	stopSpeedTween(slot)

	if smoothTime and smoothTime > 0 then
		local startSpeed = track.Speed
		local startTime  = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not track.IsPlaying then
				conn:Disconnect()
				if slot.speedConn == conn then slot.speedConn = nil end
				return
			end

			local progress = math.min((os.clock() - startTime) / smoothTime, 1)
			local t        = 0.5 * (1 - math.cos(progress * math.pi))
			track:AdjustSpeed(startSpeed + (newSpeed - startSpeed) * t)

			if progress >= 1 then
				conn:Disconnect()
				if slot.speedConn == conn then slot.speedConn = nil end
			end
		end)
		slot.speedConn = conn
	else
		track:AdjustSpeed(newSpeed)
	end

	return true
end

-- options: fadeIn, fadeOut, speed. Track sama yang masih main → hanya speed.
function DancePlayer.play(slot, track, options)
	if not track then return false end
	options = options or {}
	local speed = options.speed or 1.0

	if slot.current == track and track.IsPlaying then
		if math.abs(speed - track.Speed) > 0.01 then
			DancePlayer.setSpeed(slot, speed, DancePlayer.SAME_TRACK_SPEED_TIME)
		end
		return true
	end

	local old = slot.current
	if old and old ~= track and old.IsPlaying then
		old:Stop(options.fadeOut or 0.5)
	end

	slot.current = track
	track:Play(options.fadeIn or 0.5, 1.0, speed)
	return true
end

-- false kalau tidak ada dance yang main (pemanggil lalu memakai jalur cadangan).
function DancePlayer.stop(slot, fadeTime)
	local track = slot.current
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.5)
		slot.current = nil
		return true
	end
	return false
end

-- Respawn / keluar: lupakan track lama (track-nya dibersihkan cache DanceHandler).
function DancePlayer.reset(slot)
	stopSpeedTween(slot)
	local track = slot.current
	slot.current = nil
	if track then pcall(function() track:Stop(0) end) end
end

return DancePlayer
