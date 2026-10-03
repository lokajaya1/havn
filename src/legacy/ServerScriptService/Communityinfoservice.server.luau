-- ═══════════════════════════════════════════════════════════
-- CommunityInfoService — ServerScriptService
--
-- Remote yang dibuat otomatis di ReplicatedStorage.Remotes:
--   GetPrimaryCommunity (RemoteFunction) → {groupId, name, rank, role, fallback} | false | nil, "retry"
--   GetCommunityPref    (RemoteFunction) → boolean
--   SetCommunityPref    (RemoteEvent)    ← boolean
--
-- GroupService:GetGroupsAsync adalah web-call dan kena rate limit (kuotanya dipakai juga oleh
-- UnifiedRankManager), jadi: hanya untuk pemain yang ADA di server ini (kartu pemain), hasil
-- di-cache, request bersamaan di-dedupe, dan tiap pemain dibatasi token bucket (Config/Social).
-- Hasil: tabel = punya komunitas · false = tidak punya · nil, "retry" = dibatasi / GroupService
-- error (error di-cache sebentar saja, FAIL_TTL). Preferensi ditulis ke DataStore saat pemain
-- keluar / server shutdown; satu GetAsync per pemain (panggilan lain menunggu hasil yang sama).
-- Ruangan SOCIAL: claude/Rencana_Social.md.
-- ═══════════════════════════════════════════════════════════

local GroupService = game:GetService("GroupService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(RS:WaitForChild("Config"):WaitForChild("Social")).COMMUNITY
local SocialRules = require(RS:WaitForChild("Modules"):WaitForChild("SocialRules"))
local ToolRules = require(RS:WaitForChild("Modules"):WaitForChild("ToolRules"))

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

-- token bucket per pemain per remote (dibuat saat pertama dipakai, dibuang saat keluar)
local buckets = { community = {}, getPref = {}, setPref = {} }

local function allow(kind, player, rate, burst)
	local list = buckets[kind]
	local b = list[player]
	if not b then
		b = ToolRules.bucket(rate, burst)
		list[player] = b
	end
	return ToolRules.take(b, os.clock())
end

-- ── Community lookup ────────────────────────────────────────

-- cache[userId] = { data = tabel | false | nil (error), expires = os.clock() }
local cache, inflight = {}, {}

local function pack(groupInfo, isFallback)
	return {
		groupId = groupInfo.Id,
		name = groupInfo.Name,
		rank = groupInfo.Rank,
		role = groupInfo.Role,
		fallback = isFallback or nil,
	}
end

-- tabel = komunitas · false = tidak punya komunitas · nil = GroupService error
local function fetch(userId)
	local hit = cache[userId]
	if hit and os.clock() < hit.expires then
		return hit.data
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
		data = false
		for _, groupInfo in ipairs(groups) do
			if groupInfo.IsPrimary then
				data = pack(groupInfo, false)
				break
			end
		end
		if not data and USE_FIRST_GROUP_FALLBACK and groups[1] then
			data = pack(groups[1], true)
		end
		cache[userId] = { data = data, expires = os.clock() + Config.CACHE_TTL }
	else
		if not ok then
			warn("[CommunityInfoService] GetGroupsAsync gagal untuk", userId, "-", groups)
		end
		cache[userId] = { data = nil, expires = os.clock() + Config.FAIL_TTL }
	end

	waiters = inflight[userId]
	inflight[userId] = nil
	for _, thread in ipairs(waiters) do
		task.spawn(thread, data)
	end

	return data
end

getCommunity.OnServerInvoke = function(player, userId)
	-- Kartu pemain hanya untuk pemain di server ini → userId lain tidak diteruskan ke GroupService.
	if not SocialRules.validUserId(userId) or not Players:GetPlayerByUserId(userId) then
		return nil
	end

	local hit = cache[userId]
	if hit and os.clock() < hit.expires and hit.data ~= nil then
		return hit.data -- dari cache: tidak memakai kuota pemain
	end

	if not allow("community", player, Config.RATE, Config.BURST) then
		return nil, "retry"
	end

	local data = fetch(userId)
	if data == nil then
		return nil, "retry"
	end
	return data
end

-- ── Preferensi ──────────────────────────────────────────────

local prefs, dirty, loading = {}, {}, {}

-- Satu GetAsync per pemain: panggilan yang datang selagi memuat menunggu hasil yang sama.
local function loadPref(player)
	if prefs[player] ~= nil then
		return prefs[player]
	end
	local waiters = loading[player]
	if waiters then
		table.insert(waiters, coroutine.running())
		return coroutine.yield()
	end
	loading[player] = {}

	local value = DEFAULT_PREF
	if prefStore then
		local ok, stored = pcall(function()
			return prefStore:GetAsync("u_" .. player.UserId)
		end)
		if ok and type(stored) == "boolean" then
			value = stored
		end
	end

	waiters = loading[player]
	loading[player] = nil
	if player.Parent ~= nil then -- pemain keluar selagi memuat → tidak disimpan di memori
		if prefs[player] == nil then
			prefs[player] = value
		end
		value = prefs[player]
	end
	for _, thread in ipairs(waiters) do
		task.spawn(thread, value)
	end
	return value
end

local function savePref(player)
	if not prefStore or not dirty[player] then
		return
	end
	local value = prefs[player]
	dirty[player] = nil
	pcall(function()
		prefStore:SetAsync("u_" .. player.UserId, value)
	end)
end

getPref.OnServerInvoke = function(player)
	local cached = prefs[player]
	if cached ~= nil then
		return cached
	end
	if not allow("getPref", player, Config.PREF_RATE, Config.PREF_BURST) then
		return nil
	end
	return loadPref(player)
end

setPref.OnServerEvent:Connect(function(player, value)
	if type(value) ~= "boolean" then
		return
	end
	if not allow("setPref", player, Config.PREF_SET_RATE, Config.PREF_SET_BURST) then
		return
	end
	if prefs[player] == value then
		return
	end
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
	for _, list in pairs(buckets) do
		list[player] = nil
	end
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
		task.wait(Config.CLEAN_EVERY)
		local now = os.clock()
		for userId, entry in pairs(cache) do
			if now >= entry.expires then
				cache[userId] = nil
			end
		end
	end
end)
