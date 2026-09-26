-- CustomBackpackUI (LocalScript — StarterPlayerScripts)

local Players             = game:GetService("Players")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")
local StarterGui          = game:GetService("StarterGui")

local player   = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")

-- ══════════════════════════════════════════════════════════
-- SLOT ORDER (tool lain tetap muncul di inventory panel)
-- ══════════════════════════════════════════════════════════
local SLOT_ORDER = {
	"GlowStick",
	"Sign",
	"WaterGun",
	"Money Gun",
}

-- ══════════════════════════════════════════════════════════
-- WARNA
-- ══════════════════════════════════════════════════════════
local C = {
	BG          = Color3.fromRGB(14, 14, 14),
	SLOT_IDLE   = Color3.fromRGB(24, 22, 15),
	SLOT_ACT    = Color3.fromRGB(42, 35, 10),
	SLOT_HOVER  = Color3.fromRGB(32, 28, 12),
	BORDER      = Color3.fromRGB(55, 55, 55),
	BORDER_ACT  = Color3.fromRGB(195, 155, 35),
	GOLD        = Color3.fromRGB(195, 155, 35),
	TEXT_TOOL   = Color3.fromRGB(200, 200, 200),
	TEXT_NUM    = Color3.fromRGB(80, 70, 28),
	TEXT_DIM    = Color3.fromRGB(130, 125, 100),
	INV_BG      = Color3.fromRGB(14, 14, 14),
	INV_CELL    = Color3.fromRGB(24, 22, 15),
	INV_TITLE   = Color3.fromRGB(195, 155, 35),
	TIP_BG      = Color3.fromRGB(10, 10, 10),
	TIP_TEXT    = Color3.fromRGB(215, 215, 215),
	TIP_SUB     = Color3.fromRGB(100, 95, 50),
}

local SLOT_SIZE = 52
local GAP       = 5
local ICON_SIZE = 30

-- ══════════════════════════════════════════════════════════
-- DISABLE DEFAULT ROBLOX BACKPACK GUI
-- ══════════════════════════════════════════════════════════
local function disableDefault()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end

disableDefault()
task.spawn(function()
	for _ = 1, 10 do
		task.wait(0.1)
		disableDefault()
	end
end)

player.CharacterAdded:Connect(function()
	task.spawn(function()
		for _ = 1, 10 do
			task.wait(0.1)
			disableDefault()
		end
	end)
end)

-- ══════════════════════════════════════════════════════════
-- GUI SETUP
-- ══════════════════════════════════════════════════════════
local playerGui = player:WaitForChild("PlayerGui")
if playerGui:FindFirstChild("CustomBackpack") then
	playerGui.CustomBackpack:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name            = "CustomBackpack"
gui.ResetOnSpawn    = false
gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder    = 10
gui.IgnoreGuiInset  = false
gui.Parent          = playerGui

local BAR_H = SLOT_SIZE + GAP * 2

-- ══════════════════════════════════════════════════════════
-- HOTBAR FRAME
-- ══════════════════════════════════════════════════════════
local bar = Instance.new("Frame")
bar.Name                   = "HotBar"
bar.AnchorPoint            = Vector2.new(0.5, 1)
bar.Position               = UDim2.new(0.5, 0, 1, -10)
bar.Size                   = UDim2.new(0, 100, 0, BAR_H)
bar.BackgroundColor3       = C.BG
bar.BackgroundTransparency = 0.25
bar.BorderSizePixel        = 0
bar.Parent                 = gui
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)
local barStroke            = Instance.new("UIStroke", bar)
barStroke.Color            = C.GOLD
barStroke.Thickness        = 1
barStroke.Transparency     = 0.7

-- ══════════════════════════════════════════════════════════
-- TOMBOL INVENTORY (🎒)
-- ══════════════════════════════════════════════════════════
local invBtn = Instance.new("Frame")
invBtn.Name                   = "InvBtn"
invBtn.Size                   = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
invBtn.AnchorPoint            = Vector2.new(0, 0.5)
invBtn.Position               = UDim2.new(0, GAP, 0.5, 0) -- FIX: posisi awal sebelum rebuildHotbar
invBtn.BackgroundColor3       = Color3.fromRGB(20, 18, 10)
invBtn.BackgroundTransparency = 0.3
invBtn.BorderSizePixel        = 0
invBtn.Parent                 = bar
Instance.new("UICorner", invBtn).CornerRadius = UDim.new(0, 8)
local invBtnStroke            = Instance.new("UIStroke", invBtn)
invBtnStroke.Color            = C.GOLD
invBtnStroke.Thickness        = 1
invBtnStroke.Transparency     = 0.4

