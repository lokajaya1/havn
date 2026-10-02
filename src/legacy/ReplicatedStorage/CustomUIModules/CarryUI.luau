-- ═══════════════════════════════════════════════════════════
-- CarryUI — satu pintu untuk SEMUA tampilan carry
-- Path: ReplicatedStorage.CustomUIModules.CarryUI
--
-- Isi:
--   • Select panel → daftar jenis carry (dulu dibuat CarrySelectPanelInit
--                    + di-styling ulang oleh MenuBinder; sekarang di sini)
--   • Request card → siapa yang minta carry + Accept / Decline + bar waktu
--   • Drop card    → status sedang di-carry + tombol Stop carry
--   • Toast        → pengganti StarterGui:SetCore("SendNotification")
--
-- Tema, font, radius, dan tween persis sama dengan MenuSystemInit.
--
-- [FIX kanan-tengah] Stack notif (Request/Drop/Toast) sekarang nempel di
-- KANAN-TENGAH layar di semua device (dulu bawah-tengah), dan ukurannya
-- dikecilin lewat `notifyCfg` sendiri (terpisah dari `cfg` yang tetap
-- dipakai select panel). Supaya gak "menabrak" panel UltimateMenu
-- (StarterGui > UltimateMenu, dok terpisah) yang juga muncul dari sisi
-- kanan saat dibuka, DisplayOrder CarryGui diturunin ke bawah nol —
-- UltimateMenu.lua TIDAK pernah men-set DisplayOrder pada ScreenGui-nya
-- ("UltimatePanelSystem" & "MenuButtonGui"), jadi keduanya diam di default
-- 0. Dengan CarryGui < 0, begitu area stack & panel menu bentrok secara
-- posisi, panel menu yang menang tampil di atas dan notif carry otomatis
-- "ngumpet" di belakangnya — tanpa perlu logic hindar-posisi yang ribet.
-- ═══════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")

local CarryUI = {}

-- Client-only. Di server dikembalikan stub supaya require dari server tidak error.
if RunService:IsServer() then
	local function noop() end
	for _, name in ipairs({
		"ShowRequest", "HideRequest", "ShowDrop", "HideDrop",
		"ShowSelect", "HideSelect", "Toast", "HideAll",
		}) do
		CarryUI[name] = noop
	end
	function CarryUI.IsRequestVisible() return false end
	function CarryUI.IsDropVisible()    return false end
	return CarryUI
end

