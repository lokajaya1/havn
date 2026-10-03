-- ServerScriptService/DjStage (Script) — efek panggung Workspace["DJ STAGE"] (ruangan WORLD, claude/Rencana_World.md).
-- Menggantikan 11 skrip Studio yang dulu ada di dalam part DJ STAGE (perilaku, angka & urutan SAMA; tetap di server):
--   * LED  : dj/Interact*/Animate/BaseLED (4) dan dj/BaseCDJ*/DecorationButtons/USBButtons/USBLed (4) berkedip
--   * GIF  : stage/EntranceScreenC — 25 frame bergantian tiap 0,05 dtk, selalu jalan
--   * VJ   : tiap BasePart di stage/StageScreens — media VJ (default gambar) + fade hitam, nyala hanya saat
--            ReplicatedStorage.LiveSystem.ScreenMode == "VJ" DAN attribute "On" = true. Mode "Live" (pemain di layar)
--            tetap diurus StarterPlayerScripts/MultiScreenController di client.
-- Tiap target punya thread sendiri seperti dulu (satu skrip per part); loop berhenti kalau part-nya dihapus.
-- Angka & ID aset: Config. Logika murni: Rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(script:WaitForChild("Config"))
local Rules = require(script:WaitForChild("Rules"))

-- Semua instance di jalur `path` (segmen "Nama*" = semua anak bernama itu, selain itu anak pertama).
local function collect(root: Instance, path: { string }): { Instance }
	local current = { root }
	for _, seg in path do
		local name, all = Rules.segment(seg)
		local found = {}
		for _, inst in current do
			if all then
				for _, child in inst:GetChildren() do
					if child.Name == name then
						table.insert(found, child)
					end
				end
			else
				local child = inst:FindFirstChild(name)
				if child then
					table.insert(found, child)
				end
			end
		end
		current = found
	end
	return current
end

-- ── LED berkedip ────────────────────────────────────────────────────────────────────────────────────────────
local function startLed(part: BasePart, group)
	task.spawn(function()
		while part.Parent ~= nil do
			part.BrickColor = BrickColor.new(group.colors[1])
			task.wait(group.interval)
			part.BrickColor = BrickColor.new(group.colors[2])
			task.wait(group.interval)
		end
	end)
end

-- ── Layar GIF (dulu VJScript di EntranceScreenC) ───────────────────────────────────────────────────────────────
local function startGif(animatedPart: BasePart, cfg)
	if cfg.hidePart then
		animatedPart.Transparency = 1
	end
	animatedPart.CanCollide = false
	local surfaceGui = animatedPart:WaitForChild("SurfaceGui")
	local imageLabel = surfaceGui:WaitForChild("ImageLabel") :: ImageLabel
	local assetIDs = cfg.frames
	if #assetIDs == 0 then
		warn("⚠️ assetIDs kosong. Tambahkan ID gambar frame dulu!")
		return
	end
	-- satu ImageLabel per frame (klon template), awalnya tak terlihat
	local imageTable = {}
	for i = 1, #assetIDs do
		local clone = imageLabel:Clone()
		clone.Image = assetIDs[i]
		clone.ImageTransparency = 1
		clone.Parent = surfaceGui
		table.insert(imageTable, clone)
	end
	imageLabel.Visible = false -- sembunyikan template asli
	task.spawn(function()
		while animatedPart.Parent ~= nil do
			for i = 1, #imageTable do
				for j = 1, #imageTable do
					imageTable[j].ImageTransparency = 1
				end
				imageTable[i].ImageTransparency = 0
				task.wait(cfg.frameTime)
			end
		end
	end)
end

