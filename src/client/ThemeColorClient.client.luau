-- StarterPlayerScripts/ThemeColorClient (LocalScript) — pemilih tema warna UI (themeColor, claude/Rencana_ThemeColor.md).
-- Dibuka dari Menu › Settings › TAMPILAN › "Themes (game pass)" (SettingsClient memanggil _G.ToggleThemeColor).
-- Gaya contoh user (Salon de Fiesta): jendela kecil di tengah layar DI ATAS Settings (latar diredupkan), daftar tema
-- dengan bulatan radio warna tiap tema, garis tepi bergerak (ThemeColor.glow), Confirm / Cancel.
--   hover baris → garis tepi bergerak (sorot hover ThemeColor, otomatis untuk semua tombol panel bertanda)
--   klik baris → titik radio PINDAH ke tema itu (belum dipasang) → Confirm baru memasang:
--     gratis / sudah punya pass → ThemeColorRemotes.Select → server set atribut Player "ThemeColor" → semua UI ikut.
--     terkunci → jendela beli game pass Config.passName → setelah dibeli tema yang dipilih langsung dipasang.
-- Server (ServerScriptService.ThemeColor) yang memutuskan & menyimpan; jendela ini hanya tampilan.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Didaftarkan lebih dulu: SettingsClient bisa memanggil sebelum remote siap.
local isOpen = false
_G.ToggleThemeColor = function() end
_G.ThemeColorMenu = { IsOpen = function() return isOpen end }

local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local Config = ThemeColor.Config
local ShopConfig = require(RS:WaitForChild("ShopConfig"))
local Responsive = require(RS:WaitForChild("CustomUIModules"):WaitForChild("Responsive"))
local T = ThemeColor.tokens

_G.ThemeColorMenu.Label = function()
	return ThemeColor.label(ThemeColor.current)
end

local remotes = RS:WaitForChild("ThemeColorRemotes", 60)
local selectFn = remotes and remotes:WaitForChild("Select", 30)
if not selectFn then
	warn("[ThemeColorClient] ThemeColorRemotes.Select tidak ada — server ThemeColor tidak jalan?")
	return
end

local waited = 0
while not _G.MenuConfig and waited < 10 do
	task.wait(0.1)
	waited += 0.1
end
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold,
	MEDIUM = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local ROW_H, ROW_GAP, GAP, PAD, BTN_H = 34, 5, 6, 10, 36
local TW = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ── helper ────────────────────────────────────────────────────────────────────────────────────────────────────────
local function new(class, props)
	local o = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then o[k] = v end
	end
	o.Parent = props.Parent
	return o
end
local function corner(p, r) new("UICorner", { CornerRadius = r, Parent = p }) end
local function stroke(p, c, tr, th)
	return new("UIStroke", { Color = c, Thickness = th or 1, Transparency = tr, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p })
end

local function passInfo()
	return ShopConfig.getGamepassByName(Config.passName)
end
local function ownsPass()
	return player:GetAttribute(ThemeColor.PASS_ATTR) == true
end
local function locked(id)
	return not ThemeColor.isFree(id) and not ownsPass()
end

local paint -- function() (di bawah)

-- Harga pass dari Roblox (sekali, di latar). nil = belum / gagal → tombol tanpa angka.
local price = nil
local priceAsked = false
local function askPrice()
	local pass = passInfo()
	if priceAsked or not pass then return end
	priceAsked = true
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.id, Enum.InfoType.GamePass)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			price = info.PriceInRobux
			if isOpen then paint() end
		else
			priceAsked = false -- coba lagi saat dibuka berikutnya
		end
	end)
end

-- ── kerangka ──────────────────────────────────────────────────────────────────────────────────────────────────────
local old = playerGui:FindFirstChild("ThemeColorGui")
if old then old:Destroy() end
local gui = new("ScreenGui", {
	Name = "ThemeColorGui", ResetOnSpawn = false, Enabled = false, DisplayOrder = 100, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
})
ThemeColor.mark(gui)

-- Latar redup (ketuk = batal). Hitam murni = tidak ikut tema.
local overlay = new("TextButton", {
	Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
	Text = "", AutoButtonColor = false, Parent = gui,
})

local modal = new("Frame", {
	Name = "Modal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = T.BG, BorderSizePixel = 0, Active = true, Parent = gui, -- Active: klik tidak tembus ke overlay
})
corner(modal, UDim.new(0, 14))
ThemeColor.glow(stroke(modal, T.LINE, 0.5, 1.5), "panel")
local scale = new("UIScale", { Scale = 1, Parent = modal })

local list = new("ScrollingFrame", {
	Name = "List", Position = UDim2.fromOffset(PAD, PAD), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = T.SCROLL, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = modal,
})
local listLayout = new("UIListLayout", { Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
-- 2 px di tiap sisi: garis sorot tidak pernah menyentuh tepi daftar bergulir (tidak terpotong); kanan + ruang scrollbar.
new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2),
	PaddingRight = UDim.new(0, 6), Parent = list })

