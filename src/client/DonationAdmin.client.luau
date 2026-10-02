-- StarterPlayerScripts/DonationAdmin  (LocalScript)
-- "Donate Admin Panel" (desain v1.5, logika sendiri): tombol ADMIN di panel donasi, hanya untuk IsAdmin.
--   Tab Donation   : donasi TES atas nama pemain di server ini (tier, pesan, opsional semua server)
--                    → DonationRemotes.TestDonation — tanpa Marketplace, TIDAK disimpan / masuk TOP / papan, pesan [TES].
--   Tab Test Effect: tombol per efek (partikel / kamera / partikel+kamera / efek besar) → DonationRemotes.TestEffect.
--   Tab Produk (atribut DonationEditor = rank >= DonationConfig.tierEdit.rank): per Developer Product atur nama,
--                    partikel, kamera, efek besar, tampil/sembunyi, tes; tambah produk lewat ID → DonationRemotes.TierEdit.
-- Server mengecek rank grup, cooldown & target lagi; panel ini hanya tampilan.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(RS:WaitForChild("DonationConfig"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local remotes = RS:WaitForChild("DonationRemotes", 30)
local testFn = remotes and remotes:WaitForChild("TestDonation", 30)
local fxFn = remotes and remotes:WaitForChild("TestEffect", 30)
local editFn = remotes and remotes:WaitForChild("TierEdit", 30)
local donateGui = playerGui:WaitForChild("DonationGui", 30)
local donatePanel = donateGui and donateGui:WaitForChild("Panel", 30)
if not (testFn and fxFn and editFn and donatePanel) then
	return -- panel donasi / remote tidak ada: admin panel tidak dibuat
end

local T = ThemeColor.tokens -- tabel bersama themeColor: T.X dibaca saat melukis → ikut tema pilihan pemain
local FONT = (_G.MenuConfig and _G.MenuConfig.font) or {
	BOLD = Enum.Font.BuilderSansBold, MEDIUM = Enum.Font.BuilderSansMedium, REGULAR = Enum.Font.BuilderSans,
}
local ROBUX = utf8.char(0xE002)
local PANEL_W, PANEL_H, SIDEBAR_W = 720, 470, 156
local REASON = {
	cooldown = "tunggu " .. Config.test.cooldown .. " detik",
	admin = "khusus admin",
	filter = "pesan tidak lolos filter",
	target = "pemain target sudah keluar",
	invalid = "data tidak sah",
	rank = "khusus rank " .. Config.tierEdit.rank .. "+",
	notready = "setelan belum terbaca, coba lagi",
	notfound = "ID bukan Developer Product game ini",
	foreign = "ID sudah dipakai sistem lain (Shop dll.)",
	exists = "produk sudah ada",
	full = "maksimal " .. Config.tierEdit.maxTiers .. " produk",
	api = "Roblox gagal membaca produk, coba lagi",
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
ThemeColor.mark(gui)
-- Active = klik di area panel tidak tembus ke panel donasi di belakangnya (tembus → tombol "Effects" ikut terklik).
local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = T.BG, Active = true, Parent = gui })
corner(14, panel)
stroke(panel, 0.85)
label("Donate Admin Panel", { Position = UDim2.new(0, 18, 0, 8), Size = UDim2.new(1, -70, 0, 22), Font = FONT.BOLD,
	TextSize = 18, TextColor3 = T.TEXT, Parent = panel })
label("Admin only · donasi tes tidak disimpan & tidak masuk TOP", { Position = UDim2.new(0, 18, 0, 28),
	Size = UDim2.new(1, -70, 0, 14), TextSize = 11, Parent = panel })
local closeBtn = button("X", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 24),
	Size = UDim2.new(0, 30, 0, 30), Parent = panel })
-- Efek di layar SENDIRI (atribut DonationFX, sama dengan tombol Effects di panel donasi): OFF = tes tidak terlihat.
local myFxBtn = button("", { Name = "MyEffects", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -50, 0, 24),
	Size = UDim2.new(0, 132, 0, 30), Font = FONT.MEDIUM, TextSize = 12, Parent = panel })
local function fxOn()
	return player:GetAttribute("DonationFX") ~= false