local Responsive = require(RS:WaitForChild("CustomUIModules"):WaitForChild("Responsive"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ════════════════════════════════════════════════════════════
-- THEME (sama dengan MenuSystemInit)
-- Warna dari ReplicatedStorage.Modules.ThemeColor (themeColor): THEME.X
-- membaca token tema SEKARANG saat dipakai → hover/leave ikut tema.
-- ════════════════════════════════════════════════════════════

local THEME = ThemeColor.view({
	BG         = "BG",
	CARD       = "CARD",
	CARD_HOVER = "CARD_HOVER",
	LINE       = "LINE",
	TEXT       = "TEXT",
	TEXT_DIM   = "TEXT_DIM",
	ACCENT     = "ACCENT",
	ON_ACCENT  = "ON_ACCENT",
})

-- Hover tombol utama = ACCENT dicampur putih 14 %. Dihitung saat dipakai
-- supaya ikut tema. Warna turunan ini BUKAN token (tidak dilukis ulang),
-- jadi setHover() yang selalu memasangnya ulang saat hover / leave.
local function accentHover()
	return THEME.ACCENT:Lerp(Color3.new(1, 1, 1), 0.14)
end

local FONT = {
	BOLD    = Enum.Font.BuilderSansBold,
	MEDIUM  = Enum.Font.BuilderSansMedium,
	REGULAR = Enum.Font.BuilderSans,
}

local TWEEN_FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local TWEEN_CARD = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- ════════════════════════════════════════════════════════════
-- SIZES
-- ════════════════════════════════════════════════════════════

-- `cfg` = config SELECT PANEL SAJA. Lebar, tinggi, posisi bawah, dan font-nya
-- tetap diambil dari Responsive.Panel() seperti semula (TIDAK berubah oleh
-- fix kanan-tengah ini) supaya panel pilih jenis carry tetap sama seperti
-- sebelumnya — cuma stack notif yang pindah & mengecil.
local function getConfig()
	local p = Responsive.Panel()
	return {
		width = p.width, height = p.height, bottomInset = p.bottomInset,
		row = p.row, title = p.title, text = p.text, small = p.small,
		pad = p.pad, gap = p.gap,
	}
end

local cfg = getConfig()

-- `notifyCfg` = config khusus STACK NOTIF (Request / Drop / Toast).
-- Sengaja dipisah dari `cfg` panel & dibikin lebih kecil ("kecilin lagi")
-- karena sekarang nempel di kanan-tengah, bukan lebar penuh macam panel
-- menu. `margin` = jarak dari tepi kanan layar; berlaku sama di semua
-- device karena posisinya di-anchor relatif (1, 0.5), bukan breakpoint px.
-- `yOffset` = geser vertikal dari titik tengah layar (negatif = naik ke
-- atas). Cuma device mobile yang punya tombol sentuh sprint/jump di
-- kanan-bawah, jadi cuma mobile yang digeser naik biar gak nabrak; tablet
-- & desktop (mouse/keyboard, gak ada tombol sentuh) tetap pas di tengah.
local NOTIFY = {
	mobile  = { width = 128, avatar = 16, btn = 18, pad = 5, gap = 3, title = 10, text = 9,  small = 8, margin = 8,  yOffset = -70 },
	tablet  = { width = 164, avatar = 20, btn = 22, pad = 6, gap = 4, title = 11, text = 10, small = 9, margin = 10, yOffset = 0   },
	desktop = { width = 164, avatar = 20, btn = 22, pad = 6, gap = 4, title = 11, text = 10, small = 9, margin = 12, yOffset = 0   },
}

local function getNotifyConfig()
	local p = Responsive.Panel()
	local n = NOTIFY[p.device] or NOTIFY.desktop
	return {
		width = n.width, avatar = n.avatar, btn = n.btn, pad = n.pad, gap = n.gap,
		title = n.title, text = n.text, small = n.small, margin = n.margin,
		yOffset = n.yOffset,
	}
end

local notifyCfg = getNotifyConfig()

-- ════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════

local function new(class, props)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	return obj
end

local function corner(parent, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thick, trans)
	return new("UIStroke", {
		Name = "Stroke", Color = color, Thickness = thick or 1, Transparency = trans or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local function listLayout(parent, gap, dir)
	return new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap),
		FillDirection = dir or Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top, Parent = parent,
	})
end

local function padding(parent, value)
	return new("UIPadding", {
		PaddingTop  = UDim.new(0, value), PaddingBottom = UDim.new(0, value),
		PaddingLeft = UDim.new(0, value), PaddingRight  = UDim.new(0, value),
		Parent = parent,
	})
end

-- ════════════════════════════════════════════════════════════
-- ROOT STACK (request + drop + toast, KANAN-TENGAH)
-- ════════════════════════════════════════════════════════════

local gui = playerGui:FindFirstChild("CarryGui")
if not gui then
	gui = new("ScreenGui", {
		Name = "CarryGui", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Di bawah nol supaya SELALU kalah render dari panel UltimateMenu
		-- (dan tombol topbar-nya), yang diam di DisplayOrder default (0).
		-- Ini yang bikin notif carry "di belakang" panel menu, bukan nabrak.
		DisplayOrder = -1,
		Enabled = true, Parent = playerGui,
	})
end
ThemeColor.mark(gui)
gui.Enabled = true

local oldStack = gui:FindFirstChild("Stack")
if oldStack then oldStack:Destroy() end

-- Stack sekarang nempel KANAN-TENGAH (dulu bawah-tengah). AnchorPoint
-- (1, 0.5) bikin posisinya otomatis pas di tepi kanan + center vertikal di
-- SEMUA device tanpa perlu breakpoint per layar. AutomaticSize.Y bikin
-- stack tumbuh SIMETRIS ke atas & bawah dari titik tengah begitu ada
-- kartu/toast baru muncul.
local stack = new("Frame", {
	Name = "Stack", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -notifyCfg.margin, 0.5, notifyCfg.yOffset),
	Size = UDim2.new(0, notifyCfg.width, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui,
})
local stackLayout = listLayout(stack, notifyCfg.gap)

-- Stack dan PlayerMenu (sistem menu lama, ScreenGui "PlayerMenuGui") dulu
-- memakai slot yang sama (bawah-tengah). Fungsi ini dipertahankan untuk
-- kompatibilitas mundur — no-op kalau "PlayerMenuGui" tidak ada (mis. kalau
-- yang dipakai sekarang UltimateMenu, yang penanganannya sudah dicover
-- lewat DisplayOrder di atas, bukan lewat menutup gui).
local function closePlayerMenu()
	local menuGui = playerGui:FindFirstChild("PlayerMenuGui")
	if menuGui and menuGui.Enabled then menuGui.Enabled = false end
end

-- ════════════════════════════════════════════════════════════
-- CARD (CanvasGroup: fade seluruh isi sekaligus)
-- ════════════════════════════════════════════════════════════

local function makeCard(name, order, bgColor, padValue)
	local card = new("CanvasGroup", {
		Name = name, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = bgColor or THEME.BG,
		BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
		LayoutOrder = order, Parent = stack,
	})
	corner(card, 12)
	stroke(card, THEME.LINE, 1, 0.88)

	return {
		root  = card,
		scale = new("UIScale", { Scale = 0.96, Parent = card }),
		pad   = padding(card, padValue or notifyCfg.pad),
		list  = listLayout(card, notifyCfg.gap - 2),
	}
end

local function showCard(card, visible)
	if visible then
		card.root.Visible           = true
		card.root.GroupTransparency = 1
		card.scale.Scale            = 0.96
		TweenService:Create(card.root,  TWEEN_CARD, { GroupTransparency = 0 }):Play()
		TweenService:Create(card.scale, TWEEN_CARD, { Scale = 1 }):Play()
	else
		if not card.root.Visible then return end
		TweenService:Create(card.root, TWEEN_FAST, { GroupTransparency = 1 }):Play()
		local tw = TweenService:Create(card.scale, TWEEN_FAST, { Scale = 0.96 })
		tw:Play()
		tw.Completed:Once(function()
			if card.root.GroupTransparency >= 0.98 then card.root.Visible = false end
		end)
	end
end

-- ════════════════════════════════════════════════════════════
-- BUTTON (Accept / Decline / Stop carry)
-- ════════════════════════════════════════════════════════════

local buttons = {}

local function makeButton(parent, name, label, order, primary)
	local btn = new("TextButton", {
		Name = name, Size = UDim2.new(1, 0, 0, notifyCfg.btn),
		BackgroundColor3 = primary and THEME.ACCENT or THEME.CARD,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order, ClipsDescendants = true, Parent = parent,
	})
	corner(btn, 8)
	local st = stroke(btn, primary and THEME.ACCENT or THEME.LINE, 1, primary and 0.45 or 0.92)

	local lbl = new("TextLabel", {
		Name = "Label", Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1, Text = label,
		TextColor3 = primary and THEME.ON_ACCENT or THEME.TEXT,
		Font = primary and FONT.BOLD or FONT.MEDIUM, TextSize = notifyCfg.text,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
	})

	local function setHover(on)
		TweenService:Create(btn, TWEEN_FAST, {
			BackgroundColor3 = primary
				and (on and accentHover() or THEME.ACCENT)
				or  (on and THEME.CARD_HOVER or THEME.CARD),
		}):Play()
		TweenService:Create(st, TWEEN_FAST, {
			Transparency = primary and (on and 0.2 or 0.45) or (on and 0.78 or 0.92),
		}):Play()
	end

	btn.MouseEnter:Connect(function() setHover(true)  end)
	btn.MouseLeave:Connect(function() setHover(false) end)
	btn.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then setHover(true) end
	end)
	btn.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then setHover(false) end
	end)

	table.insert(buttons, { button = btn, label = lbl })
	return btn
