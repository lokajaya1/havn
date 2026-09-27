-- ShopClient — StarterPlayerScripts
-- Tema mengikuti UltimateMenu / DanceClient (dibaca dari _G.MenuConfig).

repeat task.wait() until _G.MenuUI and _G.InjectPanelUI and _G.MenuConfig

local Players           = game:GetService("Players")
local Marketplace       = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local TextChatService   = game:GetService("TextChatService")

local UI     = _G.MenuUI
local C      = _G.MenuConfig.colors
local player = Players.LocalPlayer

local T = _G.MenuConfig.theme or {
	BG         = Color3.fromRGB(16, 16, 17),
	CARD       = Color3.fromRGB(26, 26, 28),
	CARD_HOVER = Color3.fromRGB(36, 36, 39),
	LINE       = Color3.fromRGB(255, 255, 255),
	TEXT       = Color3.fromRGB(238, 238, 240),
	TEXT_DIM   = Color3.fromRGB(148, 148, 154),
	ACCENT     = Color3.fromRGB(212, 175, 55),
	DANGER     = Color3.fromRGB(226, 96, 96),
}

local FONT = _G.MenuConfig.font or {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local TEXT_ON_ACCENT = C.textOnAccent or Color3.fromRGB(18, 18, 20)

local TW = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function tw(obj, props)
	if obj and obj.Parent then TweenService:Create(obj, TW, props):Play() end
end

local bindHover = UI.bindHover or function(obj, apply)
	obj.MouseEnter:Connect(function() apply(true) end)
	obj.MouseLeave:Connect(function() apply(false) end)
end

-- ── Remotes ───────────────────────────────────────────────────

local Remotes = ReplicatedStorage:WaitForChild("ShopRemotes", 30)

if not Remotes then
	warn("[ShopClient] ShopRemotes tidak muncul dalam 30s. ShopServer gagal init.")
	local holder = UI.frame({ Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 })
	UI.text({
		Size = UDim2.new(1, -24, 0, 80), Position = UDim2.new(0, 12, 0.5, -40),
		Text = "Shop gagal dimuat.\nShopServer tidak aktif — cek Output server.",
		TextColor3 = T.DANGER, Font = FONT.MEDIUM, TextSize = 12, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, Parent = holder,
	})
	_G.InjectPanelUI("Shop", holder)
	return
end

local Config = require(ReplicatedStorage:WaitForChild("ShopConfig"))

local GetAllOwnership  = Remotes:WaitForChild("GetAllOwnership")
local InitiateGift     = Remotes:WaitForChild("InitiateGift")
local AdminGiftItem    = Remotes:WaitForChild("AdminGiftItem")
local GetOnlinePlayers = Remotes:WaitForChild("GetOnlinePlayers")
local OwnershipUpdated = Remotes:WaitForChild("OwnershipUpdated")
local GiftReceived     = Remotes:WaitForChild("GiftReceived")
local GiftChatNotif    = Remotes:FindFirstChild("GiftChatNotification")

-- ── State ─────────────────────────────────────────────────────

local OwnershipCache = {}    -- [passName] → bool
local PriceCache     = {}    -- [passId]   → number
local cardRenderers  = {}    -- [passName] → fungsi render ulang kartu
local playerIsAdmin  = false
local currentModal   = nil
local headerRefresh  = nil

-- ── Util ──────────────────────────────────────────────────────

-- Harga gagal dimuat → callback(nil), TIDAK dicache (dicoba lagi saat kartu dirender ulang).
-- Dulu gagal = 0 → tampil "Gratis" permanen.
local function fetchPrice(passId, callback)
	local cached = PriceCache[passId]
	if cached then callback(cached) return end
	task.spawn(function()
		local ok, info = pcall(Marketplace.GetProductInfo, Marketplace, passId, Enum.InfoType.GamePass)
		local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
		if price then PriceCache[passId] = price end
		callback(price)
	end)
end

local function chatMessage(text)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general  = channels and channels:FindFirstChild("RBXGeneral")
	if general then
		pcall(general.DisplaySystemMessage, general, text)
		return
	end
	pcall(function()
		game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {
			Text = text, Color = T.ACCENT, Font = FONT.MEDIUM,
		})
	end)
