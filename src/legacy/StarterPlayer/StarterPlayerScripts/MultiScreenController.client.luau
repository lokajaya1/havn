local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FADE_TIME = 0.4
local STAGE_MODEL_NAME = "DJ STAGE"
local SCREEN_FOLDER_NAME = "StageScreens"
local CAM_DIST = 9
local CAM_H = 2.5
local CAM_LOOK = 1.5
local CAM_FOV = 50

local liveSystem = ReplicatedStorage:WaitForChild("LiveSystem")
local currentTargetVal = liveSystem:WaitForChild("CurrentTarget")
local cameraModeVal = liveSystem:WaitForChild("CameraMode")
local screenModeVal = liveSystem:WaitForChild("ScreenMode")

local stageModel = Workspace:WaitForChild(STAGE_MODEL_NAME, 10)
local screenFolder = stageModel and stageModel:WaitForChild(SCREEN_FOLDER_NAME, 5)
if not screenFolder then warn("[MultiScreen] Folder not found") return end
print("✅ [MultiScreen] Found:", screenFolder:GetFullName())

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeScreens = {}
local targetPlayerObj = nil
local currentPlayerName = ""
local motorCache = {}
local isSettingUp = false
local currentScreenMode = "VJ"

-- ═══════════════════════════════════════════════════════════

local function getBiggestFace(part)
	local s = part.Size
	local faces = {
		{Enum.NormalId.Front, s.X * s.Y},
		{Enum.NormalId.Back, s.X * s.Y},
		{Enum.NormalId.Top, s.X * s.Z},
		{Enum.NormalId.Bottom, s.X * s.Z},
		{Enum.NormalId.Right, s.Z * s.Y},
		{Enum.NormalId.Left, s.Z * s.Y},
	}
	local best, bestArea = Enum.NormalId.Front, 0
	for _, f in ipairs(faces) do
		if f[2] > bestArea then best, bestArea = f[1], f[2] end
	end
	return best
end

