--[[Movement System (LocalScript, StarterPlayerScripts) ]]

local Players              = game:GetService("Players")
local TweenService         = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService     = game:GetService("UserInputService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

-- Warna cincin tombol sprint mobile: ReplicatedStorage.Modules.ThemeColor (themeColor) → ikut tema pilihan pemain.
local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))

-- Kecepatan dance (menari/sync) diikuti juga di sini; tanpa ini Shift saat
-- menari membuat 24, lepas → 16, dan kecepatan dance 6 hilang. DanceShared
-- membaca DanceAssets langsung, jadi tunggu dulu; gagal → sprint tetap jalan.
local DanceShared
do
	local assets  = ReplicatedStorage:WaitForChild("Assets", 15)
	local anims   = assets and assets:WaitForChild("Animations", 15)
	local dances  = anims and anims:WaitForChild("Dances", 15)
	local modules = ReplicatedStorage:WaitForChild("Modules", 15)
	local module  = dances and dances:WaitForChild("DanceAssets", 15) and modules and modules:WaitForChild("DanceShared", 15)
	if module then
		local ok, result = pcall(require, module)
		if ok then DanceShared = result else warn("[SickHavn] DanceShared gagal di-require:", result) end
	end
end

local CONFIG = {
	WalkSpeed      = 16,
	SprintSpeed    = 24,
	SlowSpeed      = 6,
	TransitionTime = 0.2,

	SprintToggle = false,
	SlowToggle   = false,

	SprintKey = Enum.KeyCode.LeftShift,
	SlowKey   = Enum.KeyCode.LeftControl,
	SprintPad = Enum.KeyCode.ButtonL3,
	SlowPad   = Enum.KeyCode.ButtonR3,

	EnableFOV = true,
	FOVBoost  = 8,

	LockAttribute = "MovementLocked", -- hook untuk sistem lain (seat/cutscene/carry)

	ButtonSize      = 64,
	GapFromJump     = 4,
	OffsetX         = 150, -- fallback kalau JumpButton nggak ketemu
	OffsetY         = 55,
	SprintIconImage = "rbxassetid://72034014768460",
	-- Warna cincin aktif = token ThemeColor ACCENT (dulu ActiveRingColor 255,196,60), lihat createMobileSprintButton.

	ForceShowMobileButton = false, -- true = paksa tombol muncul di Studio PC
}