end

-- Tombol utama (isi accent) dan tombol sekunder (kartu + garis accent).
local function makeButton(parent, text, primary, size)
	local btn = UI.button({
		Size = size or UDim2.new(0, 62, 0, 24),
		BackgroundColor3 = primary and T.ACCENT or T.CARD,
		Text = text, TextColor3 = primary and TEXT_ON_ACCENT or T.TEXT,
		Font = FONT.MEDIUM, TextSize = 10, Parent = parent,
	})
	UI.corner(8).Parent = btn

	if primary then
		bindHover(btn, function(on)
			tw(btn, { BackgroundColor3 = on and T.TEXT or T.ACCENT })
		end)
	else
		UI.stroke(T.ACCENT, 1, 0.45).Parent = btn
		bindHover(btn, function(on)
			tw(btn, { BackgroundColor3 = on and T.CARD_HOVER or T.CARD })
		end)
	end
	return btn
end

local function fetchOwnership()
	local ok, data = pcall(GetAllOwnership.InvokeServer, GetAllOwnership)
	if not ok or type(data) ~= "table" then return false end

	OwnershipCache = {}
	playerIsAdmin  = data._isAdmin or false
	for name, owned in pairs(data) do
		if name ~= "_isAdmin" then OwnershipCache[name] = owned end
	end
	return true
end

-- ══════════════════════════════════════════════════════════════
-- GIFT POPUP
-- ══════════════════════════════════════════════════════════════

local function showGiftPopup(senderName, passName)
	local gui = UI.new("ScreenGui", {
		Name = "GiftNotification", DisplayOrder = 1000,
		ResetOnSpawn = false, Parent = player.PlayerGui,
	})

	local W, H = 280, 66
	local frame = UI.frame({
		Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -H - 10),
		BackgroundColor3 = T.BG, Parent = gui,
	})
	UI.corner(12).Parent = frame
	UI.stroke(T.ACCENT, 1, 0.5).Parent = frame

	local accentBar = UI.frame({
		Size = UDim2.new(0, 2, 0, 34), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0), BackgroundColor3 = T.ACCENT, Parent = frame,
	})
	UI.corner(2).Parent = accentBar

	UI.text({
		Size = UDim2.new(1, -34, 0, 14), Position = UDim2.new(0, 22, 0, 14),
		Text = "Gift diterima", TextColor3 = T.ACCENT, Font = FONT.BOLD, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
	})
	UI.text({
		Size = UDim2.new(1, -34, 0, 26), Position = UDim2.new(0, 22, 0, 30),
		Text = senderName .. " memberimu " .. passName, TextColor3 = T.TEXT_DIM,
		Font = FONT.REGULAR, TextSize = 10, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
	})

	TweenService:Create(frame, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 14) }):Play()

	task.delay(4.5, function()
		if not frame.Parent then return end
		TweenService:Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -H - 10) }):Play()
		task.wait(0.28)
		gui:Destroy()
	end)
end

-- ══════════════════════════════════════════════════════════════
-- GIFT MODAL
-- ══════════════════════════════════════════════════════════════

local function closeModal()
	if currentModal then
		currentModal:Destroy()
		currentModal = nil
	end
end

