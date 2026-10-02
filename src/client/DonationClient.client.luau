-- StarterPlayerScripts/DonationClient  (LocalScript)
-- Tombol donasi di topbar kiri (sebelah Info, _G.TopbarLeft): pill "Donate" → [X][⬡ Robux][💰 Komunitas] → panel DONATE desain v1.5 (judul, kartu PROFILE di
-- kiri: avatar 3D sendiri + total donasi + peringkat; grid 2 kolom kartu tier di kanan) + kotak pesan sebelum membeli.
-- Layar sempit (panel < PROFILE_MIN px, mis. HP portrait): kartu Profile disembunyikan, grid selebar panel.
-- Alur: pilih tier → (opsional) tulis pesan → Donate → SetMessage ke server (difilter di sana) → prompt beli Roblox.
-- Pembayaran & pengumuman sepenuhnya di server (DonationServer); client tidak pernah mengklaim donasi.
-- Admin (atribut IsAdmin) melihat tombol TES di kotak pesan → DonationRemotes.TestDonation (server mengecek rank lagi).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenSvc = game:GetService("TweenService")
local Market = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(RS:WaitForChild("DonationConfig"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))
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
local T = ThemeColor.tokens -- tabel bersama themeColor: T.X dibaca saat melukis → ikut tema pilihan pemain
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold, MEDIUM = Enum.Font.BuilderSansMedium, REGULAR = Enum.Font.BuilderSans,
}
local TF = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROBUX = utf8.char(0xE002)

local BTN_SZ = 40
local PANEL_W, PANEL_H = 760, 440
local PROFILE_W, PROFILE_MIN = 270, 620 -- lebar kartu Profile; panel lebih sempit dari PROFILE_MIN → Profile disembunyikan
local CAM_FOV, CAM_DIST, HEAD_AT = 30, 9.5, 0.28 -- kamera avatar Profile (kepala di 28% dari atas)
local HAIR = utf8.char(0x200A)
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
		-- Warna tujuan tersimpan dari tema lama (hover base/over) → warna yang sama di tema sekarang.
		local goal = {}
		for k, v in pairs(props) do
			goal[k] = (typeof(v) == "Color3") and ThemeColor.live(v) or v
		end
		TweenSvc:Create(o, TF, goal):Play()
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
local function track(s) -- huruf berjarak (gaya papan donasi)
	local out = {}
	for _, cp in utf8.codes(s) do
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out, HAIR)
end
local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
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
ThemeColor.mark(gui)
local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = T.BG,
	Visible = false, Parent = gui })
corner(14, panel)
ThemeColor.glow(stroke(panel, 0.85), "panel") -- garis tepi bergerak (themeColor)
-- Bisa digeser dari kepala panel (area atas 70 px, judul, garis penanda); dibuat PERTAMA → di bawah tombol kepala.
local dragArea = new("Frame", { Name = "DragArea", Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Parent = panel })
local grip = new("Frame", { Name = "Grip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
	Size = UDim2.new(0, 28, 0, 3), BackgroundColor3 = T.ACCENT, BackgroundTransparency = 0.35, BorderSizePixel = 0,
	Parent = panel })
corner(2, grip)
local titleLbl = new("TextLabel", { Name = "Title", Position = UDim2.new(0, 20, 0, 14), Size = UDim2.new(1, -170, 0, 30),
	BackgroundTransparency = 1, Text = "DONATE", Font = FONT.BOLD, TextSize = 22, TextColor3 = T.TEXT,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
local subLbl = new("TextLabel", { Name = "Subtitle", Position = UDim2.new(0, 20, 0, 42), Size = UDim2.new(1, -170, 0, 18),
	BackgroundTransparency = 1, Text = "Support HAVN — thank you so much! ❤", Font = FONT.REGULAR, TextSize = 14,
	TextColor3 = T.TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 32, 0, 32), BackgroundColor3 = T.CARD, Text = "X", Font = FONT.BOLD, TextSize = 16,
	TextColor3 = T.TEXT, AutoButtonColor = false, Parent = panel })
corner(8, closeBtn)
stroke(closeBtn, 0.85)
hover(closeBtn, T.CARD, T.CARD_HOVER)
-- Efek donasi pemain lain (DonationFX) bisa dimatikan: atribut LocalPlayer "DonationFX".
local fxBtn = new("TextButton", { Name = "FxToggle", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 16),
	Size = UDim2.new(0, 88, 0, 32), BackgroundColor3 = T.CARD, Text = "", Font = FONT.BOLD, TextSize = 13,
	TextColor3 = T.TEXT, AutoButtonColor = false, Parent = panel })