end
local function paintMyFx()
	myFxBtn.Text = fxOn() and "Efek kamu: ON" or "Efek kamu: OFF ⚠"
	myFxBtn.TextColor3 = fxOn() and T.ACCENT or T.DANGER
end
myFxBtn.Activated:Connect(function()
	player:SetAttribute("DonationFX", not fxOn())
end)
player:GetAttributeChangedSignal("DonationFX"):Connect(paintMyFx)
paintMyFx()
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
local pages = { Donation = page("DonationPage"), ["Test Effect"] = page("EffectPage"), Produk = page("ProductPage") }
local tabs = {}
local function showTab(name)
	for n, p in pages do
		p.Visible = n == name
		tabs[n].TextColor3 = n == name and T.ON_ACCENT or T.TEXT
		tabs[n].BackgroundColor3 = n == name and T.ACCENT or T.CARD
	end
	status.Text = ""
end
for i, n in { "Donation", "Test Effect", "Produk" } do
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
					TextColor3 = mine and T.ON_ACCENT or T.TEXT, BackgroundColor3 = mine and T.ACCENT or T.CARD,
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
		if (fn == fxFn or fn == testFn) and not fxOn() then
			status.TextColor3 = T.DANGER
			status.Text = "Terkirim, tapi Efek kamu OFF — nyalakan di kanan atas supaya terlihat"
		end
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
local chosenId = Config.tiers[1] and Config.tiers[1].productId
local function buildTierGrid()
	for _, c in tierGrid:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	if not Config.tierForProduct(chosenId) then
		chosenId = Config.tiers[1] and Config.tiers[1].productId
	end
	for i, t in Config.tiers do
		local on = t.productId == chosenId
		local b = button(tierName(t), { Name = "Tier" .. t.robux, LayoutOrder = i, Font = FONT.MEDIUM, TextSize = 13,
			BackgroundColor3 = on and T.ACCENT or T.CARD, TextColor3 = on and T.ON_ACCENT or T.TEXT, Parent = tierGrid })
		b.Activated:Connect(function()
			chosenId = t.productId
			buildTierGrid()
		end)
	end
end
buildTierGrid()
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
	BackgroundColor3 = T.ACCENT, TextColor3 = T.ON_ACCENT, Parent = dp })
sendBtn.Activated:Connect(function()
	if call(testFn, chosenId, msg.Text, everywhere, donTarget()) then
		msg.Text = ""
	end
end)

-- Pilihan efek (dipakai tab Test Effect & Produk): { teks, nilai } — false = OFF.
local fxList, bigList = Config.effectList()
local OPTIONS = { fx = { { "OFF", false } }, cam = { { "OFF", false } }, big = { { "OFF", false } } }
for _, e in fxList do
	table.insert(OPTIONS.fx, { e.label, e.name })
end
for _, m in Config.cinematic.modes do
	table.insert(OPTIONS.cam, { m, m })
end
for _, b in bigList do
	table.insert(OPTIONS.big, { b.label, b.name })
end
local function bigLabel(name)
	for _, b in bigList do
		if b.name == name then
			return b.label
		end
	end
	return nil
