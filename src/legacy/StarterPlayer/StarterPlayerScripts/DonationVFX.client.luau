local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local VFXUtils = require(RS:WaitForChild("VFX"):WaitForChild("VFXUtils"))
local localPlayer = Players.LocalPlayer

local RemoteFolder = RS:WaitForChild("DonationRemotes", 30)
if not RemoteFolder then return end
local VFXFolder = RS:WaitForChild("VFX", 10)
if not VFXFolder then return end

local PEAK_VOL, FADE_IN, FADE_OUT, MAX_ACTIVE = 0.50, 0.30, 1.20, 3

local TIER_SOUND_NAME = {
	[1]="DonationLevel1", [2]="DonationLevel2", [3]="DonationLevel3", [4]="DonationLevel4",
	[5]="DonationLevel5", [6]="DonationLevel6", [7]="DonationLevel6",
}

local TIER_CFG = {
	[1] = {dur=3.0, lRange=12, lBright=1.5, lColor=Color3.fromRGB(255,255,150), folder="Level1", maxRate=20, maxLife=1.5},
	[2] = {dur=3.5, lRange=14, lBright=1.8, lColor=Color3.fromRGB(255,220,100), folder="Level2", maxRate=25, maxLife=2.0},
	[3] = {dur=4.0, lRange=16, lBright=2.0, lColor=Color3.fromRGB(255,180,80),  folder="Level3", maxRate=30, maxLife=2.0},
	[4] = {dur=4.5, lRange=18, lBright=2.2, lColor=Color3.fromRGB(255,140,60),  folder="Level4", maxRate=35, maxLife=2.5},
	[5] = {dur=10.0,lRange=20, lBright=2.5, lColor=Color3.fromRGB(255,100,50),  folder="Level5", maxRate=40, maxLife=2.5},
	[6] = {dur=18.0,lRange=22, lBright=2.8, lColor=Color3.fromRGB(220,80,255),  folder="Level6", maxRate=50, maxLife=3.0},
	[7] = {dur=20.0,lRange=24, lBright=3.0, lColor=Color3.fromRGB(80,200,255),  folder="Effects", maxRate=60, maxLife=3.0},
}

local REMOTE_TO_TIER = {
	FireLevel1=1, FireLevel2=2, FireLevel3=3, FireLevel4=4,
	FireLevel5=5, FireLevel6=6, FireLevel7=7,
}

local SoundsFolder = VFXFolder:FindFirstChild("Sounds")
local soundByTier = {}
local soundsReady = false
local activeCount = 0

if SoundsFolder then
	local preloadList = {}
	for tier, soundName in pairs(TIER_SOUND_NAME) do
		local snd = SoundsFolder:FindFirstChild(soundName)
		if snd and snd:IsA("Sound") then
			soundByTier[tier] = snd
			if not table.find(preloadList, snd) then table.insert(preloadList, snd) end
		end
	end
	task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, preloadList); soundsReady = true end)
else
	soundsReady = true
end

local function waitUntilReady(timeout)
	if soundsReady then return end
	local t = tick()
	while not soundsReady and (tick()-t) < timeout do task.wait(0.2) end
end

local function clampEmitter(e, maxRate, maxLife)
	if e.Rate > maxRate then e.Rate = maxRate end
	if e.Lifetime.Max > maxLife then e.Lifetime = NumberRange.new(math.min(e.Lifetime.Min, maxLife*0.5), maxLife) end
end

local function forEachEmitter(inst, fn)
	if inst:IsA("ParticleEmitter") then pcall(fn, inst) end
	for _, d in ipairs(inst:GetDescendants()) do if d:IsA("ParticleEmitter") then pcall(fn, d) end end
end

local function setEmitters(inst, enabled)
	local function apply(d) if d:IsA("ParticleEmitter") or d:IsA("Trail") then d.Enabled = enabled end end
	pcall(function() apply(inst); for _, d in ipairs(inst:GetDescendants()) do apply(d) end end)
end