corner(8, fxBtn)
stroke(fxBtn, 0.85)
hover(fxBtn, T.CARD, T.CARD_HOVER)
local function paintFx()
	local on = player:GetAttribute("DonationFX") ~= false
	fxBtn.Text = on and "Effects: ON" or "Effects: OFF"
	fxBtn.TextColor3 = on and T.ACCENT or T.TEXT_DIM
end
fxBtn.Activated:Connect(function()
	player:SetAttribute("DonationFX", player:GetAttribute("DonationFX") == false)
	paintFx()
end)
paintFx()
new("Frame", { Name = "Divider", Position = UDim2.new(0, 20, 0, 70), Size = UDim2.new(1, -40, 0, 1),
	BackgroundColor3 = T.LINE, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = panel })
local grid = new("ScrollingFrame", { Name = "Grid", Position = UDim2.new(0, 16, 0, 84), Size = UDim2.new(1, -32, 1, -100),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = panel })
new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, CARD_H), CellPadding = UDim2.new(0, 10, 0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4), Parent = grid })

-- ── Kartu Profile (kiri): avatar 3D sendiri + total donasi Robux + peringkat (atribut dari DonationServer) ──
local profile = new("Frame", { Name = "Profile", Position = UDim2.new(0, 16, 0, 84), Size = UDim2.new(0, PROFILE_W, 1, -100),
	BackgroundColor3 = T.CARD, ClipsDescendants = true, ZIndex = 2, Parent = panel })
corner(12, profile)
stroke(profile, 0.88)
local view = new("ViewportFrame", { Name = "AvatarView", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	Ambient = Color3.fromRGB(150, 152, 158), LightColor = Color3.fromRGB(255, 255, 255), ZIndex = 2, Parent = profile })
ThemeColor.skip(view) -- lampu viewport & salinan avatar = konten, tidak ikut tema
local world = new("WorldModel", { Parent = view })
local viewCam = new("Camera", { FieldOfView = CAM_FOV, Parent = view })
view.CurrentCamera = viewCam
local fade = new("Frame", { Name = "Fade", Position = UDim2.new(0, 0, 0.45, 0), Size = UDim2.new(1, 0, 0.55, 0),
	BackgroundColor3 = T.CARD, BorderSizePixel = 0, ZIndex = 2, Parent = profile })
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 0.15), NumberSequenceKeypoint.new(1, 0),
}), Parent = fade })
local function profileText(name, text, y, h, size, font, color, x, w, align)
	return new("TextLabel", { Name = name, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(x or 0, x and -18 or 18, 1, y),
		Size = UDim2.new(w or 1, w and 0 or -36, 0, h), BackgroundTransparency = 1, Text = text, Font = font, TextSize = size,
		TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3, Parent = profile })
end
local pName = profileText("DisplayName", player.DisplayName, -106, 26, 20, FONT.BOLD, T.TEXT)
profileText("Handle", "@" .. player.Name, -88, 16, 13, FONT.REGULAR, T.TEXT_DIM)
new("Frame", { Name = "Line1", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -78), Size = UDim2.new(1, -36, 0, 2),
	BackgroundColor3 = T.ACCENT, BorderSizePixel = 0, ZIndex = 3, Parent = profile })
profileText("TotalLabel", track("YOUR TOTAL DONATED"), -56, 14, 11, FONT.MEDIUM, T.TEXT_DIM, nil, nil)
local pTotal = profileText("TotalAmount", ROBUX .. " 0", -16, 38, 30, FONT.BOLD, T.ACCENT)
profileText("RankLabel", track("RANK"), -56, 14, 11, FONT.MEDIUM, T.TEXT_DIM, 1, nil, Enum.TextXAlignment.Right).Size =
	UDim2.new(0, 70, 0, 14)
local pRank = profileText("RankValue", "#—", -16, 38, 30, FONT.BOLD, T.TEXT, 1, nil, Enum.TextXAlignment.Right)
pRank.Size = UDim2.new(0, 80, 0, 38)
for _, l in { profile.RankLabel, pRank } do
	l.AnchorPoint = Vector2.new(1, 1)
end
pTotal.Size = UDim2.new(1, -120, 0, 38)

local function paintProfile()
	pName.Text = player.DisplayName
	pTotal.Text = ROBUX .. " " .. commas(player:GetAttribute("DonationTotal"))
	local rank = tonumber(player:GetAttribute("DonationRank")) or 0
	pRank.Text = rank > 0 and ("#" .. rank) or "#—"
