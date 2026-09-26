-- ═══════════════════════════════════════════════════════════
-- CommunityInfoService — ServerScriptService
--
-- Remote yang dibuat otomatis di ReplicatedStorage.Remotes:
--   GetPrimaryCommunity (RemoteFunction) → {groupId, name, rank, role, fallback}
--   GetCommunityPref    (RemoteFunction) → boolean
--   SetCommunityPref    (RemoteEvent)    ← boolean
--
-- GroupService:GetGroupsAsync adalah web-call dan kena rate limit,
-- jadi hasilnya di-cache, request bersamaan di-dedupe, dan tiap
-- player punya cooldown. Preferensi ditulis ke DataStore saat player
-- keluar / server shutdown, bukan setiap kali toggle diklik.
-- ═══════════════════════════════════════════════════════════

local GroupService = game:GetService("GroupService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CACHE_TTL = 600
local PLAYER_COOLDOWN = 0.4
local DEFAULT_PREF = true

-- Kalau user belum mengatur Primary Community di profilnya, pakai
-- community pertama yang dia ikuti. Set false untuk primary saja.
local USE_FIRST_GROUP_FALLBACK = true

local prefStore
do
	local storeName = RunService:IsStudio() and "CommunityPref_studio" or "CommunityPref"
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	prefStore = ok and store or nil
	if not prefStore then
		warn("[CommunityInfoService] DataStore tidak tersedia — preferensi jadi session-only.")
	end
end

-- ── Remote setup ────────────────────────────────────────────

local function ensure(parent, class, name)
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end

local remotes = ensure(RS, "Folder", "Remotes")
local getCommunity = ensure(remotes, "RemoteFunction", "GetPrimaryCommunity")
local getPref = ensure(remotes, "RemoteFunction", "GetCommunityPref")
local setPref = ensure(remotes, "RemoteEvent", "SetCommunityPref")

-- ── Community lookup ────────────────────────────────────────

local cache, inflight, cooldown = {}, {}, {}

local function pack(groupInfo, isFallback)
	return {
		groupId = groupInfo.Id,
		name = groupInfo.Name,
		rank = groupInfo.Rank,
		role = groupInfo.Role,
		fallback = isFallback or nil,
	}
end

local function fetch(userId)
	local hit = cache[userId]
	if hit and (os.clock() - hit.t) < CACHE_TTL then
		return hit.data or nil
	end

	local waiters = inflight[userId]
	if waiters then
		table.insert(waiters, coroutine.running())
		return coroutine.yield()
	end
	inflight[userId] = {}

	local data = nil
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(userId)
	end)

	if ok and type(groups) == "table" then
		for _, groupInfo in ipairs(groups) do
			if groupInfo.IsPrimary then
				data = pack(groupInfo, false)
				break
			end
		end
		if not data and USE_FIRST_GROUP_FALLBACK and groups[1] then
			data = pack(groups[1], true)
		end
	elseif not ok then
		warn("[CommunityInfoService] GetGroupsAsync gagal untuk", userId, "-", groups)
	end

	cache[userId] = { data = data or false, t = os.clock() }

	waiters = inflight[userId]
	inflight[userId] = nil
	for _, thread in ipairs(waiters) do
		task.spawn(thread, data)
	end

	return data
end

getCommunity.OnServerInvoke = function(player, userId)
	if type(userId) ~= "number" or userId ~= userId or userId < 1 or userId % 1 ~= 0 then
		return nil
	end

	local now = os.clock()
	local last = cooldown[player]
	if last and (now - last) < PLAYER_COOLDOWN then
		local hit = cache[userId]
		return hit and hit.data or nil
	end
	cooldown[player] = now

	return fetch(userId)
end

-- ── Preferensi ──────────────────────────────────────────────

local prefs, dirty = {}, {}

local function loadPref(player)
	local value = DEFAULT_PREF
	if prefStore then
		local ok, stored = pcall(function()
			return prefStore:GetAsync("u_" .. player.UserId)
		end)
		if ok and type(stored) == "boolean" then value = stored end
	end
	if prefs[player] == nil then prefs[player] = value end
	return prefs[player]
end

local function savePref(player)
	if not prefStore or not dirty[player] then return end
	local value = prefs[player]
	dirty[player] = nil
	pcall(function()
		prefStore:SetAsync("u_" .. player.UserId, value)
	end)
end

getPref.OnServerInvoke = function(player)
	local cached = prefs[player]
	if cached ~= nil then return cached end
	return loadPref(player)
end

setPref.OnServerEvent:Connect(function(player, value)
	if type(value) ~= "boolean" or prefs[player] == value then return end
	prefs[player] = value
	dirty[player] = true
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPref, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPref, player)
end

Players.PlayerRemoving:Connect(function(player)
	cooldown[player] = nil
	savePref(player)
	prefs[player] = nil
	dirty[player] = nil
end)

game:BindToClose(function()
	for player in pairs(dirty) do
		savePref(player)
	end
end)

-- ── Housekeeping ────────────────────────────────────────────

task.spawn(function()
	while true do
		task.wait(300)
		local now = os.clock()
		for userId, entry in pairs(cache) do
			if (now - entry.t) > CACHE_TTL then
				cache[userId] = nil
			end
		end
	end
end)

print("[CommunityInfoService] Ready")