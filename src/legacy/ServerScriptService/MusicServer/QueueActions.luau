-- MusicServer/QueueActions  (ModuleScript)  dipindah dari init.server
-- Aksi remote antrian, skip, dan siaran live. init.server menggabungkan
-- `handlers` ke tabel Actions-nya dan memberi tabel data pemain lewat bind().

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Shared   = require(RS:WaitForChild("MusicShared"))
local Library  = require(script.Parent:WaitForChild("Library"))
local Playback = require(script.Parent:WaitForChild("Playback"))
local Live     = require(script.Parent:WaitForChild("Live"))
local Perm     = require(script.Parent:WaitForChild("Permissions"))
local checkRate = require(script.Parent:WaitForChild("RateLimit")).check
local isAdmin, isPremium, isDJ = Perm.isAdmin, Perm.isPremium, Perm.isDJ
local liveBlocks, skipBlocked = Perm.liveBlocks, Perm.skipBlocked

local playerData = {} -- diganti tabel milik init.server lewat M.bind()

-- ── ANTRIAN ───────────────────────────────────────────────────────────────
local function addToQueue(p, songId)
	if not songId then return end
	if liveBlocks(p) then return Shared.to(p, "QueueError", "Live: song requests are paused") end

	local ok, msg = checkRate(p, "AddQueue", Shared.addQueueCooldown)
	if not ok then return Shared.to(p, "QueueError", msg) end

	local id = tostring(songId)
	local _, song = Library.find(id)
	if not song then
		-- Boleh antre dari Library Saya walau tidak ada di library global.
		if not Library.myIsLoaded(p) then Library.myLoad(p) end
		local _, own = Library.myFind(p, id)
		song = own
	end

	if not song         then return Shared.to(p, "QueueError", "Song is not in the library") end
	if song.unavailable then return Shared.to(p, "QueueError", "Song unavailable") end

	local np = Playback.current()
	if np and np.Id == song.Id         then return Shared.to(p, "QueueError", "Already playing") end
	if Playback.queueContains(song.Id) then return Shared.to(p, "QueueError", "Already in the queue") end
	if Playback.queueFull() then
		return Shared.to(p, "QueueError", "Queue is full (" .. Shared.maxGlobalQueue .. ")")
	end

	local d = playerData[p]
	if not d then return Shared.to(p, "QueueError", "Your data is not ready yet") end
	local limit   = d.queueLimit or 1
	local myCount = Playback.queueCountBy(p.UserId)
	if myCount >= limit then
		return Shared.to(p, "QueueError",
			("Your queue limit is %d (currently %d)"):format(limit, myCount))
	end

	local entry = Playback.entry(song, p.Name, p.UserId)

	local held = Playback.isFollowing() or (Live.isActive() and p.UserId ~= Live.djId())
	if not Playback.isPlaying() and not held then -- saat ikut siaran: masuk antrian lokal
		Playback.play(entry)
		Playback.broadcastQueue()
		Playback.broadcastIds()
		return
	end

	Playback.enqueue(entry, isPremium(p), isPremium)
	Playback.broadcastQueue()
	Playback.broadcastIds()
	if held then Shared.to(p, "QueueRemoveSuccess", "Queued - on hold until the live ends") end
end

local function removeFromQueue(p, data)
	local idx = type(data) == "table" and data.index or data
	local id  = type(data) == "table" and data.id or nil
	local okRate, msg = checkRate(p, "RemoveQueue", Shared.removeQueueCooldown)
	if not okRate then return Shared.to(p, "QueueError", msg) end
	if type(idx) == "number" and idx ~= idx then return Shared.to(p, "QueueError", "Invalid index") end

	-- Non-admin boleh menghapus antrian miliknya sendiri; DJ yang sedang live boleh menghapus semua.
	if not isAdmin(p) and not (Live.isActive() and p.UserId == Live.djId()) then
		local q, target = Playback.queue(), nil
		if id then
			for _, item in ipairs(q) do
				if item.Id == tostring(id) then target = item; break end
			end
		elseif type(idx) == "number" then
			target = q[idx]
		end
		if not target or target.RequesterId ~= p.UserId then
			return Shared.to(p, "QueueError", "You can only remove your own queue items")
		end
	end

	local removed = Playback.removeFromQueue(idx, id)
	if not removed then return Shared.to(p, "QueueError", "Invalid index") end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= p and other.UserId == removed.RequesterId then
			Shared.to(other, "QueueRemoved", '"' .. (removed.Name or "?") .. '" removed by an admin')
		end
	end
	Playback.broadcastQueue()
	Playback.broadcastIds()
	Shared.to(p, "QueueRemoveSuccess", 'Removed: "' .. (removed.Name or "?") .. '"')
end

local function forceSkip(p)
	if not (isAdmin(p) or (Live.isActive() and isDJ(p))) then return Shared.to(p, "SkipError", "Admin only!") end -- DJ saat live
	if Live.isActive() and p.UserId ~= Live.djId() then return Shared.to(p, "SkipError", "Live: only the DJ can skip") end
	if Live.isFollowing() then return Shared.to(p, "SkipError", "Live: controlled by the DJ on another server") end
	Playback.resetVotes()
	Shared.all("AdminSkipped", p.Name)
	Playback.skip()
end

local function voteSkip(p)
	if skipBlocked(p) then return Shared.to(p, "SkipError", "Live: only the DJ can skip") end
	local okRate, msg = checkRate(p, "VoteSkip", Shared.voteSkipCooldown)
	if not okRate then return Shared.to(p, "SkipError", msg) end
	Playback.voteSkip(p)
end

local function setLive(p, on) -- DJ, jeda 2 dtk
	if not isDJ(p) then return Shared.to(p, "SettingsError", "DJ only!") end
	if type(on) ~= "boolean" then return end
	local okRate, msg = checkRate(p, "Live", Shared.liveToggleCooldown, true)
	if not okRate then return Shared.to(p, "SettingsError", msg) end
	task.spawn(function()
		if on then
			local ok, err = Live.start(p, Playback.current(), Playback.elapsed())
			if not ok then Shared.to(p, "SettingsError", err) end
		else
			Live.stop("dimatikan oleh " .. p.Name)
		end
	end)
end

local M = {}

function M.bind(data) playerData = data end

M.handlers = {
	AddToQueue      = addToQueue,
	RemoveFromQueue = removeFromQueue,
	VoteSkip        = voteSkip,
	ForceSkip       = forceSkip,
	SetLive         = setLive,
}

return M
