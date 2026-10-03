-- Sign UI | LocalScript → Sign Tool (dalam Tool, bukan StarterGui)
-- RemoteEvent, BGColor, TextColor harus jadi children dari LocalScript ini
-- Depends on: DynamicTools System
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Warna UI panel: ReplicatedStorage.Modules.ThemeColor (themeColor) — T.X dibaca saat buildUI (tiap tool di-equip).
-- Warna sign (BG_COLORS/TEXT_COLORS) = KONTEN → literal + grid swatch di-skip.
local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))
local T = ThemeColor.tokens

local MAX_RETRIES = 100
local RETRY_DELAY = 0.15
local TOOL_NAME   = "Sign"

-- RemoteEvents (children dari script ini, sesuai struktur asli)
local remoteText    = script:WaitForChild("RemoteEvent")
local remoteBG      = script:WaitForChild("BGColor")
local remoteTextClr = script:WaitForChild("TextColor")

local BANNED = {
	"anjing","asu","babi","monyet","kontol","peler","payudara","memek","momok",
	"vagina","ngentot","ngentod","ngen","venis","anjeng","kondom","tai","fuck",
	"ciuman","dick","pussy","bitch","sex","boobs","pusy","puki","pepek","ppk",
	"ngewe","kentu","kenthu","nigga","nigger","whore","bbik","lonte","kntl",
	"mmk","knjt","kanjut","heuncet","jembut","tytyd","nenen","tete","pler",
	"toket","sepong","spong","bokep","engas","sagapung","sange","kokop","kulum",
	"gangbang","emut","peju","jancok","jnck","cock","penis","suck","coli",
	"jilmek","crot","bego","idiot","doggystyle","galer","butu","kocokin",
	"dikocokin","ngocok","pantat","bokong","diemut","bool","goblog","tolol",
	"sodok","disodokin","anjink","rodo","dongo","dirodo","dildo","lolok",
	"nungging","rodho","shit","cium","jokowi","prabowo","damn","dicipok",
	"cipok","cukimai","cukimay","telaso","pukimai","pukimay","69","seks",
	"gacor","maxwin","judol","entot","entod","dientot","dientod","cokil",
	"bloon","lobano","bacot","bct","lancao","lanjiao","dibungkus","koncet",
	"digencet","konjket","lc","sabu","nyabu","ewe","ngangkang","ngaceng",
	"ngtd","diewe","gangbank","gankbang","gankbank","threesome","foursome",
	"lesbi","gay","queer","lgbt","dihamilin","hamilin","becek","kobel",
	"ludahin","kentod","kentot","tobrut","tocil","tepos","tae","seggs",
	"kuy","kak",
}

local BG_COLORS = {
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(0,   0,   0  ),
	Color3.fromRGB(255, 0,   0  ), Color3.fromRGB(0,   200, 0  ),
	Color3.fromRGB(0,   0,   255), Color3.fromRGB(255, 255, 0  ),
	Color3.fromRGB(255, 128, 0  ), Color3.fromRGB(128, 0,   255),
}

local TEXT_COLORS = {
	Color3.fromRGB(0,   0,   0  ), Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 0,   0  ), Color3.fromRGB(0,   200, 0  ),
	Color3.fromRGB(0,   100, 255), Color3.fromRGB(255, 220, 0  ),
	Color3.fromRGB(255, 128, 0  ), Color3.fromRGB(200, 0,   200),
}

local State = { connections = {} }

local function conn(sig, fn)
	table.insert(State.connections, sig:Connect(fn))
end

local function disconnectAll()
	for _, c in ipairs(State.connections) do pcall(c.Disconnect, c) end
	table.clear(State.connections)
end

local function isBanned(text)
	local lower = text:lower()
	for _, w in ipairs(BANNED) do
		if lower:find(w, 1, true) then return true end
	end
	return false
end

-- ── Color Grid ────────────────────────────────────────────
local function makeColorGrid(labelText, colors, remote, order, parent)
	local section = Instance.new("Frame")
	section.Size            = UDim2.new(1, 0, 0, 0)
	section.AutomaticSize  = Enum.AutomaticSize.Y
	section.BackgroundColor3 = T.CARD
	section.BorderSizePixel = 0
	section.LayoutOrder     = order
	section.Parent          = parent

	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 8); sc.Parent = section

	local sp = Instance.new("UIPadding")
	sp.PaddingLeft   = UDim.new(0, 8); sp.PaddingRight  = UDim.new(0, 8)
	sp.PaddingTop    = UDim.new(0, 8); sp.PaddingBottom = UDim.new(0, 8)
	sp.Parent        = section

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Padding   = UDim.new(0, 6)
	sectionLayout.Parent    = section

	local lbl = Instance.new("TextLabel")
	lbl.Size               = UDim2.new(1, 0, 0, 18)
	lbl.BackgroundTransparency = 1
	lbl.Text               = labelText
	lbl.TextColor3         = T.TEXT_DIM
	lbl.TextSize           = 13
	lbl.Font               = Enum.Font.GothamBold
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.LayoutOrder        = 0
	lbl.Parent             = section

	local grid = Instance.new("Frame")
	grid.Size               = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize      = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.LayoutOrder        = 1
	grid.Parent             = section
	ThemeColor.skip(grid) -- swatch warna sign = konten

	local gl = Instance.new("UIGridLayout")
	gl.CellSize            = UDim2.new(0, 32, 0, 32)
	gl.CellPadding         = UDim2.new(0, 5, 0, 5)
	gl.SortOrder           = Enum.SortOrder.LayoutOrder
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gl.Parent              = grid

	for i, color in ipairs(colors) do
		local btn = Instance.new("TextButton")
		btn.Size            = UDim2.new(1, 0, 1, 0)
		btn.BackgroundColor3= color
		btn.BorderSizePixel = 0
		btn.Text            = ""
		btn.LayoutOrder     = i
		btn.Parent          = grid

		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color       = Color3.fromRGB(255, 255, 255)
		stroke.Thickness   = 0
		stroke.Transparency= 0.5
		stroke.Parent      = btn

		conn(btn.MouseEnter, function() stroke.Thickness = 2 end)
		conn(btn.MouseLeave, function() stroke.Thickness = 0 end)
		conn(btn.Activated,  function() remote:FireServer(color) end)
	end