local function buildPlayerRow(entry, order, passData)
	local owned = entry.OwnsPass or false

	local row = UI.frame({
		Size = UDim2.new(1, 0, 0, 42), LayoutOrder = order,
		BackgroundColor3 = T.CARD,
	})
	UI.corner(10).Parent = row
	UI.stroke(T.LINE, 1, owned and 0.96 or 0.9).Parent = row

	local avatar = UI.frame({
		Size = UDim2.new(0, 26, 0, 26), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0), BackgroundColor3 = T.CARD_HOVER, Parent = row,
	})
	UI.corner(13).Parent = avatar

	local image = UI.new("ImageLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Image = "rbxthumb://type=AvatarBust&id=" .. entry.UserId .. "&w=48&h=48",
		Parent = avatar,
	})
	UI.corner(13).Parent = image

	UI.text({
		Size = UDim2.new(1, -108, 0, 14), Position = UDim2.new(0, 42, 0, 7),
		Text = entry.DisplayName, TextColor3 = owned and T.TEXT_DIM or T.TEXT,
		Font = FONT.MEDIUM, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	UI.text({
		Size = UDim2.new(1, -108, 0, 12), Position = UDim2.new(0, 42, 0, 21),
		Text = "@" .. entry.Name, TextColor3 = T.TEXT_DIM,
		Font = FONT.REGULAR, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})

	if owned then
		UI.text({
			Size = UDim2.new(0, 56, 0, 18), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Text = "Dimiliki",
			TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
		})
		return row
	end

	local btn = makeButton(row, playerIsAdmin and "Free" or "Gift", true, UDim2.new(0, 52, 0, 22))
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position    = UDim2.new(1, -10, 0.5, 0)
	btn.Activated:Connect(function()
		closeModal()
		local remote = playerIsAdmin and AdminGiftItem or InitiateGift
		remote:FireServer(entry.UserId, passData.name)
	end)

	return row
end

local function openGiftModal(passData)
	closeModal()

	local gui = UI.new("ScreenGui", {
		Name = "GiftModal", DisplayOrder = 999, ResetOnSpawn = false,
	})

	local backdrop = UI.button({
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45, Text = "", Parent = gui,
	})
	backdrop.Activated:Connect(closeModal)

	local MW, MH = 296, 360
	local modal = UI.frame({
		Size = UDim2.new(0, MW, 0, MH), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = T.BG, Parent = backdrop,
	})
	UI.corner(16).Parent = modal
	UI.stroke(T.LINE, 1, 0.88).Parent = modal

	UI.text({
		Size = UDim2.new(1, -56, 0, 16), Position = UDim2.new(0, 14, 0, 12),
		Text = (playerIsAdmin and "Free gift · " or "Gift · ") .. passData.name,
		TextColor3 = T.ACCENT, Font = FONT.BOLD, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = modal,
	})
	UI.text({
		Size = UDim2.new(1, -56, 0, 14), Position = UDim2.new(0, 14, 0, 28),
		Text = playerIsAdmin and "Gratis ke pemain mana pun" or "Pilih pemain tujuan",
		TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = modal,
	})

	local closeBtn = UI.button({
		Size = UDim2.new(0, 22, 0, 22), AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12), BackgroundTransparency = 1,
		Text = "✕", TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 14,
		Parent = modal,
	})
	bindHover(closeBtn, function(on)
		tw(closeBtn, { TextColor3 = on and T.TEXT or T.TEXT_DIM })
	end)
	closeBtn.Activated:Connect(closeModal)

	local listScroll = UI.scroll({
		Size = UDim2.new(1, -24, 1, -62), Position = UDim2.new(0, 12, 0, 50),
		ScrollBarThickness = 3, Parent = modal,
	})
	local layout = UI.list({ padding = 6 })
	layout.Parent = listScroll
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		listScroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
	end)

	local ok, list = pcall(GetOnlinePlayers.InvokeServer, GetOnlinePlayers, passData.name)
	if not ok or type(list) ~= "table" then list = {} end

	if #list == 0 then
		UI.text({
			Size = UDim2.new(1, 0, 0, 56), Text = "Tidak ada pemain lain online",
			TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 11,
			Parent = listScroll,
		})
	else
		table.sort(list, function(a, b)
			if a.OwnsPass ~= b.OwnsPass then return not a.OwnsPass end
			return a.DisplayName < b.DisplayName
		end)
		for i, entry in ipairs(list) do
			buildPlayerRow(entry, i, passData).Parent = listScroll
		end
	end

	gui.Parent   = player.PlayerGui
	currentModal = gui
end

-- ══════════════════════════════════════════════════════════════
-- KARTU GAMEPASS
-- ══════════════════════════════════════════════════════════════

local CARD_H  = 82
local ICON    = 42
local BTN_W   = 62
local BTN_H   = 24
local BTN_GAP = 6

