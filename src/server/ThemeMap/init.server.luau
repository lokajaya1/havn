-- ServerScriptService/ThemeMap (Script) — tema map yang di-switch admin (themeMap, claude/Rencana_Tema.md).
--   * Aset   : ServerStorage.ThemeMap.<tema> (dibangun MapGen di Studio: G.themeMap("<tema>", "JALAN")), tidak direplikasi.
--   * Pasang : klon ke Workspace.ThemeMap, bertahap per anak folder; pemain yang akan tertimpa part padat dipindah dulu.
--   * Simpan : DataStore ThemeMap_v1 kunci "active" (tahan restart, server baru ikut) + MessagingService "ThemeMap"
--              {job, rev} ke server lain + baca ulang tiap Config.poll dtk. Studio memakai akhiran _studio.
--   * Remote : ReplicatedStorage.ThemeMapRemotes.Set (RemoteFunction) (id, mulai, selesai) — jeda, rank grup
--              >= RankConfig.ADMIN_MIN_RANK, daftar putih Config. State ke client lewat atribut folder itu:
--              Ready (bool), Active (id), State (JSON), Missing (JSON).
-- Logika: Service (orkestrasi, gateway disuntik) + Rules (murni). Panel admin = StarterPlayerScripts/ThemeMapAdmin (T3).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local Config = require(RS:WaitForChild("Config"):WaitForChild("ThemeMap"))
local RankConfig = require(SSS:WaitForChild("RankConfig"))
local Rules = require(script:WaitForChild("Rules"))
local Service = require(script:WaitForChild("Service"))

local suffix = if RunService:IsStudio() then Config.store.studioSuffix else ""
local jobId = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

-- ── remote ────────────────────────────────────────────────────────────────────────────────────────────────────────
local remotes = RS:FindFirstChild("ThemeMapRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "ThemeMapRemotes"
	remotes.Parent = RS
end
local setFn = remotes:FindFirstChild("Set")
if not setFn then
	setFn = Instance.new("RemoteFunction")
	setFn.Name = "Set"
	setFn.Parent = remotes
end

local svc = Service.new({
	cfg = Config,
	rules = Rules,
	store = DataStoreService:GetDataStore(Config.store.name .. suffix),
	messaging = MessagingService,
	topic = Config.topic .. suffix,
	jobId = jobId,
	assets = function()
		return SS:FindFirstChild(Config.assetFolder)
	end,
	workspace = workspace,
	players = function()
		return Players:GetPlayers()
	end,
	rankOf = function(player)
		local ok, rank = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
		return if ok then rank else nil
	end,
	adminRank = RankConfig.ADMIN_MIN_RANK,
	pivot = function(character, pos)
		character:PivotTo(CFrame.new(pos) * character:GetPivot().Rotation)
	end,
	setAttr = function(name, value)
		remotes:SetAttribute(name, value)
	end,
	json = function(value)
		return HttpService:JSONEncode(value)
	end,
	now = os.time,
	clock = os.clock,
	wait = function(sec)
		task.wait(sec)
	end,
	log = print,
	warn = warn,
})

setFn.OnServerInvoke = function(player, id, startKey, endKey)
	return svc:set(player, id, startKey, endKey)
end

Players.PlayerRemoving:Connect(function(player)
	svc:forget(player)
end)

svc:start()
print(("[ThemeMap] Ready | aktif %s | DataStore %s | %s"):format(svc.mounted or Config.default, Config.store.name .. suffix, if svc.ready then "terbaca" else "GAGAL dibaca (Default, edit ditolak)"))

task.spawn(function()
	while true do
		task.wait(Config.tick)
		local ok, err = pcall(svc.step, svc, os.clock())
		if not ok then
			warn("[ThemeMap] perawatan gagal: " .. tostring(err))
		end
	end
end)
