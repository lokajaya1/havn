-- ═══════════════════════════════════════════════════════════
-- UIManager — saklar buka/tutup ScreenGui
-- Path: ReplicatedStorage.CustomUIModules.UIManager
--
-- Modul ini TIDAK membuat UI dan TIDAK mengatur ukuran panel yang sudah
-- punya layout sendiri (MenuFrame dari MenuSystemInit, CarrySelectFrame
-- dari CarryUI). Tugasnya cuma: menunggu ScreenGui muncul, buka-tutup
-- dengan tween + debounce, dan menjaga cuma satu panel MENU_GROUP terbuka.
-- ═══════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")

local modules    = RS:WaitForChild("CustomUIModules")
local Responsive = require(modules:WaitForChild("Responsive"))

local UIManager = {}

-- ── Private state ───────────────────────────────────────────

local player: Player?
local playerGui: PlayerGui?
local guis: { [string]: ScreenGui } = {}
local currentTargetPlayer: Player? = nil
local restPos:          { [string]: UDim2 }  = {}
local lastActionTime:   { [string]: number } = {}
local activeTweens:     { [string]: Tween }  = {}
local connections:      { RBXScriptConnection } = {}
local disconnectResize: (() -> ())? = nil
local initComplete = false
local initCallbacks: { () -> () } = {}

-- ── Constants ───────────────────────────────────────────────

local DEBOUNCE_TIME = 0.15
local TWEEN_SHOW    = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_HIDE    = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

-- Panel sekarang menempel bawah layar, jadi slide-nya pendek ke bawah.
-- Nilai lama (0.5 skala tinggi layar) bikin panel terbang jauh keluar layar.
local SLIDE_OFFSET = UDim2.new(0, 0, 0, 28)

local MENU_GROUP = { "PlayerMenu", "CarrySelect", "FriendRequest" }

local FRAME_NAMES = {
	PlayerMenu    = "MenuFrame",
	CarrySelect   = "CarrySelectFrame",
	FriendRequest = "FriendRequestFrame",
}

-- Frame yang mengatur ukuran & posisinya sendiri (punya applyConfig +
-- Responsive.OnChange masing-masing). Jangan ditimpa dari sini.
local SELF_SIZED = {
	MenuFrame        = true,
	CarrySelectFrame = true,
}

-- ScreenGui bernama "carry*" yang BOLEH hidup:
--   carrygui       → panel carry dari CarryUI (request + drop + toast)
--   carryselectgui → pemilih jenis carry, dibuat CarryUI
-- CarryRequestGui dan DropCarryGui sengaja TIDAK di sini: keduanya sudah
-- digantikan CarryUI, kalau dibiarkan hidup panelnya dobel di posisi sama.
local CARRY_WHITELIST = {
	carrygui       = true,
	carryselectgui = true,
}

-- ── Ukuran FriendRequest (satu-satunya panel tanpa layout sendiri) ──

local function friendRequestSize()
	local device = Responsive.Device()
	local isP    = Responsive.Orientation() == "portrait"
	local vp     = Responsive.Viewport()

	local w, h
	if device == "mobile" then
		w = math.clamp(vp.X * (isP and 0.55 or 0.35), 220, isP and 260 or 300)
		h = math.clamp(vp.Y * (isP and 0.20 or 0.30), 170, 210)
	elseif device == "tablet" then
		w = math.clamp(vp.X * (isP and 0.35 or 0.22), 250, 300)
		h = math.clamp(vp.Y * (isP and 0.22 or 0.28), 210, 260)
	else
		w = math.clamp(vp.X * 0.14, 240, 280)
		h = math.clamp(vp.Y * 0.20, 210, 260)
	end
	return UDim2.new(0, math.floor(w), 0, math.floor(h))
end

local function bottomPosition(): UDim2
	return UDim2.new(0.5, 0, 1, -Responsive.BottomInset())
end

