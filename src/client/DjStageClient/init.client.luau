-- StarterPlayerScripts/DjStageClient (LocalScript) — menggambar panggung DJ Workspace["DJ STAGE"] di perangkat pemain
-- (ruangan WORLD, claude/Rencana_World.md). Dulu semua ini dijalankan SERVER dan setiap ganti frame/warna dikirim ke
-- semua pemain; sekarang tiap client menggambar sendiri (tampilan sama, 0 kiriman jaringan per frame):
--   * LED          : dj/Interact*/Animate/BaseLED & dj/BaseCDJ*/…/USBLed berkedip (warna & jeda dari Config)
--   * Layar utama  : stage/EntranceScreenC — Config.LAYAR_UTAMA (bawaan GIF 25 frame), selalu menyala
--   * Layar samping: tiap BasePart di stage/StageScreens — Config.LAYAR_SAMPING (bawaan gambar) + fade hitam; menyala
--                    saat mode Gambar (ScreenMode "Gambar") & attribute "On". Mode Live = MultiScreenController.
-- Jenis media yang tampil = atribut Utama/Samping di ReplicatedStorage.DjStageRemotes ("IMAGE" | "GIF" | "VIDEO"),
-- diisi server DjStage (MEDIA_TYPE saat mulai, lalu pilihan admin).
-- Hemat: GIF & video berhenti saat kamera terlalu jauh; video juga saat layar tidak terlihat (Config.PAUSE).

local RS = game:GetService("ReplicatedStorage")

local Config = require(RS:WaitForChild("Config"):WaitForChild("DjStage"))
local Rules = require(RS:WaitForChild("Modules"):WaitForChild("DjStageRules"))
local Screen = require(script:WaitForChild("Screen"))

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

-- ── media yang dipilih ──────────────────────────────────────────────────────────────────────────────────────
local remotes: Instance? = RS:FindFirstChild("DjStageRemotes")
local function chosen(layarId: string): any
	local layar = Config.LAYAR[layarId]
	local picked = if remotes then remotes:GetAttribute(layarId) else nil
	return Rules.mediaOf(layar, picked) or Rules.mediaOf(layar, (Rules.startType(Config, layar)))
end

-- ── mulai ────────────────────────────────────────────────────────────────────────────────────────────────────
local stage = workspace:WaitForChild(Config.STAGE_NAME, Config.FIND_TIMEOUT)
if not stage then
	warn("[DjStageClient] Workspace." .. Config.STAGE_NAME .. " tidak ada — efek panggung dilewati")
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
		warn("[DjStageClient] LED " .. group.name .. " tidak ketemu di " .. table.concat(group.path, "/"))
	end
	nLed += n
end

local screens: { [string]: { any } } = { Utama = {}, Samping = {} }
local function addScreen(layarId: string, part: BasePart, style: string)
	task.spawn(function()
		local s = Screen.new(part, style, Config.LAYAR[layarId], Rules, function()
			return chosen(layarId)
		end, Config.PAUSE.interval)
		if s then
			table.insert(screens[layarId], s)
		end
	end)
end

local nUtama = 0
for _, part in collect(stage, Config.LAYAR_UTAMA.path) do
	if part:IsA("BasePart") then
		nUtama += 1
		addScreen("Utama", part, "utama")
	end
end
if nUtama == 0 then
	warn("[DjStageClient] layar utama tidak ketemu di " .. table.concat(Config.LAYAR_UTAMA.path, "/"))
end

local nSamping = 0
for _, folder in collect(stage, Config.LAYAR_SAMPING.folder) do
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			nSamping += 1
			addScreen("Samping", part, "samping")
		end
	end
end
if nSamping == 0 then
	warn("[DjStageClient] layar samping tidak ketemu di " .. table.concat(Config.LAYAR_SAMPING.folder, "/"))
end

-- Admin mengganti media → server mengubah atribut → semua layar itu ikut.
local function applyLayar(layarId: string)
	local m = chosen(layarId)
	if m then
		for _, s in screens[layarId] do
			s.setMedia(m)
		end
	end
end
local function bindRemotes(r: Instance)
	remotes = r
	for layarId in screens do
		r:GetAttributeChangedSignal(layarId):Connect(function()
			applyLayar(layarId)
		end)
		applyLayar(layarId)
	end
end
if remotes then
	bindRemotes(remotes)
else
	task.spawn(function()
		local r = RS:WaitForChild("DjStageRemotes", 60)
		if r then
			bindRemotes(r)
		end
	end)
end

-- Hemat: tiap Config.PAUSE.interval dtk, layar GIF/video yang terlalu jauh berhenti; video juga saat tidak terlihat
-- kamera. Dekat sekali (di dalam ukuran layar) selalu dihitung terlihat.
local function isVisible(cam: Camera, part: BasePart, distance: number): boolean
	local size = part.Size
	if distance <= math.max(size.X, size.Y, size.Z) then
		return true
	end
	local cf = part.CFrame
	for _, sx in { -0.5, 0, 0.5 } do
		for _, sy in { -0.5, 0, 0.5 } do
			for _, sz in { -0.5, 0, 0.5 } do
				local _, onScreen = cam:WorldToViewportPoint(cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz))
				if onScreen then
					return true
				end
			end
		end
	end
	return false
end
task.spawn(function()
	while true do
		task.wait(Config.PAUSE.interval)
		local cam = workspace.CurrentCamera
		if cam then
			local camPos = cam.CFrame.Position
			for _, list in screens do
				for _, s in list do
					local kind = s.kind()
					if kind and kind ~= "IMAGE" then
						local distance = (camPos - s.part.Position).Magnitude
						local visible = kind == "VIDEO" and isVisible(cam, s.part, distance)
						s.setAwake(Rules.awake(kind, distance, Config.PAUSE.distance, visible))
					end
				end
			end
		end
	end
end)

print(("[DjStageClient] ✅ LED %d · layar utama %d · layar samping %d"):format(nLed, nUtama, nSamping))
