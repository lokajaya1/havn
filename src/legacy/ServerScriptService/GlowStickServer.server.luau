-- GlowStick Server | Script → ServerScriptService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local remoteEvent = ReplicatedStorage:FindFirstChild("GlowStickColorChanged")
	or Instance.new("RemoteEvent")
if not remoteEvent.Parent then
	remoteEvent.Name   = "GlowStickColorChanged"
	remoteEvent.Parent = ReplicatedStorage
end

local function applyColor(tool, color)
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Color     = color
			desc.BrickColor= BrickColor.new(color)
		elseif desc:IsA("Light") then
			desc.Color = color
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
			desc.Color = ColorSequence.new(color)
		end
	end
end

local function getStoredColor(player)
	local r = player:GetAttribute("GlowColor_R")
	local g = player:GetAttribute("GlowColor_G")
	local b = player:GetAttribute("GlowColor_B")
	if r and g and b then return Color3.new(r, g, b) end
	return nil
end

remoteEvent.OnServerEvent:Connect(function(player, color)
	if typeof(color) ~= "Color3" then return end
	local char = player.Character
	if not char then return end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and child.Name == "GlowStick" then
			applyColor(child, color)
		end
	end

	player:SetAttribute("GlowColor_R", color.R)
	player:SetAttribute("GlowColor_G", color.G)
	player:SetAttribute("GlowColor_B", color.B)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(child)
			if not (child:IsA("Tool") and child.Name == "GlowStick") then return end
			task.wait(0.1)
			local color = getStoredColor(player)
			if color then applyColor(child, color) end
		end)
	end)
end)

print("[GlowStickServer] Ready")