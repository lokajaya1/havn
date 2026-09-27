-- ═══════════════════════════════════════════════════════════
-- CarrySystemHandler (SERVER)
-- Path: ServerScriptService.Misc.CarrySystemHandler
-- ═══════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")

local CarryReplic  = RS:WaitForChild("CarryReplic")
local CarryRemotes = CarryReplic:WaitForChild("CarryRemotes")
local CarryRemote  = CarryRemotes:WaitForChild("CarryRemote")

local DanceAssets = require(RS.Assets.Animations.Dances.DanceAssets)

local DEFAULT_WALKSPEED  = 16
local DEFAULT_JUMPPOWER  = 50
local DEFAULT_JUMPHEIGHT = 7.2
local DANCE_WALKSPEED    = 6

local danceIdSet = {}
for _, id in pairs(DanceAssets.dances) do
	danceIdSet["rbxassetid://" .. id] = true
end

local function isDanceTrack(track)
	local anim = track.Animation
	if not anim then return false end
	if DanceAssets.dances[anim.Name] then return true end
	return danceIdSet[anim.AnimationId] == true
end

-- ═══ STATE ═══

local carryPairs        = {}
local pendingRequests   = {}
-- [FIX 2b] modul carry dicatat server saat AskCarry; Carry hanya sah kalau ada permintaan tertunda
local pendingModules    = {} -- [target] → ModuleScript yang diminta requester
local lastAsk           = {} -- [player] → os.clock() AskCarry terakhir
local ASK_COOLDOWN      = 1
local function isCarryModule(mod)
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then return false end
	local choices = CarryReplic:FindFirstChild("CarryChoices")
	local assets  = RS:FindFirstChild("Assets")
	local extra   = assets and assets:FindFirstChild("Carry")
	return (choices ~= nil and mod.Parent == choices) or (extra ~= nil and mod.Parent == extra)
end
local releaseFuncs      = {}
local preCarryWalkSpeed = {}

local function setPair(a, b) carryPairs[a] = b; carryPairs[b] = a end

local function clearPair(plr)
	local partner = carryPairs[plr]
	if partner then carryPairs[partner] = nil end
	carryPairs[plr] = nil
	return partner
end

local function storeRelease(a, b, fn)
	if fn then releaseFuncs[a] = fn; releaseFuncs[b] = fn end
end

local function popRelease(plr)
	local fn = releaseFuncs[plr]
	if fn then
		for p, f in pairs(releaseFuncs) do
			if f == fn then releaseFuncs[p] = nil end
		end
	end
	return fn
end

local function setPending(requester, target) pendingRequests[target] = requester end

local function clearPending(target)
	local requester = pendingRequests[target]
	pendingRequests[target] = nil
	if requester and requester.Parent then
		local v = requester:FindFirstChild("CanAskCarry")
		if v then v.Value = true end
	end
	if target and target.Parent then
		local v = target:FindFirstChild("CanAskCarry")
		if v then v.Value = true end
	end
	return requester
end

local function clearPendingByRequester(requester)
	for target, req in pairs(pendingRequests) do
		if req == requester then
			pendingRequests[target] = nil
			if target and target.Parent then
				local v = target:FindFirstChild("CanAskCarry")
				if v then v.Value = true end
			end
			return target
		end
	end
end

-- ═══ PLAYER SETUP ═══

local function setupChar(char)
	if not char:FindFirstChild("Carryble") then
		local v = Instance.new("BoolValue")
		v.Name = "Carryble"; v.Value = true; v.Parent = char
	end
end

local function onPlayerAdded(plr)
	if not plr:FindFirstChild("CanAskCarry") then
		local v = Instance.new("BoolValue")
		v.Name = "CanAskCarry"; v.Value = true; v.Parent = plr
	end
	plr:SetAttribute("InCarry", false)
	if plr.Character then setupChar(plr.Character) end
	plr.CharacterAdded:Connect(setupChar)
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

-- ═══ HELPERS ═══

local function returnOwnership(char, owner)
	if not char or not char.Parent then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				if part:CanSetNetworkOwnership() then
					part:SetNetworkOwner(owner)
				end
			end)
		end
	end
end