end
local ROW_TITLE = { fx = "PARTIKEL (di pemain)", cam = "KAMERA SINEMATIK", big = "EFEK BESAR (di titik map, bukan di pemain)" }
-- Baris pilihan: satu tombol per opsi, yang aktif disorot. onPick(nilai) dipanggil saat diklik.
local function chipRow(parent, at, field, value, onPick)
	label(ROW_TITLE[field], { LayoutOrder = at, Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = FONT.BOLD,
		TextColor3 = T.ACCENT, Parent = parent })
	local row = new("Frame", { Name = "Opt_" .. field, LayoutOrder = at + 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = parent })
	new("UIGridLayout", { CellSize = UDim2.new(0, 84, 0, 28), CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	for i, o in OPTIONS[field] do
		local on = (value or false) == o[2]
		local b = button(o[1], { Name = tostring(o[2]), LayoutOrder = i, Font = FONT.MEDIUM, TextSize = 12,
			BackgroundColor3 = on and T.ACCENT or T.CARD, TextColor3 = on and T.ON_ACCENT or T.TEXT, Parent = row })
		b.Activated:Connect(function()
			onPick(o[2])
		end)
	end
end
local function mixText(fx, cam, big)
	return ("%s  +  kamera %s  +  %s"):format(fx or "tanpa partikel", cam or "OFF", big and bigLabel(big) or "tanpa efek besar")
end

-- ── Tab Test Effect: racik partikel + kamera + efek besar, lalu ▶ TEST EFFECT ──────────
-- Hanya visual (tanpa notifikasi/data/papan). Tidak ada yang terkirim sebelum tombol TEST EFFECT.
local ep = pages["Test Effect"]
label("TARGET PLAYER", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16), Parent = ep })
local fxTarget, fxRebuild = playerPicker(ep, 2)
local mix = { fx = false, cam = false, big = false }
local mixBox = new("Frame", { Name = "Mix", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Parent = ep })
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = mixBox })
local buildMix
buildMix = function()
	for _, c in mixBox:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for n, field in { "fx", "cam", "big" } do
		chipRow(mixBox, n * 2, field, mix[field], function(v)
			mix[field] = v
			buildMix()
		end)
	end
	label("RACIKAN: " .. mixText(mix.fx, mix.cam, mix.big), { Name = "Summary", LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 18), Font = FONT.MEDIUM, TextSize = 13, TextColor3 = T.TEXT, TextWrapped = true, Parent = mixBox })
	local any = mix.fx or mix.cam or mix.big
	local runBtn = button("▶  TEST EFFECT", { Name = "Run", LayoutOrder = 11, Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = any and T.ACCENT or T.CARD, TextColor3 = any and T.ON_ACCENT or T.TEXT_DIM, Parent = mixBox })
	runBtn.Activated:Connect(function()
		if not (mix.fx or mix.cam or mix.big) then
			status.TextColor3 = T.DANGER
			status.Text = "Pilih minimal satu efek dulu"
			return
		end
		call(fxFn, mix.fx or nil, mix.cam or nil, mix.big or nil, fxTarget())
	end)
	label("Jeda " .. Config.test.cooldown .. " detik antar tes", { LayoutOrder = 12, Size = UDim2.new(1, 0, 0, 14), TextSize = 11,
		Parent = mixBox })
end
buildMix()

-- ── Tab Produk (setelan per Developer Product, desain "Config - per Dev Product") ─────
-- Kiri: daftar produk. Kanan: form produk terpilih. Pilihan = draf; baru terkirim lewat 💾 SIMPAN.
local pp = pages.Produk
local addRow = new("Frame", { Name = "AddRow", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1,
	Parent = pp })
local idBox = new("TextBox", { Name = "ProductId", Size = UDim2.new(1, -216, 1, 0), BackgroundColor3 = T.CARD, Text = "",
	PlaceholderText = "ID Developer Product baru (Creator Hub)…", PlaceholderColor3 = T.TEXT_DIM, TextColor3 = T.TEXT,
	Font = FONT.REGULAR, TextSize = 13, ClearTextOnFocus = false, Parent = addRow })
corner(6, idBox)
local addBtn = button("+ Tambah", { Name = "Add", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -108, 0, 0),
	Size = UDim2.new(0, 100, 1, 0), TextSize = 13, Parent = addRow })
local priceBtn = button("↻ Reload", { Name = "Prices", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 100, 1, 0), TextSize = 13, Parent = addRow })
local saveAllBtn = button("", { Name = "SaveAll", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36), TextSize = 14, Parent = pp })
local body = new("Frame", { Name = "Body", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Parent = pp })
local plist = new("Frame", { Name = "Products", Size = UDim2.new(0.36, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Parent = body })
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = plist })
local form = new("Frame", { Name = "Form", Position = UDim2.new(0.36, 4, 0, 0), Size = UDim2.new(0.64, -4, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.CARD, Parent = body })
corner(10, form)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10), Parent = form })
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = form })

