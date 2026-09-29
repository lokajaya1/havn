-- StarterPlayerScripts/DonationAdmin  (LocalScript)
-- "Donate Admin Panel" (desain v1.5, logika sendiri): tombol ADMIN di panel donasi, hanya untuk IsAdmin.
--   Tab Donation   : donasi TES atas nama pemain di server ini (tier, pesan, opsional semua server)
--                    → DonationRemotes.TestDonation — tanpa Marketplace, TIDAK disimpan / masuk TOP / papan, pesan [TES].
--   Tab Test Effect: efek tier saja di pemain target / di map → DonationRemotes.TestEffect.
-- Server mengecek rank grup, cooldown & target lagi; panel ini hanya tampilan.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(RS:WaitForChild("DonationConfig"))
local remotes = RS:WaitForChild("DonationRemotes", 30)
local testFn = remotes and remotes:WaitForChild("TestDonation", 30)
local fxFn = remotes and remotes:WaitForChild("TestEffect", 30)
local donateGui = playerGui:WaitForChild("DonationGui", 30)
local donatePanel = donateGui and donateGui:WaitForChild("Panel", 30)
if not (testFn and fxFn and donatePanel) then
	return -- panel donasi / remote tidak ada: admin panel tidak dibuat
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
local ROBUX = utf8.char(0xE002)
local PANEL_W, PANEL_H, SIDEBAR_W = 720, 470, 156
local REASON = {
	cooldown = "tunggu " .. Config.test.cooldown .. " detik",
	admin = "khusus admin",
	filter = "pesan tidak lolos filter",
	target = "pemain target sudah keluar",
	invalid = "data tidak sah",
}

local function new(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	o.Parent = props.Parent
	return o
end
local function corner(r, p)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = p })
end
local function stroke(p, tr, color)
	return new("UIStroke", { Color = color or T.LINE, Transparency = tr or 0.88, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = p })
end
local function button(text, props)
	props.Text = text
	props.Font = props.Font or FONT.BOLD
	props.TextSize = props.TextSize or 14
	props.TextColor3 = props.TextColor3 or T.TEXT
	props.BackgroundColor3 = props.BackgroundColor3 or T.CARD
	props.AutoButtonColor = false
	local b = new("TextButton", props)
	corner(8, b)
	stroke(b)
	return b
end
local function label(text, props)
	props.Text = text
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT.MEDIUM
	props.TextSize = props.TextSize or 12
	props.TextColor3 = props.TextColor3 or T.TEXT_DIM
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props)
end

-- ── Tombol ADMIN di panel donasi ───────────────────────────────────────────
local adminBtn = button("ADMIN", { Name = "AdminBtn", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -152, 0, 16),
	Size = UDim2.new(0, 72, 0, 32), TextSize = 13, TextColor3 = T.ACCENT, Visible = false, Parent = donatePanel })

-- ── Panel admin ────────────────────────────────────────────────────────────
local gui = new("ScreenGui", { Name = "DonationAdminGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 62,
	Enabled = false, Parent = playerGui })
local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = T.BG, Parent = gui })
corner(14, panel)
stroke(panel, 0.85)
label("Donate Admin Panel", { Position = UDim2.new(0, 18, 0, 8), Size = UDim2.new(1, -70, 0, 22), Font = FONT.BOLD,
	TextSize = 18, TextColor3 = T.TEXT, Parent = panel })
label("Admin only · donasi tes tidak disimpan & tidak masuk TOP", { Position = UDim2.new(0, 18, 0, 28),
	Size = UDim2.new(1, -70, 0, 14), TextSize = 11, Parent = panel })
local closeBtn = button("X", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 24),
	Size = UDim2.new(0, 30, 0, 30), Parent = panel })
new("Frame", { Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.LINE,
	BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = panel })
local sidebar = new("Frame", { Name = "Sidebar", Position = UDim2.new(0, 10, 0, 58), Size = UDim2.new(0, SIDEBAR_W - 20, 1, -90),
	BackgroundTransparency = 1, Parent = panel })
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })
local status = label("", { Name = "Status", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, SIDEBAR_W, 1, -8),
	Size = UDim2.new(1, -SIDEBAR_W - 16, 0, 16), Parent = panel })