local function restorePlayerState(plr)
	local char = plr and plr.Character
	if not char or not char.Parent then
		preCarryWalkSpeed[plr] = nil
		return
	end

	local hum = char:FindFirstChild("Humanoid")

	local isDancing = false
	if hum then
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			pcall(function()
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if isDanceTrack(track) and track.IsPlaying then
						isDancing = true
						break
					end
				end
			end)
		end
	end

	if hum then
		local restoredSpeed = preCarryWalkSpeed[plr] or DEFAULT_WALKSPEED
		if isDancing then
			restoredSpeed = DANCE_WALKSPEED
		end
		pcall(function()
			hum.WalkSpeed = restoredSpeed
		end)
	end

	preCarryWalkSpeed[plr] = nil

	local canAsk = plr:FindFirstChild("CanAskCarry")
	if canAsk then canAsk.Value = true end

	local carryble = char:FindFirstChild("Carryble")
	if carryble then carryble.Value = true end
end

local function cleanupCarryProps(plr)
	local char = plr and plr.Character
	if not char or not char.Parent then return end

	local hum = char:FindFirstChild("Humanoid")

	if hum then
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			pcall(function()
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if not isDanceTrack(track) then
						track:Stop(0)
					end
				end
			end)
		end
	end

	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("Weld") or d:IsA("WeldConstraint")) and d.Name == "CarryWeld" then
			d:Destroy()
		end
	end

	if hum then
		pcall(function()
			hum.PlatformStand = false
			hum.AutoRotate    = true
			hum.JumpPower     = DEFAULT_JUMPPOWER
			hum.JumpHeight    = DEFAULT_JUMPHEIGHT
		end)
	end

	pcall(function()
		plr.DevComputerMovementMode = Enum.DevComputerMovementMode.UserChoice
	end)

	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then p.Massless = false end
	end

	returnOwnership(char, plr)
end

local function fullStop(plr)
	-- FIX: hanya jalankan kalau player memang sedang dalam carry pair
	if not carryPairs[plr] then return end

	local partner = clearPair(plr)
	local releaseFn = popRelease(plr)

	plr:SetAttribute("InCarry", false)
	if partner then partner:SetAttribute("InCarry", false) end
	-- Jaga-jaga: atribut dari CarryWeld tidak boleh tertinggal (mis. respawn).
	plr:SetAttribute("Carried", nil)
	if partner then partner:SetAttribute("Carried", nil) end

	if releaseFn then
		local ok, err = pcall(releaseFn)
		if not ok then
			warn("[CarryHandler] releaseCarry error:", err)
			cleanupCarryProps(plr)
			if partner and partner.Parent then cleanupCarryProps(partner) end
		end
	else
		cleanupCarryProps(plr)
		if partner and partner.Parent then cleanupCarryProps(partner) end
	end

	restorePlayerState(plr)
	if partner and partner.Parent then restorePlayerState(partner) end

	CarryRemote:FireClient(plr, { cmd = "DestroyCarryInfo" })
	if partner and partner.Parent then
		CarryRemote:FireClient(partner, { cmd = "DestroyCarryInfo" })
	end
end

-- ═══ EXECUTE CARRY MODULE ═══

local function executeCarryModule(carryMod, firstPlr, secondPlr)
	local requireOk, modResult = pcall(require, carryMod)
	if not requireOk then
		warn("[CarryHandler] require FAILED:", carryMod.Name, tostring(modResult))
		return nil
	end

	if type(modResult) ~= "function" then
		warn("[CarryHandler] Module harus return function:", carryMod.Name)
		return nil
	end

	local callOk, releaseOrErr = pcall(modResult, {
		Players = { First = firstPlr, Second = secondPlr },
	})

	if not callOk then
		warn("[CarryHandler] Carry error:", carryMod.Name, tostring(releaseOrErr))
		return nil
	end

	return type(releaseOrErr) == "function" and releaseOrErr or nil
end

-- ═══ REMOTE HANDLER ═══