local selected = Config.tiers[1] and Config.tiers[1].productId
-- Draf per produk: drafts[id] = { field = nilai } (false = OFF); hilang setelah SIMPAN / Batal / Reload.
local drafts = {}
local EDIT_FIELDS = { "label", "fx", "cam", "big", "hidden" }
local function current(t, field)
	local d = drafts[t.productId]
	if d and d[field] ~= nil then
		return d[field]
	end
	return t[field] or false
end
local function setDraft(t, field, value)
	local d = drafts[t.productId] or {}
	if value == (t[field] or false) then
		d[field] = nil
	else
		d[field] = value
	end
	drafts[t.productId] = next(d) and d or nil
end
local function dirtyCount()
	local n = 0
	for id in drafts do
		n += Config.tierForProduct(id) and 1 or 0
	end
	return n
end
local buildProducts
local function buildForm(t)
	for _, c in form:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not t then
		label("Pilih produk di kiri", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), Parent = form })
		return
	end
	local dirty = drafts[t.productId] ~= nil
	label(("%s %s · %s"):format(ROBUX, t.robux, current(t, "label") or ""), { Name = "Title", LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 22), Font = FONT.BOLD, TextSize = 17, TextColor3 = T.TEXT, Parent = form })
	label(("ID %d · %s · harga diatur di Creator Hub%s"):format(t.productId, t.custom and "produk tambahan" or "produk bawaan",
		dirty and "   ● BELUM DISIMPAN" or ""), { Name = "Info", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 14), TextSize = 11,
		TextColor3 = dirty and T.ACCENT or T.TEXT_DIM, Parent = form })
	label("NAMA DI PANEL DONASI", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = FONT.BOLD,
		TextColor3 = T.ACCENT, Parent = form })
	local nameBox = new("TextBox", { Name = "Label", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = T.BG,
		Text = current(t, "label") or "", PlaceholderText = "Nama tier…", PlaceholderColor3 = T.TEXT_DIM, TextColor3 = T.TEXT,
		Font = FONT.REGULAR, TextSize = 13, ClearTextOnFocus = false, Parent = form })
	corner(6, nameBox)
	nameBox.FocusLost:Connect(function()
		local text = string.gsub(string.gsub(nameBox.Text, "^%s+", ""), "%s+$", "")
		if text ~= "" and text ~= current(t, "label") then
			setDraft(t, "label", text)
			buildProducts()
		end
	end)
	for n, field in { "fx", "cam", "big" } do
		chipRow(form, 4 + n * 2, field, current(t, field), function(v)
			setDraft(t, field, v)
			buildProducts()
		end)
	end
	local hidden = current(t, "hidden")
	local hideBtn = button((hidden and "☑" or "☐") .. "  Sembunyikan dari panel donasi", { Name = "Hide", LayoutOrder = 12,
		Size = UDim2.new(1, 0, 0, 28), Font = FONT.MEDIUM, TextSize = 13, TextColor3 = hidden and T.ACCENT or T.TEXT,
		BackgroundColor3 = T.BG, Parent = form })
	hideBtn.Activated:Connect(function()
		setDraft(t, "hidden", not hidden)
		buildProducts()
	end)
	label("HASIL: " .. mixText(current(t, "fx"), current(t, "cam"), current(t, "big")), { Name = "Summary", LayoutOrder = 13,
		Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12,
		TextColor3 = T.TEXT, Parent = form })
	local actions = new("Frame", { Name = "Actions", LayoutOrder = 14, Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1, Parent = form })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = actions })
	local testBtn = button("▶ Tes donasi", { Name = "Test", Size = UDim2.new(0, 116, 1, 0), BackgroundColor3 = T.ACCENT,
		TextColor3 = T.ON_ACCENT, TextSize = 13, Parent = actions })
	testBtn.Activated:Connect(function()
		if drafts[t.productId] then
			status.TextColor3 = T.DANGER
			status.Text = "💾 SIMPAN dulu — tes donasi memakai setelan yang tersimpan"
			return
		end
		call(testFn, t.productId, "", false, nil)
	end)
	if dirty then
		local undo = button("Batal", { Name = "Undo", Size = UDim2.new(0, 70, 1, 0), TextSize = 13, Parent = actions })
		undo.Activated:Connect(function()
			drafts[t.productId] = nil
			buildProducts()
		end)
	end
	if t.custom then
		local delBtn = button("Hapus", { Name = "Remove", Size = UDim2.new(0, 80, 1, 0), TextColor3 = T.DANGER, TextSize = 13,
			Parent = actions })
		delBtn.Activated:Connect(function()
			if delBtn.Text == "Yakin hapus?" then
				drafts[t.productId] = nil
				call(editFn, "remove", t.productId)
			else
				delBtn.Text = "Yakin hapus?"
			end
		end)
	end
