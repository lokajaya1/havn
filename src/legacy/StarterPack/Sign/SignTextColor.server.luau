-- StarterPack > Sign > LocalScript > TextColor > Script
-- [FIX 2026-09-26] versi lama menerima nilai apa pun dari client dan siapa pun bisa
-- mengubah Sign milik orang lain. Sekarang: hanya Color3, hanya pemilik tool.
-- Perilaku untuk pemilik sah tidak berubah.

local bg = script.Parent.Parent.Parent.Handle.Part.SurfaceGui.TextLabel
local tool = script.Parent.Parent.Parent

local function isOwner(player: Player): boolean
	local parent = tool.Parent
	return parent ~= nil and (parent == player.Character or parent == player:FindFirstChildOfClass("Backpack"))
end

script.Parent.OnServerEvent:Connect(function(ply: Player, color: any)
	if typeof(color) ~= "Color3" or not isOwner(ply) then
		return
	end
	bg.TextColor3 = Color3.fromRGB(color.R * 255, color.G * 255, color.B * 255)
end)