end

-- ════════════════════════════════════════════════════════════
-- REQUEST CARD
-- ════════════════════════════════════════════════════════════

local requestCard = makeCard("RequestCard", 1)

local reqHead = new("Frame", {
	Name = "Head", Size = UDim2.new(1, 0, 0, notifyCfg.avatar),
	BackgroundTransparency = 1, LayoutOrder = 1, Parent = requestCard.root,
})

local reqAvatar = new("ImageLabel", {
	Name = "Avatar", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, notifyCfg.avatar, 0, notifyCfg.avatar),
	BackgroundColor3 = THEME.CARD, BorderSizePixel = 0,
	ScaleType = Enum.ScaleType.Fit, Image = "", Parent = reqHead,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = reqAvatar })
stroke(reqAvatar, THEME.LINE, 1, 0.9)

local reqName = new("TextLabel", {
	Name = "Name", BackgroundTransparency = 1, Text = "Player",
	TextColor3 = THEME.ACCENT, Font = FONT.BOLD, TextSize = notifyCfg.title,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = reqHead,
})

local reqSub = new("TextLabel", {
	Name = "Sub", BackgroundTransparency = 1, Text = "wants to carry you",
	TextColor3 = THEME.TEXT_DIM, Font = FONT.REGULAR, TextSize = notifyCfg.small,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = reqHead,
})

