-- ============================================
--  🪞 MIRROR SCRIPT - LocalScript
--  Taruh di: StarterPlayerScripts
-- ============================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============================================
-- KONFIGURASI — ganti sesuai nama di Explorer
-- ============================================
local MIRROR_PATH = {
	"Toilet",   -- level 1 dari Workspace
	"Folder",   -- level 2
	"Glass K"   -- level 3 — GANTI jika nama beda
}
local MAX_DISTANCE = 50

-- ============================================
-- Cari mirror part dengan debug otomatis
-- ============================================
local function findMirrorPart()
	local current = workspace

	for i, name in ipairs(MIRROR_PATH) do
		local found = current:WaitForChild(name, 5) -- timeout 5 detik

		if not found then
			warn("❌ Tidak ditemukan: '" .. name .. "' di dalam '" .. current.Name .. "'")

			-- Print semua anak supaya bisa cek nama aslinya
			warn("📋 Isi dari '" .. current.Name .. "':")
			for _, child in ipairs(current:GetChildren()) do
				warn("   → " .. child.Name .. " [" .. child.ClassName .. "]")
			end
			return nil
		end

		current = found
	end

	print("✅ Mirror part ditemukan: " .. current:GetFullName())
	return current
end

local mirrorPart = findMirrorPart()
if not mirrorPart then
	warn("🛑 Mirror Script berhenti — perbaiki path di MIRROR_PATH.")
	return
end

-- ============================================
-- Hapus MirrorGui lama (anti duplikat)
-- ============================================
local old = mirrorPart:FindFirstChild("MirrorGui")
if old then old:Destroy() end

-- ============================================
-- Buat SurfaceGui + ViewportFrame
-- ============================================
local surfaceGui = Instance.new("SurfaceGui")
surfaceGui.Name           = "MirrorGui"
surfaceGui.Face           = Enum.NormalId.Front
surfaceGui.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
surfaceGui.PixelsPerStud  = 150
surfaceGui.LightInfluence = 0
surfaceGui.Parent         = mirrorPart

local viewport = Instance.new("ViewportFrame")
viewport.Size                   = UDim2.new(1, 0, 1, 0)
viewport.BackgroundColor3       = Color3.fromRGB(20, 20, 30)
viewport.BackgroundTransparency = 0
viewport.Ambient                = Color3.fromRGB(180, 180, 200)
viewport.LightColor             = Color3.fromRGB(255, 255, 245)
viewport.LightDirection         = Vector3.new(-1, -2, -1)
viewport.Parent                 = surfaceGui

local vpCamera = Instance.new("Camera")
vpCamera.Parent        = viewport
viewport.CurrentCamera = vpCamera

-- ============================================
-- Fungsi refleksi kamera terhadap cermin
-- ============================================
local function getMirrorCamera(camCF, playerPos)
	local mirrorNormal = mirrorPart.CFrame.LookVector
	local mirrorPos    = mirrorPart.CFrame.Position

	local d    = (camCF.Position - mirrorPos):Dot(mirrorNormal)
	local rPos = camCF.Position - 2 * d * mirrorNormal

	local dP    = (playerPos - mirrorPos):Dot(mirrorNormal)
	local rLook = playerPos - 2 * dP * mirrorNormal

	local up  = camCF.UpVector
	local rUp = up - 2 * (up:Dot(mirrorNormal)) * mirrorNormal

	return CFrame.lookAt(rPos, rLook, rUp)
end

-- ============================================
-- Clone karakter ke ViewportFrame
-- ============================================
local charClone = nil

local function buildClone(character)
	if charClone then charClone:Destroy(); charClone = nil end
	task.wait(1)

	local clone = character:Clone()

	for _, v in clone:GetDescendants() do
		if v:IsA("BaseScript") or v:IsA("ModuleScript") then
			v:Destroy()
		elseif v:IsA("BasePart") then
			v.Anchored   = true
			v.CanCollide = false
		elseif v:IsA("BillboardGui") or v:IsA("SurfaceGui") then
			v:Destroy()
		end
	end

	clone.Parent = viewport
	charClone    = clone
	print("✅ Clone karakter berhasil! Cermin aktif.")
end

-- ============================================
-- Sync pose + animasi (Motor6D)
-- ============================================
local function syncPose(character)
	if not charClone then return end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local cp = charClone:FindFirstChild(part.Name, true)
			if cp and cp:IsA("BasePart") then
				cp.CFrame = part.CFrame
			end
		end

		if part:IsA("Motor6D") then
			local cm = charClone:FindFirstChild(part.Name, true)
			if cm and cm:IsA("Motor6D") then
				cm.CurrentAngle = part.CurrentAngle
				cm.Transform    = part.Transform
			end
		end
	end
end

-- ============================================
-- Init
-- ============================================
if player.Character then
	buildClone(player.Character)
end

player.CharacterAdded:Connect(function(char)
	buildClone(char)
end)

-- ============================================
-- Update loop
-- ============================================
RunService.RenderStepped:Connect(function()
	local char = player.Character
	if not char or not charClone then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if (hrp.Position - mirrorPart.Position).Magnitude > MAX_DISTANCE then return end

	syncPose(char)

	local mirrorCF = getMirrorCamera(camera.CFrame, hrp.Position)
	vpCamera.CFrame      = mirrorCF
	vpCamera.FieldOfView = camera.FieldOfView
end)

print("🪞 Mirror Script aktif!")