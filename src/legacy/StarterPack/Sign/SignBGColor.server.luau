-- StarterPack > Sign > LocalScript > BGColor > Script
-- [FIX 2026-09-26] versi lama menerima nilai apa pun dari client dan siapa pun bisa
-- mengubah Sign milik orang lain. Sekarang: hanya Color3, hanya pemilik tool.
-- Perilaku untuk pemilik sah tidak berubah (`Part.Color = color`).
-- [TOOLS] Color3 wajib 0–1 (NaN/inf ditolak) + batas terima + jeda terapkan per Sign (warna terakhir selalu
-- diterapkan). Angka: ReplicatedStorage.Config.Tools.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cfg = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools"))
local ToolRules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolRules"))

local bg = script.Parent.Parent.Parent.Handle.Part
local tool = script.Parent.Parent.Parent

local function isOwner(player: Player): boolean
	local parent = tool.Parent
	return parent ~= nil and (parent == player.Character or parent == player:FindFirstChildOfClass("Backpack"))
end

local bucket = ToolRules.bucket(Cfg.RECEIVE.RATE, Cfg.RECEIVE.BURST)
local push = ToolRules.gate(Cfg.SIGN.APPLY_EVERY, function(req)
	if isOwner(req.player) then
		bg.Color = req.color
	end
end, os.clock, task.delay)

script.Parent.OnServerEvent:Connect(function(ply: Player, color: any)
	if not ToolRules.isColor(color) or not isOwner(ply) then
		return
	end
	if not ToolRules.take(bucket, os.clock()) then
		return
	end
	push({ player = ply, color = color })
end)