-- Confirm: isi gradasi aksen (gelap → terang). BackgroundColor3 putih = warna sepenuhnya dari UIGradient.
local confirmBtn = new("TextButton", {
	Name = "Confirm", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AutoButtonColor = false,
	Text = "Confirm", TextColor3 = T.ON_ACCENT, Font = FONT.BOLD, TextSize = 15, Parent = modal,
})
corner(confirmBtn, UDim.new(0, 9))
local confirmGrad = new("UIGradient", { Parent = confirmBtn })
ThemeColor.skip(confirmGrad) -- diwarnai paint() (warna turunan aksen, bukan token)

local cancelBtn = new("TextButton", {
	Name = "Cancel", BackgroundColor3 = T.CARD, BorderSizePixel = 0, AutoButtonColor = false,
	Text = "Cancel", TextColor3 = T.TEXT, Font = FONT.MEDIUM, TextSize = 15, Parent = modal,
})
corner(cancelBtn, UDim.new(0, 9))

-- ── baris tema ────────────────────────────────────────────────────────────────────────────────────────────────────
local rows = {}
local pending = ThemeColor.current -- tema yang DIPILIH (titik radio); baru dipasang saat Confirm
local busy = false
local note = nil -- teks sementara di tombol Confirm (mis. "Tunggu sebentar…")

for i, id in ThemeColor.ids() do
	local preset = Config.presets[id]
	local btn = new("TextButton", {
		Name = id, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = T.CARD, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "", LayoutOrder = i, Parent = list,
	})
	corner(btn, UDim.new(0, 8))
	-- bulatan radio = warna aksen tema itu (KONTEN: tidak ikut lukis ulang); titik = tema yang dipilih
	local ring = new("Frame", {
		Name = "Ring", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1, Parent = btn,
	})
	ThemeColor.skip(ring)
	corner(ring, UDim.new(1, 0))
	stroke(ring, preset.tokens.ACCENT, 0, 1.5)
	local dot = new("Frame", {
		Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = preset.tokens.ACCENT, BorderSizePixel = 0, Visible = false, Parent = ring,
	})
	corner(dot, UDim.new(1, 0))
	local name = new("TextLabel", {
		Name = "Label", Position = UDim2.new(0, 36, 0, 0), Size = UDim2.new(1, -66, 1, 0), BackgroundTransparency = 1,
		Text = preset.label, TextColor3 = T.TEXT, Font = FONT.MEDIUM, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
	})
	local lock = new("TextLabel", {
		Name = "Lock", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1, Text = "🔒", TextColor3 = T.TEXT_DIM, Font = FONT.MEDIUM, TextSize = 12, Parent = btn,
	})
	rows[id] = { btn = btn, dot = dot, name = name, lock = lock }
	btn.Activated:Connect(function() -- pilih saja (titik pindah); tema dipasang lewat Confirm
		if busy then return end
		pending = id
		note = nil
		paint()
	end)
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = T.CARD_HOVER
	end)
	btn.MouseLeave:Connect(function()
		if isOpen then paint() end
	end)
end

-- ── tampilan ──────────────────────────────────────────────────────────────────────────────────────────────────────
function paint()
	local current = ThemeColor.current
	for id, r in rows do
		local chosen = id == pending
		r.dot.Visible = chosen
		r.btn.BackgroundColor3 = T.CARD
		r.name.TextColor3 = if chosen then T.TEXT_STRONG else T.TEXT
		r.lock.Visible = locked(id)
	end

	local a = T.ACCENT
	confirmGrad.Color = ColorSequence.new(a:Lerp(Color3.new(0, 0, 0), 0.22), a)
	confirmBtn.TextColor3 = T.ON_ACCENT
	confirmBtn.TextTransparency = if pending == current and not note then 0.45 else 0
	if note then
		confirmBtn.Text = note
	elseif busy then
		confirmBtn.Text = "…"
	elseif locked(pending) then
		confirmBtn.Text = if not passInfo() then "🔒 Segera hadir"
			elseif price then ("🔒 Unlock · R$ %d"):format(price)
			else "🔒 Unlock (game pass)"
	else
		confirmBtn.Text = "Confirm"
	end
end

local function flash(text)
	note = text
	paint()
	task.delay(1.6, function()
		if note == text then
			note = nil
			if isOpen then paint() end
		end
	end)
end