end
player:GetAttributeChangedSignal("DonationTotal"):Connect(paintProfile)
player:GetAttributeChangedSignal("DonationRank"):Connect(paintProfile)
paintProfile()

-- Avatar: salinan karakter sendiri di WorldModel (skrip/suara dibuang), emote resmi berulang, kamera ikut kepala.
local rig, head, builtFor, focus, camConnP
local function clearRig()
	if rig then
		rig:Destroy()
	end
	rig, head, focus = nil, nil, nil
end
local function buildRig()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum and char:FindFirstChild("HumanoidRootPart")) then
		return
	end
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(char.Clone, char)
	char.Archivable = was
	if not ok or not clone then
		return
	end
	clearRig()
	for _, d in clone:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
		end
	end
	clone.HumanoidRootPart.Anchored = true
	local h = clone:FindFirstChildOfClass("Humanoid")
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	clone:PivotTo(CFrame.new())
	clone.Parent = world
	rig, head, builtFor = clone, clone:FindFirstChild("Head"), char
	local animId = Config.boards.danceAnims[1]
	pcall(function()
		local animator = h:FindFirstChildOfClass("Animator") or new("Animator", { Parent = h })
		local a = new("Animation", { AnimationId = "rbxassetid://" .. animId })
		local t = animator:LoadAnimation(a)
		t.Looped = true
		t:Play()
	end)
end
local function followHead()
	if not (head and head.Parent) then
		return
	end
	local viewH = 2 * CAM_DIST * math.tan(math.rad(CAM_FOV / 2))
	local p = head.Position - Vector3.new(0, viewH * (0.5 - HEAD_AT), 0)
	local target = Vector3.new(p.X, p.Y, 0)
	focus = focus and focus:Lerp(target, 0.18) or target
	viewCam.CFrame = CFrame.lookAt(focus + Vector3.new(0, 0, -CAM_DIST), focus)
end
local function syncProfile()
	local active = panel.Visible and profile.Visible
	if active and (not rig or builtFor ~= player.Character) then
		buildRig()
	end
	if active and not camConnP then
		camConnP = RunService.RenderStepped:Connect(followHead)
	elseif not active and camConnP then
		camConnP:Disconnect()
		camConnP = nil
	end
end
player.CharacterAppearanceLoaded:Connect(function()
	builtFor = nil
	task.delay(0.5, syncProfile)
end)

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
	TextColor3 = T.ON_ACCENT, AutoButtonColor = false, ZIndex = 5, Parent = modal })
corner(10, payBtn)
-- Tes donasi admin: di atas tombol Cancel/Donate, hanya terlihat untuk IsAdmin.
local testRow = new("Frame", { Name = "AdminTest", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -68),
	Size = UDim2.new(1, -40, 0, 32), BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = modal })
local function testButton(text, x)
	local b = new("TextButton", { Position = UDim2.new(x, x > 0 and 5 or 0, 0, 0), Size = UDim2.new(0.5, -5, 1, 0),
		BackgroundColor3 = T.CARD, Text = text, Font = FONT.BOLD, TextSize = 13, TextColor3 = T.ACCENT,
		AutoButtonColor = false, ZIndex = 5, Parent = testRow })
	corner(8, b)
	stroke(b, 0.6, T.ACCENT)
	hover(b, T.CARD, T.CARD_HOVER)
	return b
end
local testHere = testButton("TES · server ini", 0)
local testAll = testButton("TES · semua server", 0.5)

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

-- Posisi bawaan = TENGAH layar (antara topbar & hotbar). Digeser → tetap di situ sampai ditutup; dibuka lagi → tengah.
local customPos, reclamp = false, nil
local function ensureDrag() -- _G.MenuUI (UltimateMenu) pasti ada saat panel pertama dibuka
	if reclamp or not (_G.MenuUI and _G.MenuUI.makeDraggable) then
		return
	end
	local ok, r = pcall(_G.MenuUI.makeDraggable, panel, { dragArea, grip, titleLbl, subLbl }, function()
		customPos = true
	end)
	if ok and type(r) == "function" then
		reclamp = r
	end
end
local function centerTop(h)
	local vp, top = viewport(), panelTop()
	return math.max(top, math.min(math.floor((vp.Y - h) / 2), math.floor(vp.Y) - HOTBAR_SPACE - h))
end