local TWEEN_INFO = TweenInfo.new(CONFIG.TransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RING_INFO  = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRINT_ACTION = "SickHavn_Sprint"
local SLOW_ACTION   = "SickHavn_Slow"

local TOUCH_INPUT_TYPES = {
	[Enum.UserInputType.Touch]        = true,
	[Enum.UserInputType.MouseButton1] = true,
}

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera
local baseFOV = camera and camera.FieldOfView or 70
local humanoid = nil

local flags = { sprint = false, slow = false }
local currentSpeed, currentFOV
local wasLocked = false
local activeTweens = {}
local resetMobileButtonVisual = nil
local setSprintButtonHidden   = nil
local sprintGui               = nil -- ScreenGui tombol sprint (diisi saat dibuat)
local sprintButton            = nil -- ImageButton sprint (diisi saat dibuat)

local function tweenTo(instance, property, value)
	if activeTweens[property] then activeTweens[property]:Cancel() end
	local t = TweenService:Create(instance, TWEEN_INFO, { [property] = value })
	activeTweens[property] = t
	t:Play()
end

-- FOV dasar: /fov (CommandPanel) menyimpan pilihan pemain di atribut lokal
-- "BaseFOV"; tanpa itu = FOV kamera saat skrip mulai. Sprint & respawn kembali
-- ke angka ini (dulu selalu ke FOV awal, jadi /fov hilang setelah berlari).
local function getBaseFOV()
	local v = player:GetAttribute("BaseFOV")
	return type(v) == "number" and v or baseFOV
end

local function isLocked()
	return humanoid ~= nil and humanoid:GetAttribute(CONFIG.LockAttribute) == true
end

local function isDancing()
	return DanceShared ~= nil and DanceShared.isDancing(player)
end

local function desiredSpeed()
	if isDancing() then return DanceShared.WALKSPEED.dance end -- sprint/slow tidak berlaku saat menari
	if flags.sprint then return CONFIG.SprintSpeed end
	if flags.slow   then return CONFIG.SlowSpeed   end
	return CONFIG.WalkSpeed
end

local function refresh()
	if not humanoid or humanoid.Health <= 0 then return end
	if isLocked() then wasLocked = true return end

	local force = wasLocked
	wasLocked = false

	local speed = desiredSpeed()
	if force or speed ~= currentSpeed then
		currentSpeed = speed
		tweenTo(humanoid, "WalkSpeed", speed)
	end

	if CONFIG.EnableFOV and camera then
		local fov = getBaseFOV() + ((flags.sprint and not isDancing()) and CONFIG.FOVBoost or 0)
		if force or fov ~= currentFOV then
			currentFOV = fov
			tweenTo(camera, "FieldOfView", fov)
		end
	end
end

local function setFlag(key, value)
	if flags[key] == value then return end
	flags[key] = value
	refresh()
end

local function makeHandler(key, toggleMode)
	return function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setFlag(key, toggleMode and (not flags[key]) or true)
		elseif inputState == Enum.UserInputState.End and not toggleMode then
			setFlag(key, false)
		end
		return Enum.ContextActionResult.Pass
	end
end

--------------------------------------------------------------------
-- Tombol sprint mobile (Roblox tidak punya default sprint button)
--------------------------------------------------------------------
local function createMobileSprintButton()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SickHavnMobileUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 3
	gui.Enabled = CONFIG.ForceShowMobileButton or UserInputService.TouchEnabled
	gui.Parent = player:WaitForChild("PlayerGui")
	ThemeColor.mark(gui)
	sprintGui = gui

	-- Visibilitas reaktif: nggak cuma dicek sekali di awal, tapi ngikutin
	-- input type terakhir yang dipakai player. Ini nutup celah kalau
	-- TouchEnabled belum sinkron pas script pertama jalan.
	UserInputService.LastInputTypeChanged:Connect(function()
		if CONFIG.ForceShowMobileButton then return end
		gui.Enabled = UserInputService.TouchEnabled
	end)

	local size = CONFIG.ButtonSize

	local btn = Instance.new("ImageButton")
	btn.Name = "SprintButton"
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -CONFIG.OffsetX, 1, -CONFIG.OffsetY) -- fallback, dioverride di bawah kalau JumpButton ketemu
	btn.Size = UDim2.fromOffset(size, size)
	btn.AutoButtonColor = false
	btn.Active = true
	btn.Selectable = false
	btn.ZIndex = 5
	btn.Parent = gui
	sprintButton = btn

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = btn

	btn.Image = CONFIG.SprintIconImage
	btn.ScaleType = Enum.ScaleType.Fit
	btn.BackgroundTransparency = 1

	-- Nempelin tombol sprint ke tombol jump asli (bukan angka offset statis),
	-- supaya posisinya selalu pas di semua device/orientasi/resolusi.
	task.spawn(function()
		local touchGui = player.PlayerGui:WaitForChild("TouchGui", 5)
		local frame = touchGui and touchGui:WaitForChild("TouchControlFrame", 5)
		local jumpButton = frame and frame:WaitForChild("JumpButton", 5)
		if not jumpButton then
			warn("[SickHavn] JumpButton default tidak ditemukan, pakai posisi fallback statis.")
			return
		end

		local function followJumpButton()
			local pos, jSize = jumpButton.AbsolutePosition, jumpButton.AbsoluteSize
			btn.Position = UDim2.fromOffset(pos.X - CONFIG.GapFromJump, pos.Y + jSize.Y / 2)
		end

		followJumpButton()
		jumpButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(followJumpButton)
		jumpButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(followJumpButton)
	end)

	local activeRing = Instance.new("UIStroke")
	activeRing.Name = "ActiveRing"
	activeRing.Thickness = 3
	activeRing.Color = ThemeColor.tokens.ACCENT -- cincin UI tombol sprint = sorotan (bukan warna dunia)
	activeRing.Transparency = 1
	activeRing.Parent = btn

	local function setActiveRingVisible(visible)
		TweenService:Create(activeRing, RING_INFO, { Transparency = visible and 0 or 1 }):Play()
	end

	local activeInputs = {}
	local isPressed = false

	local function setPressedVisual(pressed)
		if isPressed == pressed then return end
		isPressed = pressed
		TweenService:Create(btn, PRESS_INFO, {
			Size = UDim2.fromOffset(pressed and size * 0.9 or size, pressed and size * 0.9 or size),
			ImageTransparency = pressed and 0.15 or 0,
		}):Play()
	end

	local function press(input)
		local alreadyHeld = next(activeInputs) ~= nil
		activeInputs[input] = true
		setPressedVisual(true)
		if alreadyHeld then return end

		setFlag("sprint", CONFIG.SprintToggle and (not flags.sprint) or true)
		if CONFIG.SprintToggle then
			setActiveRingVisible(flags.sprint)
		end
	end

	local function release(input)
		if not activeInputs[input] then return end
		activeInputs[input] = nil
		if next(activeInputs) then return end

		setPressedVisual(false)
		if not CONFIG.SprintToggle then
			setFlag("sprint", false)
		end
	end

	btn.InputBegan:Connect(function(input)
		if TOUCH_INPUT_TYPES[input.UserInputType] then press(input) end
	end)
	btn.InputEnded:Connect(function(input)
		if TOUCH_INPUT_TYPES[input.UserInputType] then release(input) end
	end)
	btn.MouseLeave:Connect(function()
		for input in pairs(activeInputs) do
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				release(input)
			end
		end
	end)

	resetMobileButtonVisual = function()
		activeInputs = {}
		isPressed = false
		btn.Size = UDim2.fromOffset(size, size)
		btn.ImageTransparency = 0
		setActiveRingVisible(false)
	end

	-- Didefinisikan SEKALI di sini (bukan lagi di-nested dalam
	-- resetMobileButtonVisual, yang dulu bikin fungsi ini nil sampai karakter
	-- spawn). Sekarang selalu siap dipakai auto-hide detector di bawah, plus
	-- dedupe biar nggak kerja percuma tiap frame.
	local hiddenState = false
	setSprintButtonHidden = function(hidden)
		hidden = hidden and true or false
		if hiddenState == hidden then return end
		hiddenState = hidden
		btn.Visible = not hidden
		-- Mode hold-to-sprint: kalau tombol disembunyiin selagi ditahan,
		-- InputEnded nggak akan fire → lepas manual biar sprint nggak nyangkut
		-- & activeInputs nggak nyimpen ghost input.
		if hidden and not CONFIG.SprintToggle then
			for input in pairs(activeInputs) do activeInputs[input] = nil end
			setPressedVisual(false)
			setFlag("sprint", false)
		end
	end
