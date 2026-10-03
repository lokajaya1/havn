-- GlowStick Server | Script → ServerScriptService
-- Warna GlowStick dari panel (StarterGui.GlowStickUI) → semua part/lampu/partikel tool + atribut Player GlowColor_R/G/B
-- (dipasang lagi tiap GlowStick di-equip, juga sesudah respawn).
-- [TOOLS] remote divalidasi (Color3 0–1) + batas terima per pemain + jeda terapkan (warna terakhir selalu diterapkan);
-- warna tidak lagi dibulatkan ke palet BrickColor. Angka: ReplicatedStorage.Config.Tools.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Cfg = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools"))
local ToolRules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolRules"))
local G = Cfg.GLOWSTICK

local remoteEvent = ReplicatedStorage:FindFirstChild("GlowStickColorChanged")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "GlowStickColorChanged"
	remoteEvent.Parent = ReplicatedStorage
end

local function applyColor(tool, color)
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") or desc:IsA("Light") then
			desc.Color = color -- [TOOLS] tanpa BrickColor (dulu menimpa warna ke palet BrickColor terdekat)
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
			desc.Color = ColorSequence.new(color)
		end
	end
end

local function getStoredColor(player)
	local r = player:GetAttribute("GlowColor_R")
	local g = player:GetAttribute("GlowColor_G")
	local b = player:GetAttribute("GlowColor_B")
	if r and g and b then
		return Color3.new(r, g, b)
	end
	return nil
end

-- Terapkan warna ke GlowStick yang sedang dipegang + simpan di atribut (dipanggil lewat gate).
local function applyPlayer(player, color)
	if not player.Parent then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and child.Name == G.TOOL_NAME then
			applyColor(child, color)
		end
	end
	player:SetAttribute("GlowColor_R", color.R)
	player:SetAttribute("GlowColor_G", color.G)
	player:SetAttribute("GlowColor_B", color.B)
end

local buckets = {}
local gates = {}

remoteEvent.OnServerEvent:Connect(function(player, color)
	if not ToolRules.isColor(color) then
		return
	end
	local bucket = buckets[player]
	if not bucket then
		bucket = ToolRules.bucket(Cfg.RECEIVE.RATE, Cfg.RECEIVE.BURST)
		buckets[player] = bucket
	end
	if not ToolRules.take(bucket, os.clock()) then
		return
	end
	local push = gates[player]
	if not push then
		push = ToolRules.gate(G.APPLY_EVERY, function(c)
			applyPlayer(player, c)
		end, os.clock, task.delay)
		gates[player] = push
	end
	push(color)
end)

local function onCharacter(player, char)
	char.ChildAdded:Connect(function(child)
		if not (child:IsA("Tool") and child.Name == G.TOOL_NAME) then
			return
		end
		task.wait(G.REAPPLY_DELAY)
		local color = getStoredColor(player)
		if color then
			applyColor(child, color)
		end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	gates[player] = nil
end)
