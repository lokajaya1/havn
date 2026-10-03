-- ═══════════════════════════════════════════════════════════
-- CommunityInfo — ReplicatedStorage > CustomUIModules (ModuleScript)
--
-- Menyediakan data Primary Community seorang user ke UI, plus
-- preferensi on/off yang dipakai toggle di menu Players.
--
-- API:
--   CommunityInfo.ApplyTo(gui, userId)   isi background + label
--   CommunityInfo.Get(userId)            data mentah (yields) → data, perluCobaLagi
--   CommunityInfo.IsEnabled() / SetEnabled(bool)
--   CommunityInfo.Changed                event saat preferensi berubah
--   CommunityInfo.Refresh()              render ulang target terakhir
--
-- Server menjawab "retry" (dibatasi / GroupService error) → hasil TIDAK
-- di-cache dan ApplyTo mencoba lagi (Config/Social COMMUNITY.CLIENT_RETRY).
-- Set DEBUG = true kalau perlu menelusuri kenapa background kosong.
-- ═══════════════════════════════════════════════════════════

local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(RS:WaitForChild("Config"):WaitForChild("Social")).COMMUNITY

local DEBUG = false
local THUMB_SIZE = 150       -- GroupIcon hanya mendukung 150 atau 420
local BG_TRANSPARENCY = 0.55 -- makin besar makin samar
local CACHE_TTL = Config.CLIENT_TTL

local CommunityInfo = {}

local cache, inflight = {}, {}
local token = 0
local enabled = true
local lastGui, lastUserId
local warnedNoRemote = false

local changedEvent = Instance.new("BindableEvent")
CommunityInfo.Changed = changedEvent.Event

local function log(...)
	if DEBUG then print("[CommunityInfo]", ...) end
end

-- ── Remotes ────────────────────────────────────────────────

local function getRemote(name, timeout)
	local remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", timeout or 10)
	if not remotes then
		if not warnedNoRemote then
			warnedNoRemote = true
			warn("[CommunityInfo] ReplicatedStorage.Remotes tidak ada. Pastikan CommunityInfoService jalan di ServerScriptService.")
		end
		return nil
	end
	local remote = remotes:FindFirstChild(name) or remotes:WaitForChild(name, timeout or 10)
	if not remote and not warnedNoRemote then
		warnedNoRemote = true
		warn("[CommunityInfo] Remote '" .. name .. "' tidak ditemukan.")
	end
	return remote
end

-- ── Preferensi ─────────────────────────────────────────────

task.spawn(function()
	local rf = getRemote("GetCommunityPref", 15)
	if not rf then return end
	local ok, value = pcall(function() return rf:InvokeServer() end)
	if ok and type(value) == "boolean" and value ~= enabled then
		enabled = value
		changedEvent:Fire(enabled)
		CommunityInfo.Refresh()
	end
end)

function CommunityInfo.IsEnabled()
	return enabled
end

function CommunityInfo.SetEnabled(value)
	value = value and true or false
	if value == enabled then return end
	enabled = value
	changedEvent:Fire(enabled)
	CommunityInfo.Refresh()

	task.spawn(function()
		local ev = getRemote("SetCommunityPref", 5)
		if ev then pcall(function() ev:FireServer(enabled) end) end
	end)
end

-- ── Fetch ──────────────────────────────────────────────────

function CommunityInfo.Get(userId)
	if type(userId) ~= "number" then return nil end

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

	-- retry = server membatasi / GroupService error / remote gagal → jangan di-cache
	local data, retry = nil, false
	local rf = getRemote("GetPrimaryCommunity", 10)
	if rf then
		local ok, result, flag = pcall(function() return rf:InvokeServer(userId) end)
		if ok then
			if type(result) == "table" then
				data = result
			elseif result == nil and flag == "retry" then
				retry = true
				log("server minta coba lagi untuk userId", userId)
			else
				log("tidak ada community untuk userId", userId)
			end
		else
			retry = true
			warn("[CommunityInfo] InvokeServer gagal:", result)
		end
	else
		retry = true
	end

	if not retry then
		cache[userId] = { data = data or false, t = os.clock() }
	end

	waiters = inflight[userId]
	inflight[userId] = nil
	for _, thread in ipairs(waiters) do
		task.spawn(thread, data, retry)
	end

	return data, retry
end

-- ── Apply ke UI ────────────────────────────────────────────

local function findNodes(gui)
	if not gui then return nil, nil end
	return gui:FindFirstChild("CommunityBackground", true), gui:FindFirstChild("CommunityLabel", true)
end

function CommunityInfo.ApplyTo(gui, userId)
	lastGui, lastUserId = gui, userId

	local bg, label = findNodes(gui)
	if not bg and not label then
		log("CommunityBackground/CommunityLabel tidak ditemukan di", gui and gui:GetFullName())
		return
	end

	token += 1
	local myToken = token

	if bg then
		bg.Image = ""
		bg.ImageTransparency = 1
	end
	if label then label.Text = "" end

	if not enabled or type(userId) ~= "number" then return end

	task.spawn(function()
		local info, retry = CommunityInfo.Get(userId)
		for _, delay in ipairs(Config.CLIENT_RETRY) do
			if not retry or myToken ~= token or not enabled then break end
			task.wait(delay)
			if myToken ~= token or not enabled then return end
			info, retry = CommunityInfo.Get(userId)
		end
		if myToken ~= token or not enabled then return end
		if not info or not info.groupId then return end

		if bg and bg.Parent then
			bg.Image = string.format(
				"rbxthumb://type=GroupIcon&id=%d&w=%d&h=%d",
				info.groupId, THUMB_SIZE, THUMB_SIZE
			)
			TweenService:Create(
				bg,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageTransparency = BG_TRANSPARENCY }
			):Play()
		end

		if label and label.Parent then
			label.Text = info.role and (info.name .. "  ·  " .. info.role) or info.name
		end

		log("applied", info.name, info.groupId, info.fallback and "(fallback)" or "(primary)")
	end)
end

function CommunityInfo.Refresh()
	if lastGui then
		CommunityInfo.ApplyTo(lastGui, lastUserId)
	end
end

function CommunityInfo.Invalidate(userId)
	cache[userId] = nil
end

return CommunityInfo