-- ── Internal helpers ────────────────────────────────────────

local function cancelTween(name: string)
	local tween = activeTweens[name]
	if tween then
		tween:Cancel()
		activeTweens[name] = nil
	end
end

local function getFrame(gui: ScreenGui, menuName: string): Frame?
	local frameName = FRAME_NAMES[menuName]
	if not frameName then return nil end
	return gui:FindFirstChild(frameName)
end

-- Posisi istirahat dibaca LANGSUNG dari frame kalau tidak ada tween jalan.
-- Dulu disimpan sekali di Init, jadi setelah panel me-resize sendiri
-- (Responsive.OnChange) nilainya basi dan panel melompat saat dibuka.
local function restOf(name: string, frame: Frame): UDim2
	if not activeTweens[name] then
		restPos[frame.Name] = frame.Position
	end
	return restPos[frame.Name] or frame.Position
end

local function animate(name: string, frame: Frame, targetPos: UDim2, info: TweenInfo): Tween
	cancelTween(name)
	local tween = TweenService:Create(frame, info, { Position = targetPos })
	activeTweens[name] = tween
	tween:Play()
	return tween
end

local function waitForGUI(name: string, timeout: number?): ScreenGui?
	if not playerGui then return nil end
	local deadline = os.clock() + (timeout or 30)

	while os.clock() < deadline do
		local gui = playerGui:FindFirstChild(name)
		if gui then
			if name ~= "PlayerMenuGui" then return gui end
			if gui:GetAttribute("SetupComplete") or gui:FindFirstChild("MenuFrame") then
				gui:SetAttribute("SetupComplete", true)
				return gui
			end
		end
		task.wait(0.1)
	end
	return nil
end

local function setupGUI(gui: ScreenGui?, frameName: string)
	if not gui then return end
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = false
	gui.Enabled        = false

	local frame = gui:FindFirstChild(frameName)
	if not frame then return end
	frame.Visible = true
	frame.Active  = true

	if not SELF_SIZED[frameName] then
		frame.Size        = friendRequestSize()
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position    = bottomPosition()
	end

	restPos[frameName] = frame.Position
end

local function isStrayCarryGui(gui: Instance): boolean
	if not gui:IsA("ScreenGui") then return false end
	local low = gui.Name:lower()
	if not low:find("carry", 1, true) then return false end
	return not CARRY_WHITELIST[low]
end

local function hideMenuGroup(exceptName: string?)
	for _, name in ipairs(MENU_GROUP) do
		if name ~= exceptName then
			local gui = guis[name]
			if gui and gui.Enabled then
				cancelTween(name)
				local frame = getFrame(gui, name)
				if frame and restPos[frame.Name] then
					frame.Position = restPos[frame.Name]
				end
				gui.Enabled = false
			end
		end
	end
end

local function applyResponsive()
	local gui   = guis.FriendRequest
	local frame = gui and gui:FindFirstChild("FriendRequestFrame")
	if frame then
		frame.Size     = friendRequestSize()
		frame.Position = bottomPosition()
		restPos.FriendRequestFrame = frame.Position
	end
end

-- ── Init ────────────────────────────────────────────────────

local function initOnce(): boolean
	if initComplete then return true end

	player = Players.LocalPlayer
	if not player then return false end

	playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then return false end

	for _, child in ipairs(playerGui:GetChildren()) do
		if isStrayCarryGui(child) then child.Enabled = false end
	end

	guis.PlayerMenu = waitForGUI("PlayerMenuGui", 30)
	if not guis.PlayerMenu or not guis.PlayerMenu:FindFirstChild("MenuFrame") then
		warn("[UIManager] PlayerMenuGui tidak ada atau MenuFrame hilang")
		return false
	end

	guis.CarrySelect   = waitForGUI("CarrySelectGui", 10)
	guis.FriendRequest = waitForGUI("FriendRequestGui", 10)

	setupGUI(guis.PlayerMenu,    "MenuFrame")
	setupGUI(guis.CarrySelect,   "CarrySelectFrame")
	setupGUI(guis.FriendRequest, "FriendRequestFrame")

	disconnectResize = Responsive.OnChange(applyResponsive)

	-- ScreenGui carry lama bisa dibuat belakangan oleh script warisan
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if isStrayCarryGui(child) then child.Enabled = false end
	end))

	initComplete = true
	for _, cb in ipairs(initCallbacks) do task.spawn(cb) end
	table.clear(initCallbacks)

	print("[UIManager] Ready |", Responsive.Device(), "|", Responsive.Orientation())
	return true
