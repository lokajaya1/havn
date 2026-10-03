-- StarterPlayerScripts/DjStageClient/Screen (ModuleScript) — SATU layar panggung DJ di client (ruangan WORLD,
-- claude/Rencana_World.md). Membangun media (gambar / GIF frame / GIF sprite / video) di SurfaceGui buatan Studio milik
-- part, menyalakan/mematikan dengan fade, mengganti media, dan berhenti sementara saat jauh (setAwake).
--   style "utama"   = layar utama (EntranceScreenC): klon template apa adanya, selalu menyala, tanpa fade.
--   style "samping" = layar samping (StageScreens): klon template ukuran penuh/mirror, fade hitam, menyala hanya saat
--                     mode Gambar (ScreenMode "Gambar") & attribute "On" = true.
-- Urutan & nilai properti SAMA dengan skrip layar lama (dites transkrip). Semua perubahan di sini hanya di client ini.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Screen = {}

-- part   : BasePart layar
-- style  : "utama" | "samping"
-- cfg    : Config.LAYAR_UTAMA (utama) / Config.LAYAR_SAMPING (samping)
-- rules  : ReplicatedStorage.Modules.DjStageRules
-- getMedia(): media yang sedang dipilih untuk layar ini (DjStageRules.mediaOf; dibaca saat media pertama dibangun)
-- pauseStep : detik menunggu saat animasi sedang berhenti (Config.PAUSE.interval)
function Screen.new(part: BasePart, style: string, cfg: any, rules: any, getMedia: () -> any, pauseStep: number): any
	local side = style == "samping"
	local self = { part = part }
	local LABEL = part.Name .. "_Screen" -- nama untuk pesan warn di Output

	local surfaceGui = part:WaitForChild("SurfaceGui") :: SurfaceGui
	local template: ImageLabel? -- utama: wajib (ditunggu), samping: boleh nil
	if side then
		template = surfaceGui:FindFirstChild("ImageLabel") :: ImageLabel?
	else
		template = surfaceGui:WaitForChild("ImageLabel") :: ImageLabel
	end
	local sizeX, posX = rules.mediaLayout(side and cfg.MIRROR_HORIZONTAL == true)
	local MEDIA_SIZE = UDim2.new(sizeX, 0, 1, 0)
	local MEDIA_POS = UDim2.new(posX, 0, 0, 0)
	local fade = side and cfg.USE_FADE == true

	-- ScreenMode dari LiveSystem (layar samping saja, hanya kalau dipakai)
	local screenModeVal: StringValue? = nil
	if side and cfg.USE_SCREENMODE then
		local liveSystem = ReplicatedStorage:WaitForChild(cfg.LIVE_SYSTEM, cfg.MODE_WAIT)
		screenModeVal = liveSystem and liveSystem:WaitForChild(cfg.SCREEN_MODE, cfg.MODE_WAIT) :: StringValue?
		if not screenModeVal then
			warn("[" .. LABEL .. "] ScreenMode tidak ketemu — saklar hanya pakai attribute 'On'")
		end
	end

	-- ImageLabel baru untuk satu gambar (awalnya tak terlihat)
	local function newLabel(image: string): ImageLabel
		local lbl: ImageLabel
		if not side then
			lbl = (template :: ImageLabel):Clone() -- layar utama: klon template apa adanya
			lbl.Image = image
			lbl.ImageTransparency = 1
			lbl.Visible = true -- template sudah disembunyikan sesudah media pertama → klon berikutnya ikut tersembunyi
			lbl.Parent = surfaceGui
			return lbl
		end
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
		lbl.ImageTransparency = 1
		lbl.Visible = true
		lbl.Parent = surfaceGui
		return lbl
	end

	local function newVideo(m: any): VideoFrame
		local vf = Instance.new("VideoFrame")
		vf.Name = "LoopVideo"
		if side or not template then
			vf.Size = MEDIA_SIZE
			vf.Position = MEDIA_POS
		else
			vf.AnchorPoint = template.AnchorPoint
			vf.Size = template.Size
			vf.Position = template.Position
		end
		vf.BackgroundTransparency = 1
		vf.Video = m.video
		vf.Looped = true
		vf.Volume = m.volume or 0
		vf.Playing = false -- baru jalan saat layar menyala & dekat
		vf.Parent = surfaceGui
		return vf
	end

	-- ── isi layar ───────────────────────────────────────────────────────────────────────────────────────────────
	local media: any = nil -- media yang sedang terpasang (DjStageRules.mediaOf)
	local labels: { ImageLabel } = {} -- FRAMES: satu per frame · IMAGE/SPRITE: satu
	local video: VideoFrame? = nil
	local currentFrame = 0
	local loopVersion = 0 -- naik = loop animasi lama berhenti
	local showVersion = 0 -- naik = tunda-matikan lama dibatalkan (side)
	local shown = false
	local awake = true

	local function build(m: any)
		media = m
		labels = {}
		video = nil
		currentFrame = 0
		if m.kind == "FRAMES" then
			for i, id in ipairs(m.frames) do
				labels[i] = newLabel(id)
			end
		elseif m.kind == "IMAGE" then
			labels[1] = newLabel(m.image)
		elseif m.kind == "SPRITE" then
			local lbl = newLabel(m.image)
			lbl.ImageRectSize = Vector2.new(m.frameSize[1], m.frameSize[2])
			lbl.ImageRectOffset = Vector2.new(0, 0)
			labels[1] = lbl
		elseif m.kind == "VIDEO" then
			video = newVideo(m)
		end
		if template then
			template.Visible = false -- template asli disembunyikan supaya tidak dobel
		end
	end

	local function clear()
		for _, lbl in labels do
			lbl:Destroy()
		end
		if video then
			video.Playing = false
			video:Destroy()
		end
		labels = {}
		video = nil
		currentFrame = 0
	end

	local function stopMedia()
		if not media then
			return
		end
		if media.kind == "FRAMES" then
			if currentFrame > 0 and currentFrame <= #labels then
				labels[currentFrame].ImageTransparency = 1
			end
			currentFrame = 0
		elseif (media.kind == "IMAGE" or media.kind == "SPRITE") and labels[1] then
			labels[1].ImageTransparency = 1
		elseif media.kind == "VIDEO" and video then
			video.Playing = false
		end
	end

	-- tunggu selama animasi sedang berhenti (jauh); false = loop ini sudah tidak berlaku
	local function waitAwake(v: number): boolean
		while not awake do
			task.wait(pauseStep)
			if loopVersion ~= v then
				return false
			end
		end
		return true
	end

	local function startMedia(v: number)
		local m = media
		if m.kind == "FRAMES" then
			task.spawn(function()
				while loopVersion == v and part.Parent ~= nil do
					for i = 1, #labels do
						if loopVersion ~= v or not waitAwake(v) then
							return
						end
						if currentFrame > 0 then
							labels[currentFrame].ImageTransparency = 1
						end
						labels[i].ImageTransparency = 0
						currentFrame = i
						task.wait(m.frameTime)
					end
				end
			end)
		elseif m.kind == "SPRITE" then
			local lbl = labels[1]
			lbl.ImageTransparency = 0
			task.spawn(function()
				local i = 0
				while loopVersion == v and part.Parent ~= nil do
					if not waitAwake(v) then
						return
					end
					i = i % m.count + 1
					local x, y = rules.spriteOffset(i, m.columns, m.frameSize[1], m.frameSize[2])
					lbl.ImageRectOffset = Vector2.new(x, y)
					task.wait(m.frameTime)
				end
			end)
		elseif m.kind == "IMAGE" then
			labels[1].ImageTransparency = 0
		elseif m.kind == "VIDEO" and video then
			video.Playing = awake
		end
	end

	-- pasang media lain (loop lama berhenti); kalau layar sedang menyala, media baru langsung jalan
	local function replace(m: any)
		loopVersion += 1
		stopMedia()
		clear()
		build(m)
		if shown then
			startMedia(loopVersion)
		end
	end

	-- ── fade (side) ─────────────────────────────────────────────────────────────────────────────────────────────
	local fadeOverlay: Frame? = nil
	local function fadeTo(targetTransparency: number)
		if fadeOverlay then
			TweenService:Create(
				fadeOverlay,
				TweenInfo.new(cfg.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = targetTransparency }
			):Play()
		end
	end

	local function show()
		showVersion += 1
		loopVersion += 1
		surfaceGui.Enabled = true
		if fade then
			(fadeOverlay :: Frame).BackgroundTransparency = 0 -- mulai dari hitam
			fadeTo(1) -- lalu memudar ke transparan
		end
		startMedia(loopVersion)
	end

	local function hide()
		showVersion += 1 -- tunda-matikan lama batal
		loopVersion += 1 -- loop animasi berhenti
		local v = showVersion
		if fade then
			fadeTo(0) -- gelapkan dulu
			task.delay(cfg.FADE_TIME, function()
				if showVersion == v then -- hanya matikan kalau belum keburu dinyalakan lagi
					stopMedia()
					surfaceGui.Enabled = false
				end
			end)
		else
			stopMedia()
			surfaceGui.Enabled = false
		end
	end

	-- ── mulai ───────────────────────────────────────────────────────────────────────────────────────────────────
	local first = getMedia()
	if not first then
		warn("[" .. LABEL .. "] tidak ada media yang diisi (IMAGE_ID / GIF_FRAMES / VIDEO_ID) — layar dilewati")
		return nil
	end
	build(first)

	if side then
		local overlay = Instance.new("Frame") -- layar hitam yang memudar
		overlay.Name = "FadeOverlay"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.ZIndex = cfg.FADE_ZINDEX
		overlay.Parent = surfaceGui
		fadeOverlay = overlay

		local function isActive(): boolean
			local mode = if screenModeVal then screenModeVal.Value else nil
			local on = part:GetAttribute("On") -- diisi server (START_ON); belum ada = START_ON
			if on == nil then
				on = cfg.START_ON
			end
			return rules.isActive(on, cfg.USE_SCREENMODE, screenModeVal ~= nil, mode, cfg.ACTIVE_ON_MODE)
		end
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
	else
		shown = true -- layar utama selalu menyala
		loopVersion += 1
		startMedia(loopVersion)
	end

	-- ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────
	local wanted = media
	local swapping = false

	-- Ganti isi layar. Layar samping yang sedang menyala: gelap dulu (fade), ganti, lalu terang lagi. Pilihan yang
	-- datang selama fade hanya mencatat `wanted` — yang dipasang selalu pilihan TERAKHIR.
	function self.setMedia(m: any)
		wanted = m
		if swapping or (media and media.id == m.id) then
			return
		end
		if not (fade and shown) then
			replace(m)
			return
		end
		swapping = true
		fadeTo(0)
		task.delay(cfg.FADE_TIME, function()
			swapping = false
			if not (media and media.id == wanted.id) then
				replace(wanted)
			end
			if shown then
				fadeTo(1)
			end
		end)
	end

	-- Dari pengecek jarak/kamera DjStageClient. Animasi menunggu, video berhenti/lanjut.
	function self.setAwake(a: boolean)
		if a == awake then
			return
		end
		awake = a
		if media and media.kind == "VIDEO" and video and shown then
			video.Playing = awake
		end
	end

	function self.kind(): string?
		return media and media.kind
	end

	function self.mediaId(): string?
		return media and media.id
	end

	return self
end

return Screen