local function createGamepassCard(passData)
	local hasGift = passData.giftProduct and passData.giftProduct ~= 0

	local card = UI.frame({ Size = UDim2.new(1, 0, 0, CARD_H), BackgroundColor3 = T.CARD })
	UI.corner(12).Parent = card
	local cardStroke = UI.stroke(T.LINE, 1, 0.94)
	cardStroke.Parent = card

	local iconBg = UI.frame({
		Size = UDim2.new(0, ICON, 0, ICON), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 11, 0.5, 0), BackgroundColor3 = T.CARD_HOVER, Parent = card,
	})
	UI.corner(10).Parent = iconBg

	UI.new("ImageLabel", {
		Size = UDim2.new(0.72, 0, 0.72, 0), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1,
		Image = passData.icon or "rbxassetid://103867908310819",
		ScaleType = Enum.ScaleType.Fit, Parent = iconBg,
	})

	local textX = 11 + ICON + 10
	local textW = -(textX + BTN_W + 22)

	local nameLbl = UI.text({
		Size = UDim2.new(1, textW, 0, 15), Position = UDim2.new(0, textX, 0, 13),
		Text = passData.name, TextColor3 = T.TEXT, Font = FONT.MEDIUM, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
	})
	UI.text({
		Size = UDim2.new(1, textW, 0, 24), Position = UDim2.new(0, textX, 0, 29),
		Text = passData.desc, TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = card,
	})
	local priceLbl = UI.text({
		Size = UDim2.new(1, textW, 0, 13), Position = UDim2.new(0, textX, 0, 55),
		Text = "", TextColor3 = T.TEXT_DIM, Font = FONT.MEDIUM, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
	})

	local buyBtn = makeButton(card, "Beli", true)
	buyBtn.AnchorPoint = Vector2.new(1, 0)
	buyBtn.Activated:Connect(function()
		Marketplace:PromptGamePassPurchase(player, passData.id)
	end)

	local giftBtn
	if hasGift then
		giftBtn = makeButton(card, "Gift", false)
		giftBtn.AnchorPoint = Vector2.new(1, 0)
		giftBtn.Activated:Connect(function() openGiftModal(passData) end)
	end

	-- Satu fungsi untuk seluruh tampilan kartu; dipanggil ulang saat ownership
	-- berubah, jadi kartu tidak perlu dibuat ulang dari nol.
	local function render()
		local owned = OwnershipCache[passData.name] or false

		nameLbl.TextColor3      = owned and T.ACCENT or T.TEXT
		cardStroke.Transparency = owned and 0.72 or 0.94
		cardStroke.Color        = owned and T.ACCENT or T.LINE
		buyBtn.Visible          = not owned
		if giftBtn then
			giftBtn.Text    = playerIsAdmin and "Free" or "Gift"
			giftBtn.Visible = true
		end

		local showGift = giftBtn ~= nil
		if not owned and showGift then
			local top = (CARD_H - (BTN_H * 2 + BTN_GAP)) / 2
			buyBtn.Position  = UDim2.new(1, -11, 0, top)
			giftBtn.Position = UDim2.new(1, -11, 0, top + BTN_H + BTN_GAP)
		else
			local mid = (CARD_H - BTN_H) / 2
			buyBtn.Position = UDim2.new(1, -11, 0, mid)
			if showGift then giftBtn.Position = UDim2.new(1, -11, 0, mid) end
		end

		if owned then
			priceLbl.Text       = "Dimiliki"
			priceLbl.TextColor3 = T.ACCENT
			return
		end

		priceLbl.Text       = "Memuat…"
		priceLbl.TextColor3 = T.TEXT_DIM
		fetchPrice(passData.id, function(price)
			if not priceLbl.Parent or OwnershipCache[passData.name] then return end
			if not price then
				priceLbl.Text       = "—"
				priceLbl.TextColor3 = T.TEXT_DIM
				return
			end
			priceLbl.Text       = price > 0 and (price .. " R$") or "Gratis"
			priceLbl.TextColor3 = T.ACCENT
		end)
	end

	cardRenderers[passData.name] = render
	render()
	return card
end

-- ══════════════════════════════════════════════════════════════
-- BUILD
-- ══════════════════════════════════════════════════════════════

