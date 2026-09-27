-- ServerScriptService/ServerList  (Script)
-- DAFTAR SERVER HAVN + pindah server.
--   * Tiap server mendaftarkan diri ke MemoryStore SortedMap "HavnServers"
--     (kunci = JobId) tiap REFRESH dtk dan saat pemain masuk/keluar.
--     Server mati → entri kedaluwarsa sendiri dalam EXPIRE dtk.
--   * Client meminta daftar lewat RemoteFunction (jeda per pemain), server
--     menyimpan hasil baca CACHE_TTL dtk supaya kuota MemoryStore hemat.
--   * Pindah server divalidasi server (ada, belum penuh, bukan server ini),
--     lalu TeleportAsync ke instance tujuan.
-- Server privat (reserved/VIP) dan sesi Studio tidak masuk daftar publik.

local Players         = game:GetService("Players")
local MSS             = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local RS              = game:GetService("ReplicatedStorage")
local SSS             = game:GetService("ServerScriptService")
local HttpService     = game:GetService("HttpService")
local RunService      = game:GetService("RunService")

local MAP_NAME      = "HavnServers"
local EXPIRE        = 90   -- dtk; entri hilang kalau server tidak memperbarui
local REFRESH       = 30   -- dtk
local CACHE_TTL     = 10   -- dtk; hasil baca daftar dipakai bersama
local LIST_COOLDOWN = 3    -- dtk per pemain
local JOIN_COOLDOWN = 10   -- dtk per pemain
local MAX_AVATARS   = 8
local MAX_SERVERS   = 200  -- batas satu GetRangeAsync

local IS_STUDIO = RunService:IsStudio()
local IS_PRIVATE = game.PrivateServerId ~= ""
local jobId = (game.JobId ~= "" and game.JobId) or ("studio-" .. HttpService:GenerateGUID(false))
local startedAt = os.time()
local map = MSS:GetSortedMap(MAP_NAME)

-- ── remote ────────────────────────────────────────────────────────────────
local folder = RS:FindFirstChild("ServerListRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ServerListRemotes"
	folder.Parent = RS
end
local function remote(className, name)
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end
local getFn    = remote("RemoteFunction", "GetServers")
local joinEv   = remote("RemoteEvent",    "JoinServer")
local noticeEv = remote("RemoteEvent",    "Notice")

local function notice(p, text)
	if p and p.Parent then pcall(noticeEv.FireClient, noticeEv, p, text) end
end

-- ── status LIVE musik (opsional) ──────────────────────────────────────────
local Live
task.spawn(function()
	local ms = SSS:WaitForChild("MusicServer", 30)
	local mod = ms and ms:WaitForChild("Live", 30)
	if mod then
		local ok, m = pcall(require, mod)
		if ok and type(m) == "table" then Live = m end
	end
end)
local function liveHere()
	return Live ~= nil and Live.isActive ~= nil and Live.isActive() == true
end

-- ── pendaftaran server ini ────────────────────────────────────────────────
local function snapshot()
	local uids = {}
	for i, p in ipairs(Players:GetPlayers()) do
		if i > MAX_AVATARS then break end
		table.insert(uids, p.UserId)
	end
	return {
		id = jobId, n = #Players:GetPlayers(), max = Players.MaxPlayers,
		up = startedAt, ver = game.PlaceVersion, live = liveHere(),
		uids = uids, t = os.time(), studio = IS_STUDIO,
	}
end

local function publish()
	if IS_PRIVATE then return end
	local ok, err = pcall(map.SetAsync, map, jobId, snapshot(), EXPIRE)
	if not ok then warn("[ServerList] gagal mendaftar:", err) end
end

local pubQueued = false
local function publishSoon()
	if pubQueued then return end
	pubQueued = true
	task.delay(3, function()
		pubQueued = false
		publish()
	end)
end

Players.PlayerAdded:Connect(publishSoon)
Players.PlayerRemoving:Connect(publishSoon)

task.spawn(function()
	task.wait(2)
	while true do
		publish()
		task.wait(REFRESH)
	end
end)

game:BindToClose(function()
	if IS_PRIVATE then return end
	pcall(map.RemoveAsync, map, jobId)
end)

-- ── baca daftar (dipakai bersama semua pemain di server ini) ──────────────
local cache, cacheAt, reading = {}, -math.huge, false

local function readList()
	if os.clock() - cacheAt < CACHE_TTL then return cache end
	if reading then
		local t0 = os.clock()
		while reading and os.clock() - t0 < 10 do task.wait(0.1) end
		return cache
	end
	reading = true
	local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, MAX_SERVERS)
	reading = false
	if not ok then
		warn("[ServerList] gagal membaca daftar:", items)
		return cache
	end
	local out, now = {}, os.time()
	for _, item in ipairs(items) do
		local v = item.value
		if type(v) == "table" and type(v.id) == "string"
			and (now - (tonumber(v.t) or 0)) <= EXPIRE
			and (v.studio == true) == IS_STUDIO then
			table.insert(out, v)
		end
	end
	cache, cacheAt = out, os.clock()
	return cache
end

-- Daftar untuk client: server ini selalu ada dengan data terbaru.
local function listFor()
	local list, seen = {}, false
	for _, v in ipairs(readList()) do
		if v.id == jobId then seen = true; table.insert(list, snapshot())
		else table.insert(list, v) end
	end
	if not seen and not IS_PRIVATE then table.insert(list, snapshot()) end
	return list
end

local lastList, lastJoin = {}, {}

getFn.OnServerInvoke = function(p)
	local now = os.clock()
	if lastList[p] and now - lastList[p] < LIST_COOLDOWN then
		return { ok = false, wait = true, self = jobId }
	end
	lastList[p] = now
	return { ok = true, self = jobId, list = listFor() }
end

-- ── pindah server ─────────────────────────────────────────────────────────
joinEv.OnServerEvent:Connect(function(p, targetId)
	if type(targetId) ~= "string" or #targetId < 8 or #targetId > 64 then return end
	local now = os.clock()
	if lastJoin[p] and now - lastJoin[p] < JOIN_COOLDOWN then
		return notice(p, ("Please wait %ds"):format(math.ceil(JOIN_COOLDOWN - (now - lastJoin[p]))))
	end
	if targetId == jobId then return notice(p, "You are already in this server") end

	local target
	for _, v in ipairs(readList()) do
		if v.id == targetId then target = v; break end
	end
	if not target then return notice(p, "Server not found, refresh the list") end
	if (tonumber(target.n) or 0) >= (tonumber(target.max) or 0) then return notice(p, "Server is full") end
	if IS_STUDIO then return notice(p, "Teleport does not work in Studio") end

	lastJoin[p] = now
	notice(p, "Teleporting...")
	local opts = Instance.new("TeleportOptions")
	opts.ServerInstanceId = targetId
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { p }, opts)
	if not ok then
		warn("[ServerList] teleport gagal:", err)
		notice(p, "Teleport failed, try again")
	end
end)

TeleportService.TeleportInitFailed:Connect(function(p, result, msg)
	warn("[ServerList] TeleportInitFailed:", p and p.Name, result, msg)
	notice(p, "Teleport failed: " .. tostring(result and result.Name or msg))
end)

Players.PlayerRemoving:Connect(function(p)
	lastList[p], lastJoin[p] = nil, nil
end)

print(("[ServerList] Ready | server %s | %s"):format(string.sub(jobId, 1, 13), IS_PRIVATE and "private (not listed)" or "listed"))