local invIconLbl = Instance.new("TextLabel", invBtn)
invIconLbl.Size                   = UDim2.new(1, 0, 0.65, 0)
invIconLbl.Position               = UDim2.new(0, 0, 0, 4)
invIconLbl.BackgroundTransparency = 1
invIconLbl.Text                   = "🎒"
invIconLbl.TextSize               = 20
invIconLbl.Font                   = Enum.Font.GothamBold
invIconLbl.TextXAlignment         = Enum.TextXAlignment.Center
invIconLbl.TextYAlignment         = Enum.TextYAlignment.Center
invIconLbl.ZIndex                 = 3

local invHintLbl = Instance.new("TextLabel", invBtn)
invHintLbl.Size                   = UDim2.new(1, 0, 0, 12)
invHintLbl.Position               = UDim2.new(0, 0, 1, -14)
invHintLbl.BackgroundTransparency = 1
invHintLbl.Text                   = "[ ` ]"
invHintLbl.TextColor3             = C.TEXT_NUM
invHintLbl.TextSize               = 7
invHintLbl.Font                   = Enum.Font.Gotham
invHintLbl.TextXAlignment         = Enum.TextXAlignment.Center
invHintLbl.ZIndex                 = 3

local invBtnClick = Instance.new("TextButton", invBtn)
invBtnClick.Size                   = UDim2.new(1, 0, 1, 0)
invBtnClick.BackgroundTransparency = 1
invBtnClick.Text                   = ""
invBtnClick.ZIndex                 = 10

-- ══════════════════════════════════════════════════════════
-- TOOLTIP
-- ══════════════════════════════════════════════════════════
local tip = Instance.new("Frame")
tip.Size                   = UDim2.new(0, 160, 0, 46)
tip.BackgroundColor3       = C.TIP_BG
tip.BackgroundTransparency = 0.1
tip.BorderSizePixel        = 0
tip.Visible                = false
tip.ZIndex                 = 80
tip.Parent                 = gui
Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 7)
local tipStroke            = Instance.new("UIStroke", tip)
tipStroke.Color            = C.GOLD
tipStroke.Thickness        = 1
tipStroke.Transparency     = 0.5

local tipName = Instance.new("TextLabel", tip)
tipName.Size                   = UDim2.new(1, -10, 0, 22)
tipName.Position               = UDim2.new(0, 7, 0, 4)
tipName.BackgroundTransparency = 1
tipName.TextColor3             = C.TIP_TEXT
tipName.TextSize               = 11
tipName.Font                   = Enum.Font.GothamBold
tipName.TextXAlignment         = Enum.TextXAlignment.Left
tipName.Text                   = ""

local tipSub = Instance.new("TextLabel", tip)
tipSub.Size                   = UDim2.new(1, -10, 0, 16)
tipSub.Position               = UDim2.new(0, 7, 0, 26)
tipSub.BackgroundTransparency = 1
tipSub.TextColor3             = C.TIP_SUB
tipSub.TextSize               = 9
tipSub.Font                   = Enum.Font.Gotham
tipSub.TextXAlignment         = Enum.TextXAlignment.Left
tipSub.Text                   = ""

-- ══════════════════════════════════════════════════════════
-- INVENTORY PANEL
-- ══════════════════════════════════════════════════════════
local invPanel = Instance.new("Frame")
invPanel.Name                   = "InventoryPanel"
invPanel.Size                   = UDim2.new(0, 360, 0, 320)
invPanel.AnchorPoint            = Vector2.new(0.5, 1)
invPanel.Position               = UDim2.new(0.5, 0, 1, -(BAR_H + 10 + 8))
invPanel.BackgroundColor3       = C.INV_BG
invPanel.BackgroundTransparency = 0.06
invPanel.BorderSizePixel        = 0
invPanel.Visible                = false
invPanel.ZIndex                 = 30
invPanel.Parent                 = gui
Instance.new("UICorner", invPanel).CornerRadius = UDim.new(0, 12)
local invPanelStroke            = Instance.new("UIStroke", invPanel)
invPanelStroke.Color            = C.GOLD
invPanelStroke.Thickness        = 1
invPanelStroke.Transparency     = 0.4