local reqPillRow = new("Frame", {
	Name = "PillRow", Size = UDim2.new(1, 0, 0, notifyCfg.small + 14),
	BackgroundTransparency = 1, LayoutOrder = 2, Parent = requestCard.root,
})

local reqPill = new("Frame", {
	Name = "TypePill", Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 0, 0, notifyCfg.small + 14), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, Parent = reqPillRow,
})
corner(reqPill, 8)
stroke(reqPill, THEME.ACCENT, 1, 0.62)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7), Parent = reqPill,
})

local reqType = new("TextLabel", {
	Name = "Type", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Text = "Carry", TextColor3 = THEME.ACCENT,
	Font = FONT.MEDIUM, TextSize = notifyCfg.small + 1,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = reqPill,
})

local reqBarBg = new("Frame", {
	Name = "TimeoutBar", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = THEME.LINE,
	BackgroundTransparency = 0.88, BorderSizePixel = 0, LayoutOrder = 3,
	Parent = requestCard.root,
})
corner(reqBarBg, 2)

local reqBarFill = new("Frame", {
	Name = "Fill", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.ACCENT,
	BorderSizePixel = 0, Parent = reqBarBg,
})
corner(reqBarFill, 2)

local reqActions = new("Frame", {
	Name = "Actions", Size = UDim2.new(1, 0, 0, notifyCfg.btn),
	BackgroundTransparency = 1, LayoutOrder = 4, Parent = requestCard.root,
})
listLayout(reqActions, notifyCfg.gap, Enum.FillDirection.Horizontal)

local declineBtn = makeButton(reqActions, "Decline", "Decline", 1, false)
local acceptBtn  = makeButton(reqActions, "Accept",  "Accept",  2, true)
declineBtn.Size  = UDim2.new(0.5, -notifyCfg.gap / 2, 1, 0)
acceptBtn.Size   = UDim2.new(0.5, -notifyCfg.gap / 2, 1, 0)

local requestState = { onAccept = nil, onDecline = nil, barTween = nil, token = 0 }

local function layoutRequestHead()
	local x = notifyCfg.avatar + 10
	reqHead.Size     = UDim2.new(1, 0, 0, notifyCfg.avatar)
	reqAvatar.Size   = UDim2.new(0, notifyCfg.avatar, 0, notifyCfg.avatar)
	reqName.Position = UDim2.new(0, x, 0, math.floor(notifyCfg.avatar * 0.16))
	reqName.Size     = UDim2.new(1, -x, 0, notifyCfg.title + 4)
	reqName.TextSize = notifyCfg.title
	reqSub.Position  = UDim2.new(0, x, 0, math.floor(notifyCfg.avatar * 0.56))
	reqSub.Size      = UDim2.new(1, -x, 0, notifyCfg.small + 4)
	reqSub.TextSize  = notifyCfg.small
end
layoutRequestHead()

local function stopBar()
	if requestState.barTween then
		requestState.barTween:Cancel()
		requestState.barTween = nil
	end
end

function CarryUI.HideRequest()
	requestState.token    += 1
	requestState.onAccept  = nil
	requestState.onDecline = nil
	stopBar()
	showCard(requestCard, false)