local function buildShopUI()
	cardRenderers = {}

	local container = UI.frame({
		Name = "ShopContainer", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	})

	local scroll = UI.scroll({
		Size = UDim2.new(1, -4, 1, 0), Position = UDim2.new(0, 2, 0, 0),
		ScrollBarThickness = 3, Parent = container,
	})

	local content = UI.frame({
		Size = UDim2.new(1, -8, 0, 0), Position = UDim2.new(0, 4, 0, 4),
		BackgroundTransparency = 1, Parent = scroll,
	})

	local layout = UI.list({ padding = 7 })
	layout.Parent = content
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local h = layout.AbsoluteContentSize.Y
		content.Size      = UDim2.new(1, -8, 0, h)
		scroll.CanvasSize = UDim2.new(0, 0, 0, h + 14)
	end)

	local order = 0
	local function L() order = order + 1 return order end

	-- Header
	local header = UI.frame({
		Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.CARD,
		LayoutOrder = L(), Parent = content,
	})
	UI.corner(12).Parent = header
	UI.stroke(T.LINE, 1, 0.94).Parent = header

	local bar = UI.frame({
		Size = UDim2.new(0, 2, 0, 24), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0), BackgroundColor3 = T.ACCENT, Parent = header,
	})
	UI.corner(2).Parent = bar

	local titleLbl = UI.text({
		Size = UDim2.new(1, -30, 0, 15), Position = UDim2.new(0, 22, 0, 8),
		Text = "Game Passes", TextColor3 = T.ACCENT, Font = FONT.BOLD, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
	})
	local subLbl = UI.text({
		Size = UDim2.new(1, -30, 0, 13), Position = UDim2.new(0, 22, 0, 24),
		Text = "", TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
	})

	headerRefresh = function()
		titleLbl.Text = playerIsAdmin and "Game Passes · Owner" or "Game Passes"
		subLbl.Text   = playerIsAdmin
			and "Semua pass aktif · gift gratis"
			or  "Upgrade permanen · bisa di-gift"
	end
	headerRefresh()

	for _, passData in ipairs(Config.gamepasses) do
		local card = createGamepassCard(passData)
		card.LayoutOrder = L()
		card.Parent      = content
	end

	local footer = UI.frame({
		Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
		LayoutOrder = L(), Parent = content,
	})
	UI.text({
		Size = UDim2.new(1, 0, 1, 0), Text = "SICK HAVN",
		TextColor3 = T.TEXT_DIM, Font = FONT.REGULAR, TextSize = 9, Parent = footer,
	})

	return container
end

-- Render ulang kartu yang ada; tidak membangun instance baru.
local function renderAll()
	for _, render in pairs(cardRenderers) do
		pcall(render)
	end
	if headerRefresh then pcall(headerRefresh) end
end

local function refreshShop()
	if fetchOwnership() then renderAll() end
end

-- ══════════════════════════════════════════════════════════════
-- EVENT
-- ══════════════════════════════════════════════════════════════

OwnershipUpdated.OnClientEvent:Connect(function(passName, owned)
	OwnershipCache[passName] = owned
	local render = cardRenderers[passName]
	if render then pcall(render) end
end)

GiftReceived.OnClientEvent:Connect(function(senderName, passName)
	OwnershipCache[passName] = true
	showGiftPopup(senderName, passName)
	chatMessage(senderName .. " memberimu " .. passName .. "!")
	local render = cardRenderers[passName]
	if render then pcall(render) end
end)

if GiftChatNotif then
	GiftChatNotif.OnClientEvent:Connect(function(senderName, recipientName, passName)
		-- Penerima sudah dapat "X memberimu …" dari GiftReceived → jangan dobel
		if recipientName == player.Name then return end
		chatMessage(senderName .. " memberikan " .. passName .. " ke " .. recipientName .. "!")
	end)
end

Marketplace.PromptGamePassPurchaseFinished:Connect(function(plr, _, purchased)
	if plr == player and purchased then task.delay(1, refreshShop) end
end)

player.CharacterRemoving:Connect(closeModal)

-- ── Init ──────────────────────────────────────────────────────

_G.ShopConfig  = Config
_G.RefreshShop = refreshShop

fetchOwnership()
_G.InjectPanelUI("Shop", buildShopUI())