local invHeader = Instance.new("Frame", invPanel)
invHeader.Size                   = UDim2.new(1, 0, 0, 38)
invHeader.BackgroundColor3       = Color3.fromRGB(20, 17, 7)
invHeader.BackgroundTransparency = 0.1
invHeader.BorderSizePixel        = 0
invHeader.ZIndex                 = 31
Instance.new("UICorner", invHeader).CornerRadius = UDim.new(0, 12)

local invHeaderFix = Instance.new("Frame", invPanel)
invHeaderFix.Size                   = UDim2.new(1, 0, 0, 12)
invHeaderFix.Position               = UDim2.new(0, 0, 0, 26)
invHeaderFix.BackgroundColor3       = Color3.fromRGB(20, 17, 7)
invHeaderFix.BackgroundTransparency = 0.1
invHeaderFix.BorderSizePixel        = 0
invHeaderFix.ZIndex                 = 31

local invHeaderLbl = Instance.new("TextLabel", invHeader)
invHeaderLbl.Size                   = UDim2.new(1, -12, 1, 0)
invHeaderLbl.Position               = UDim2.new(0, 12, 0, 0)
invHeaderLbl.BackgroundTransparency = 1
invHeaderLbl.Text                   = "🎒  Inventory"
invHeaderLbl.TextColor3             = C.INV_TITLE
invHeaderLbl.TextSize               = 13
invHeaderLbl.Font                   = Enum.Font.GothamBold
invHeaderLbl.TextXAlignment         = Enum.TextXAlignment.Left
invHeaderLbl.ZIndex                 = 32

local invCloseLbl = Instance.new("TextLabel", invHeader)
invCloseLbl.Size                   = UDim2.new(0, 90, 1, 0)
invCloseLbl.Position               = UDim2.new(1, -95, 0, 0)
invCloseLbl.BackgroundTransparency = 1
invCloseLbl.Text                   = "[ ` ] tutup"
invCloseLbl.TextColor3             = Color3.fromRGB(70, 65, 35)
invCloseLbl.TextSize               = 9
invCloseLbl.Font                   = Enum.Font.Gotham
invCloseLbl.TextXAlignment         = Enum.TextXAlignment.Right
invCloseLbl.ZIndex                 = 32

local invDiv = Instance.new("Frame", invPanel)
invDiv.Size                   = UDim2.new(1, -16, 0, 1)
invDiv.Position               = UDim2.new(0, 8, 0, 39)
invDiv.BackgroundColor3       = C.GOLD
invDiv.BackgroundTransparency = 0.5
invDiv.BorderSizePixel        = 0
invDiv.ZIndex                 = 32

local invCountLbl = Instance.new("TextLabel", invPanel)
invCountLbl.Size                   = UDim2.new(1, -16, 0, 14)
invCountLbl.Position               = UDim2.new(0, 12, 0, 42)
invCountLbl.BackgroundTransparency = 1
invCountLbl.Text                   = ""
invCountLbl.TextColor3             = Color3.fromRGB(70, 65, 35)
invCountLbl.TextSize               = 9
invCountLbl.Font                   = Enum.Font.Gotham
invCountLbl.TextXAlignment         = Enum.TextXAlignment.Left
invCountLbl.ZIndex                 = 32

local invScroll = Instance.new("ScrollingFrame", invPanel)
invScroll.Size                   = UDim2.new(1, -10, 1, -62)
invScroll.Position               = UDim2.new(0, 5, 0, 57)
invScroll.BackgroundTransparency = 1
invScroll.BorderSizePixel        = 0
invScroll.ScrollBarThickness     = 3
invScroll.ScrollBarImageColor3   = C.GOLD
invScroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
invScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
invScroll.ZIndex                 = 31

local invGrid = Instance.new("UIGridLayout", invScroll)
invGrid.CellSize            = UDim2.new(0, 68, 0, 82)
invGrid.CellPadding         = UDim2.new(0, 6, 0, 6)
invGrid.SortOrder           = Enum.SortOrder.LayoutOrder
invGrid.StartCorner         = Enum.StartCorner.TopLeft
invGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left

local invPad = Instance.new("UIPadding", invScroll)
invPad.PaddingLeft   = UDim.new(0, 4)
invPad.PaddingTop    = UDim.new(0, 4)
invPad.PaddingBottom = UDim.new(0, 8)
invPad.PaddingRight  = UDim.new(0, 4)