end

function CarryUI.IsRequestVisible()
	return requestCard.root.Visible and requestCard.root.GroupTransparency < 0.5
end

function CarryUI.ShowRequest(fromPlayer, carryName, timeout, onAccept, onDecline)
	if not fromPlayer then return end

	requestState.token    += 1
	local token             = requestState.token
	requestState.onAccept   = onAccept
	requestState.onDecline  = onDecline

	local isInstance = typeof(fromPlayer) == "Instance"
	local userId     = (isInstance and fromPlayer.UserId) or 0

	reqAvatar.Image = (userId > 0)
		and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
		or ""
	reqName.Text = isInstance and (fromPlayer.DisplayName or fromPlayer.Name)
		or tostring(fromPlayer)
	reqSub.Text  = "wants to carry you"
	reqType.Text = tostring(carryName or "Carry")

	stopBar()
	reqBarFill.Size = UDim2.new(1, 0, 1, 0)

	local seconds    = tonumber(timeout) or 15
	reqBarBg.Visible = seconds > 0

	if seconds > 0 then
		requestState.barTween = TweenService:Create(reqBarFill,
			TweenInfo.new(seconds, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, 0, 1, 0) })
		requestState.barTween:Play()

		task.delay(seconds + 1, function()
			if requestState.token == token then CarryUI.HideRequest() end
		end)
	end

	closePlayerMenu()
	showCard(requestCard, true)
end

acceptBtn.Activated:Connect(function()
	local cb = requestState.onAccept
	CarryUI.HideRequest()
	if cb then task.spawn(cb) end
end)

declineBtn.Activated:Connect(function()
	local cb = requestState.onDecline
	CarryUI.HideRequest()
	if cb then task.spawn(cb) end
end)

-- ════════════════════════════════════════════════════════════
-- DROP CARD
-- ════════════════════════════════════════════════════════════

local dropCard = makeCard("DropCard", 2)

local dropStatus = new("TextLabel", {
	Name = "Status", Size = UDim2.new(1, 0, 0, notifyCfg.text + 4),
	BackgroundTransparency = 1, Text = "You are in a carry",
	TextColor3 = THEME.TEXT, Font = FONT.MEDIUM, TextSize = notifyCfg.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1, Parent = dropCard.root,
})

local dropHint = new("TextLabel", {
	Name = "Hint", Size = UDim2.new(1, 0, 0, notifyCfg.small + 3),
	BackgroundTransparency = 1, Text = "Tap stop to break free",
	TextColor3 = THEME.TEXT_DIM, Font = FONT.REGULAR, TextSize = notifyCfg.small,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2, Parent = dropCard.root,
})

local stopBtn = makeButton(dropCard.root, "StopCarry", "Stop carry", 3, false)
do
	local lbl = stopBtn:FindFirstChild("Label")
	local st  = stopBtn:FindFirstChild("Stroke")
	if lbl then lbl.TextColor3 = THEME.ACCENT; lbl.Font = FONT.BOLD end
	if st  then st.Color = THEME.ACCENT; st.Transparency = 0.6 end
end

local dropState = { onStop = nil }

function CarryUI.ShowDrop(statusText, onStop)
	dropState.onStop = onStop
	dropStatus.Text  = statusText or "You are in a carry"
	closePlayerMenu()
	showCard(dropCard, true)
end

function CarryUI.HideDrop()
	dropState.onStop = nil
	showCard(dropCard, false)
end

function CarryUI.IsDropVisible()
	return dropCard.root.Visible and dropCard.root.GroupTransparency < 0.5
end

stopBtn.Activated:Connect(function()
	local cb = dropState.onStop
	CarryUI.HideDrop()
	if cb then task.spawn(cb) end
end)

-- ════════════════════════════════════════════════════════════
-- TOAST — maksimal 3 di layar; kalau penuh, yang paling lama dipakai ulang
-- ════════════════════════════════════════════════════════════

local MAX_TOAST = 3
local toasts    = {}
local toastSeq  = 0