-- ── buka / tutup ──────────────────────────────────────────────────────────────────────────────────────────────────
local function layout()
	local vp = Responsive.Viewport()
	local w = math.clamp(math.floor(vp.X - 32), 220, 280)
	local fullList = #ThemeColor.ids() * (ROW_H + ROW_GAP) - ROW_GAP + 4 -- + UIPadding atas/bawah
	local maxH = math.floor(math.min(vp.Y - 48, vp.Y * 0.78))
	local listH = math.max(math.min(fullList, maxH - (PAD * 2 + BTN_H * 2 + GAP * 2)), ROW_H * 2 + ROW_GAP + 4)
	modal.Size = UDim2.fromOffset(w, PAD + listH + GAP + BTN_H + GAP + BTN_H + PAD)
	list.Size = UDim2.new(1, -PAD * 2 + 4, 0, listH)
	confirmBtn.Position = UDim2.fromOffset(PAD, PAD + listH + GAP)
	confirmBtn.Size = UDim2.new(1, -PAD * 2, 0, BTN_H)
	cancelBtn.Position = UDim2.fromOffset(PAD, PAD + listH + GAP + BTN_H + GAP)
	cancelBtn.Size = UDim2.new(1, -PAD * 2, 0, BTN_H)
end
Responsive.OnChange(function()
	if isOpen then layout() end
end)

local function scrollToPending()
	local idx = table.find(ThemeColor.ids(), pending) or 1
	local y = 2 + (idx - 1) * (ROW_H + ROW_GAP) - (list.AbsoluteSize.Y - ROW_H) / 2
	local maxY = math.max(listLayout.AbsoluteContentSize.Y + 4 - list.AbsoluteSize.Y, 0)
	list.CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY))
end

local function setOpen(open)
	if open == isOpen then return end
	isOpen = open
	if open then
		pending = ThemeColor.current
		note = nil
		askPrice()
		layout()
		paint()
		gui.Enabled = true
		overlay.BackgroundTransparency = 1
		scale.Scale = 0.94
		TweenService:Create(overlay, TW, { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(scale, TW, { Scale = 1 }):Play()
		task.defer(scrollToPending)
	else
		gui.Enabled = false
	end
	if _G.ThemeColorMenu.OnChanged then pcall(_G.ThemeColorMenu.OnChanged, open) end
end
-- Jendela ini TIDAK menutup Menu (tampil di atas Settings seperti contoh; overlay menahan klik ke belakang).
-- Kalau panel lain menutup semua lewat PanelCoordinator.CloseAll, jendela ini ikut tertutup.
task.spawn(function()
	local t0 = os.clock()
	while not (_G.PanelCoordinator and _G.PanelCoordinator.Register) and os.clock() - t0 < 30 do task.wait(0.2) end
	local pc = _G.PanelCoordinator
	if pc and pc.Register then pc.Register("ThemeColor", function() setOpen(false) end) end
end)

local function promptPass()
	local pass = passInfo()
	if not pass then
		flash("Game pass segera hadir")
		return
	end
	local ok = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.id)
	if not ok then flash("Coba lagi") end
end

local REASON = { jeda = "Tunggu sebentar…", pass = "Butuh game pass " .. Config.passName, tema = "Tema tidak dikenal" }

local function confirm()
	if busy then return end
	if pending == ThemeColor.current then
		setOpen(false)
		return
	end
	if locked(pending) then
		promptPass()
		return
	end
	busy = true
	paint()
	local ok, r = pcall(selectFn.InvokeServer, selectFn, pending)
	busy = false
	if ok and type(r) == "table" and (r.ok or r.reason == "sama") then
		setOpen(false)
	else
		local why = ok and type(r) == "table" and r.reason
		flash(REASON[why] or "Tidak ada jawaban server")
	end
end

confirmBtn.Activated:Connect(confirm)
cancelBtn.Activated:Connect(function() setOpen(false) end)
overlay.Activated:Connect(function() setOpen(false) end)
cancelBtn.MouseEnter:Connect(function() TweenService:Create(cancelBtn, TW, { BackgroundColor3 = T.CARD_HOVER }):Play() end)
cancelBtn.MouseLeave:Connect(function() TweenService:Create(cancelBtn, TW, { BackgroundColor3 = T.CARD }):Play() end)

_G.ToggleThemeColor = function() setOpen(not isOpen) end
_G.ThemeColorMenu.Open = function() setOpen(true) end
_G.ThemeColorMenu.Close = function() setOpen(false) end
_G.ThemeColorMenu.Gui = gui

UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)

-- Tema berubah (pilihan sendiri / server) → isi jendela ikut.
ThemeColor.onChanged(function()
	if isOpen then paint() end
end)
-- Pass baru dibeli saat jendela terbuka → tema berbayar yang sedang disorot langsung dipasang.
player:GetAttributeChangedSignal(ThemeColor.PASS_ATTR):Connect(function()
	if not isOpen then return end
	paint()
	if ownsPass() and pending ~= ThemeColor.current and not ThemeColor.isFree(pending) then
		task.spawn(confirm)
	end
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	local pass = passInfo()
	if plr ~= player or not pass or passId ~= pass.id or not isOpen or not purchased then return end
	flash("Terima kasih! Membuka tema…")
end)