local function getDonorHRP(userId)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then local c = p.Character; if c then return c:FindFirstChild("HumanoidRootPart") end end
	end
	local c = localPlayer.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function attachToHRP(clone, hrp)
	local char = hrp.Parent
	if clone:IsA("Model") then
		pcall(function()
			if clone.PrimaryPart then clone:SetPrimaryPartCFrame(hrp.CFrame) else clone:PivotTo(hrp.CFrame) end
		end)
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false; part.CanCollide = false
				local w = Instance.new("WeldConstraint"); w.Part0 = hrp; w.Part1 = part; w.Parent = part
			end
		end
		clone.Parent = char
	elseif clone:IsA("BasePart") then
		clone.CFrame = hrp.CFrame; clone.Anchored = false; clone.CanCollide = false
		local w = Instance.new("WeldConstraint"); w.Part0 = hrp; w.Part1 = clone; w.Parent = clone
		clone.Parent = char
	else
		clone.Parent = hrp
	end
end

local function playTierSound(tier)
	local template = soundByTier[tier]
	if not template then return end
	waitUntilReady(15)
	local snd = template:Clone(); snd.Volume = 0; snd.Name = "DonationSFX_Tier"..tier; snd.Parent = SoundService
	if not snd.IsLoaded then
		local t = tick()
		while not snd.IsLoaded and (tick()-t) < 5 do task.wait(0.1) end
		if not snd.IsLoaded then snd:Destroy(); return end
	end
	snd:Play()
	VFXUtils.tw(snd, FADE_IN, {Volume = PEAK_VOL}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeOutStart = math.max(0.1, (snd.TimeLength or 3) - FADE_IN - FADE_OUT)
	task.delay(fadeOutStart, function()
		if snd and snd.Parent and snd.IsPlaying then
			VFXUtils.tw(snd, FADE_OUT, {Volume = 0}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	task.delay(fadeOutStart + FADE_OUT + 0.5, function() VFXUtils.safeDestroy(snd) end)
end

local SKIP_CLASSES = {PointLight=true, SpotLight=true, SurfaceLight=true, Folder=true}

local function spawnEffects(userId, tier)
	if activeCount >= MAX_ACTIVE then return end
	activeCount += 1
	local cfg = TIER_CFG[tier]
	if not cfg then activeCount = math.max(0, activeCount-1); return end
	local hrp = getDonorHRP(userId)
	if not hrp then activeCount = math.max(0, activeCount-1); return end
	local tierFolder = VFXFolder:FindFirstChild(cfg.folder)
	if not tierFolder then
		for fb = 6, 1, -1 do tierFolder = VFXFolder:FindFirstChild("Level"..fb); if tierFolder then break end end
		if not tierFolder then activeCount = math.max(0, activeCount-1); return end
	end
	local dur = cfg.dur
	local pl = Instance.new("PointLight"); pl.Brightness = 0; pl.Range = 0; pl.Color = cfg.lColor; pl.Parent = hrp
	VFXUtils.tw(pl, 0.3, {Brightness = cfg.lBright, Range = cfg.lRange})
	task.delay(dur-0.8, function()
		if pl and pl.Parent then VFXUtils.tw(pl, 0.8, {Brightness = 0, Range = 0}, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	end)
	local clones = {}
	for _, tmpl in ipairs(tierFolder:GetChildren()) do
		if SKIP_CLASSES[tmpl.ClassName] then continue end
		local ok, clone = pcall(tmpl.Clone, tmpl)
		if not ok or not clone then continue end
		table.insert(clones, clone)
		forEachEmitter(clone, function(e) clampEmitter(e, cfg.maxRate, cfg.maxLife) end)
		setEmitters(clone, false)
		attachToHRP(clone, hrp)
		task.defer(function() if clone and clone.Parent then setEmitters(clone, true) end end)
		task.delay(dur-0.5, function() if clone and clone.Parent then setEmitters(clone, false) end end)
	end
	task.delay(dur+2, function()
		for _, c in ipairs(clones) do VFXUtils.safeDestroy(c) end
		VFXUtils.safeDestroy(pl)
		activeCount = math.max(0, activeCount-1)
	end)
end

local function handleDonation(tier, _, _, _, userId)
	if localPlayer:GetAttribute("GlobalEffects") == false then return end
	task.spawn(playTierSound, tier)
	task.spawn(spawnEffects, userId, tier)
end

for remoteName, tier in pairs(REMOTE_TO_TIER) do
	local remote = RemoteFolder:WaitForChild(remoteName, 10)
	if remote then
		remote.OnClientEvent:Connect(function(donorName, recipient, price, userId)
			handleDonation(tier, donorName, recipient, price, userId)
		end)
	end
end