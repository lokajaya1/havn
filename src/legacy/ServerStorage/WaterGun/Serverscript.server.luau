-- Water Gun Server | Script → Tool/WaterGun
-- [TOOLS] Semprotan & suara diatur DI SERVER → terlihat semua pemain (dulu hanya di layar pemakainya; Script server
-- lama Disabled). Pola sama dengan Money Gun: hanya pemegang tool, batas terima, start/stop lewat jeda terapkan
-- (keadaan terakhir selalu diterapkan), burst ber-cooldown. Rate & Burst dari panel (WaterGunUI) dipakai dalam rentang
-- Config. Angka: ReplicatedStorage.Config.Tools.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cfg = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools"))
local ToolRules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolRules"))
local W = Cfg.WATER_GUN

local Tool = script.Parent
local Remote = Tool:WaitForChild("RemoteEvent")
local water = Tool:WaitForChild("Part"):WaitForChild("Water")

local function getSound()
	local handle = Tool:FindFirstChild("Handle")
	return handle and handle:FindFirstChild("Explosion")
end

local function isHolder(player)
	local character = player.Parent and player.Character
	return character ~= nil and Tool.Parent == character
end

local function stopAll()
	water.Enabled = false
	local sound = getSound()
	if sound then sound:Stop() end
end

-- start/stop: diterapkan lewat gate (dicek ulang pemegangnya saat diterapkan).
local pushState = ToolRules.gate(W.STATE_EVERY, function(req)
	if not isHolder(req.player) then return end
	if req.action == "start" then
		water.Rate = req.rate
		water.Enabled = true
		local sound = getSound()
		if sound then sound:Play() end
	else
		stopAll()
	end
end, os.clock, task.delay)

local bucket = ToolRules.bucket(Cfg.RECEIVE.RATE, Cfg.RECEIVE.BURST)
local lastBurst = 0

Remote.OnServerEvent:Connect(function(player, action, amount)
	if action ~= "start" and action ~= "stop" and action ~= "burst" then return end
	if not isHolder(player) then return end
	if not ToolRules.take(bucket, os.clock()) then return end

	if action == "burst" then
		local now = os.clock()
		if now - lastBurst < W.BURST_COOLDOWN then return end
		lastBurst = now
		local count = ToolRules.choose(amount, W.BURST)
		task.defer(function() water:Emit(count) end)
		local sound = getSound()
		if sound then
			sound:Play()
			task.delay(W.BURST_SOUND, function() sound:Stop() end)
		end
	else
		pushState({ player = player, action = action, rate = ToolRules.choose(amount, W.RATE) })
	end
end)

-- Dilepas → berhenti (client juga mengirim "stop", tapi saat itu tool sudah bukan di karakter → ditolak cek pemegang).
Tool.Unequipped:Connect(stopAll)