local function createScreenOnPart(part)
	if not part:IsA("BasePart") then return end
	for _, sd in ipairs(activeScreens) do
		if sd.Part == part then return end
	end

	local face = getBiggestFace(part)

	-- ★ SurfaceGui di PLAYERGUI dengan Adornee — render ON TOP of VJ
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveScreen_" .. part.Name .. "_" .. (#activeScreens + 1)
	gui.Face = face
	gui.Adornee = part
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.ZOffset = 1 -- di atas VJ SurfaceGui
	gui.Enabled = false
	gui.Parent = playerGui -- ★ KUNCI: parent ke PlayerGui!

	local vp = Instance.new("ViewportFrame")
	vp.Name = "VP"
	vp.Size = UDim2.new(1, 0, 1, 0)
	vp.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vp.BackgroundTransparency = 0
	vp.ImageTransparency = 0
	vp.BorderSizePixel = 0
	pcall(function() vp.Ambient = Color3.fromRGB(180, 180, 180) end)
	pcall(function() vp.LightColor = Color3.fromRGB(255, 255, 255) end)
	pcall(function() vp.LightDirection = Vector3.new(-1, -1, -1) end)
	vp.Parent = gui

	local cam = Instance.new("Camera")
	cam.FieldOfView = CAM_FOV
	cam.CFrame = CFrame.lookAt(Vector3.new(0, CAM_H, CAM_DIST), Vector3.new(0, CAM_LOOK, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam

	local wm = Instance.new("WorldModel")
	wm.Parent = vp

	table.insert(activeScreens, {
		Gui = gui, Viewport = vp, WorldModel = wm, Cam = cam,
		Clone = nil, Part = part, Face = face
	})

	print(string.format("  [Screen] %s | Face:%s | Size:%s | Parent:PlayerGui", part.Name, tostring(face), tostring(part.Size)))
end

-- ═══════════════════════════════════════════════════════════

local function clearAll()
	table.clear(motorCache)
	for _, sd in ipairs(activeScreens) do
		if sd.Clone then sd.Clone:Destroy() sd.Clone = nil end
		sd.WorldModel:ClearAllChildren()
	end
end

local function cleanClone(clone)
	local kill = {}
	for _, x in ipairs(clone:GetDescendants()) do
		if x:IsA("BaseScript") or x:IsA("Sound") or x:IsA("Tool")
			or x:IsA("ForceField") or x:IsA("BillboardGui")
			or x:IsA("ParticleEmitter") or x:IsA("Fire") or x:IsA("Smoke")
			or x:IsA("Sparkles") or x:IsA("Trail") or x:IsA("Beam")
			or x:IsA("Highlight") or x:IsA("SelectionBox") then
			table.insert(kill, x)
		end
	end
	for _, x in ipairs(kill) do x:Destroy() end
	local h = clone:FindFirstChildOfClass("Humanoid")
	if h then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
		pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
	end
end

local function buildMotors(realChar, clones)
	table.clear(motorCache)
	local rm = {}
	for _, o in ipairs(realChar:GetDescendants()) do
		if o:IsA("Motor6D") then table.insert(rm, o) end
	end
	for _, cl in ipairs(clones) do
		for _, m in ipairs(rm) do
			local cm = cl:FindFirstChild(m.Name, true)
			if cm and cm:IsA("Motor6D") then
				if not motorCache[m] then motorCache[m] = {} end
				table.insert(motorCache[m], cm)
			end
		end
	end
end

local function setupDisplays(pName)
	if isSettingUp then return end
	isSettingUp = true
	clearAll()

	if not pName or pName == "" then
		currentPlayerName = "" targetPlayerObj = nil isSettingUp = false return
	end

	local p = Players:FindFirstChild(pName)
	if not p or not p.Character then
		warn("[MultiScreen] No player/char:", tostring(pName))
		isSettingUp = false return
	end

	local rc = p.Character
	local rr = rc:FindFirstChild("HumanoidRootPart")
	if not rr then isSettingUp = false return end

	targetPlayerObj = p
	currentPlayerName = pName
	local origA = rc.Archivable
	rc.Archivable = true

	local mode = cameraModeVal.Value
	local allC = {}

	for i, sd in ipairs(activeScreens) do
		sd.WorldModel:ClearAllChildren()

		local ok, cl = pcall(function() return rc:Clone() end)
		if not ok or not cl then warn("[MultiScreen] Clone fail", i) continue end

		local hrp = cl:FindFirstChild("HumanoidRootPart")
		if not hrp then cl:Destroy() continue end

		cl.PrimaryPart = hrp
		cl.Name = "Actor"
		cleanClone(cl)
		cl.Parent = sd.WorldModel

		local cf
		if mode == "Dynamic" then
			local _, y, _ = rr.CFrame:ToOrientation()
			cf = CFrame.Angles(0, y + math.pi, 0)
		else
			cf = CFrame.Angles(0, math.pi, 0)
		end
		pcall(function() cl:PivotTo(cf) end)

		sd.Cam.CFrame = CFrame.lookAt(Vector3.new(0, CAM_H, CAM_DIST), Vector3.new(0, CAM_LOOK, 0))
		sd.Viewport.CurrentCamera = sd.Cam
		sd.Clone = cl
		table.insert(allC, cl)

		print(string.format("  [%d] %s | HRP:%s | WM:%d", i, sd.Part.Name, tostring(hrp.Position), #sd.WorldModel:GetChildren()))
	end

	rc.Archivable = origA
	if #allC > 0 then buildMotors(rc, allC) end
	isSettingUp = false
	print("[MultiScreen] ✅ Done:", pName, "| Clones:", #allC)
end

-- ═══════════════════════════════════════════════════════════

local function setGUIs(on)
	for _, sd in ipairs(activeScreens) do sd.Gui.Enabled = on end
end

local ver = 0

local function onModeChanged(m)
	ver += 1
	local v = ver
	currentScreenMode = m
	print("[MultiScreen] Mode:", m, "V:", v)

	if m == "VJ" then
		task.delay(FADE_TIME * 0.5, function()
			if ver == v then setGUIs(false) clearAll() end
		end)
	elseif m == "Live" then
		task.delay(FADE_TIME + 0.05, function()
			if ver ~= v then return end
			setGUIs(true)
			local t = currentTargetVal.Value
			if t and t ~= "" then setupDisplays(t) end
			task.defer(function()
				for _, sd in ipairs(activeScreens) do
					sd.Viewport.CurrentCamera = sd.Cam
				end
			end)
		end)
	end
end

-- ═══════════════════════════════════════════════════════════

local fc = 0
RunService.RenderStepped:Connect(function()
	if currentScreenMode ~= "Live" then return end

	for _, sd in ipairs(activeScreens) do
		if sd.Gui.Enabled and sd.Viewport.CurrentCamera ~= sd.Cam then
			sd.Viewport.CurrentCamera = sd.Cam
		end
	end

	if not targetPlayerObj or not targetPlayerObj.Parent then
		if targetPlayerObj then clearAll() targetPlayerObj = nil currentPlayerName = "" end
		return
	end

	local rc = targetPlayerObj.Character
	if not rc then return end
	local rr = rc:FindFirstChild("HumanoidRootPart")
	if not rr then return end

	for rm, cms in pairs(motorCache) do
		if rm.Parent then
			local t = rm.Transform
			for _, cm in ipairs(cms) do if cm.Parent then cm.Transform = t end end
		end
	end

	fc += 1
	if fc % 2 == 0 then
		local static = cameraModeVal.Value == "Static"
		local yR
		if not static then local _, y, _ = rr.CFrame:ToOrientation() yR = y end
		for _, sd in ipairs(activeScreens) do
			local c = sd.Clone
			if c and c.PrimaryPart then
				if static then
					pcall(function() c:PivotTo(CFrame.Angles(0, math.pi, 0)) end)
				else
					pcall(function() c:PivotTo(CFrame.Angles(0, yR + math.pi, 0)) end)
				end
			end
		end
	end
end)

-- ═══════════════════════════════════════════════════════════

local function init()
	for _, c in ipairs(screenFolder:GetChildren()) do createScreenOnPart(c) end
	screenFolder.ChildAdded:Connect(function(c) task.wait(0.1) createScreenOnPart(c) end)
	print("✅ [MultiScreen] Init. Screens:", #activeScreens)
end

init()

currentTargetVal.Changed:Connect(function(v)
	print("[MultiScreen] Target:", v)
	if currentScreenMode == "Live" then setGUIs(true) setupDisplays(v) end
end)

cameraModeVal.Changed:Connect(function()
	if currentScreenMode == "Live" and currentPlayerName ~= "" then setupDisplays(currentPlayerName) end
end)

screenModeVal.Changed:Connect(function(m) onModeChanged(m) end)

Players.PlayerRemoving:Connect(function(lp)
	if targetPlayerObj and lp == targetPlayerObj then clearAll() targetPlayerObj = nil currentPlayerName = "" end
end)

task.spawn(function()
	while true do
		task.wait(3)
		if currentScreenMode == "Live" and currentPlayerName ~= "" then
			local has = false
			for _, sd in ipairs(activeScreens) do if sd.Clone and sd.Clone.Parent then has = true break end end
			if not has then setGUIs(true) setupDisplays(currentPlayerName) end
		end
	end
end)

if screenModeVal.Value == "Live" then onModeChanged("Live") end
print("✅ [MultiScreen] Ready | Screens:", #activeScreens)