-- ══════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════
local activeSlot = nil
local slotFrames = {}
local invOpen    = false

-- ══════════════════════════════════════════════════════════
-- HELPERS
-- ══════════════════════════════════════════════════════════
local function findTool(name)
	if not name or name == "" then return nil end
	return backpack:FindFirstChild(name)
		or (player.Character and player.Character:FindFirstChild(name))
end

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function getAllToolsSorted()
	local result = {}
	local seen   = {}

	for _, name in ipairs(SLOT_ORDER) do
		local t = findTool(name)
		if t and not seen[t.Name] then
			table.insert(result, t)
			seen[t.Name] = true
		end
	end

	local bpChildren = backpack:GetChildren()
	table.sort(bpChildren, function(a, b) return a.Name < b.Name end)
	for _, child in ipairs(bpChildren) do
		if child:IsA("Tool") and not seen[child.Name] then
			table.insert(result, child)
			seen[child.Name] = true
		end
	end

	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and not seen[child.Name] then
				table.insert(result, child)
				seen[child.Name] = true
			end
		end
	end

	return result
end

-- ══════════════════════════════════════════════════════════
-- EQUIP TOGGLE
-- ══════════════════════════════════════════════════════════
local function equipToggle(toolName)
	local hum = getHumanoid()
	if not hum then return end

	if activeSlot == toolName then
		activeSlot = nil
		hum:UnequipTools()
	else
		activeSlot = toolName
		hum:UnequipTools()
		task.wait(0.05)
		local t = backpack:FindFirstChild(toolName)
		if t then hum:EquipTool(t) end
	end
end

-- ══════════════════════════════════════════════════════════
-- REBUILD INVENTORY PANEL
-- ══════════════════════════════════════════════════════════
local function rebuildInventory()
	for _, child in ipairs(invScroll:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local tools = getAllToolsSorted()
	invCountLbl.Text = #tools > 0 and (#tools .. " item") or ""

	if #tools == 0 then
		local empty = Instance.new("TextLabel", invScroll)
		empty.Size                   = UDim2.new(0, 320, 0, 80)
		empty.BackgroundTransparency = 1
		empty.Text                   = "Inventory kosong"
		empty.TextColor3             = Color3.fromRGB(60, 58, 35)
		empty.TextSize               = 12
		empty.Font                   = Enum.Font.Gotham
		empty.TextXAlignment         = Enum.TextXAlignment.Center
		empty.TextYAlignment         = Enum.TextYAlignment.Center
		empty.LayoutOrder            = 999
		empty.ZIndex                 = 32
		return
	end

	for order, tool in ipairs(tools) do
		local tName = tool.Name
		local isAct = (tName == activeSlot)

		local cell = Instance.new("Frame", invScroll)
		cell.Size                   = UDim2.new(0, 68, 0, 82)
		cell.BackgroundColor3       = isAct and C.SLOT_ACT or C.INV_CELL
		cell.BackgroundTransparency = isAct and 0.06 or 0.32
		cell.BorderSizePixel        = 0
		cell.LayoutOrder            = order
		cell.ZIndex                 = 32
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 8)

		local cs = Instance.new("UIStroke", cell)
		cs.Color        = isAct and C.BORDER_ACT or C.BORDER
		cs.Thickness    = isAct and 1.5 or 0.6
		cs.Transparency = isAct and 0 or 0.6

		if isAct then
			local topLine = Instance.new("Frame", cell)
			topLine.Size                   = UDim2.new(0.6, 0, 0, 2)
			topLine.Position               = UDim2.new(0.2, 0, 0, 2)
			topLine.BackgroundColor3       = C.GOLD
			topLine.BackgroundTransparency = 0
			topLine.BorderSizePixel        = 0
			topLine.ZIndex                 = 34
			Instance.new("UICorner", topLine).CornerRadius = UDim.new(1, 0)
		end

		local tex = tool.TextureId
		if tex ~= "" and tex ~= "rbxassetid://0" then
			local ico = Instance.new("ImageLabel", cell)
			ico.Size                   = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
			ico.Position               = UDim2.new(0.5, -ICON_SIZE/2, 0, 10)
			ico.BackgroundTransparency = 1
			ico.ScaleType              = Enum.ScaleType.Fit
			ico.Image                  = tex
			ico.ImageTransparency      = isAct and 0 or 0.05
			ico.ZIndex                 = 33
		else
			local tlbl = Instance.new("TextLabel", cell)
			tlbl.Size                   = UDim2.new(1, -4, 0, ICON_SIZE)
			tlbl.Position               = UDim2.new(0, 2, 0, 10)
			tlbl.BackgroundTransparency = 1
			tlbl.Text                   = tName
			tlbl.TextColor3             = isAct and C.TEXT_TOOL or C.TEXT_DIM
			tlbl.TextSize               = 7
			tlbl.Font                   = Enum.Font.GothamBold
			tlbl.TextWrapped            = true
			tlbl.TextXAlignment         = Enum.TextXAlignment.Center
			tlbl.TextYAlignment         = Enum.TextYAlignment.Center
			tlbl.ZIndex                 = 33
		end

		local nameLbl = Instance.new("TextLabel", cell)
		nameLbl.Size                   = UDim2.new(1, -4, 0, 24)
		nameLbl.Position               = UDim2.new(0, 2, 1, -26)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text                   = tName
		nameLbl.TextColor3             = isAct and C.GOLD or C.TEXT_DIM
		nameLbl.TextSize               = 7
		nameLbl.Font                   = Enum.Font.GothamBold
		nameLbl.TextWrapped            = true
		nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
		nameLbl.TextXAlignment         = Enum.TextXAlignment.Center
		nameLbl.ZIndex                 = 33

		local cbtn = Instance.new("TextButton", cell)
		cbtn.Size                   = UDim2.new(1, 0, 1, 0)
		cbtn.BackgroundTransparency = 1
		cbtn.Text                   = ""
		cbtn.ZIndex                 = 35

		local capturedName = tName
		cbtn.MouseButton1Click:Connect(function()
			equipToggle(capturedName)
			task.wait(0.06)
			rebuildInventory()
		end)

		cbtn.MouseEnter:Connect(function()
			if capturedName ~= activeSlot then
				TweenService:Create(cell, TweenInfo.new(0.08), {
					BackgroundColor3       = C.SLOT_HOVER,
					BackgroundTransparency = 0.18,
				}):Play()
			end
		end)

		cbtn.MouseLeave:Connect(function()
			if capturedName ~= activeSlot then
				TweenService:Create(cell, TweenInfo.new(0.08), {
					BackgroundColor3       = C.INV_CELL,
					BackgroundTransparency = 0.32,
				}):Play()
			end
		end)
	end
