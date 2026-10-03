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
local REBUILD_DELAY = 1 -- detik: tunggu karakter baru (respawn) lengkap sebelum disalin ulang ke layar
local PROBE_WARMUP = 5 -- frame pertama sesudah salinan tidak dinilai (klon baru dipasang, part masih berpindah)
local PROBE_MAX_FRAMES = 600 -- cek-otomatis pose klon (stepProbe) berhenti sesudah sekian frame tanpa keputusan

local liveSystem = ReplicatedStorage:WaitForChild("LiveSystem")
local currentTargetVal = liveSystem:WaitForChild("CurrentTarget")
local cameraModeVal = liveSystem:WaitForChild("CameraMode")
local screenModeVal = liveSystem:WaitForChild("ScreenMode")

local stageModel = Workspace:WaitForChild(STAGE_MODEL_NAME, 10)
-- [FIX 4a] StageScreens sekarang ada di DJ STAGE > stage > StageScreens (dulu langsung di DJ STAGE) → cari bertingkat
local function findScreenFolder(root)
	if not root then return nil end
	local found = root:FindFirstChild(SCREEN_FOLDER_NAME, true)
	if found then return found end
	local stage = root:WaitForChild("stage", 10)
	return (stage and stage:WaitForChild(SCREEN_FOLDER_NAME, 5)) or root:FindFirstChild(SCREEN_FOLDER_NAME, true)
end
local screenFolder = findScreenFolder(stageModel)
if not screenFolder then warn("[MultiScreen] Folder not found") return end
print("✅ [MultiScreen] Found:", screenFolder:GetFullName())

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeScreens = {}
local targetPlayerObj = nil
local currentPlayerName = ""
local jointPairs = {} -- [klon] = { root = HumanoidRootPart klon, reals = {sendi asli}, clones = {sendi klon} } (urutan sama)
local isSettingUp = false
local currentScreenMode = "Gambar"
-- [FIX avatar Live diam] (ruangan WORLD, claude/Rencana_World.md §15)
local lodAnimator = nil -- Animator target yang penghemat animasinya sedang dimatikan di client ini
local lodPrev = nil
local setupChar = nil -- karakter yang terakhir disalin ke layar
local charConn = nil -- CharacterAdded target (respawn → salin ulang)
local accConns = {} -- aksesori target dipasang/dilepas → salin ulang
local accDirty = false
local lastRebuild = 0
-- [FIX baju layered hilang] (§16) Klon memakai sendinya sendiri. Kalau mesin ternyata tidak menggerakkan
-- AnimationConstraint di WorldModel, cek-otomatis (stepProbe) memindah klon ke Motor6D untuk sisa sesi (useMotor).
local useMotor = false
local probe = nil

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

	-- ★ SurfaceGui di PLAYERGUI dengan Adornee — tampil DI ATAS layar gambar (DjStageClient)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveScreen_" .. part.Name .. "_" .. (#activeScreens + 1)
	gui.Face = face
	gui.Adornee = part
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.ZOffset = 1 -- di atas SurfaceGui layar gambar
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

-- Roblox melewati pose karakter yang jauh / tidak terlihat kamera di tiap client (ClientAnimatorThrottling, selalu
-- aktif sejak 29 Apr 2026) → layar menyalin pose yang tidak bergerak. Target yang sedang tampil dihitung penuh di
-- client ini (Animator.PreferLodEnabled = false; hanya 1 karakter), nilai lama dikembalikan saat target ganti/selesai.
local function releaseLod()
	local a, prev = lodAnimator, lodPrev
	lodAnimator, lodPrev = nil, nil
	if a then
		pcall(function() a.PreferLodEnabled = prev end)
	end
end

local function holdLod(char)
	releaseLod()
	local hum = char:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if not anim then return end
	local okRead, prev = pcall(function() return anim.PreferLodEnabled end)
	if okRead and pcall(function() anim.PreferLodEnabled = false end) then
		lodAnimator, lodPrev = anim, prev
	end
end