-- ── Layar VJ (dulu VJScript "ScreenMediaScript" di tiap StageScreens/EntranceScreen) ──────────────────────────
local function startVj(part: BasePart, CONFIG)
	local sizeX, posX = Rules.mediaLayout(CONFIG.MIRROR_HORIZONTAL)
	local MEDIA_SIZE = UDim2.new(sizeX, 0, 1, 0)
	local MEDIA_POS = UDim2.new(posX, 0, 0, 0)

	if CONFIG.HIDE_PART then
		part.Transparency = 1
	end
	part.CanCollide = false

	local LABEL = part.Name .. "_Screen" -- nama untuk pesan warn di Output
	local surfaceGui = part:WaitForChild("SurfaceGui") :: SurfaceGui
	local template = surfaceGui:FindFirstChild("ImageLabel") :: ImageLabel? -- boleh nil

	-- ScreenMode dari LiveSystem (hanya kalau dipakai)
	local screenModeVal: StringValue? = nil
	if CONFIG.USE_SCREENMODE then
		local liveSystem = ReplicatedStorage:WaitForChild(CONFIG.LIVE_SYSTEM, CONFIG.MODE_WAIT)
		screenModeVal = liveSystem and liveSystem:WaitForChild(CONFIG.SCREEN_MODE, CONFIG.MODE_WAIT) :: StringValue?
		if not screenModeVal then
			warn("[" .. LABEL .. "] ScreenMode tidak ketemu — saklar hanya pakai attribute 'On'")
		end
	end

	-- Saklar manual: attribute "On" di Part (bisa diubah di Studio / skrip lain).
	if part:GetAttribute("On") == nil then
		part:SetAttribute("On", CONFIG.START_ON)
	end

	local function isActive(): boolean
		local mode = if screenModeVal then screenModeVal.Value else nil
		return Rules.isActive(part:GetAttribute("On"), CONFIG.USE_SCREENMODE, screenModeVal ~= nil, mode, CONFIG.ACTIVE_ON_MODE)
	end

	-- ImageLabel baru (klon template kalau ada, biar ukuran/ScaleType sama)
	local function newImageLabel(image: string): ImageLabel
		local lbl: ImageLabel
		if template then
			lbl = template:Clone()
		else
			lbl = Instance.new("ImageLabel")
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
		end
		lbl.Image = image
		lbl.AnchorPoint = Vector2.new(0, 0)
		lbl.Size = MEDIA_SIZE
		lbl.Position = MEDIA_POS
		lbl.ImageTransparency = 1 -- awalnya tak terlihat
		lbl.Visible = true
		lbl.Parent = surfaceGui
		return lbl
	end

	local mediaType = Rules.mediaType(CONFIG.MEDIA_TYPE)
	local frames: { ImageLabel } = {} -- [GIF]
	local totalFrames = 0
	local currentFrame = 0
	local imageLabel: ImageLabel? = nil -- [IMAGE]
	local videoFrame: VideoFrame? = nil -- [VIDEO]

	if mediaType == "GIF" then
		if #CONFIG.GIF_FRAMES == 0 then
			warn("[" .. LABEL .. "] GIF_FRAMES kosong!")
			return
		end
		for i, id in ipairs(CONFIG.GIF_FRAMES) do
			frames[i] = newImageLabel(id)
		end
		totalFrames = #frames
	elseif mediaType == "IMAGE" then
		imageLabel = newImageLabel(CONFIG.IMAGE_ID)
	elseif mediaType == "VIDEO" then
		local vf = Instance.new("VideoFrame")
		vf.Name = "LoopVideo"
		vf.Size = MEDIA_SIZE
		vf.Position = MEDIA_POS
		vf.BackgroundTransparency = 1
		vf.Video = CONFIG.VIDEO_ID
		vf.Looped = true
		vf.Volume = CONFIG.VIDEO_VOLUME
		vf.Playing = false -- baru jalan saat layar ON
		vf.Parent = surfaceGui
		videoFrame = vf
	else
		warn("[" .. LABEL .. "] MEDIA_TYPE salah: " .. tostring(CONFIG.MEDIA_TYPE) .. " (pilih GIF / VIDEO / IMAGE)")
		return
	end

	if template then
		template.Visible = false -- template asli disembunyikan supaya tidak dobel
	end

	-- Layar hitam yang memudar
	local fadeOverlay = Instance.new("Frame")
	fadeOverlay.Name = "FadeOverlay"
	fadeOverlay.Size = UDim2.new(1, 0, 1, 0)
	fadeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	fadeOverlay.BackgroundTransparency = 1 -- 1 = transparan (tidak menutupi)
	fadeOverlay.BorderSizePixel = 0
	fadeOverlay.ZIndex = CONFIG.FADE_ZINDEX
	fadeOverlay.Parent = surfaceGui

	local function fadeTo(targetTransparency: number)
		TweenService:Create(
			fadeOverlay,
			TweenInfo.new(CONFIG.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = targetTransparency }
		):Play()
	end

	-- "version" menghentikan loop lama kalau layar ON/OFF cepat-cepat
	local version = 0

	local function stopMedia()
		if mediaType == "GIF" then
			if currentFrame > 0 and currentFrame <= totalFrames then
				frames[currentFrame].ImageTransparency = 1
			end
			currentFrame = 0
		elseif mediaType == "IMAGE" and imageLabel then
			imageLabel.ImageTransparency = 1
		elseif mediaType == "VIDEO" and videoFrame then
			videoFrame.Playing = false
		end
	end

	local function startMedia(v: number)
		if mediaType == "GIF" then
			task.spawn(function()
				while version == v do
					for i = 1, totalFrames do
						if version ~= v then
							return
						end
						if currentFrame > 0 then
							frames[currentFrame].ImageTransparency = 1
						end
						frames[i].ImageTransparency = 0
						currentFrame = i
						task.wait(CONFIG.FRAME_SPEED)
					end
				end
			end)
		elseif mediaType == "IMAGE" and imageLabel then
			imageLabel.ImageTransparency = 0
		elseif mediaType == "VIDEO" and videoFrame then
			videoFrame.Playing = true
		end
	end

	local shown = false

	local function show()
		version += 1
		local v = version
		surfaceGui.Enabled = true
		if CONFIG.USE_FADE then
			fadeOverlay.BackgroundTransparency = 0 -- mulai dari hitam
			fadeTo(1) -- lalu memudar ke transparan
		end
		startMedia(v)
	end

	local function hide()
		version += 1 -- otomatis menghentikan loop GIF
		local v = version
		if CONFIG.USE_FADE then
			fadeTo(0) -- gelapkan dulu
			task.delay(CONFIG.FADE_TIME, function()
				if version == v then -- hanya matikan kalau belum keburu dinyalakan lagi
					stopMedia()
					surfaceGui.Enabled = false
				end
			end)
		else
			stopMedia()
			surfaceGui.Enabled = false
		end
	end

	-- Terapkan saklar (hanya bereaksi kalau status berubah)
	local function refresh()
		local want = isActive()
		if want == shown then
			return
		end
		shown = want
		if want then
			show()
		else
			hide()
		end
	end

	surfaceGui.Enabled = false
	part:GetAttributeChangedSignal("On"):Connect(refresh)
	if screenModeVal then
		screenModeVal.Changed:Connect(refresh)
	end
	refresh()
