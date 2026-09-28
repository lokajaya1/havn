-- StarterPlayerScripts/DonationClient  (LocalScript)
-- Tombol donasi di topbar kiri (sebelah Info, _G.TopbarLeft) + panel DONATE (tata letak BebeqDonare:
-- judul, grid 2 kolom kartu tier, pill DONATE) + kotak pesan opsional sebelum membeli.
-- Alur: pilih tier → (opsional) tulis pesan → Donate → SetMessage ke server (difilter di sana) → prompt beli Roblox.
-- Pembayaran & pengumuman sepenuhnya di server (DonationServer); client tidak pernah mengklaim donasi.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenSvc = game:GetService("TweenService")
local Market = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(RS:WaitForChild("DonationConfig"))
local msgFolder = RS:WaitForChild("DonationMessageSystem", 30)
local setMessage = msgFolder and msgFolder:WaitForChild("SetMessage", 30)
if not setMessage then
	warn("[Donation] SetMessage tidak ditemukan, panel donasi tidak dibuat")
	return
end

-- ── Tema (sama dengan menu game) ───────────────────────────────────────────
do
	local waited = 0
	while not _G.MenuConfig and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end
end
local T = (_G.MenuConfig and _G.MenuConfig.theme) or {
	BG = Color3.fromRGB(16, 16, 17), CARD = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39), LINE = Color3.fromRGB(255, 255, 255),
	TEXT = Color3.fromRGB(238, 238, 240), TEXT_DIM = Color3.fromRGB(148, 148, 154),
	ACCENT = Color3.fromRGB(212, 175, 55), DANGER = Color3.fromRGB(226, 96, 96),
	SUCCESS = Color3.fromRGB(96, 196, 132),
}
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold, MEDIUM = Enum.Font.BuilderSansMedium, REGULAR = Enum.Font.BuilderSans,
}
local ON_ACCENT = Color3.fromRGB(18, 18, 20)
local TF = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROBUX = utf8.char(0xE002)

local BTN_SZ = 40
local PANEL_W, PANEL_H = 460, 440
local CARD_H = 104
local HOTBAR_SPACE = 96
local MSG_GAP = Config.message.cooldown + 0.1 -- jeda antar SetMessage (server menolak < cooldown)

local function new(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	if props.Parent then
		o.Parent = props.Parent
	end
	return o
end
local function corner(r, p)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = p })
end
local function stroke(p, tr, color)
	return new("UIStroke", { Color = color or T.LINE, Thickness = 1, Transparency = tr or 0.92,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p })
end
local function tw(o, props)
	if o and o.Parent then
		TweenSvc:Create(o, TF, props):Play()
	end
end
local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then
		return Vector2.new(1280, 720)
	end
	return vp
end
local function panelTop()
	if _G.TopbarLayout and _G.TopbarLayout.contentTop then
		local ok, v = pcall(_G.TopbarLayout.contentTop)
		if ok and type(v) == "number" then
			return v
		end
	end
	return 64
end
local function hover(btn, base, over)
	btn.MouseEnter:Connect(function()
		tw(btn, { BackgroundColor3 = over })
	end)
	btn.MouseLeave:Connect(function()
		tw(btn, { BackgroundColor3 = base })
	end)
end

-- ── Panel ──────────────────────────────────────────────────────────────────
local gui = new("ScreenGui", { Name = "DonationGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 61, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = T.BG,
	Visible = false, Parent = gui })
corner(14, panel)
stroke(panel, 0.85)
new("TextLabel", { Name = "Title", Position = UDim2.new(0, 20, 0, 14), Size = UDim2.new(1, -80, 0, 30),
	BackgroundTransparency = 1, Text = "DONATE", Font = FONT.BOLD, TextSize = 22, TextColor3 = T.TEXT,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
new("TextLabel", { Name = "Subtitle", Position = UDim2.new(0, 20, 0, 42), Size = UDim2.new(1, -80, 0, 18),
	BackgroundTransparency = 1, Text = "Support HAVN — thank you so much! ❤", Font = FONT.REGULAR, TextSize = 14,
	TextColor3 = T.TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 32, 0, 32), BackgroundColor3 = T.CARD, Text = "X", Font = FONT.BOLD, TextSize = 16,
	TextColor3 = T.TEXT, AutoButtonColor = false, Parent = panel })
corner(8, closeBtn)
stroke(closeBtn, 0.85)
hover(closeBtn, T.CARD, T.CARD_HOVER)
new("Frame", { Name = "Divider", Position = UDim2.new(0, 20, 0, 70), Size = UDim2.new(1, -40, 0, 1),
	BackgroundColor3 = T.LINE, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = panel })
local grid = new("ScrollingFrame", { Name = "Grid", Position = UDim2.new(0, 16, 0, 84), Size = UDim2.new(1, -32, 1, -100),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = panel })
new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, CARD_H), CellPadding = UDim2.new(0, 10, 0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4), Parent = grid })