end

-- [FIX 4c] Init bisa dipanggil 2x bersamaan (InteractionLoad: start + CharacterAdded saat Init pertama
-- masih menunggu GUI) → dulu GUI di-setup 2x, listener resize/ChildAdded dobel, "Ready" tercetak 2x.
-- Sekarang panggilan kedua MENUNGGU yang pertama selesai lalu memakai hasilnya.
local initRunning = false
function UIManager.Init(): boolean
	if initComplete then return true end
	if initRunning then
		local t0 = os.clock()
		repeat task.wait(0.1) until not initRunning or os.clock() - t0 > 60
		return initComplete
	end
	initRunning = true
	local ok, result = pcall(initOnce)
	initRunning = false
	if not ok then error(result, 0) end
	return result
end

function UIManager.OnReady(callback: () -> ())
	if initComplete then task.spawn(callback) else table.insert(initCallbacks, callback) end
end

function UIManager.IsReady(): boolean
	return initComplete
end

function UIManager.Get(name: string): ScreenGui?
	return guis[name]
end

-- ── Show / Hide ─────────────────────────────────────────────

local function debounced(name: string, suffix: string): boolean
	local key = name .. suffix
	local now = os.clock()
	if (now - (lastActionTime[key] or 0)) < DEBOUNCE_TIME then return true end
	lastActionTime[key] = now
	return false
end

function UIManager.Show(name: string)
	local gui = guis[name]
	if not gui or gui.Enabled then return end
	if debounced(name, "_s") then return end

	hideMenuGroup(name)
	gui.Enabled = true

	local frame = getFrame(gui, name)
	if not frame then return end

	frame.Visible = true
	local rest = restOf(name, frame)
	frame.Position = rest + SLIDE_OFFSET
	animate(name, frame, rest, TWEEN_SHOW)
end

function UIManager.Hide(name: string)
	local gui = guis[name]
	if not gui or not gui.Enabled then return end
	if debounced(name, "_h") then return end

	local frame = getFrame(gui, name)
	if not frame then
		gui.Enabled = false
		return
	end

	local rest  = restOf(name, frame)
	local tween = animate(name, frame, rest + SLIDE_OFFSET, TWEEN_HIDE)
	tween.Completed:Once(function()
		gui.Enabled    = false
		frame.Position = rest
	end)
end

function UIManager.HideAll()
	for name in pairs(guis) do UIManager.Hide(name) end
end

function UIManager.Toggle(name: string)
	local gui = guis[name]
	if not gui then return end
	if gui.Enabled then UIManager.Hide(name) else UIManager.Show(name) end
end

function UIManager.IsAnyMenuVisible(): boolean
	for _, gui in pairs(guis) do
		if gui and gui.Enabled then return true end
	end
	return false
end

-- ── Target Player ───────────────────────────────────────────

function UIManager.SetTargetPlayer(target: Player?): boolean
	if not target or not target:IsA("Player") then
		currentTargetPlayer = nil
		return false
	end
	currentTargetPlayer = target
	return true
end

function UIManager.GetTargetPlayer(): Player?
	if currentTargetPlayer and currentTargetPlayer.Parent == nil then
		currentTargetPlayer = nil
	end
	return currentTargetPlayer
end

return UIManager