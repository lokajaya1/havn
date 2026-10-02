-- ═══════════════════════════════════════════════════════════
-- CarrySelectPanelInit — bikin kerangka ScreenGui "CarrySelectGui"
-- Path: StarterPlayerScripts (LocalScript)
--
-- KENAPA SCRIPT INI ADA:
-- UIManager.Init() nunggu (waitForGUI, timeout 10 detik) ScreenGui bernama
-- "CarrySelectGui" muncul di PlayerGui, lalu MenuBinder.populateCarrySelect()
-- ngisi tombol jenis carry ke dalam CarrySelectFrame.ScrollingFrame.ButtonsFrame.
-- Tapi TIDAK ADA script manapun yang benar-benar MEMBUAT ScreenGui itu --
-- kalau ini gak dibuat (baik manual di Studio atau lewat script), maka:
--   1. UIManager.Init() timeout diam-diam setelah 10 detik
--   2. guis.CarrySelect tetap nil
--   3. Klik tombol "Carry" di menu (Choose_Carry) gak nampilin apa-apa,
--      TANPA error yang kelihatan ke pemain.
--
-- Script ini bikin KERANGKA KOSONGNYA SAJA lewat kode (gak perlu bikin
-- manual di Studio). Ukuran, posisi final, dan isi tombol tetap diatur
-- sepenuhnya oleh UIManager (setupGUI / applyResponsive) dan MenuBinder
-- (populateCarrySelect) seperti biasa -- jangan diubah urutan/nama child-nya.
--
-- Kalau kamu SUDAH punya CarrySelectGui yang dibikin manual di StarterGui
-- atau lewat script lain (mis. "MenuSystemInit"), script ini otomatis
-- gak ngapa-ngapain (deteksi duplikat di bawah) -- aman ditaruh bareng.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Jangan bikin dobel kalau sudah ada (manual di Studio / script lain).
if playerGui:FindFirstChild("CarrySelectGui") then
	return
end

-- ── Tema (samakan dengan CarryUI.lua biar konsisten) ─────────

local THEME = {
	BG     = Color3.fromRGB(16, 16, 17),
	CARD   = Color3.fromRGB(26, 26, 28),
	LINE   = Color3.fromRGB(255, 255, 255),
	ACCENT = Color3.fromRGB(212, 175, 55),
	TEXT   = Color3.fromRGB(238, 238, 240),
	TEXT_DIM = Color3.fromRGB(148, 148, 154),
}

local function new(class, props)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	return obj
end

-- ── ScreenGui root ────────────────────────────────────────────

local gui = new("ScreenGui", {
	Name           = "CarrySelectGui",
	ResetOnSpawn   = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder   = 10,
	Enabled        = false, -- UIManager yang nyalain lewat Show("CarrySelect")
	Parent         = playerGui,
})

-- ── Frame utama ───────────────────────────────────────────────
-- Ukuran & posisi di bawah cuma nilai default sementara; begitu UIManager.Init()
-- nemu GUI ini, dia langsung timpa Size/Position/AnchorPoint-nya sendiri
-- (lihat UIManager.setupGUI, dipanggil dengan cfg.w / cfg.hS per device).

local frame = new("Frame", {
	Name             = "CarrySelectFrame",
	AnchorPoint      = Vector2.new(0.5, 0.5),
	Position         = UDim2.new(0.5, 0, 0.5, 0),
	Size             = UDim2.new(0, 280, 0, 380),
	BackgroundColor3 = THEME.BG,
	BorderSizePixel  = 0,
	Visible          = true,
	Active           = true,
	Parent           = gui,
})

new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = frame })
new("UIStroke", {
	Color            = THEME.ACCENT,
	Thickness        = 1,
	Transparency     = 0.65,
	ApplyStrokeMode  = Enum.ApplyStrokeMode.Border,
	Parent           = frame,
})

-- ── Judul + tombol tutup ────────────────────────────────────

local title = new("TextLabel", {
	Name                    = "Title",
	BackgroundTransparency  = 1,
	Position                = UDim2.new(0, 14, 0, 10),
	Size                    = UDim2.new(1, -50, 0, 24),
	Font                    = Enum.Font.GothamBold,
	Text                    = "Choose Carry",
	TextColor3              = THEME.ACCENT,
	TextSize                = 16,
	TextXAlignment          = Enum.TextXAlignment.Left,
	Parent                  = frame,
})

local subtitle = new("TextLabel", {
	Name                    = "Subtitle",
	BackgroundTransparency  = 1,
	Position                = UDim2.new(0, 14, 0, 32),
	Size                    = UDim2.new(1, -50, 0, 16),
	Font                    = Enum.Font.Gotham,
	Text                    = "Pick a carry type to request",
	TextColor3              = THEME.TEXT_DIM,
	TextSize                = 11,
	TextXAlignment          = Enum.TextXAlignment.Left,
	Parent                  = frame,
})

local closeButton = new("TextButton", {
	Name             = "CloseButton",
	AnchorPoint      = Vector2.new(1, 0),
	Position         = UDim2.new(1, -8, 0, 8),
	Size             = UDim2.new(0, 28, 0, 28),
	BackgroundTransparency = 1,
	AutoButtonColor  = false,
	Font             = Enum.Font.GothamBold,
	Text             = "✕",
	TextColor3       = Color3.fromRGB(200, 200, 200),
	TextSize         = 16,
	Parent           = frame,
})
closeButton.MouseEnter:Connect(function() closeButton.TextColor3 = Color3.fromRGB(255, 100, 100) end)
closeButton.MouseLeave:Connect(function() closeButton.TextColor3 = Color3.fromRGB(200, 200, 200) end)

-- ── ScrollingFrame + ButtonsFrame ────────────────────────────
-- Nama & hierarki ini WAJIB persis sama karena dipakai langsung oleh
-- MenuBinder.populateCarrySelect(): find(gui, "CarrySelectFrame.ScrollingFrame")
-- lalu scrollFrame:FindFirstChild("ButtonsFrame").

local scrollingFrame = new("ScrollingFrame", {
	Name                     = "ScrollingFrame",
	Position                 = UDim2.new(0, 10, 0, 54),
	Size                     = UDim2.new(1, -20, 1, -64),
	BackgroundTransparency   = 1,
	BorderSizePixel          = 0,
	ScrollBarThickness       = 4,
	ScrollBarImageColor3     = THEME.ACCENT,
	CanvasSize               = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize      = Enum.AutomaticSize.Y,
	ScrollingDirection       = Enum.ScrollingDirection.Y,
	Parent                   = frame,
})

local buttonsFrame = new("Frame", {
	Name                    = "ButtonsFrame",
	Size                    = UDim2.new(1, 0, 0, 0),
	AutomaticSize           = Enum.AutomaticSize.Y,
	BackgroundTransparency  = 1,
	Parent                  = scrollingFrame,
})
-- MenuBinder.populateCarrySelect() bakal nambahin/nge-reset UIListLayout &
-- UIPadding sendiri di dalam ButtonsFrame ini kalau belum ada, jadi gak
-- perlu dibikin manual di sini.

-- ── Wire tombol tutup (nunggu UIManager siap, non-blocking) ──

task.spawn(function()
	local modules = RS:WaitForChild("CustomUIModules")
	local ok, UIManager = pcall(require, modules:WaitForChild("UIManager"))
	if ok and UIManager then
		closeButton.Activated:Connect(function()
			UIManager.Hide("CarrySelect")
		end)
	else
		warn("[CarrySelectPanelInit] Gagal require UIManager buat wire CloseButton")
	end
end)

print("[CarrySelectPanelInit] Kerangka CarrySelectGui dibuat")