local function makeToast(order)
	local card = makeCard("Toast" .. order, 10 + order, THEME.CARD, notifyCfg.pad - 2)

	local title = new("TextLabel", {
		Name = "Title", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Text = "", TextColor3 = THEME.TEXT,
		Font = FONT.BOLD, TextSize = notifyCfg.small + 2, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = card.root,
	})

	local body = new("TextLabel", {
		Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Text = "", TextColor3 = THEME.TEXT_DIM,
		Font = FONT.REGULAR, TextSize = notifyCfg.small, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = card.root,
	})

	local entry = { card = card, title = title, body = body, token = 0, seq = 0, busy = false }
	table.insert(toasts, entry)
	return entry
end

local function acquireToast()
	for _, t in ipairs(toasts) do
		if not t.busy then return t end
	end
	if #toasts < MAX_TOAST then return makeToast(#toasts + 1) end

	local oldest = toasts[1]
	for _, t in ipairs(toasts) do
		if t.seq < oldest.seq then oldest = t end
	end
	return oldest
end

function CarryUI.Toast(title, text, duration)
	local t = acquireToast()

	t.token  += 1
	toastSeq += 1
	t.seq     = toastSeq
	t.busy    = true

	local token    = t.token
	t.title.Text   = tostring(title or "Carry")
	t.body.Text    = tostring(text or "")
	t.body.Visible = t.body.Text ~= ""

	closePlayerMenu()
	showCard(t.card, true)

	task.delay(tonumber(duration) or 3, function()
		if t.token ~= token then return end
		t.busy = false
		showCard(t.card, false)
	end)
end

-- ════════════════════════════════════════════════════════════
-- SELECT PANEL (jenis carry)
-- Nama GUI & hierarki dipertahankan ("CarrySelectGui" >
-- "CarrySelectFrame" > "ScrollingFrame" > "ButtonsFrame") supaya
-- UIManager.Init() dan InteractionLoad.isClickInsideMenu tetap kenal.
-- TIDAK terdampak fix kanan-tengah — tetap pakai `cfg` (bawah-tengah,
-- lebar selebar panel menu) seperti semula, karena ini dialog aktif yang
-- sengaja dibuka pemain, bukan notifikasi pasif.
-- ════════════════════════════════════════════════════════════

local selectGui = playerGui:FindFirstChild("CarrySelectGui")
if not selectGui then
	selectGui = new("ScreenGui", {
		Name = "CarrySelectGui", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 11,
		Enabled = false, Parent = playerGui,
	})
end
ThemeColor.mark(selectGui)
selectGui.Enabled = false

local oldSelectFrame = selectGui:FindFirstChild("CarrySelectFrame")
if oldSelectFrame then oldSelectFrame:Destroy() end

local selectFrame = new("Frame", {
	Name = "CarrySelectFrame", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -cfg.bottomInset),
	Size = UDim2.new(0, cfg.width, 0, cfg.height),
	BackgroundColor3 = THEME.BG, BorderSizePixel = 0, Active = true,
	ClipsDescendants = true, Parent = selectGui,
})
corner(selectFrame, 16)
stroke(selectFrame, THEME.LINE, 1, 0.88)

local selectTitle = new("TextLabel", {
	Name = "Title", BackgroundTransparency = 1, Text = "Choose carry",
	TextColor3 = THEME.ACCENT, Font = FONT.BOLD, TextSize = cfg.title,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = selectFrame,
})

local selectSub = new("TextLabel", {
	Name = "Subtitle", BackgroundTransparency = 1, Text = "Pick a carry type",
	TextColor3 = THEME.TEXT_DIM, Font = FONT.REGULAR, TextSize = cfg.small,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = selectFrame,
})

local selectClose = new("TextButton", {
	Name = "CloseButton", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8), Size = UDim2.new(0, 26, 0, 26),
	BackgroundTransparency = 1, Text = "X", TextColor3 = THEME.TEXT_DIM,
	Font = FONT.BOLD, TextSize = cfg.title, BorderSizePixel = 0,
	AutoButtonColor = false, ZIndex = 5, Parent = selectFrame,
})
selectClose.MouseEnter:Connect(function()
	TweenService:Create(selectClose, TWEEN_FAST, { TextColor3 = THEME.TEXT }):Play()
end)
selectClose.MouseLeave:Connect(function()
	TweenService:Create(selectClose, TWEEN_FAST, { TextColor3 = THEME.TEXT_DIM }):Play()
end)

