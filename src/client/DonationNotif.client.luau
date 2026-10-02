-- StarterPlayerScripts/DonationNotif  (LocalScript)
-- Notifikasi donasi untuk semua pemain, tata letak kartu (avatar kiri, "TERIMA KASIH!", nama + ikon Robux,
-- pesan donatur) dengan warna tema menu HAVN. Data dari DonationServer lewat
-- DonationMessageSystem.ShowMessage(displayName, username, robux, message, userId, gold) — pesan sudah difilter server.
-- robux 0 = donasi luar (bagibagi): nominal poin GOLD (bukan Rupiah), tanpa @akun.
-- Maksimal 3 kartu tampil, sisanya antre; lama tampil per tier (DonationConfig.tiers[].notif).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenSvc = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(RS:WaitForChild("DonationConfig"))
local ThemeColor = require(RS:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local folder = RS:WaitForChild("DonationMessageSystem", 30)
local showMessage = folder and folder:WaitForChild("ShowMessage", 30)
if not showMessage then
	warn("[Donation] ShowMessage tidak ditemukan, notifikasi donasi tidak aktif")
	return
end

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
local ROBUX = utf8.char(0xE002)
local WIDTH = 380
local MAX_VISIBLE = 3
local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DEFAULT_SECONDS = 6

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
local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 100 or vp.Y < 100 then
		return Vector2.new(1280, 720)
	end
	return vp
end
local function top()
	if _G.TopbarLayout and _G.TopbarLayout.contentTop then
		local ok, v = pcall(_G.TopbarLayout.contentTop)
		if ok and type(v) == "number" then
			return v + 8
		end
	end
	return 72
end

local gui = new("ScreenGui", { Name = "DonationNotifGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 55, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
ThemeColor.mark(gui)
local holder = new("Frame", { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y, Parent = gui })
new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })

local function layout()
	local w = math.min(WIDTH, viewport().X - 24)
	holder.Size = UDim2.new(0, w, 0, 0)
	holder.Position = UDim2.new(0.5, 0, 0, top())
end
layout()

local function durationFor(robux)
	local best = DEFAULT_SECONDS
	for _, tier in Config.tiers do
		if robux >= tier.robux and tier.notif then
			best = tier.notif
		end
	end
	return best
end

local visible, queue, order = 0, {}, 0

local function card(d)
	order += 1
	local c = new("CanvasGroup", { Name = "Notif", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.BG, BackgroundTransparency = 0.1,
		GroupTransparency = 1, Parent = holder })
	new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = c })
	new("UIStroke", { Color = T.ACCENT, Thickness = 1.5, Transparency = 0.2, Parent = c })
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12), Parent = c })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
	local avatar = new("ImageLabel", { Name = "Avatar", LayoutOrder = 1, Size = UDim2.new(0, 46, 0, 46),
		BackgroundColor3 = T.CARD,
		Image = (d.userId and d.userId > 0) and ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(d.userId) or "",
		Parent = c })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = avatar })
	new("UIStroke", { Color = T.ACCENT, Thickness = 1.5, Transparency = 0.3, Parent = avatar })
	local text = new("Frame", { Name = "TextHolder", LayoutOrder = 2, Size = UDim2.new(1, -58, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = c })
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = text })
	new("TextLabel", { Name = "NTitle", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1,
		Text = "TERIMA KASIH!", Font = FONT.BOLD, TextSize = 18, TextColor3 = T.ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = text })
	new("TextLabel", { Name = "NBody", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = d.robux > 0 and ("%s (@%s) donated %s %d"):format(d.display, d.name, ROBUX, d.robux)
			or d.gold > 0 and ("%s donated %s GOLD"):format(d.display, (tostring(d.gold):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")))
			or (d.display .. " sent support " .. utf8.char(0x2764)),
		Font = FONT.MEDIUM, TextSize = 15, TextColor3 = T.TEXT, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = text })
	if d.message ~= "" then
		new("TextLabel", { Name = "NMsg", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Text = "\"" .. d.message .. "\"", Font = FONT.REGULAR, TextSize = 14,
			TextColor3 = T.TEXT_DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = text })
	end
	return c
end

local show
local function nextInQueue()
	while visible < MAX_VISIBLE and #queue > 0 do
		show(table.remove(queue, 1))
	end
end
show = function(d)
	visible += 1
	layout()
	local c = card(d)
	TweenSvc:Create(c, FADE, { GroupTransparency = 0 }):Play()
	task.delay(durationFor(d.robux), function()
		TweenSvc:Create(c, FADE, { GroupTransparency = 1 }):Play()
		task.delay(0.35, function()
			c:Destroy()
			visible -= 1
			nextInQueue()
		end)
	end)
end

showMessage.OnClientEvent:Connect(function(display, name, robux, message, userId, gold)
	local d = {
		display = typeof(display) == "string" and display or "?",
		name = typeof(name) == "string" and name or "?",
		robux = math.floor(tonumber(robux) or 0),
		message = typeof(message) == "string" and message or "",
		userId = tonumber(userId),
		gold = math.max(0, math.floor(tonumber(gold) or 0)),
	}
	table.insert(queue, d)
	nextInQueue()
end)