end
buildProducts = function()
	for _, c in plist:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	-- `selected` dibiarkan walau belum ada (produk baru menunggu daftar dari server); tampil = produk pertama dulu
	local shown = Config.tierForProduct(selected) or Config.tiers[1]
	for i, t in Config.tiers do
		local on = t == shown
		local dirty = drafts[t.productId] ~= nil
		local text = ("%s %s · %s%s%s"):format(ROBUX, t.robux, current(t, "label") or "", current(t, "hidden") and "  (hidden)" or "",
			dirty and "  ●" or "")
		local b = button(text, { Name = "P" .. t.productId, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 30), Font = FONT.MEDIUM,
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundColor3 = on and T.ACCENT or T.CARD, TextColor3 = on and T.ON_ACCENT or (dirty and T.ACCENT or T.TEXT),
			Parent = plist })
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = b })
		b.Activated:Connect(function()
			selected = t.productId
			buildProducts()
		end)
	end
	buildForm(shown)
	local n = dirtyCount()
	saveAllBtn.Text = n > 0 and ("💾  SIMPAN (%d produk berubah)"):format(n) or "Tersimpan ✓"
	saveAllBtn.BackgroundColor3 = n > 0 and T.SUCCESS or T.CARD
	saveAllBtn.TextColor3 = n > 0 and T.ON_ACCENT or T.TEXT_DIM
end
buildProducts()
saveAllBtn.Activated:Connect(function()
	local saved = 0
	for _, t in table.clone(Config.tiers) do
		local d = drafts[t.productId]
		if d then
			local changes = {}
			for _, f in EDIT_FIELDS do
				if d[f] ~= nil then
					changes[f] = d[f]
				end
			end
			if saved > 0 then
				task.wait(Config.tierEdit.cooldown + 0.1)
			end
			if not call(editFn, "save", t.productId, nil, changes) then
				buildProducts()
				return -- alasan ditolak tampil di status; draf lain tetap
			end
			drafts[t.productId] = nil
			saved += 1
		end
	end
	if saved > 0 then
		status.TextColor3 = T.SUCCESS
		status.Text = ("Tersimpan ✓ %d produk — berlaku di semua server"):format(saved)
	end
	buildProducts()
end)
addBtn.Activated:Connect(function()
	local id = tonumber((string.gsub(idBox.Text, "%D", "")))
	if not id then
		status.TextColor3 = T.DANGER
		status.Text = "Tempel ID Developer Product (angka)"
		return
	end
	if call(editFn, "add", id) then
		idBox.Text = ""
		selected = id
	end
end)
priceBtn.Activated:Connect(function()
	drafts = {}
	buildProducts()
	call(editFn, "prices")
end)

-- Daftar tier dari server (atribut DonationRemotes.Tiers) → Config + bangun ulang tab Donation & Produk.
local function syncTiers()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(remotes:GetAttribute("Tiers"))
	end)
	if ok and type(list) == "table" and #list > 0 then
		Config.applyTiers(list)
		buildTierGrid()
		buildProducts()
	end
end
remotes:GetAttributeChangedSignal("Tiers"):Connect(syncTiers)
if remotes:GetAttribute("Tiers") then
	syncTiers()
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
	local editor = player:GetAttribute("DonationEditor") == true
	adminBtn.Visible = isAdmin or editor
	tabs.Produk.Visible = editor
	if not editor and pages.Produk.Visible then
		showTab("Donation")
	end
	isAdmin = isAdmin or editor
	if not isAdmin then
		close()
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(paintAdmin)
player:GetAttributeChangedSignal("DonationEditor"):Connect(paintAdmin)
paintAdmin()
showTab("Donation")