local selectScroll = new("ScrollingFrame", {
	Name = "ScrollingFrame", BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.TEXT_DIM,
	ScrollBarImageTransparency = 0.5, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y, Parent = selectFrame,
})

local selectButtons = new("Frame", {
	Name = "ButtonsFrame", Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
	Parent = selectScroll,
})
local selectLayout = listLayout(selectButtons, cfg.gap - 2)
new("UIPadding", {
	PaddingBottom = UDim.new(0, 6), Parent = selectButtons,
})

local selectRows = {}

-- Baris carry: sama persis dengan baris aksi di MenuSystemInit
-- (CARD + corner 10 + stroke LINE 0.92 + bar accent saat hover).
local function makeSelectRow(title, order)
	local btn = new("TextButton", {
		Name = "Carry_" .. title, Size = UDim2.new(1, 0, 0, cfg.row),
		BackgroundColor3 = THEME.CARD, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", LayoutOrder = order, ClipsDescendants = true, Parent = selectButtons,
	})
	corner(btn, 10)
	local st = stroke(btn, THEME.LINE, 1, 0.92)

	local accent = new("Frame", {
		Name = "Accent", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 2, 0, 0),
		BackgroundColor3 = THEME.ACCENT, BorderSizePixel = 0, ZIndex = 2, Parent = btn,
	})
	corner(accent, 2)

	local label = new("TextLabel", {
		Name = "Label", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -28, 1, 0),
		BackgroundTransparency = 1, Text = title, TextColor3 = THEME.TEXT,
		Font = FONT.MEDIUM, TextSize = cfg.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
	})

	local function setHover(on)
		TweenService:Create(btn, TWEEN_FAST, {
			BackgroundColor3 = on and THEME.CARD_HOVER or THEME.CARD,
		}):Play()
		TweenService:Create(accent, TWEEN_FAST, {
			Size = on and UDim2.new(0, 2, 0.55, 0) or UDim2.new(0, 2, 0, 0),
		}):Play()
		TweenService:Create(st, TWEEN_FAST, { Transparency = on and 0.78 or 0.92 }):Play()
	end

	btn.MouseEnter:Connect(function() setHover(true)  end)
	btn.MouseLeave:Connect(function() setHover(false) end)
	btn.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then setHover(true) end
	end)
	btn.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch then setHover(false) end
	end)

	table.insert(selectRows, { button = btn, label = label })
	return btn
end

local function applySelectLayout()
	local headerH = cfg.title + cfg.small + 12
	local sideGap = cfg.pad * 2 + 30

	selectFrame.Size        = UDim2.new(0, cfg.width, 0, cfg.height)
	selectFrame.AnchorPoint = Vector2.new(0.5, 1)
	selectFrame.Position    = UDim2.new(0.5, 0, 1, -cfg.bottomInset)

	selectTitle.Position = UDim2.new(0, cfg.pad + 2, 0, cfg.pad)
	selectTitle.Size     = UDim2.new(1, -sideGap, 0, cfg.title + 4)
	selectTitle.TextSize = cfg.title
	selectSub.Position   = UDim2.new(0, cfg.pad + 2, 0, cfg.pad + cfg.title + 4)
	selectSub.Size       = UDim2.new(1, -sideGap, 0, cfg.small + 4)
	selectSub.TextSize   = cfg.small
	selectClose.TextSize = cfg.title

	selectScroll.Position = UDim2.new(0, cfg.pad, 0, cfg.pad + headerH)
	selectScroll.Size     = UDim2.new(1, -cfg.pad * 2, 1, -(cfg.pad * 2 + headerH))
	selectLayout.Padding  = UDim.new(0, cfg.gap - 2)

	for _, row in ipairs(selectRows) do
		row.button.Size    = UDim2.new(1, 0, 0, cfg.row)
		row.label.TextSize = cfg.text
	end
end
applySelectLayout()

function CarryUI.HideSelect()
	selectGui.Enabled = false
end

selectClose.Activated:Connect(CarryUI.HideSelect)