end

-- ══════════════════════════════════════════════════════════
-- TOGGLE INVENTORY
-- ══════════════════════════════════════════════════════════
local function toggleInventory()
	invOpen = not invOpen
	if invOpen then
		rebuildInventory()
		invPanel.Visible          = true
		invBtnStroke.Transparency = 0.02
		TweenService:Create(invBtn, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(40, 32, 8),
		}):Play()
	else
		invPanel.Visible          = false
		invBtnStroke.Transparency = 0.4
		TweenService:Create(invBtn, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(20, 18, 10),
		}):Play()
	end
end

-- ══════════════════════════════════════════════════════════
-- REBUILD HOTBAR
-- ══════════════════════════════════════════════════════════
local function rebuildHotbar()
	for _, s in ipairs(slotFrames) do
		if s.frame and s.frame.Parent then s.frame:Destroy() end
	end
	slotFrames = {}

	local visible = {}
	for _, name in ipairs(SLOT_ORDER) do
		if findTool(name) then table.insert(visible, name) end
	end

	local totalW = GAP + #visible * (SLOT_SIZE + GAP) + SLOT_SIZE + GAP
	bar.Size     = UDim2.new(0, totalW, 0, BAR_H)

	-- FIX: tombol 🎒 di kanan slots
	invBtn.Position = UDim2.new(0, GAP + #visible * (SLOT_SIZE + GAP), 0.5, 0)

	for i, toolName in ipairs(visible) do
		local isAct = (toolName == activeSlot)
		local tool  = findTool(toolName)

		local f = Instance.new("Frame")
		f.Size                   = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		f.Position               = UDim2.new(0, GAP + (i-1)*(SLOT_SIZE+GAP), 0, GAP)
		f.BackgroundColor3       = isAct and C.SLOT_ACT or C.SLOT_IDLE
		f.BackgroundTransparency = isAct and 0.05 or 0.32
		f.BorderSizePixel        = 0
		f.ZIndex                 = 2
		f.Parent                 = bar
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)

		local stroke = Instance.new("UIStroke", f)
		stroke.Color        = isAct and C.BORDER_ACT or C.BORDER
		stroke.Thickness    = isAct and 1.5 or 0.7
		stroke.Transparency = isAct and 0 or 0.6

		local indicator = Instance.new("Frame", f)
		indicator.Size                   = UDim2.new(0.55, 0, 0, 2)
		indicator.Position               = UDim2.new(0.225, 0, 1, -3)
		indicator.BackgroundColor3       = C.GOLD
		indicator.BackgroundTransparency = isAct and 0 or 1
		indicator.BorderSizePixel        = 0
		indicator.ZIndex                 = 4
		Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

		local num = Instance.new("TextLabel", f)
		num.Size                   = UDim2.new(0, 14, 0, 12)
		num.Position               = UDim2.new(0, 3, 0, 3)
		num.BackgroundTransparency = 1
		num.Text                   = tostring(i)
		num.TextColor3             = C.TEXT_NUM
		num.TextSize               = 7
		num.Font                   = Enum.Font.GothamBold
		num.ZIndex                 = 5

		local tex = tool and tool.TextureId or ""
		if tex ~= "" and tex ~= "rbxassetid://0" then
			local ico = Instance.new("ImageLabel", f)
			ico.Size                   = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
			ico.Position               = UDim2.new(0.5, -ICON_SIZE/2, 0.5, -ICON_SIZE/2)
			ico.BackgroundTransparency = 1
			ico.Image                  = tex
			ico.ScaleType              = Enum.ScaleType.Fit
			ico.ImageTransparency      = isAct and 0 or 0.08
			ico.ZIndex                 = 3
		else
			local lbl = Instance.new("TextLabel", f)
			lbl.Size                   = UDim2.new(1, -4, 0.6, 0)
			lbl.Position               = UDim2.new(0, 2, 0.15, 0)
			lbl.BackgroundTransparency = 1
			lbl.Text                   = toolName
			lbl.TextColor3             = isAct and C.TEXT_TOOL or C.TEXT_DIM
			lbl.TextSize               = 8
			lbl.Font                   = Enum.Font.GothamBold
			lbl.TextWrapped            = true
			lbl.TextXAlignment         = Enum.TextXAlignment.Center
			lbl.TextYAlignment         = Enum.TextYAlignment.Center
			lbl.ZIndex                 = 3
		end

		local btn = Instance.new("TextButton", f)
		btn.Size                   = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text                   = ""
		btn.ZIndex                 = 10

		local capturedName = toolName
		local capturedIdx  = i

		btn.MouseButton1Click:Connect(function()
			equipToggle(capturedName)
			task.wait(0.06)
			rebuildHotbar()
			if invOpen then rebuildInventory() end
		end)

		btn.MouseEnter:Connect(function()
			if capturedName ~= activeSlot then
				TweenService:Create(f, TweenInfo.new(0.08), {
					BackgroundColor3       = C.SLOT_HOVER,
					BackgroundTransparency = 0.18,
				}):Play()
			end
			local t2 = findTool(capturedName)
			if t2 then
				tipName.Text = t2.Name
				tipSub.Text  = (t2.ToolTip ~= "") and t2.ToolTip
					or "Klik atau tekan [" .. capturedIdx .. "]"
				local abs    = f.AbsolutePosition
				tip.Position = UDim2.new(0, abs.X - 4, 0, abs.Y - 54)
				tip.Visible  = true
			end
		end)

		btn.MouseLeave:Connect(function()
			if capturedName ~= activeSlot then
				TweenService:Create(f, TweenInfo.new(0.08), {
					BackgroundColor3       = C.SLOT_IDLE,
					BackgroundTransparency = 0.32,
				}):Play()
			end
			tip.Visible = false
		end)

		table.insert(slotFrames, { toolName = toolName, frame = f })
	end
