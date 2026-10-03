-- ═══════════════════════════════════════════════════════════
-- TOOL GIVER
-- Location: ServerScriptService > ToolGiver (Script)
-- Memberi tool ServerStorage (Money Gun, WaterGun, Flying Broom) ke Backpack sesuai pass / rank komunitas.
-- [TOOLS] (claude/Rencana_Tools.md)
--   • rank dari atribut "RankInGroup" (UnifiedRankManager) + beri ulang saat atribut berubah → join komunitas di
--     tengah sesi langsung dapat tool tanpa rejoin (IsInGroup/GetRankInGroup di-cache sejak panggilan pertama).
--     Atribut tidak muncul dalam Config.GIVER.RANK_WAIT dtk → cara lama.
--   • Backpack tidak ada (pemain keluar di tengah jeda) → dilewati tanpa error.
--   • Server mulai: tool HAVN yang hilang / tanpa Handle → warn jelas (tool tanpa Handle tidak bisa dipakai).
--   • Tool HAVN yang tergeletak di Workspace (dijatuhkan) dihapus → tidak bisa dipungut pemain lain.
-- Aturan & angka: ReplicatedStorage.Config.Tools (GIVER, HAVN_TOOLS) + Modules.ToolRules.
-- ═══════════════════════════════════════════════════════════

local ServerStorage     = game:GetService("ServerStorage")
local SSS               = game:GetService("ServerScriptService")
local Players           = game:GetService("Players")
local StarterPack       = game:GetService("StarterPack")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopConfig        = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Cfg               = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools"))
local ToolRules         = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolRules"))
local RankConfig        = require(SSS:WaitForChild("RankConfig"))

local GIVER            = Cfg.GIVER
local VIP_GAMEPASS_ID  = ShopConfig.getGamepassByName("VIP Access").id
local VVIP_GAMEPASS_ID = ShopConfig.getGamepassByName("VVIP Access").id

-- ───────────────────────────────────────────────────────────
local ShopReady = false
task.spawn(function()
	local t = os.clock()
	repeat task.wait(0.1)
		if _G.ShopServer and _G.ShopServer.HasGamepass then
			ShopReady = true; break
		end
	until os.clock() - t > 10
end)

local function ownsGamepass(player, passId, passName)
	if ShopReady and _G.ShopServer and passName then
		local ok, owns = pcall(_G.ShopServer.HasGamepass, player.UserId, passName, true)
		if ok and owns then return true end
	end
	-- pass baru ATAU pass HAVN lama
	return ShopConfig.userOwnsPass(player.UserId, ShopConfig.getGamepassById(passId))
end

-- Cara lama (cadangan kalau atribut RankManager tidak pernah muncul).
local function legacyGroupRank(player)
	local okMember, isMember = pcall(player.IsInGroup, player, RankConfig.GROUP_ID) -- error API → anggap bukan member
	if not okMember or not isMember then return 0 end
	local ok, rank = pcall(player.GetRankInGroup, player, RankConfig.GROUP_ID)
	return ok and rank or 0
end

local function getGroupRank(player)
	local rank = ToolRules.rankOf(player:GetAttribute(GIVER.RANK_ATTRIBUTE))
	local deadline = os.clock() + GIVER.RANK_WAIT
	while rank == nil and player.Parent and os.clock() < deadline do
		task.wait(0.25)
		rank = ToolRules.rankOf(player:GetAttribute(GIVER.RANK_ATTRIBUTE))
	end
	if rank ~= nil then return rank end
	if not player.Parent then return 0 end
	return legacyGroupRank(player)
end

local function giveTool(player, toolName)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	if backpack:FindFirstChild(toolName) then return end
	local char = player.Character
	if char and char:FindFirstChild(toolName) then return end
	local source = ServerStorage:FindFirstChild(toolName)
	if source then source:Clone().Parent = backpack end
end

-- patch: toolgiver-debug-flag
-- true = tampilkan log debug pemberian tool di Output
local DEBUG = false
local function debugLog(msg)
	if DEBUG then
		warn(msg)
	end
end

local function giveAllTools(player)
	if not player.Character then return end

	local rank    = getGroupRank(player)
	local hasVIP  = ownsGamepass(player, VIP_GAMEPASS_ID,  "VIP Access")
	local hasVVIP = ownsGamepass(player, VVIP_GAMEPASS_ID, "VVIP Access")
	if not (player.Parent and player.Character) then return end -- keluar / mati selama API di atas menunggu

	-- DEBUG — lihat di output Roblox
	debugLog(string.format("[ToolGiver DEBUG] %s | Rank:%d | HasVIP:%s | HasVVIP:%s | ShopReady:%s",
		player.Name, rank, tostring(hasVIP), tostring(hasVVIP), tostring(ShopReady)))

	for _, rule in ipairs(GIVER.RULES) do
		if ToolRules.eligible(rule, rank, hasVIP, hasVVIP) then
			for _, toolName in ipairs(rule.names) do
				debugLog("[ToolGiver DEBUG] Giving '"..toolName.."' to "..player.Name)
				giveTool(player, toolName)
			end
		end
	end
end

-- ───────────────────────────────────────────────────────────
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		task.wait(GIVER.SPAWN_DELAY)
		giveAllTools(player)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	-- rank berubah (join komunitas di tengah sesi / API grup pulih) → beri yang belum dimiliki
	player:GetAttributeChangedSignal(GIVER.RANK_ATTRIBUTE):Connect(function()
		if player.Parent and player.Character then giveAllTools(player) end
	end)
end

Players.PlayerAdded:Connect(onPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
	if player.Character then task.spawn(giveAllTools, player) end
end

task.spawn(function()
	local folder = SSS:WaitForChild("ShopServerEvents", 15)
	if not folder then warn("[ToolGiver] ShopServerEvents not found"); return end
	local event = folder:WaitForChild("OnOwnershipChanged", 10)
	if not event then warn("[ToolGiver] OnOwnershipChanged not found"); return end
	event.Event:Connect(function(player, _passName, owned)
		if not player or not player.Parent or not owned then return end
		task.delay(GIVER.OWNERSHIP_DELAY, function()
			if player and player.Parent then giveAllTools(player) end
		end)
	end)
end)

-- ── tool HAVN: cek aset saat server mulai + penjaga Workspace ─────────────
local HAVN = {}
for _, t in ipairs(Cfg.HAVN_TOOLS) do
	HAVN[t.name] = true
	local tool = (t.where == "StarterPack" and StarterPack or ServerStorage):FindFirstChild(t.name)
	if not (tool and tool:IsA("Tool")) then
		warn(("[ToolGiver] Tool %s/%s tidak ada → tidak bisa diberikan"):format(t.where, t.name))
	elseif tool.RequiresHandle and not tool:FindFirstChild("Handle") then
		warn(("[ToolGiver] Tool %s/%s tanpa Handle → tidak bisa dipakai (pulihkan dari cadangan, claude/Rencana_Tools.md)"):format(t.where, t.name))
	end
end

workspace.ChildAdded:Connect(function(child)
	if child:IsA("Tool") and HAVN[child.Name] then
		task.defer(function()
			if child.Parent == workspace then child:Destroy() end
		end)
	end
end)
