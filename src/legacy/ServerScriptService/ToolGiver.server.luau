-- ═══════════════════════════════════════════════════════════
-- TOOL GIVER (Debug Mode)
-- Location: ServerScriptService > ToolGiver (Script)
-- ═══════════════════════════════════════════════════════════

local ServerStorage = game:GetService("ServerStorage")
local SSS           = game:GetService("ServerScriptService")
local Players       = game:GetService("Players")
local ShopConfig    = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig"))

local GROUP_ID         = 277580244
local VIP_GAMEPASS_ID  = ShopConfig.getGamepassByName("VIP Access").id
local VVIP_GAMEPASS_ID = ShopConfig.getGamepassByName("VVIP Access").id

local TOOLS = {
	{
		names = { "Money Gun", "WaterGun" },
		check = function(rank, hasVIP, hasVVIP)
			return hasVIP or rank >= 1
		end,
	},
	{
		names = { "Flying Broom" },
		check = function(rank, hasVIP, hasVVIP)
			return hasVVIP or rank >= 10
		end,
	},
}

-- ───────────────────────────────────────────────────────────
local ShopReady = false
task.spawn(function()
	local t = tick()
	repeat task.wait(0.1)
		if _G.ShopServer and _G.ShopServer.HasGamepass then
			ShopReady = true; break
		end
	until tick() - t > 10
end)

local function ownsGamepass(player, passId, passName)
	if ShopReady and _G.ShopServer and passName then
		local ok, owns = pcall(_G.ShopServer.HasGamepass, player.UserId, passName, true)
		if ok and owns then return true end
	end
	-- pass baru ATAU pass HAVN lama
	return ShopConfig.userOwnsPass(player.UserId, ShopConfig.getGamepassById(passId))
end

local function getGroupRank(player)
	if not player:IsInGroup(GROUP_ID) then return 0 end
	local ok, rank = pcall(player.GetRankInGroup, player, GROUP_ID)
	return ok and rank or 0
end

local function giveTool(player, toolName)
	if player.Backpack:FindFirstChild(toolName) then return end
	local char = player.Character
	if char and char:FindFirstChild(toolName) then return end
	local source = ServerStorage:FindFirstChild(toolName)
	if source then source:Clone().Parent = player.Backpack end
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

	-- DEBUG — lihat di output Roblox
	debugLog(string.format("[ToolGiver DEBUG] %s | Rank:%d | HasVIP:%s | HasVVIP:%s | ShopReady:%s",
		player.Name, rank, tostring(hasVIP), tostring(hasVVIP), tostring(ShopReady)))

	for _, rule in ipairs(TOOLS) do
		if rule.check(rank, hasVIP, hasVVIP) then
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
		task.wait(1)
		giveAllTools(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)
end)

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then task.spawn(giveAllTools, player) end
end

task.spawn(function()
	local folder = SSS:WaitForChild("ShopServerEvents", 15)
	if not folder then warn("[ToolGiver] ShopServerEvents not found"); return end
	local event = folder:WaitForChild("OnOwnershipChanged", 10)
	if not event then warn("[ToolGiver] OnOwnershipChanged not found"); return end
	event.Event:Connect(function(player, passName, owned)
		if not player or not player.Parent or not owned then return end
		task.delay(0.5, function()
			if player and player.Parent then giveAllTools(player) end
		end)
	end)
end)

print("[ToolGiver] Ready | ShopServer:", ShopReady and "connected" or "waiting")