local function clearAll()
	releaseLod()
	setupChar = nil
	probe = nil
	accDirty = false
	if charConn then charConn:Disconnect() charConn = nil end
	for _, c in ipairs(accConns) do c:Disconnect() end
	table.clear(accConns)
	table.clear(jointPairs)
	for _, sd in ipairs(activeScreens) do
		if sd.Clone then sd.Clone:Destroy() sd.Clone = nil end
		sd.WorldModel:ClearAllChildren()
	end
end

-- Cadangan (lihat stepProbe): AnimationConstraint klon → Motor6D dengan titik sendi yang sama (C0/C1 = CFrame
-- Attachment, Part0/Part1 = induk Attachment). Nama & induk tetap → pasangan sendi asli ↔ klon tidak berubah.
local function toMotors(clone)
	for _, ac in ipairs(clone:GetDescendants()) do
		if ac:IsA("AnimationConstraint") then
			local a0, a1 = ac.Attachment0, ac.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local m = Instance.new("Motor6D")
				m.Name = ac.Name
				m.Part0 = p0
				m.Part1 = p1
				m.C0 = a0.CFrame
				m.C1 = a1.CFrame
				m.Parent = ac.Parent
				ac:Destroy()
			end
		end
	end
end

local function cleanClone(clone, hrp)
	local kill = {}
	for _, x in ipairs(clone:GetDescendants()) do
		if x:IsA("BaseScript") or x:IsA("Sound") or x:IsA("Tool")
			or x:IsA("ForceField") or x:IsA("BillboardGui")
			or x:IsA("ParticleEmitter") or x:IsA("Fire") or x:IsA("Smoke")
			or x:IsA("Sparkles") or x:IsA("Trail") or x:IsA("Beam")
			or x:IsA("Highlight") or x:IsA("SelectionBox")
			or x:IsA("Animator") then -- klon tidak memutar animasi sendiri: pose disalin dari target
			table.insert(kill, x)
		end
	end
	for _, x in ipairs(kill) do x:Destroy() end
	local h = clone:FindFirstChildOfClass("Humanoid")
	if h then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
		pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
		pcall(function() h.RequiresNeck = false end)
		pcall(function() h.BreakJointsOnDeath = false end)
		pcall(function() h.AutomaticScalingEnabled = false end) -- jangan bangun ulang sendi klon
		pcall(function() h.EvaluateStateMachine = false end) -- klon pajangan: tanpa logika jalan/jatuh/mati
	end
	-- [FIX baju layered hilang] Sendi klon DIBIARKAN utuh (sendi tubuh + las aksesori): mesin hanya menggambar baju
	-- layered (WrapLayer) pada karakter yang part-nya tersambung sendi. Dulu semua sendi klon dibuang & part dipaku →
	-- avatar bergerak tapi baju layered hilang dari layar. Sekarang hanya HumanoidRootPart yang dipaku; part lain
	-- digerakkan sendinya (Transform disalin dari target tiap frame). Sendi avatar = AnimationConstraint ("Avatar Joint
	-- Upgrade") atau Motor6D (rig lama) — dua-duanya punya Transform.
	for _, x in ipairs(clone:GetDescendants()) do
		if x:IsA("BasePart") then
			x.Anchored = x == hrp
		elseif x:IsA("AnimationConstraint") then
			x.IsKinematic = true -- klon tidak disimulasikan fisika: part harus mengikuti Transform persis (seperti Motor6D)
			x.Enabled = true
		end
	end
	if useMotor then toMotors(clone) end
end

-- Sendi yang membawa pose animasi (Animator menulis Transform-nya tiap frame).
local function isPoseJoint(x)
	return x:IsA("Motor6D") or x:IsA("AnimationConstraint")
end

-- Pasangan sendi asli ↔ sendi klon (kunci = jalur nama dari karakter + urutan kalau kembar, mis.
-- "RightUpperArm/RightShoulder#1"). Sendi asli tanpa pasangan (di Tool yang dibuang dari klon) dilewati.
local function keyedJoints(root)
	local out, seen = {}, {}
	for _, d in ipairs(root:GetDescendants()) do
		if isPoseJoint(d) then
			local names = {}
			local cur = d
			while cur and cur ~= root do
				table.insert(names, 1, cur.Name)
				cur = cur.Parent
			end
			local key = table.concat(names, "/")
			seen[key] = (seen[key] or 0) + 1
			out[key .. "#" .. seen[key]] = d
		end
	end
	return out
end

local function buildJoints(realChar, clones)
	table.clear(jointPairs)
	local real = keyedJoints(realChar)
	for _, cl in ipairs(clones) do
		local jp = { root = cl:FindFirstChild("HumanoidRootPart"), reals = {}, clones = {} }
		for key, cj in pairs(keyedJoints(cl)) do
			local rj = real[key]
			if rj then
				table.insert(jp.reals, rj)
				table.insert(jp.clones, cj)
			end
		end
		jointPairs[cl] = jp
	end
end

-- ── cek-otomatis pose klon ──────────────────────────────────
-- Sesudah tiap salinan, ≤ 4 bagian tubuh klon dibandingkan dengan target (CFrame relatif HumanoidRootPart).
-- Sama 30 frame berturut-turut → selesai. Target bergerak 20 frame tapi klon tidak pernah sama (sendi klon tidak
-- dijalankan mesin di WorldModel) → sisa sesi memakai Motor6D (toMotors) dan disalin ulang. Tanpa langkah manual.
local function movedPart(j)
	if j:IsA("Motor6D") then return j.Part1 end
	local a = j.Attachment1
	return a and a.Parent
end

local function close(a, b, maxDist, maxAngle)
	local d = a:ToObjectSpace(b)
	local _, angle = d:ToAxisAngle()
	return d.Position.Magnitude <= maxDist and math.abs(angle) <= maxAngle
end

local function startProbe(realRoot, jp)
	if not (realRoot and jp and jp.root) then return nil end
	local reals, clones, kind = {}, {}, "Motor6D"
	for i, rj in ipairs(jp.reals) do
		local cj = jp.clones[i]
		if cj:IsA("AnimationConstraint") then kind = "AnimationConstraint" end
		local rp, cp = movedPart(rj), movedPart(cj)
		if #reals < 4 and rp and cp and rp:IsA("BasePart") and cp:IsA("BasePart") then
			table.insert(reals, rp)
			table.insert(clones, cp)
		end
	end
	if #reals == 0 then return nil end
	return {
		realRoot = realRoot, cloneRoot = jp.root, reals = reals, clones = clones, kind = kind,
		prev = {}, frames = 0, realMoved = 0, sameFrames = 0, run = 0,
	}
end

-- "ok" | "fail" | "stop" | nil (belum bisa diputuskan)
local function stepProbe(p)
	p.frames += 1
	local realMoved, same = false, true
	for i, rp in ipairs(p.reals) do
		local cp = p.clones[i]
		if not (rp.Parent and cp.Parent and p.realRoot.Parent and p.cloneRoot.Parent) then return "stop" end
		local r = p.realRoot.CFrame:ToObjectSpace(rp.CFrame)
		local c = p.cloneRoot.CFrame:ToObjectSpace(cp.CFrame)
		if p.prev[i] and not close(p.prev[i], r, 1e-3, 1e-3) then realMoved = true end
		p.prev[i] = r
		if not close(r, c, 0.05, 0.02) then same = false end
	end
	if p.frames <= PROBE_WARMUP then return nil end
	if realMoved then p.realMoved += 1 end
	if same then
		p.sameFrames += 1
		p.run += 1
	else
		p.run = 0
	end
	if p.run >= 30 then return "ok" end
	if p.realMoved >= 20 and p.sameFrames == 0 then return "fail" end
	if p.frames >= PROBE_MAX_FRAMES then return "stop" end
	return nil
end

local setupDisplays -- (didefinisikan di bawah)

local function onProbe(verdict, p)
	if verdict == "ok" then
		print("[MultiScreen] ✅ pose klon ikut target (sendi: " .. p.kind .. ")")
	elseif verdict == "fail" then
		if not useMotor and p.kind == "AnimationConstraint" then
			useMotor = true
			warn("[MultiScreen] sendi AnimationConstraint klon tidak bergerak di layar → disalin ulang memakai Motor6D")
			task.defer(function()
				if currentScreenMode == "Live" and currentPlayerName ~= "" then setupDisplays(currentPlayerName) end
			end)
		else
			warn("[MultiScreen] ⚠ pose klon tidak ikut target (sendi: " .. p.kind .. ")")
		end
	end
end

local watchRespawn -- (didefinisikan sesudah setupDisplays)

-- Aksesori target dipasang / dilepas (ganti avatar tanpa respawn) → salin ulang (lihat loop pose).
local function watchAccessories(rc)
	for _, c in ipairs(accConns) do c:Disconnect() end
	table.clear(accConns)
	local function onChild(x)
		if x:IsA("Accessory") then accDirty = true end
	end
	table.insert(accConns, rc.ChildAdded:Connect(onChild))
	table.insert(accConns, rc.ChildRemoved:Connect(onChild))
end

setupDisplays = function(pName)
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
		cleanClone(cl, hrp)
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
	if #allC > 0 then
		buildJoints(rc, allC)
		probe = startProbe(rr, jointPairs[allC[1]])
	end
	setupChar = rc
	holdLod(rc)
	watchRespawn(p)
	watchAccessories(rc)
	isSettingUp = false
	print("[MultiScreen] ✅ Done:", pName, "| Clones:", #allC)
end

-- Target respawn (reset, /re, mati) → part lama hilang; salin ulang karakter baru setelah lengkap.
watchRespawn = function(p)
	if charConn then charConn:Disconnect() end
	charConn = p.CharacterAdded:Connect(function(newChar)
		newChar:WaitForChild("HumanoidRootPart", 10)
		task.wait(REBUILD_DELAY)
		if currentScreenMode == "Live" and currentPlayerName == p.Name and p.Character == newChar then
			setupDisplays(p.Name)
		end
	end)
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

	if m == "Gambar" then
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

-- [FIX] Pose: Transform tiap sendi target disalin ke sendi klon yang sama di PreSimulation — sesudah Animator menulis
-- Transform target, sebelum mesin menerapkan semua Transform (asli & klon) → klon sama dengan target di frame yang sama.
-- Akar klon dipaku di titik layar (Statis: menghadap kamera; Dinamis: ikut arah hadap pemain), part lain ikut sendinya.
RunService.PreSimulation:Connect(function()
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

	-- pose frame lalu sudah diterapkan ke target & klon → bandingkan dulu, baru salin pose frame ini
	if probe then
		local p = probe
		local verdict = stepProbe(p)
		if verdict then
			probe = nil
			onProbe(verdict, p)
		end
	end

	local rootCF
	if cameraModeVal.Value == "Static" then
		rootCF = CFrame.Angles(0, math.pi, 0)
	else
		local _, yR, _ = rr.CFrame:ToOrientation()
		rootCF = CFrame.Angles(0, yR + math.pi, 0)
	end
	local stale = accDirty
	for _, sd in ipairs(activeScreens) do
		local jp = sd.Clone and jointPairs[sd.Clone]
		if jp then
			if jp.root and jp.root.CFrame ~= rootCF then jp.root.CFrame = rootCF end
			for i, rj in ipairs(jp.reals) do
				if rj.Parent then
					jp.clones[i].Transform = rj.Transform
				else
					stale = true
				end
			end
		end
	end
	-- Sendi / bagian tubuh / aksesori target diganti tanpa respawn (mis. ganti avatar) → salin ulang, maks 1× per
	-- REBUILD_DELAY. Respawn diurus watchRespawn.
	if stale and not isSettingUp and rc == setupChar and os.clock() - lastRebuild > REBUILD_DELAY then
		lastRebuild = os.clock()
		accDirty = false
		task.defer(function()
			if currentScreenMode == "Live" and currentPlayerName ~= "" then setupDisplays(currentPlayerName) end
		end)
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

-- Statis / Dinamis: akar klon diatur ulang tiap frame (loop pose) → tidak perlu menyalin ulang karakter
-- (menyalin ulang = baju layered dibangun ulang & sempat hilang sesaat).

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