end

local function onCharacterAdded(character)
	humanoid = character:WaitForChild("Humanoid")

	flags.sprint, flags.slow = false, false
	currentSpeed, currentFOV, wasLocked = nil, nil, false

	humanoid.WalkSpeed = CONFIG.WalkSpeed
	if camera then camera.FieldOfView = getBaseFOV() end
	if resetMobileButtonVisual then resetMobileButtonVisual() end

	humanoid:GetAttributeChangedSignal(CONFIG.LockAttribute):Connect(refresh)
	refresh()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

-- Mulai/berhenti menari atau sync → hitung ulang kecepatan (6 ↔ jalan/sprint).
player:GetAttributeChangedSignal("IsDancing"):Connect(refresh)
player:GetAttributeChangedSignal("IsSyncing"):Connect(refresh)
player:GetAttributeChangedSignal("BaseFOV"):Connect(refresh)

ContextActionService:BindAction(SPRINT_ACTION, makeHandler("sprint", CONFIG.SprintToggle),
	false, CONFIG.SprintKey, CONFIG.SprintPad)
ContextActionService:BindAction(SLOW_ACTION, makeHandler("slow", CONFIG.SlowToggle),
	false, CONFIG.SlowKey, CONFIG.SlowPad)

createMobileSprintButton()