local function layout()
	local vp = viewport()
	local top = panelTop()
	local w = math.min(PANEL_W, vp.X - 24)
	local h = math.max(260, math.min(PANEL_H, vp.Y - top - HOTBAR_SPACE))
	panel.Size = UDim2.new(0, w, 0, h)
	if customPos and reclamp then
		reclamp()
	else
		panel.Position = UDim2.new(0.5, 0, 0, centerTop(h))
	end
	local wide = w >= PROFILE_MIN
	profile.Visible = wide
	local left = wide and (PROFILE_W + 30) or 16
	grid.Position = UDim2.new(0, left, 0, 84)
	grid.Size = UDim2.new(1, -left - 16, 1, -100)
	syncProfile()
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
	customPos = false
	syncProfile()
end
local function open()
	customPos = false -- selalu dibuka di tengah
	ensureDrag()
	panel.Visible = true
	paintProfile()
	layout()
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

local testFn -- DonationRemotes.TestDonation (dicari di latar)
local TEST_REASON = {
	cooldown = "tunggu " .. Config.test.cooldown .. " detik",
	admin = "khusus admin",
	filter = "pesan tidak lolos filter",
	invalid = "data tidak sah",
}
local function paintAdmin()
	testRow.Visible = testFn ~= nil and player:GetAttribute("IsAdmin") == true
end
local function runTest(everywhere)
	if busy or not chosen or not testFn then
		return
	end
	busy = true
	status.Text = "…"
	local text = string.gsub(string.gsub(box.Text, "^%s+", ""), "%s+$", "")
	local ok, res, reason = pcall(function()
		return testFn:InvokeServer(chosen.productId, text, everywhere)
	end)
	busy = false
	if ok and res == true then
		box.Text = ""
		close()
		return
	end
	local why = ok and reason or res
	status.Text = "Tes ditolak: " .. (TEST_REASON[why] or tostring(why))
end
testHere.Activated:Connect(function()
	runTest(false)
end)
testAll.Activated:Connect(function()
	runTest(true)
end)
player:GetAttributeChangedSignal("IsAdmin"):Connect(paintAdmin)
task.spawn(function()
	local folder = RS:WaitForChild("DonationRemotes", 30)
	testFn = folder and folder:WaitForChild("TestDonation", 30)
	paintAdmin()
end)
closeBtn.Activated:Connect(close)

-- ── Popup 💰 Komunitas (tanpa link: Social Links resmi di halaman game) ─────────────────────────
local CM = Config.community
local commOverlay = new("TextButton", { Name = "CommunityOverlay", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 20, Parent = gui })
local commPop = new("Frame", { Name = "Community", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 340, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.BG, Active = true, ZIndex = 21,
	Parent = commOverlay })
corner(14, commPop)
stroke(commPop, 0.8, T.ACCENT)
new("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18),
	PaddingRight = UDim.new(0, 18), Parent = commPop })
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = commPop })
new("TextLabel", { Name = "Title", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
	Text = "💰  " .. CM.title, Font = FONT.BOLD, TextSize = 20, TextColor3 = T.ACCENT, TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 22, Parent = commPop })
new("TextLabel", { Name = "Body", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Text = CM.body, Font = FONT.REGULAR, TextSize = 14, TextColor3 = T.TEXT, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = commPop })
local function commButton(order, name, text, color)
	local b = new("TextButton", { Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.CARD,
		Text = text, Font = FONT.BOLD, TextSize = 15, TextColor3 = color, AutoButtonColor = false, ZIndex = 22, Parent = commPop })
	corner(10, b)
	stroke(b, 0.85)
	hover(b, T.CARD, T.CARD_HOVER)
	return b
end
local groupBtn = commButton(3, "JoinGroup", "👥  Gabung Group", T.ACCENT)
local favBtn = commButton(4, "Favorite", "⭐  Favorite Game", T.TEXT)
local commClose = commButton(5, "Close", "Tutup", T.TEXT_DIM)
local function paintGroup()
	task.spawn(function()
		local ok, inGroup = pcall(player.IsInGroup, player, CM.groupId)
		groupBtn.Text = (ok and inGroup) and "👥  Sudah Gabung ✓" or "👥  Gabung Group"
		groupBtn.TextColor3 = (ok and inGroup) and T.SUCCESS or T.ACCENT
	end)
end
local function openCommunity()
	commPop.Size = UDim2.new(0, math.min(340, viewport().X - 24), 0, 0) -- HP sempit: selebar layar − 24
	commOverlay.Visible = true
	paintGroup()
end
local function closeCommunity()
	commOverlay.Visible = false
end
groupBtn.Activated:Connect(function()
	pcall(function()
		GroupService:PromptJoinAsync(CM.groupId)
	end)
	paintGroup()
end)
favBtn.Activated:Connect(function()
	pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
end)
commClose.Activated:Connect(closeCommunity)
commOverlay.Activated:Connect(closeCommunity) -- klik di luar popup

UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape then
		closeCommunity()
	end
end)

-- Kartu tier: dari Config.tiers (setelan admin tiba lewat atribut DonationRemotes.Tiers → dibangun ulang).
local makeCard
local function buildCards()
	for _, c in grid:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	for i, tier in Config.tiers do
		if not tier.hidden then
			makeCard(i, tier)
		end
	end
end
makeCard = function(i, tier)
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
		TextColor3 = T.ON_ACCENT, Parent = card })
	corner(14, pill)
	card.Activated:Connect(function()
		openModal(tier)
	end)
end
buildCards()
task.spawn(function()
	local folder = RS:WaitForChild("DonationRemotes", 30)
	if not folder then
		return
	end
	local function sync()
		local raw = folder:GetAttribute("Tiers")
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(list) == "table" and #list > 0 then
			Config.applyTiers(list)
			buildCards()
		end
	end
	folder:GetAttributeChangedSignal("Tiers"):Connect(sync)
	if folder:GetAttribute("Tiers") then
		sync()
	end
end)

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
-- Tombol topbar = pill "Donate" (gaya tombol Info). Klik → pill melebar jadi [X] [⬡ Robux] [💰 Komunitas];
-- Robux = panel DONATE, 💰 = popup Komunitas, X / Escape = kembali "Donate". Lebar ikut isi (AutomaticSize X),
-- jadi baris topbar (InfoTopBar LeftRow) ikut bergeser rapi di semua perangkat.
-- Gaya themeColor tombol topbar: latar TOPBAR, teks/X TEXT_STRONG; sorot ACCENT (hover, ⬡, 💰) tetap. Pill ini ikut
-- dilukis ulang lewat ScreenGui tempatnya menumpang (InfoTopbarGui / _G.TopbarGui, keduanya di-mark skripnya).
local collapseTop -- function() (diisi makeTopButton)
local function makeTopButton(size, parent)
	local pillF = new("Frame", { Name = "DonateBtn", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, size),
		BackgroundColor3 = T.TOPBAR, BorderSizePixel = 0, Parent = parent })
	corner(size / 2, pillF)
	local st = stroke(pillF, 0.35, T.ACCENT)
	st.Thickness = 1
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pillF })
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = pillF })
	local pop = new("UIScale", { Scale = 1, Parent = pillF })
	local main = new("TextButton", { Name = "Main", LayoutOrder = 0, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, Text = "Donate", Font = FONT.BOLD, TextSize = 15,
		TextColor3 = T.TEXT_STRONG, AutoButtonColor = false, Parent = pillF })
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = main })
	ThemeColor.hoverHost(main, pillF) -- garis sorot hover mengikuti bentuk PIL (bukan kotak teks di dalamnya)
	local ICON = size - 10
	local function icon(order, name, text, color)
		local b = new("TextButton", { Name = name, LayoutOrder = order, Size = UDim2.new(0, ICON, 0, ICON),
			BackgroundColor3 = T.BG, Text = text, Font = FONT.BOLD, TextSize = 18, TextColor3 = color, AutoButtonColor = false,
			Visible = false, Parent = pillF })
		corner(ICON / 2, b)
		hover(b, T.BG, T.CARD_HOVER)
		return b
	end
	local closeI = icon(1, "Close", "X", T.TEXT_STRONG)
	closeI.TextSize = 15
	local robuxI = icon(2, "Robux", ROBUX, T.ACCENT)
	local commI = icon(3, "Community", "💰", T.ACCENT)
	local expanded = false
	local function setExpanded(on)
		expanded = on
		main.Visible = not on
		closeI.Visible, robuxI.Visible, commI.Visible = on, on, on
		pop.Scale = 0.92
		TweenSvc:Create(pop, TF, { Scale = 1 }):Play()
	end
	collapseTop = function()
		if expanded then
			setExpanded(false)
		end
	end
	main.MouseEnter:Connect(function()
		tw(main, { TextColor3 = T.ACCENT })
	end)
	main.MouseLeave:Connect(function()
		tw(main, { TextColor3 = T.TEXT_STRONG })
	end)
	main.Activated:Connect(function()
		setExpanded(true)
	end)
	closeI.Activated:Connect(function()
		setExpanded(false)
	end)
	robuxI.Activated:Connect(function()
		setExpanded(false)
		closeCommunity()
		if not panel.Visible then
			toggle()
		end
	end)
	commI.Activated:Connect(function()
		setExpanded(false)
		if panel.Visible then
			toggle()
		end
		openCommunity()
	end)
	return pillF
end
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and collapseTop then
		collapseTop()
	end
end)
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