-- ── Kotak pesan (menutupi panel) ───────────────────────────────────────────
local modal = new("Frame", { Name = "Modal", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = T.BG,
	Visible = false, ZIndex = 5, Parent = panel })
corner(14, modal)
local mTitle = new("TextLabel", { Position = UDim2.new(0, 20, 0, 18), Size = UDim2.new(1, -40, 0, 28),
	BackgroundTransparency = 1, Text = "", Font = FONT.BOLD, TextSize = 22, TextColor3 = T.TEXT,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = modal })
new("TextLabel", { Position = UDim2.new(0, 20, 0, 50), Size = UDim2.new(1, -40, 0, 36), BackgroundTransparency = 1,
	Text = "Add a message (optional). Everyone sees it after Roblox's text filter.", Font = FONT.REGULAR,
	TextSize = 14, TextColor3 = T.TEXT_DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5, Parent = modal })
local boxBg = new("Frame", { Position = UDim2.new(0, 20, 0, 92), Size = UDim2.new(1, -40, 0, 96),
	BackgroundColor3 = T.CARD, ZIndex = 5, Parent = modal })
corner(10, boxBg)
stroke(boxBg, 0.85)
local box = new("TextBox", { Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -20, 1, -16),
	BackgroundTransparency = 1, Text = "", PlaceholderText = "Type your message…", PlaceholderColor3 = T.TEXT_DIM,
	Font = FONT.REGULAR, TextSize = 15, TextColor3 = T.TEXT, TextWrapped = true, MultiLine = true,
	ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 5, Parent = boxBg })
local counter = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 192),
	Size = UDim2.new(0, 80, 0, 16), BackgroundTransparency = 1, Text = "0/" .. Config.message.maxChars,
	Font = FONT.REGULAR, TextSize = 13, TextColor3 = T.TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 5, Parent = modal })
local status = new("TextLabel", { Position = UDim2.new(0, 20, 0, 212), Size = UDim2.new(1, -40, 0, 36),
	BackgroundTransparency = 1, Text = "", Font = FONT.MEDIUM, TextSize = 14, TextColor3 = T.DANGER,
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = modal })
local cancelBtn = new("TextButton", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.new(0.5, -25, 0, 40), BackgroundColor3 = T.CARD, Text = "Cancel", Font = FONT.BOLD, TextSize = 16,
	TextColor3 = T.TEXT, AutoButtonColor = false, ZIndex = 5, Parent = modal })
corner(10, cancelBtn)
stroke(cancelBtn, 0.85)
hover(cancelBtn, T.CARD, T.CARD_HOVER)
local payBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.new(0.5, -25, 0, 40), BackgroundColor3 = T.ACCENT, Text = "Donate", Font = FONT.BOLD, TextSize = 16,
	TextColor3 = ON_ACCENT, AutoButtonColor = false, ZIndex = 5, Parent = modal })
corner(10, payBtn)

local function cut(text)
	local len = utf8.len(text)
	if len and len > Config.message.maxChars then
		return string.sub(text, 1, utf8.offset(text, Config.message.maxChars + 1) - 1)
	end
	return text