local function page(name)
	local f = new("ScrollingFrame", { Name = name, Position = UDim2.new(0, SIDEBAR_W, 0, 58),
		Size = UDim2.new(1, -SIDEBAR_W - 12, 1, -90), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = panel })
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = f })
	return f
end
local pages = { Donation = page("DonationPage"), ["Test Effect"] = page("EffectPage") }
local tabs = {}
local function showTab(name)
	for n, p in pages do
		p.Visible = n == name
		tabs[n].TextColor3 = n == name and ON_ACCENT or T.TEXT
		tabs[n].BackgroundColor3 = n == name and T.ACCENT or T.CARD
	end
	status.Text = ""
end
for i, n in { "Donation", "Test Effect" } do
	tabs[n] = button(n, { Name = "Tab" .. i, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 40), Parent = sidebar })
	tabs[n].Activated:Connect(function()
		showTab(n)
	end)
end

-- Daftar pemain (dengan pencarian); pilihan = userId atau nil (diri sendiri).
local function playerPicker(parent, order)
	local picked = nil
	local wrap = new("Frame", { Name = "Picker", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = parent })
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wrap })
	local search = new("TextBox", { Name = "Search", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = T.CARD,
		Text = "", PlaceholderText = "Cari pemain… (kosong = diri sendiri)", PlaceholderColor3 = T.TEXT_DIM, TextColor3 = T.TEXT,
		Font = FONT.REGULAR, TextSize = 13, ClearTextOnFocus = false, Parent = wrap })
	corner(6, search)
	local list = new("Frame", { Name = "List", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Parent = wrap })
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 28), CellPadding = UDim2.new(0, 6, 0, 4), Parent = list })
	local function rebuild()
		for _, c in list:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local q = string.lower(search.Text)
		for _, p in Players:GetPlayers() do
			local text = p.DisplayName .. " (@" .. p.Name .. ")"
			if q == "" or string.find(string.lower(text), q, 1, true) then
				local mine = (picked or player.UserId) == p.UserId
				local b = button(text, { Name = "P" .. p.UserId, Font = FONT.MEDIUM, TextSize = 12,
					TextColor3 = mine and ON_ACCENT or T.TEXT, BackgroundColor3 = mine and T.ACCENT or T.CARD,
					TextTruncate = Enum.TextTruncate.AtEnd, Parent = list })
				b.Activated:Connect(function()
					picked = p ~= player and p.UserId or nil
					rebuild()
				end)
			end
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(rebuild)
	Players.PlayerAdded:Connect(rebuild)
	Players.PlayerRemoving:Connect(function(p)
		if picked == p.UserId then
			picked = nil
		end
		task.defer(rebuild)
	end)
	rebuild()
	return function()
		return picked
	end, rebuild
end

local function tierName(t)
	return ("%s %d · %s"):format(ROBUX, t.robux, t.label or "")
end
local busy = false
local function call(fn, ...)
	if busy then
		return
	end
	busy = true
	status.TextColor3 = T.TEXT_DIM
	status.Text = "…"
	local ok, res, reason = pcall(fn.InvokeServer, fn, ...)
	busy = false
	if ok and res == true then
		status.TextColor3 = T.SUCCESS
		status.Text = "Terkirim ✓"
		return true
	end
	local why = ok and reason or tostring(res)
	status.TextColor3 = T.DANGER
	status.Text = "Ditolak: " .. (REASON[why] or tostring(why))
	return false
end

-- ── Tab Donation ───────────────────────────────────────────────────────────
local dp = pages.Donation
label("TARGET PLAYER (nama & avatar donatur di notifikasi)", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16), Parent = dp })
local donTarget, donRebuild = playerPicker(dp, 2)
label("TIER", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 16), Parent = dp })
local tierGrid = new("Frame", { Name = "Tiers", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Parent = dp })
new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 30), CellPadding = UDim2.new(0, 6, 0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = tierGrid })
local chosenTier = Config.tiers[1]
local tierBtns = {}
local function paintTiers()
	for t, b in tierBtns do
		local on = t == chosenTier
		b.BackgroundColor3 = on and T.ACCENT or T.CARD
		b.TextColor3 = on and ON_ACCENT or T.TEXT
	end
