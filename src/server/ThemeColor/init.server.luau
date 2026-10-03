-- ServerScriptService/ThemeColor (Script) — tema warna UI per pemain (themeColor, claude/Rencana_ThemeColor.md).
--   * Atribut Player : ThemeColor (id tema efektif) · ThemeColorPass (boleh tema berbayar). Client hanya membaca.
--   * Remote         : ReplicatedStorage.ThemeColorRemotes.Select (RemoteFunction) (id) → { ok, reason?, id }
--                      daftar putih Config, jeda Config.selectCooldown, tema berbayar wajib pass.
--   * Pass           : _G.ShopHasGamepass(player, Config.passName) (ShopServer; admin rank ≥ ShopConfig.group.adminRankMin
--                      = punya) + ServerScriptService.ShopServerEvents.OnOwnershipChanged (beli / gift di tengah game).
--   * Staf           : atribut Player Config.rankAttribute (RankInGroup) ≥ Config.freeRankMin = dianggap punya pass
--                      (Rules.rankUnlocks); berubah di tengah sesi → ikut tanpa rejoin.
--   * Simpan         : DataStore ThemeColor_v1 kunci u_<userId> = { v, id, at } (Studio: akhiran _studio), tulis
--                      menyusul ≥ Config.saveGap dtk per kunci + saat keluar / BindToClose.
-- Logika: Service (orkestrasi, gateway disuntik) + ReplicatedStorage.Modules.ThemeColor.Rules (murni).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(RS:WaitForChild("Config"):WaitForChild("ThemeColor"))
local Rules = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"):WaitForChild("Rules"))
local Service = require(script:WaitForChild("Service"))

for _, problem in Rules.validate(Config) do
	warn("[ThemeColor] Config: " .. problem)
end

local suffix = if RunService:IsStudio() then Config.store.studioSuffix else ""

-- ── remote ────────────────────────────────────────────────────────────────────────────────────────────────────────
local remotes = RS:FindFirstChild("ThemeColorRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "ThemeColorRemotes"
	remotes.Parent = RS
end
local selectFn = remotes:FindFirstChild("Select")
if not selectFn then
	selectFn = Instance.new("RemoteFunction")
	selectFn.Name = "Select"
	selectFn.Parent = remotes
end

-- Pass Themes dari ShopServer (menunggu ShopServer siap ≤ Config.passWait dtk).
local function passOwned(player): boolean
	local t0 = os.clock()
	while type(_G.ShopHasGamepass) ~= "function" and os.clock() - t0 < Config.passWait do
		task.wait(0.5)
	end
	if type(_G.ShopHasGamepass) ~= "function" then
		warn("[ThemeColor] _G.ShopHasGamepass tidak ada — tema berbayar terkunci")
		return false
	end
	local ok, owns = pcall(_G.ShopHasGamepass, player, Config.passName)
	return ok and owns == true
end

-- Staf (rank grup ≥ Config.freeRankMin) = semua tema terbuka.
local function rankOpen(player): boolean
	return Rules.rankUnlocks(Config, player:GetAttribute(Config.rankAttribute))
end

-- Rank dicek lagi SESUDAH menunggu pass: atribut rank bisa muncul selama ShopServer belum siap.
local function ownsPass(player): boolean
	if rankOpen(player) then
		return true
	end
	local owns = passOwned(player)
	return owns or rankOpen(player)
end

local svc = Service.new({
	cfg = Config,
	rules = Rules,
	store = DataStoreService:GetDataStore(Config.store.name .. suffix),
	ownsPass = ownsPass,
	setAttr = function(player, name, value)
		if player.Parent then
			player:SetAttribute(name, value)
		end
	end,
	now = os.time,
	clock = os.clock,
	wait = function(sec)
		task.wait(sec)
	end,
	spawn = function(fn)
		task.spawn(fn)
	end,
	log = print,
	warn = warn,
})

selectFn.OnServerInvoke = function(player, id)
	return svc:select(player, id)
end

-- Rank grup berubah di tengah sesi (naik jadi staf / turun) → hak tema ikut, tanpa rejoin.
local function watchRank(player)
	player:GetAttributeChangedSignal(Config.rankAttribute):Connect(function()
		if rankOpen(player) then
			svc:ownership(player, true)
			return
		end
		task.spawn(function()
			local owns = passOwned(player)
			svc:ownership(player, owns or rankOpen(player))
		end)
	end)
end

-- ── pemain ────────────────────────────────────────────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	watchRank(player)
	svc:join(player)
end)
for _, player in Players:GetPlayers() do
	watchRank(player)
	task.spawn(svc.join, svc, player)
end
Players.PlayerRemoving:Connect(function(player)
	svc:leave(player)
end)
game:BindToClose(function()
	svc:closeAll(20)
end)

-- Beli / gift pass di tengah game (ShopServer). Event dibuat ShopServer saat mulai.
task.spawn(function()
	local folder = SSS:WaitForChild("ShopServerEvents", 30)
	local event = folder and folder:WaitForChild("OnOwnershipChanged", 10)
	if not event then
		warn("[ThemeColor] ShopServerEvents.OnOwnershipChanged tidak ada — beli pass baru terasa setelah rejoin")
		return
	end
	event.Event:Connect(function(player, passName, owned)
		if passName == Config.passName and typeof(player) == "Instance" then
			svc:ownership(player, owned ~= false or rankOpen(player))
		end
	end)
end)

print(("[ThemeColor] Ready | %d tema | default %s | pass %q | staf rank ≥ %s | store %s"):format(
	#Rules.ids(Config), Config.default, Config.passName, tostring(Config.freeRankMin), Config.store.name .. suffix))