end

-- ══════════════════════════════════════════════════════════
-- INVENTORY BUTTON EVENTS
-- ══════════════════════════════════════════════════════════
invBtnClick.MouseButton1Click:Connect(toggleInventory)

invBtnClick.MouseEnter:Connect(function()
	TweenService:Create(invBtn, TweenInfo.new(0.08), { BackgroundTransparency = 0.1 }):Play()
	tipName.Text = "Inventory"
	tipSub.Text  = "[ ` ] buka / tutup"
	local abs    = invBtn.AbsolutePosition
	tip.Position = UDim2.new(0, abs.X - 4, 0, abs.Y - 54)
	tip.Visible  = true
end)

invBtnClick.MouseLeave:Connect(function()
	if not invOpen then
		TweenService:Create(invBtn, TweenInfo.new(0.08), { BackgroundTransparency = 0.3 }):Play()
	end
	tip.Visible = false
end)

-- ══════════════════════════════════════════════════════════
-- KEYBOARD INPUT
-- Tilde (~) : toggle inventory — gp SENGAJA diabaikan.
--   Di Studio gp=true (dev console intercept), di production
--   gp=false. Keduanya harus bisa buka inventory.
-- 1–9       : equip hotbar slot
-- ══════════════════════════════════════════════════════════
local numKeys = {
	[Enum.KeyCode.One]=1,   [Enum.KeyCode.Two]=2,
	[Enum.KeyCode.Three]=3, [Enum.KeyCode.Four]=4,
	[Enum.KeyCode.Five]=5,  [Enum.KeyCode.Six]=6,
	[Enum.KeyCode.Seven]=7, [Enum.KeyCode.Eight]=8,
	[Enum.KeyCode.Nine]=9,
}