end
for i, t in Config.tiers do
	local b = button(tierName(t), { Name = "Tier" .. t.robux, LayoutOrder = i, Font = FONT.MEDIUM, TextSize = 13, Parent = tierGrid })
	tierBtns[t] = b
	b.Activated:Connect(function()
		chosenTier = t
		paintTiers()
	end)
end
paintTiers()
label("MESSAGE (OPTIONAL)", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 16), Parent = dp })
local msg = new("TextBox", { Name = "Message", LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = T.CARD,
	Text = "", PlaceholderText = "Pesan donasi tes…", PlaceholderColor3 = T.TEXT_DIM, TextColor3 = T.TEXT, Font = FONT.REGULAR,
	TextSize = 13, TextWrapped = true, MultiLine = true, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, Parent = dp })
corner(6, msg)
local counter = label("0/" .. Config.message.maxChars, { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 14), TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right, Parent = dp })
msg:GetPropertyChangedSignal("Text"):Connect(function()
	local len = utf8.len(msg.Text) or #msg.Text
	if len > Config.message.maxChars then
		msg.Text = string.sub(msg.Text, 1, utf8.offset(msg.Text, Config.message.maxChars + 1) - 1)
		return
	end
	counter.Text = len .. "/" .. Config.message.maxChars
end)
local everywhere = false
local allBtn = button("", { Name = "Everywhere", LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 30), Font = FONT.MEDIUM,
	TextSize = 13, Parent = dp })
local function paintAll()
	allBtn.Text = everywhere and "☑  Kirim ke semua server" or "☐  Kirim ke semua server"
	allBtn.TextColor3 = everywhere and T.ACCENT or T.TEXT
end
allBtn.Activated:Connect(function()
	everywhere = not everywhere
	paintAll()
end)
paintAll()
local sendBtn = button("SEND FAKE DONATION", { Name = "Send", LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = T.ACCENT, TextColor3 = ON_ACCENT, Parent = dp })
sendBtn.Activated:Connect(function()
	if call(testFn, chosenTier.robux, msg.Text, everywhere, donTarget()) then
		msg.Text = ""
	end
end)

-- ── Tab Test Effect ────────────────────────────────────────────────────────
local ep = pages["Test Effect"]
label("TARGET PLAYER (efek partikel menempel ke pemain ini; efek besar di map)", { LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 16), Parent = ep })
local fxTarget, fxRebuild = playerPicker(ep, 2)
label("AVAILABLE EFFECTS (klik untuk tes)", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 16), Parent = ep })
local fxGrid = new("Frame", { Name = "Effects", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Parent = ep })
new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 30), CellPadding = UDim2.new(0, 6, 0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = fxGrid })
for i, t in Config.tiers do
	local b = button(("%s  (%s)"):format(tierName(t), t.fx or t.big or "-"), { Name = "Fx" .. t.robux, LayoutOrder = i,
		Font = FONT.MEDIUM, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Parent = fxGrid })
	b.Activated:Connect(function()
		call(fxFn, t.robux, fxTarget())
	end)
end

-- ── Buka / tutup ───────────────────────────────────────────────────────────
local function layout()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	panel.Size = UDim2.new(0, math.min(PANEL_W, vp.X - 24), 0, math.min(PANEL_H, vp.Y - 24))
end
local function open()
	layout()
	donRebuild()
	fxRebuild()
	gui.Enabled = true
end
local function close()
	gui.Enabled = false
end
adminBtn.Activated:Connect(function()
	if gui.Enabled then
		close()
	else
		open()
	end
end)
closeBtn.Activated:Connect(close)
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
		close()
	end
end)
local function paintAdmin()
	local isAdmin = player:GetAttribute("IsAdmin") == true
	adminBtn.Visible = isAdmin
	if not isAdmin then
		close()
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(paintAdmin)
paintAdmin()
showTab("Donation")