end

-- ── mulai ────────────────────────────────────────────────────────────────────────────────────────────────────
local stage = workspace:WaitForChild(Config.STAGE_NAME, Config.FIND_TIMEOUT)
if not stage then
	warn("[DjStage] Workspace." .. Config.STAGE_NAME .. " tidak ada — efek panggung dilewati")
	return
end

local nLed = 0
for _, group in Config.LED_GROUPS do
	local n = 0
	for _, part in collect(stage, group.path) do
		if part:IsA("BasePart") then
			n += 1
			startLed(part, group)
		end
	end
	if n == 0 then
		warn("[DjStage] LED " .. group.name .. " tidak ketemu di " .. table.concat(group.path, "/"))
	end
	nLed += n
end

local nGif = 0
for _, part in collect(stage, Config.GIF_SCREEN.path) do
	if part:IsA("BasePart") then
		nGif += 1
		task.spawn(startGif, part, Config.GIF_SCREEN)
	end
end
if nGif == 0 then
	warn("[DjStage] layar GIF tidak ketemu di " .. table.concat(Config.GIF_SCREEN.path, "/"))
end

local nVj = 0
for _, folder in collect(stage, Config.VJ_SCREENS.folder) do
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			nVj += 1
			task.spawn(startVj, part, Config.VJ_SCREENS)
		end
	end
end
if nVj == 0 then
	warn("[DjStage] layar VJ tidak ketemu di " .. table.concat(Config.VJ_SCREENS.folder, "/"))
end

print(("[DjStage] ✅ LED %d · layar GIF %d · layar VJ %d"):format(nLed, nGif, nVj))