end
box:GetPropertyChangedSignal("Text"):Connect(function()
	local c = cut(box.Text)
	if c ~= box.Text then
		box.Text = c
		return
	end
	counter.Text = (utf8.len(c) or #c) .. "/" .. Config.message.maxChars
end)

-- ── Logika ─────────────────────────────────────────────────────────────────
local chosen = nil -- tier yang dipilih
local busy = false
local skipMessage = false -- pesan ditolak → tekan Donate lagi = donasi tanpa pesan
local lastInvoke = -math.huge

local function layout()
	local vp = viewport()
	local top = panelTop()
	panel.Size = UDim2.new(0, math.min(PANEL_W, vp.X - 24), 0, math.max(260, math.min(PANEL_H, vp.Y - top - HOTBAR_SPACE)))
	panel.Position = UDim2.new(0.5, 0, 0, top)
end
local function closeModal()
	modal.Visible = false
	chosen, busy, skipMessage = nil, false, false
	payBtn.Text = "Donate"
	status.Text = ""
end
local function close()
	closeModal()
	panel.Visible = false
end
local function open()
	layout()
	panel.Visible = true
end
local function toggle()
	if panel.Visible then
		close()
	else
		open()
	end
end
local function openModal(tier)
	chosen, skipMessage = tier, false
	mTitle.Text = "Donate " .. ROBUX .. " " .. tier.robux
	payBtn.Text = "Donate " .. ROBUX .. " " .. tier.robux
	status.Text = ""
	modal.Visible = true
end

local function sendMessage(text)
	local waitFor = MSG_GAP - (os.clock() - lastInvoke)
	if waitFor > 0 then
		task.wait(waitFor)
	end
	lastInvoke = os.clock()
	local ok, res = pcall(function()
		return setMessage:InvokeServer(text)
	end)
	return ok and res == true
end

payBtn.Activated:Connect(function()
	if busy or not chosen then
		return
	end
	busy = true
	local tier = chosen
	payBtn.Text = "…"
	local text = skipMessage and "" or string.gsub(string.gsub(box.Text, "^%s+", ""), "%s+$", "")
	local accepted = sendMessage(text)
	if not accepted and text ~= "" then
		skipMessage = true
		busy = false
		status.Text = "Message could not be used. Press Donate again to donate without a message."
		payBtn.Text = "Donate " .. ROBUX .. " " .. tier.robux
		return
	end
	box.Text = ""
	close()
	local ok, err = pcall(function()
		Market:PromptProductPurchase(player, tier.productId)
	end)
	if not ok then
		warn("[Donation] prompt beli gagal: " .. tostring(err))
	end
end)
cancelBtn.Activated:Connect(closeModal)
closeBtn.Activated:Connect(close)

for i, tier in Config.tiers do
	local card = new("TextButton", { Name = "Tier" .. tier.robux, LayoutOrder = i, BackgroundColor3 = T.CARD,
		Text = "", AutoButtonColor = false, Parent = grid })
	corner(12, card)
	stroke(card, 0.88)
	hover(card, T.CARD, T.CARD_HOVER)
	new("TextLabel", { Name = "Amount", Position = UDim2.new(0, 8, 0, 12), Size = UDim2.new(1, -16, 0, 28),
		BackgroundTransparency = 1, Text = ROBUX .. " " .. tier.robux, Font = FONT.BOLD, TextSize = 24,
		TextColor3 = T.TEXT, Parent = card })
	new("TextLabel", { Name = "Label", Position = UDim2.new(0, 8, 0, 42), Size = UDim2.new(1, -16, 0, 16),
		BackgroundTransparency = 1, Text = tier.label or "", Font = FONT.REGULAR, TextSize = 14,
		TextColor3 = T.TEXT_DIM, Parent = card })
	local pill = new("TextLabel", { Name = "Pill", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 28), BackgroundColor3 = T.ACCENT, Text = "DONATE", Font = FONT.BOLD, TextSize = 14,
		TextColor3 = ON_ACCENT, Parent = card })
	corner(14, pill)
	card.Activated:Connect(function()
		openModal(tier)
	end)
end

local resizeGen = 0
local function onResize()
	resizeGen += 1
	local g = resizeGen
	task.delay(0.12, function()
		if g == resizeGen and panel.Visible then
			layout()
		end
	end)
end
local camConn
local function bindCam()
	if camConn then
		camConn:Disconnect()
	end
	local cam = workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onResize)
	end
end
bindCam()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCam()
	onResize()
end)
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
		close()
	end
end)

-- ── Tombol topbar: baris KIRI sebelah Info (_G.TopbarLeft dari InfoTopBar) ──────
-- Cadangan: baris kanan _G.TopbarLayout (order 24) kalau InfoTopBar tidak ada.
local function makeTopButton(size, parent)
	local btn = new("TextButton", { Name = "DonateBtn", Size = UDim2.new(0, size, 0, size), BackgroundColor3 = T.CARD,
		BorderSizePixel = 0, Text = ROBUX, Font = FONT.BOLD, TextSize = 20, TextColor3 = T.ACCENT,
		AutoButtonColor = false, Parent = parent })
	corner(size / 2, btn)
	local st = stroke(btn, 0.35, T.ACCENT)
	st.Thickness = 1
	hover(btn, T.CARD, T.CARD_HOVER)
	btn.Activated:Connect(toggle)
	return btn
end
task.spawn(function()
	local waited = 0
	repeat
		task.wait(0.1)
		waited += 0.1
	until _G.TopbarLeft or _G.TopbarGui or waited >= 15
	if not _G.TopbarLeft then
		waited = 0
		repeat -- InfoTopBar mungkin sedikit lebih lambat dari UltimateMenu
			task.wait(0.1)
			waited += 0.1
		until _G.TopbarLeft or waited >= 12
	end
	if _G.TopbarLeft then
		_G.TopbarLeft.add(makeTopButton(_G.TopbarLeft.height or BTN_SZ, nil), 2)
	elseif _G.TopbarGui then
		local old = _G.TopbarGui:FindFirstChild("DonateBtn")
		if old then
			old:Destroy()
		end
		local btn = makeTopButton(BTN_SZ, _G.TopbarGui)
		btn.AnchorPoint = Vector2.new(1, 0)
		btn.Position = UDim2.new(1, -200, 0, 13)
		if _G.TopbarLayout then
			_G.TopbarLayout.register("donate", btn, 24, "info")
		end
	else
		warn("[Donation] topbar tidak ditemukan, tombol donasi tidak dibuat")
	end
end)

print("[Donation] panel siap")
