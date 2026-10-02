local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Warna tombol keluar: ReplicatedStorage.Modules.ThemeColor (themeColor) → ikut tema pilihan pemain.
local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local camFolder = workspace:WaitForChild("360Cam")
local camPart = camFolder:WaitForChild("Camera")
local centerPart = camFolder:WaitForChild("Center")

local prompt = camPart:FindFirstChild("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Activate 360 Cam"
	prompt.ObjectText = "360 Camera"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = camPart
end

local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "360CamGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui
ThemeColor.mark(screenGui)

local exitButton = Instance.new("TextButton")
exitButton.Name = "ExitButton"
exitButton.Size = UDim2.new(0.088, 0, 0.052, 0)
exitButton.Position = UDim2.new(0.9, 0, 0.585, 0)
exitButton.AnchorPoint = Vector2.new(0, 0)
exitButton.BackgroundColor3 = ThemeColor.tokens.BG
exitButton.BackgroundTransparency = 0.2
exitButton.BorderSizePixel = 0
exitButton.Text = "Exit 360 Cam"
exitButton.TextColor3 = ThemeColor.tokens.TEXT_STRONG
exitButton.Font = Enum.Font.GothamBold
exitButton.TextSize = 14
exitButton.Visible = false
exitButton.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = exitButton

local isActive = false
local rotationSpeed = 0.3
local distance = 15
local height = 5
local angle = 0
local connection
local originalPosition
local originalCamPartCFrame
local yOffset = 3

local function activate360Cam()
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
	local rootPart = player.Character.HumanoidRootPart

	originalPosition = rootPart.CFrame
	originalCamPartCFrame = camPart.CFrame

	local centerPos = centerPart.Position
	local newPos = Vector3.new(centerPos.X, centerPos.Y + (centerPart.Size.Y/2) + yOffset, centerPos.Z)
	rootPart.CFrame = CFrame.new(newPos)

	local humanoid = player.Character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	isActive = true
	exitButton.Visible = true
	prompt.Enabled = false
	camera.CameraType = Enum.CameraType.Scriptable
	angle = 0

	connection = RunService.RenderStepped:Connect(function(dt)
		if not isActive or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then 
			return 
		end
		local charRootPart = player.Character.HumanoidRootPart
		local centerPos = charRootPart.Position

		angle = angle + (rotationSpeed * dt)

		local x = centerPos.X + (distance * math.cos(angle))
		local z = centerPos.Z + (distance * math.sin(angle))
		local y = centerPos.Y + height

		local camPos = Vector3.new(x, y, z)

		camera.CFrame = CFrame.new(camPos, centerPos)
		camPart.CFrame = CFrame.new(camPos, centerPos)
	end)
end

local function deactivate360Cam()
	isActive = false
	angle = 0
	exitButton.Visible = false
	prompt.Enabled = true

	if connection then
		connection:Disconnect()
		connection = nil
	end

	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") and originalPosition then
		player.Character.HumanoidRootPart.CFrame = originalPosition
	end

	if originalCamPartCFrame then
		camPart.CFrame = originalCamPartCFrame
	end

	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	if humanoid then
		-- Masih menari/sync → kembali ke kecepatan dance (6), bukan 16.
		local dancing = player:GetAttribute("IsDancing") == true or player:GetAttribute("IsSyncing") == true
		local modules = ReplicatedStorage:FindFirstChild("Modules")
		local shared  = modules and modules:FindFirstChild("DanceShared")
		local ok, DanceShared = pcall(function() return shared and require(shared) end)
		local danceSpeed = (ok and DanceShared and DanceShared.WALKSPEED.dance) or 6
		humanoid.WalkSpeed = dancing and danceSpeed or 16
		humanoid.JumpPower = 50
	end

	if player.Character and player.Character:FindFirstChild("Humanoid") then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = player.Character.Humanoid
	end
end

prompt.Triggered:Connect(function()
	if not isActive then
		activate360Cam()
	end
end)

exitButton.MouseButton1Click:Connect(function()
	if isActive then
		deactivate360Cam()
	end
end)

player.CharacterAdded:Connect(function()
	if isActive then
		deactivate360Cam()
	end
end)