--------------------------------------------------------------------
-- AUTO-HIDE tombol sprint saat ketiban panel UI APA PUN (generic).
--
-- Masalah lama: hide cuma jalan lewat _G.PanelCoordinator, jadi CUMA panel
-- yang terdaftar di coordinator (mis. Music) yang bikin tombol sembunyi.
-- Panel lain yang ScreenGui-nya berdiri sendiri tetap ketiban tombol sprint
-- (DisplayOrder tinggi) dan touch-nya kecolong.
--
-- Solusi: deteksi langsung secara visual. Cek titik tengah tombol pakai
-- PlayerGui:GetGuiObjectsAtPosition — kalau ada elemen "solid" milik ScreenGui
-- lain (bukan punya kita, bukan kontrol touch bawaan) yang menutupi titik itu,
-- berarti ada panel kebuka di atas tombol → sembunyikan. Nggak butuh panel
-- daftar ke mana-mana; berlaku untuk SEMUA panel otomatis.
--------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local COVER_MIN_SIZE = 60 -- px; abaikan elemen kecil (label/ikon HUD, dsb.)

local function isButtonCoveredByPanel()
	if not sprintButton or not sprintButton.Parent then return false end
	if not sprintGui or not sprintGui.Enabled then return false end -- PC / tombol off

	local absPos, absSize = sprintButton.AbsolutePosition, sprintButton.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then return false end
	local cx = absPos.X + absSize.X * 0.5
	local cy = absPos.Y + absSize.Y * 0.5

	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(cx, cy)
	end)
	if not ok or type(objects) ~= "table" then return false end

	for _, obj in ipairs(objects) do
		if obj ~= sprintButton and obj.Visible then
			local sg = obj:FindFirstAncestorWhichIsA("ScreenGui")
			if sg and sg ~= sprintGui and sg.Name ~= "TouchGui" then
				local sz = obj.AbsoluteSize
				if sz.X >= COVER_MIN_SIZE and sz.Y >= COVER_MIN_SIZE then
					-- Hitung "menutupi" hanya kalau elemen benar-benar tampak:
					-- tombol, atau punya background / gambar / teks kelihatan.
					-- Frame transparan (sekadar wadah layout) diabaikan supaya
					-- tombol nggak salah disembunyiin.
					local solid = false
					if obj:IsA("GuiButton") then
						solid = true
					elseif obj.BackgroundTransparency < 0.95 then
						solid = true
					elseif obj:IsA("ImageLabel") and obj.Image ~= "" and obj.ImageTransparency < 0.95 then
						solid = true
					elseif obj:IsA("TextLabel") and obj.Text ~= "" and obj.TextTransparency < 0.95 then
						solid = true
					end
					if solid then return true end
				end
			end
		end
	end
	return false
end

local lastCoverState = nil
local function refreshSprintCover()
	if not setSprintButtonHidden then return end
	local covered = isButtonCoveredByPanel()
	if covered ~= lastCoverState then
		lastCoverState = covered
		setSprintButtonHidden(covered)
	end
end

-- Poll ringan (~7x/detik). Perlu karena banyak panel toggle-nya lewat Visible
-- di frame dalam, bukan ScreenGui.Enabled, jadi nggak bisa di-hook satu-satu
-- dengan bersih. GetGuiObjectsAtPosition murah, dan langsung early-return kalau
-- tombol lagi non-aktif (PC / bukan touch).
task.spawn(function()
	while true do
		task.wait(0.15)
		refreshSprintCover()
	end
end)

-- Opsional: kalau ada _G.PanelCoordinator, dipakai HANYA sebagai pemicu re-cek
-- instan (biar sembunyi tanpa nunggu poll berikutnya). Coordinator TIDAK dipakai
-- sebagai sumber kebenaran — deteksi overlap tetap yang menentukan — jadi
-- coordinator yang nyangkut nggak akan bikin tombol hilang permanen.
task.spawn(function()
	local deadline = os.clock() + 10
	repeat task.wait(0.1)
	until (_G.PanelCoordinator and _G.PanelCoordinator.OnChange) or os.clock() > deadline

	local coord = _G.PanelCoordinator
	if coord and coord.OnChange then
		coord.OnChange(function()
			refreshSprintCover()
			task.delay(0.05, refreshSprintCover) -- setelah panel selesai layout
			task.delay(0.20, refreshSprintCover)
		end)
	end
end)