UserInputService.InputBegan:Connect(function(input, gp)
	-- Tilde: selalu toggle, abaikan gp agar works di Studio & production
	if input.KeyCode == Enum.KeyCode.Tilde then
		toggleInventory()
		return
	end

	if gp then return end

	local idx = numKeys[input.KeyCode]
	if not idx then return end

	local visible = {}
	for _, name in ipairs(SLOT_ORDER) do
		if findTool(name) then table.insert(visible, name) end
	end
	local tName = visible[idx]
	if not tName then return end

	equipToggle(tName)
	task.wait(0.06)
	rebuildHotbar()
	if invOpen then rebuildInventory() end
end)

-- ══════════════════════════════════════════════════════════
-- SCROLL WHEEL CYCLING
-- ══════════════════════════════════════════════════════════
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end

	local visible = {}
	for _, name in ipairs(SLOT_ORDER) do
		if findTool(name) then table.insert(visible, name) end
	end
	if #visible == 0 then return end

	local cur = 0
	for i, n in ipairs(visible) do if n == activeSlot then cur = i end end

	local nxt = cur + (input.Position.Z > 0 and -1 or 1)
	if nxt < 1 then nxt = #visible elseif nxt > #visible then nxt = 1 end

	local hum = getHumanoid()
	if not hum then return end

	activeSlot = visible[nxt]
	hum:UnequipTools()
	task.wait(0.05)
	local t = backpack:FindFirstChild(activeSlot)
	if t then hum:EquipTool(t) end
	task.wait(0.05)
	rebuildHotbar()
	if invOpen then rebuildInventory() end
end)

-- ══════════════════════════════════════════════════════════
-- AUTO REFRESH — watch backpack & karakter
-- ══════════════════════════════════════════════════════════
local debounce = false
local function scheduleRefresh()
	if debounce then return end
	debounce = true
	task.delay(0.15, function()
		debounce = false
		rebuildHotbar()
		if invOpen then rebuildInventory() end
	end)
end

backpack.ChildAdded:Connect(scheduleRefresh)
backpack.ChildRemoved:Connect(function(child)
	if child:IsA("Tool") then
		task.wait(0.06)
		if not findTool(child.Name) and activeSlot == child.Name then
			activeSlot = nil
		end
		scheduleRefresh()
	end
end)

local function watchChar(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then scheduleRefresh() end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			task.wait(0.06)
			if not findTool(c.Name) and activeSlot == c.Name then activeSlot = nil end
			scheduleRefresh()
		end
	end)
end

player.CharacterAdded:Connect(function(char)
	activeSlot       = nil
	invOpen          = false
	invPanel.Visible = false
	task.wait(0.3)
	disableDefault()
	task.wait(0.3)
	watchChar(char)
	rebuildHotbar()
	-- Safety: rebuild lagi 2 detik kemudian setelah ToolGiver selesai
	task.delay(2, function()
		rebuildHotbar()
		if invOpen then rebuildInventory() end
	end)
end)

if player.Character then
	watchChar(player.Character)
end

-- ══════════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════════
-- wait 2s: kasih waktu ToolGiver & ShopServer selesai ngasih tools
task.wait(2)
disableDefault()
rebuildHotbar()

-- Safety rebuild 2 detik kemudian untuk tool giver yang lambat
task.delay(2, function()
	rebuildHotbar()
	if invOpen then rebuildInventory() end
end)