-- types: tabel { [key] = { title = "..." } } atau { "Nama", ... }
-- onPick: dipanggil dengan judul carry yang dipilih.
function CarryUI.ShowSelect(types, onPick)
	local titles = {}
	for key, data in pairs(types or {}) do
		local title = (type(data) == "table" and data.title) or (type(data) == "string" and data)
			or tostring(key)
		table.insert(titles, title)
	end
	table.sort(titles)

	if #titles == 0 then
		CarryUI.Toast("Carry", "Belum ada jenis carry yang termuat", 3)
		return false
	end

	for _, child in ipairs(selectButtons:GetChildren()) do
		if child:IsA("GuiButton") then child:Destroy() end
	end
	table.clear(selectRows)

	for i, title in ipairs(titles) do
		local btn = makeSelectRow(title, i)
		btn.Activated:Connect(function()
			CarryUI.HideSelect()
			if onPick then task.spawn(onPick, title) end
		end)
	end

	selectSub.Text = #titles == 1 and "1 carry type available"
		or (#titles .. " carry types available")

	applySelectLayout()
	selectGui.Enabled = true
	return true
end

function CarryUI.HideAll()
	CarryUI.HideRequest()
	CarryUI.HideDrop()
	CarryUI.HideSelect()
	for _, t in ipairs(toasts) do
		t.token += 1
		t.busy   = false
		showCard(t.card, false)
	end
end

-- ════════════════════════════════════════════════════════════
-- RESPONSIVE
-- ════════════════════════════════════════════════════════════

local function applyConfig(c, n)
	cfg       = c
	notifyCfg = n

	-- Stack (notif) — tetap kanan-tengah di ukuran layar baru manapun,
	-- naik dikit di mobile (yOffset) biar gak nabrak tombol sprint.
	stack.AnchorPoint   = Vector2.new(1, 0.5)
	stack.Size          = UDim2.new(0, n.width, 0, 0)
	stack.Position      = UDim2.new(1, -n.margin, 0.5, n.yOffset)
	stackLayout.Padding = UDim.new(0, n.gap)

	for _, card in ipairs({ requestCard, dropCard }) do
		card.pad.PaddingTop    = UDim.new(0, n.pad)
		card.pad.PaddingBottom = UDim.new(0, n.pad)
		card.pad.PaddingLeft   = UDim.new(0, n.pad)
		card.pad.PaddingRight  = UDim.new(0, n.pad)
		card.list.Padding      = UDim.new(0, n.gap - 2)
	end

	layoutRequestHead()
	reqPillRow.Size  = UDim2.new(1, 0, 0, n.small + 14)
	reqPill.Size     = UDim2.new(0, 0, 0, n.small + 14)
	reqType.TextSize = n.small + 1

	reqActions.Size = UDim2.new(1, 0, 0, n.btn)
	declineBtn.Size = UDim2.new(0.5, -n.gap / 2, 1, 0)
	acceptBtn.Size  = UDim2.new(0.5, -n.gap / 2, 1, 0)

	dropStatus.Size     = UDim2.new(1, 0, 0, n.text + 4)
	dropStatus.TextSize = n.text
	dropHint.Size       = UDim2.new(1, 0, 0, n.small + 3)
	dropHint.TextSize   = n.small

	for _, b in ipairs(buttons) do
		b.label.TextSize = n.text
		if b.button.Parent ~= reqActions then
			b.button.Size = UDim2.new(1, 0, 0, n.btn)
		end
	end

	for _, t in ipairs(toasts) do
		t.card.pad.PaddingTop    = UDim.new(0, n.pad - 2)
		t.card.pad.PaddingBottom = UDim.new(0, n.pad - 2)
		t.card.pad.PaddingLeft   = UDim.new(0, n.pad - 2)
		t.card.pad.PaddingRight  = UDim.new(0, n.pad - 2)
		t.title.TextSize = n.small + 2
		t.body.TextSize  = n.small
	end

	-- Select panel (bawah-tengah) tetap dihitung ulang dari `cfg`, terpisah
	-- dari metrik notif di atas.
	applySelectLayout()
end

Responsive.OnChange(function()
	if stack.Parent then applyConfig(getConfig(), getNotifyConfig()) end
end)

return CarryUI