end

-- ── Build UI ──────────────────────────────────────────────
local function buildUI()
	disconnectAll()

	local main = Instance.new("Frame")
	main.Name            = "SignSettings"
	main.Size            = UDim2.new(1, 0, 0, 0)
	main.AutomaticSize   = Enum.AutomaticSize.Y
	main.BackgroundTransparency = 1

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 8)
	layout.Parent    = main

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 10); pad.PaddingRight  = UDim.new(0, 10)
	pad.PaddingTop    = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent        = main

	-- Title
	local title = Instance.new("TextLabel")
	title.Size               = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Text               = "📋 Sign Settings"
	title.TextColor3         = T.TEXT_STRONG
	title.TextSize           = 18
	title.Font               = Enum.Font.GothamBold
	title.TextXAlignment     = Enum.TextXAlignment.Left
	title.LayoutOrder        = 1
	title.Parent             = main

	-- Text Input section
	local inputSection = Instance.new("Frame")
	inputSection.Size            = UDim2.new(1, 0, 0, 72)
	inputSection.BackgroundColor3= T.CARD
	inputSection.BorderSizePixel = 0
	inputSection.LayoutOrder     = 2
	inputSection.Parent          = main

	local isc = Instance.new("UICorner"); isc.CornerRadius = UDim.new(0, 8); isc.Parent = inputSection

	local isp = Instance.new("UIPadding")
	isp.PaddingLeft   = UDim.new(0, 10); isp.PaddingRight  = UDim.new(0, 10)
	isp.PaddingTop    = UDim.new(0, 8);  isp.PaddingBottom = UDim.new(0, 8)
	isp.Parent        = inputSection

	local inputLbl = Instance.new("TextLabel")
	inputLbl.Size               = UDim2.new(1, 0, 0, 18)
	inputLbl.BackgroundTransparency = 1
	inputLbl.Text               = "Text"
	inputLbl.TextColor3         = T.TEXT_DIM
	inputLbl.TextSize           = 13
	inputLbl.Font               = Enum.Font.GothamBold
	inputLbl.TextXAlignment     = Enum.TextXAlignment.Left
	inputLbl.Position           = UDim2.new(0, 0, 0, 0)
	inputLbl.Parent             = inputSection

	local textBox = Instance.new("TextBox")
	textBox.Size               = UDim2.new(1, 0, 0, 34)
	textBox.Position           = UDim2.new(0, 0, 0, 26)
	textBox.BackgroundColor3   = T.BG
	textBox.BorderSizePixel    = 0
	textBox.Text               = ""
	textBox.PlaceholderText    = "Ketik teks sign..."
	textBox.TextColor3         = T.TEXT
	textBox.PlaceholderColor3  = T.TEXT_DIM
	textBox.TextSize           = 14
	textBox.Font               = Enum.Font.Gotham
	textBox.ClearTextOnFocus   = false
	textBox.MultiLine          = false
	textBox.Parent             = inputSection

	local tbc = Instance.new("UICorner"); tbc.CornerRadius = UDim.new(0, 6); tbc.Parent = textBox

	conn(textBox.FocusLost, function()
		local text = textBox.Text
		if text == "" then return end
		if isBanned(text) then
			textBox.Text = ""
			return
		end
		remoteText:FireServer(text)
	end)

	-- Color grids
	makeColorGrid("Warna Background", BG_COLORS,   remoteBG,      3, main)
	makeColorGrid("Warna Teks",       TEXT_COLORS, remoteTextClr, 4, main)

	return main
end

-- ── Register ke DynamicTools ──────────────────────────────
task.spawn(function()
	for _ = 1, MAX_RETRIES do
		if _G.RegisterDynamicTool then
			_G.RegisterDynamicTool(TOOL_NAME, buildUI, { iconText = "📋" })
			return
		end
		task.wait(RETRY_DELAY)
	end
	warn("[Sign UI] DynamicTools not found")
end)