CarryRemote.OnServerEvent:Connect(function(plr, args)
	if type(args) ~= "table" or not args.cmd then return end

	local ok, err = pcall(function()
		local canAsk   = plr:FindFirstChild("CanAskCarry")
		local char     = plr.Character
		local carryble = char and char:FindFirstChild("Carryble")
		if not canAsk or not carryble then return end

		local cmd = args.cmd

		if cmd == "AskCarry" then
			local target   = args.targetPlr
			local carryMod = args.carrychoicesss
			if typeof(target) ~= "Instance" or not target:IsA("Player") or target == plr then return end
			if not isCarryModule(carryMod) then return end -- [FIX 2b] hanya modul carry resmi
			local now = os.clock()
			if lastAsk[plr] and now - lastAsk[plr] < ASK_COOLDOWN then return end
			lastAsk[plr] = now

			-- FIX: set canAsk false di sini (dulu di PromptAction terpisah
			-- yang bisa bikin race condition). Sekarang atomic dalam satu event.
			if not canAsk.Value then return end
			canAsk.Value = false

			local tCanAsk   = target:FindFirstChild("CanAskCarry")
			local tChar     = target.Character
			local tCarryble = tChar and tChar:FindFirstChild("Carryble")

			if tCanAsk and tCanAsk.Value and tCarryble and tCarryble.Value and carryble.Value then
				setPending(plr, target)
				pendingModules[target] = carryMod -- [FIX 2b]
				tCanAsk.Value = false
				CarryRemote:FireClient(target, {
					cmd = "GetMessage", messageSentBy = plr, carrychoicesss = carryMod,
				})
			else
				-- Target tidak bisa di-carry, kembalikan flag requester
				canAsk.Value = true
				CarryRemote:FireClient(plr, { cmd = "Messagesserror", targetPlr = target })
			end

		elseif cmd == "Carry" then
			local firstPlr = args.firstPlr
			if typeof(firstPlr) ~= "Instance" or not firstPlr:IsA("Player") or firstPlr == plr then return end
			-- [FIX 2b] hanya boleh menerima permintaan yang benar-benar ada (dulu: carry paksa tanpa persetujuan)
			if pendingRequests[plr] ~= firstPlr then return end
			local carryMod = pendingModules[plr]
			pendingModules[plr] = nil
			if not isCarryModule(carryMod) then return end

			pendingRequests[plr] = nil
			canAsk.Value = true; carryble.Value = false

			local fCanAsk   = firstPlr:FindFirstChild("CanAskCarry")
			local fCarryble = firstPlr.Character and firstPlr.Character:FindFirstChild("Carryble")
			if fCanAsk   then fCanAsk.Value   = true  end
			if fCarryble then fCarryble.Value  = false end

			setPair(plr, firstPlr)

			local plrHum = char and char:FindFirstChild("Humanoid")
			if plrHum then preCarryWalkSpeed[plr] = plrHum.WalkSpeed end

			local firstChar = firstPlr.Character
			local firstHum  = firstChar and firstChar:FindFirstChild("Humanoid")
			if firstHum then preCarryWalkSpeed[firstPlr] = firstHum.WalkSpeed end

			plr:SetAttribute("InCarry", true)
			firstPlr:SetAttribute("InCarry", true)

			CarryRemote:FireClient(plr, {
				cmd = "GetCarryInfo", otherPlr = firstPlr, carrychoicesss = carryMod,
			})
			CarryRemote:FireClient(firstPlr, {
				cmd = "GetCarryInfo", otherPlr = plr, carrychoicesss = carryMod,
			})

			local releaseFn = executeCarryModule(carryMod, firstPlr, plr)
			if releaseFn then storeRelease(plr, firstPlr, releaseFn) end

			-- FIX: hapus cmd "PromptAction" karena sudah digabung ke AskCarry

		elseif cmd == "CancelAll" then
			canAsk.Value = true; clearPendingByRequester(plr)

		elseif cmd == "Declinecarry" then
			clearPending(plr); canAsk.Value = true
			-- Hanya fullStop kalau memang sedang dalam carry pair
			if carryPairs[plr] then fullStop(plr) end

		elseif cmd == "StopCarry" then
			fullStop(plr)
		end
	end)

	if not ok then warn("[CarryHandler]", err) end
end)

-- ═══ AUTO-CLEANUP ═══

Players.PlayerRemoving:Connect(function(plr)
	clearPendingByRequester(plr)
	clearPending(plr)
	-- FIX: fullStop sudah punya guard carryPairs[plr] di dalamnya
	fullStop(plr)
	carryPairs[plr] = nil
	releaseFuncs[plr] = nil
	preCarryWalkSpeed[plr] = nil
	pendingModules[plr] = nil -- [FIX 2b]
	lastAsk[plr] = nil
end)

local function bindRespawn(plr)
	plr.CharacterRemoving:Connect(function()
		clearPendingByRequester(plr)
		clearPending(plr)
		-- FIX: hanya fullStop kalau player memang sedang dalam carry.
		-- Sebelumnya fullStop selalu jalan saat respawn, menyebabkan
		-- DestroyCarryInfo dikirim ke client yang masih menunggu request,
		-- sehingga panel request carry tidak pernah muncul.
		if carryPairs[plr] then
			fullStop(plr)
		end
	end)
end

for _, p in ipairs(Players:GetPlayers()) do bindRespawn(p) end
Players.PlayerAdded:Connect(function(plr) onPlayerAdded(plr); bindRespawn(plr) end)