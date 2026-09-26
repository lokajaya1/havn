-- StarterPack > Sign > LocalScript > BGColor > Script
-- [FIX 2026-09-26] versi lama menerima nilai apa pun dari client dan siapa pun bisa
-- mengubah Sign milik orang lain. Sekarang: hanya Color3, hanya pemilik tool.
-- Perilaku untuk pemilik sah tidak berubah (`Part.Color = color`).

local bg = script.Parent.Parent.Parent.Handle.Part
local tool = script.Parent.Parent.Parent

local function isOwner(player: Player): boolean
	local parent = tool.Parent
	return parent ~= nil and (parent == player.Character or parent == player:FindFirstChildOfClass("Backpack"))
end

script.Parent.OnServerEvent:Connect(function(ply: Player, color: any)
	if typeof(color) ~= "Color3" or not isOwner(ply) then
		return
	end
	bg.Color = color
end)
