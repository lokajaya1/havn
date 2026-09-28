-- StarterPlayerScripts/DonationFX  (LocalScript)
-- Efek donasi di karakter DONATUR, dijalankan di tiap client (bisa dimatikan per pemain).
-- Server (DonationServer) mengirim DonationRemotes.Effect(userId, robux) SETELAH donasi tersimpan.
-- Template partikel: ReplicatedStorage.DonationEffects (Level1–6 + Exotic, 0 skrip);
-- Model ber-atribut WholeAtBase (Exotic) ditempatkan utuh di kaki donatur.
-- Donatur tidak ada di server / belum punya karakter → efek dilewati (tidak jatuh ke pemain sendiri).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local Config = require(RS:WaitForChild("DonationConfig"))
local FX = Config.fx

local templates = RS:WaitForChild("DonationEffects", 30)
local remotes = RS:WaitForChild("DonationRemotes", 30)
local effectEvent = remotes and remotes:WaitForChild("Effect", 30)
if not templates or not effectEvent then
	warn("[Donation] DonationEffects / DonationRemotes.Effect tidak ditemukan, efek donasi tidak aktif")
	return
end

-- Penanda posisi efek besar (Workspace.DonationMarkers, kotak neon untuk diatur di Studio) tidak terlihat di game.
local function hideMarker(d)
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = 1
	end
end
task.spawn(function()
	local markers = workspace:WaitForChild("DonationMarkers", 30)
	if markers then
		for _, d in markers:GetDescendants() do
			hideMarker(d)
		end
		markers.DescendantAdded:Connect(hideMarker)
	end
end)

local holder = workspace:FindFirstChild("DonationFX") or Instance.new("Folder")
holder.Name = "DonationFX"
holder.Parent = workspace

-- Pengaturan pemain: atribut LocalPlayer "DonationFX" (nil/true = nyala, false = mati).
local function enabled()
	return player:GetAttribute("DonationFX") ~= false
end

-- Suara di-preload sekali supaya efek pertama tidak telat.
task.spawn(function()
	local list, seen = {}, {}
	for _, e in Config.effects do
		if e.sound and not seen[e.sound] then
			seen[e.sound] = true
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. e.sound
			table.insert(list, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end)

local active = 0

local function lock(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function weld(part, hrp)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = hrp
	w.Parent = part
end

-- Titik terendah karakter (kaki), robust R6/R15.
local function footPosition(char, hrp)
	local lowest = math.huge
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") then
			lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2)
		end
	end
	if lowest == math.huge then
		lowest = hrp.Position.Y
	end
	return Vector3.new(hrp.Position.X, lowest, hrp.Position.Z)
end

-- → root yang dipasang ke workspace, daftar emitter
local function build(src, char, hrp)
	local emitters = {}
	if src:GetAttribute("WholeAtBase") then
		local model = src:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
				table.insert(emitters, d)
			end
		end
		model.Parent = holder
		local pivot = model:GetPivot()
		local bbCF, bbSize = model:GetBoundingBox()
		local toBottom = pivot.Position.Y - (bbCF.Position.Y - bbSize.Y / 2)
		local f = footPosition(char, hrp)
		local _, yaw = hrp.CFrame:ToEulerAnglesYXZ()
		model:PivotTo(CFrame.new(f.X, f.Y + toBottom + (src:GetAttribute("BaseYOffset") or 0), f.Z) * CFrame.Angles(0, yaw, 0))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				weld(d, hrp) -- dibuat saat masih anchored, baru dilepas → tidak sempat jatuh
				d.Anchored = false
			end
		end
		return model, emitters, model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	end

	local host = Instance.new("Part")
	host.Name = "DonationFX_" .. src.Name
	host.Transparency = 1
	host.Size = Vector3.new(1, 1, 1)
	lock(host)
	host.CFrame = hrp.CFrame
	weld(host, hrp)
	for _, child in src:GetChildren() do
		local c = child:Clone()
		if c:IsA("BasePart") then
			lock(c)
			c.CFrame = hrp.CFrame
			weld(c, hrp)
		end
		if c:IsA("ParticleEmitter") then
			c.Enabled = false
			table.insert(emitters, c)
		end
		for _, d in c:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
				table.insert(emitters, d)
			end
		end
		c.Parent = host
	end
	host.Parent = holder
	return host, emitters, host
end

local function play(userId, robux)
	if not enabled() or active >= FX.maxActive then
		return
	end
	local tier = Config.tierForRobux(robux)
	local name = tier and tier.fx
	local spec = name and Config.effects[name]
	local src = name and templates:FindFirstChild(name)
	if not spec or not src then
		return
	end
	local donor = Players:GetPlayerByUserId(userId)
	local char = donor and donor.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	active += 1
	local ok, root, emitters, soundHost = pcall(build, src, char, hrp)
	if not ok then
		active -= 1
		warn("[Donation] efek " .. name .. " gagal dipasang: " .. tostring(root))
		return
	end
	for _, e in emitters do
		e.Enabled = true
	end
	local sound
	if spec.sound and soundHost then
		sound = Instance.new("Sound")
		sound.Name = "DonationFXSound"
		sound.SoundId = "rbxassetid://" .. spec.sound
		sound.Volume = FX.volume
		sound.RollOffMaxDistance = FX.hearDistance
		sound.Parent = soundHost
		sound:Play()
	end

	task.delay(spec.time, function()
		for _, e in emitters do
			if e.Parent then
				e.Enabled = false
			end
		end
		if sound and sound.Parent and sound.IsPlaying then
			TweenService:Create(sound, TweenInfo.new(FX.fadeOut), { Volume = 0 }):Play()
		end
		task.delay(math.max(FX.cleanup, FX.fadeOut), function()
			root:Destroy()
			active -= 1
		end)
	end)
end

effectEvent.OnClientEvent:Connect(function(userId, robux)
	userId, robux = tonumber(userId), tonumber(robux)
	if userId and robux then
		play(userId, robux)
	end
end)
