-- ═══════════════════════════════════════════════════════════
-- Responsive — deteksi device, viewport, jarak aman bawah, sinyal resize
-- Path: ReplicatedStorage.CustomUIModules.Responsive
--
-- Satu sumber untuk semua panel (MenuSystemInit, PlayersPanel, CarryUI,
-- UIManager): device, orientasi, jarak aman bawah, sinyal resize, dan
-- ukuran panel utama lewat Responsive.Panel(). Metrik yang khas satu panel
-- (mis. tinggi kartu avatar) tetap tinggal di panel itu sendiri.
-- ═══════════════════════════════════════════════════════════

local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

local Responsive = {}

local FALLBACK  = Vector2.new(1280, 720)
local TABLET_PX = 1000   -- sisi terpanjang minimum untuk dihitung tablet

-- Tinggi yang dipakai hotbar/inventory default Roblox di bawah layar,
-- plus sedikit celah. Panel apa pun tidak boleh masuk area ini.
local BOTTOM_RESERVE = { mobile = 92, tablet = 100, desktop = 100 }

local TOP_MARGIN = 16

-- Ukuran & metrik panel utama. SATU tabel untuk semua panel bertumpuk di
-- bawah layar (PlayerMenu di MenuSystemInit, CarrySelect di CarryUI,
-- FriendRequest di UIManager) supaya lebarnya tidak pernah beda-beda lagi.
local PANEL = {
	mobile = {
		portrait  = { width = {0.55, 180, 220}, height = {0.38, 260, 310},
			row = 36, title = 13, text = 12, small = 10, pad = 10, gap = 5 },
		-- layar pendek (~390px): frame dibikin tinggi, sisanya di-scroll
		landscape = { width = {0.30, 170, 210}, height = {0.86, 200, 300},
			row = 32, title = 13, text = 12, small = 10, pad = 9,  gap = 5 },
	},
	tablet = {
		portrait  = { width = {0.25, 190, 230}, height = {0.34, 280, 340},
			row = 40, title = 15, text = 13, small = 11, pad = 12, gap = 6 },
		landscape = { width = {0.20, 195, 240}, height = {0.60, 260, 340},
			row = 38, title = 14, text = 12, small = 10, pad = 11, gap = 6 },
	},
	desktop = {
		portrait  = { width = {0.16, 200, 240}, height = {0.40, 290, 350},
			row = 40, title = 15, text = 13, small = 11, pad = 12, gap = 6 },
		landscape = { width = {0.15, 200, 240}, height = {0.42, 290, 355},
			row = 40, title = 15, text = 13, small = 11, pad = 12, gap = 6 },
	},
}

function Responsive.Viewport(): Vector2
	local cam = workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize
	if not vp or vp.X <= 10 or vp.Y <= 10 then return FALLBACK end
	return vp
end

function Responsive.Device(): string
	local touch, keyboard = UIS.TouchEnabled, UIS.KeyboardEnabled
	if touch and not keyboard then
		local vp = Responsive.Viewport()
		return (math.max(vp.X, vp.Y) >= TABLET_PX) and "tablet" or "mobile"
	elseif touch and keyboard then
		return "tablet"
	end
	return "desktop"
end

function Responsive.Orientation(): string
	local vp = Responsive.Viewport()
	return (vp.X > vp.Y) and "landscape" or "portrait"
end

-- Jarak dari sisi bawah layar yang harus dikosongkan. Panel dipasang
-- AnchorPoint (0.5, 1) di Position UDim2.new(0.5, 0, 1, -BottomInset()).
-- Di layar pendek (landscape HP) nilainya dipangkas supaya panel tetap
-- kebagian ruang.
function Responsive.BottomInset(): number
	local vp   = Responsive.Viewport()
	local base = BOTTOM_RESERVE[Responsive.Device()] or 100
	return math.floor(math.min(base, vp.Y * 0.22))
end

-- spec = { skala, minimum, maksimum }
function Responsive.Resolve(axis: number, spec: { number }): number
	return math.floor(math.clamp(axis * spec[1], spec[2], spec[3]))
end

-- Ukuran + metrik panel bawah. Tinggi selalu dipangkas supaya tidak
-- menembus hotbar (BottomInset) maupun keluar sisi atas layar.
function Responsive.Panel()
	local vp     = Responsive.Viewport()
	local device = Responsive.Device()
	local orient = Responsive.Orientation()
	local s      = PANEL[device][orient]
	local inset  = Responsive.BottomInset()

	local width     = math.min(Responsive.Resolve(vp.X, s.width), math.floor(vp.X) - 24)
	local maxHeight = math.max(math.floor(vp.Y) - inset - TOP_MARGIN, 160)
	local height    = math.min(Responsive.Resolve(vp.Y, s.height), maxHeight)

	return {
		device = device, orientation = orient,
		width = width, height = height, bottomInset = inset,
		row = s.row, title = s.title, text = s.text, small = s.small,
		pad = s.pad, gap = s.gap,
	}
end

-- Sinyal resize dengan debounce + rebind kamera.
-- Rebind penting: kalau CurrentCamera diganti (respawn, cutscene), koneksi
-- ke kamera lama mati diam-diam dan panel berhenti responsif tanpa error.
-- Mengembalikan fungsi disconnect.
function Responsive.OnChange(callback: () -> (), debounce: number?): () -> ()
	local delay  = debounce or 0.1
	local queued = false
	local camConn

	local function fire()
		if queued then return end
		queued = true
		task.delay(delay, function()
			queued = false
			callback()
		end)
	end

	local function bind()
		if camConn then camConn:Disconnect() end
		local cam = workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(fire)
		end
	end

	local camChanged = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bind()
		fire()
	end)
	bind()

	return function()
		if camConn then camConn:Disconnect(); camConn = nil end
		camChanged:Disconnect()
	end
end

if RunService:IsServer() then
	warn("[Responsive] Modul ini client-only — hasil di server tidak berarti.")
end

return Responsive