-- StarterPlayerScripts/DonationCinematic  (LocalScript)
-- Kamera sinematik donasi: server mengirim mode di DonationRemotes.Effect(userId, robux, cam) — `cam` dari tier
-- (bawaan kosong = OFF) atau pilihan admin (Test Effect) → kamera menyorot donatur dari depan selama `cinematic.hold`
-- detik + letterbox & vignette, lalu kembali mulus. Sinyal sama dengan partikel DonationFX (hanya server donatur).
-- Dilewati kalau: Effects OFF (atribut LocalPlayer "DonationFX" = false), kamera sedang Scriptable (FreeCam / 360 /
-- LiveScreen memakai kamera), donatur/karakter tidak ada, atau sinematik lain sedang jalan.
-- Gerak kamera mengikuti pola CineFront BebeqClientEffects (ditulis ulang, hanya 5 mode).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Config = require(RS:WaitForChild("DonationConfig"))
local remotes = RS:WaitForChild("DonationRemotes", 30)
local effectEvent = remotes and remotes:WaitForChild("Effect", 30)
if not effectEvent then
	return
end
local C = Config.cinematic

local function smooth(a)
	return a * a * (3 - 2 * a)
end

-- mode → function(hrp, a 0..1, elapsed) → posisi kamera, titik fokus, lerp, roll (radian)
local SHOTS = {
	Hero = function(hrp, a) -- sudut rendah dari depan, mendekat pelan
		local d = 13 + (10 - 13) * a
		return (hrp.CFrame * CFrame.new(0, -2.5, -d)).Position, hrp.Position + Vector3.new(0, 2.5, 0), 0.16
	end,
	Push = function(hrp, a) -- dorong sangat pelan ke wajah
		local d = 16 + (9 - 16) * a
		return (hrp.CFrame * CFrame.new(0, 2, -d)).Position, hrp.Position + Vector3.new(0, 2, 0), 0.12
	end,
	Arc = function(hrp, a) -- setengah lingkaran di depan (kiri → kanan), wajah selalu terlihat
		a = a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2
		local ang = math.rad(-55) + math.rad(110) * a
		return (hrp.CFrame * CFrame.Angles(0, ang, 0) * CFrame.new(0, 4, -14)).Position, hrp.Position + Vector3.new(0, 1.5, 0), 0.2
	end,
	Crane = function(hrp, a) -- turun dari atas-depan ke setinggi mata
		a = smooth(a)
		local h, d = 22 + (4 - 22) * a, 10 + (12 - 10) * a
		return (hrp.CFrame * CFrame.new(0, h, -d)).Position, hrp.Position + Vector3.new(0, 1.5, 0), 0.16
	end,
	Orbit = function(hrp, a) -- mengorbit rendah 360°
		local pos = (CFrame.new(hrp.Position) * CFrame.Angles(0, a * math.pi * 2, 0) * CFrame.new(0, -2, -14)).Position
		return pos, hrp.Position + Vector3.new(0, 2.5, 0), 0.25
	end,
}

-- ── Letterbox + vignette ───────────────────────────────────────────────────
local overlay
local function ensureOverlay()
	if overlay and overlay.Parent then
		return overlay
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DonationCinematic"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Enabled = false
	-- Frame biasa (bukan CanvasGroup): CanvasGroup bisa jatuh ke mode tanpa GroupTransparency → vignette tidak hilang.
	local vig = Instance.new("Frame")
	vig.Name = "Vignette"
	vig.BackgroundTransparency = 1
	vig.Size = UDim2.fromScale(1, 1)
	vig.Parent = gui
	for _, e in {
		{ Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0), UDim2.new(1, 0, 0.35, 0), 90, 0, 1 },
		{ Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, 0), UDim2.new(1, 0, 0.35, 0), 90, 1, 0 },
		{ Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0), UDim2.new(0.35, 0, 1, 0), 0, 0, 1 },
		{ Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.new(0.35, 0, 1, 0), 0, 1, 0 },
	} do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.AnchorPoint, f.Position, f.Size = e[1], e[2], e[3]
		local g = Instance.new("UIGradient")
		g.Rotation = e[4]
		g.Transparency = NumberSequence.new(e[5], e[6])
		g.Parent = f
		f.Parent = vig
	end
	for _, bar in { { "TopBar", 0 }, { "BottomBar", 1 } } do
		local f = Instance.new("Frame")
		f.Name = bar[1]
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, bar[2])
		f.Position = UDim2.new(0.5, 0, bar[2], 0)
		f.Size = UDim2.new(1, 0, 0, 0)
		f.ZIndex = 2
		f.Parent = gui
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	overlay = gui
	return gui
end
local function showOverlay(on)
	local gui = ensureOverlay()
	gui.Enabled = true
	local info = TweenInfo.new(C.fade, Enum.EasingStyle.Quad, on and Enum.EasingDirection.Out or Enum.EasingDirection.In)
	local bar = UDim2.new(1, 0, on and C.bars or 0, 0)
	TweenService:Create(gui.TopBar, info, { Size = bar }):Play()
	TweenService:Create(gui.BottomBar, info, { Size = bar }):Play()
	for _, f in gui.Vignette:GetChildren() do
		TweenService:Create(f, info, { BackgroundTransparency = on and C.vignette or 1 }):Play()
	end
end
local function hideOverlay() -- pasti hilang: semua transparan + ScreenGui dimatikan
	if overlay then
		overlay.Enabled = false
		overlay.TopBar.Size = UDim2.new(1, 0, 0, 0)
		overlay.BottomBar.Size = UDim2.new(1, 0, 0, 0)
		for _, f in overlay.Vignette:GetChildren() do
			f.BackgroundTransparency = 1
		end
	end
end

-- ── Jalankan ───────────────────────────────────────────────────────────────
local active = false
local function run(userId, mode)
	local shot = type(mode) == "string" and SHOTS[mode]
	local cam = workspace.CurrentCamera
	if active or not shot or not cam or player:GetAttribute("DonationFX") == false then
		return
	end
	if cam.CameraType == Enum.CameraType.Scriptable then
		return -- kamera sedang dipakai skrip lain (FreeCam / 360 / LiveScreen)
	end
	local donor = Players:GetPlayerByUserId(tonumber(userId) or 0)
	local char = donor and donor.Character
	if not (char and char:FindFirstChild("HumanoidRootPart")) then
		return
	end
	active = true
	local prevType, prevCFrame = cam.CameraType, cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	pcall(showOverlay, true)
	local ok, err = pcall(function()
		local elapsed = 0
		while elapsed < C.hold do
			elapsed += RunService.RenderStepped:Wait()
			local hrp = char.Parent and char:FindFirstChild("HumanoidRootPart")
			if not hrp or cam.CameraType ~= Enum.CameraType.Scriptable then
				break -- donatur pergi / kamera diambil alih
			end
			local pos, focus, lerp = shot(hrp, math.min(elapsed / C.hold, 1), elapsed)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(pos, focus), lerp)
		end
	end)
	if not ok then
		warn("[Donation] sinematik gagal: " .. tostring(err))
	end
	pcall(showOverlay, false)
	pcall(function()
		local t = TweenService:Create(cam, TweenInfo.new(C.back, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = prevCFrame })
		t:Play()
		t.Completed:Wait()
	end)
	if C.fade > C.back then
		task.wait(C.fade - C.back)
	end
	pcall(hideOverlay)
	if cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = prevType
	end
	active = false
end

effectEvent.OnClientEvent:Connect(function(userId, _robux, cam)
	task.spawn(run, userId, cam)
end)
