-- MusicClient/UI  (ModuleScript)
-- Palet warna, pabrik widget, penyusun layout, slider, dan bar notifikasi.
-- Tidak ada logika musik di sini.
--
-- ATURAN TEMA (satu tema untuk seluruh panel):
--   * Latar kartu   : C.bgCard, garis tepi C.border
--   * Tombol primer : isi C.accent, teks C.onAccent
--   * Tombol sekunder: isi C.bgLight, garis C.border, teks C.accent/C.gray
--   * Status aktif  : isi C.accent
--   * Favorit       : SATU-SATUNYA pengecualian. Bukan isian emas, melainkan
--     hati merah + garis tepi merah di atas kartu gelap (gaya outline).
--
-- ATURAN LAYOUT:
--   Tidak ada elemen berkoordinat negatif dan tidak ada yang menempel tepi
--   kanan panel. Itu penyebab slider volume & tombol favorit tidak bisa
--   diklik (tertimpa tepi/scrollbar panel host).

local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService  = game:GetService("TextService")

local UI = {}

UI.C = {
	bg         = Color3.fromRGB(18,  18,  22),
	bgCard     = Color3.fromRGB(26,  26,  30),
	bgLight    = Color3.fromRGB(32,  32,  38),
	section    = Color3.fromRGB(38,  38,  44),
	hover      = Color3.fromRGB(46,  46,  54),
	accent     = Color3.fromRGB(255, 195, 40),
	accentDk   = Color3.fromRGB(210, 160, 30),
	white      = Color3.fromRGB(240, 240, 245),
	gray       = Color3.fromRGB(160, 160, 168),
	muted      = Color3.fromRGB(100, 100, 108),
	onAccent   = Color3.fromRGB(18,  18,  22),
	danger     = Color3.fromRGB(230, 80,  80),
	success    = Color3.fromRGB(72,  196, 120),
	border     = Color3.fromRGB(44,  44,  52),
	gold       = Color3.fromRGB(255, 215, 0),
	validating = Color3.fromRGB(255, 165, 0),
	love       = Color3.fromRGB(255, 92,  108),
	inQueue    = Color3.fromRGB(80,  150, 255),
	playing    = Color3.fromRGB(72,  196, 120),
}

UI.SEC_TW    = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UI.STD_TW    = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UI.INDIE_KEY = "★ Independent Creators"

local C = UI.C

-- ══ TWEEN ═════════════════════════════════════════════════════════════════
local active = {}

function UI.tw(obj, info, props)
	if not obj or not obj.Parent then return end
	if active[obj] then active[obj]:Cancel() end
	local t = TweenService:Create(obj, info, props)
	active[obj] = t
	t:Play()
	t.Completed:Once(function() active[obj] = nil end)
	return t
end

function UI.tws(obj, props) return UI.tw(obj, UI.STD_TW, props) end

function UI.cancelTweens()
	for _, t in pairs(active) do pcall(function() t:Cancel() end) end
	active = {}
end

-- ══ UTIL ══════════════════════════════════════════════════════════════════
function UI.fmtTime(s)
	if not s or s ~= s or s < 0 then return "0:00" end
	return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60))
end

-- UI.extractId dihapus: pakai Shared.rawId (isinya sama persis).

function UI.clearList(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding") or c:IsA("UIGridLayout")) then
			c:Destroy()
		end
	end
end

function UI.hover(btn, norm, hov)
	if not btn then return end
	btn.MouseEnter:Connect(function() UI.tws(btn, { BackgroundColor3 = hov  }) end)
	btn.MouseLeave:Connect(function() UI.tws(btn, { BackgroundColor3 = norm }) end)
end

-- ══ PABRIK WIDGET ═════════════════════════════════════════════════════════
local w = _G.MenuUI or {}
local function ap(o, p) if p then for k, v in pairs(p) do o[k] = v end end end

function w.image(p)
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	ap(i, p)
	return i
end

if not w.corner then
	function w.corner(r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 8)
		return c
	end
end
if not w.stroke then
	function w.stroke(col, t)
		local s = Instance.new("UIStroke")
		s.Color = col; s.Thickness = t or 1
		return s
	end
end
if not w.padding then
	function w.padding(a)
		local p = Instance.new("UIPadding")
		p.PaddingLeft   = UDim.new(0, a)
		p.PaddingRight  = UDim.new(0, a)
		p.PaddingTop    = UDim.new(0, a)
		p.PaddingBottom = UDim.new(0, a)
		return p
	end
end
if not w.text then
	function w.text(p)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Gotham
		t.TextSize = 12
		t.TextColor3 = C.white
		ap(t, p)
		return t
	end
end
if not w.button then
	function w.button(p)
		local b = Instance.new("TextButton")
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.BorderSizePixel = 0
		b.TextColor3 = C.white
		ap(b, p)
		return b
	end
end
if not w.textbox then
	function w.textbox(p)
		local t = Instance.new("TextBox")
		t.Font = Enum.Font.Gotham
		t.TextSize = 12
		t.BorderSizePixel = 0
		t.ClearTextOnFocus = false
		t.TextColor3 = C.white
		ap(t, p)
		return t
	end
end
if not w.scroll then
	function w.scroll(p)
		local s = Instance.new("ScrollingFrame")
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.ScrollBarThickness = 3
		s.ScrollBarImageColor3 = C.accent
		ap(s, p)
		return s
	end
end
if not w.list then
	function w.list(p)
		local pad = p and p.padding
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, pad or 8)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		if p then
			for k, v in pairs(p) do
				if k ~= "padding" then pcall(function() l[k] = v end) end
			end
		end
		return l
	end
end
if not w.frame then
	function w.frame(p)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = C.section
		f.BorderSizePixel = 0
		ap(f, p)
		return f
	end
end

_G.MenuUI = w
UI.w = w

-- Warna teks yang kontras di atas warna latar apa pun. Dipakai bar notifikasi:
-- latar kuning WAJIB berteks gelap, kalau putih teksnya hilang ditelan latar.
function UI.textOn(bg)
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return (lum > 0.55) and C.onAccent or C.white
end

-- ══ TEKS BERJALAN (MARQUEE) ═══════════════════════════════════════════════
-- Untuk judul yang tidak muat di kotaknya.
--
-- Gerakannya SATU ARAH dan menyambung (gaya running text papan iklan):
-- teks digeser terus ke kiri, dan begitu salinan kedua tiba tepat di posisi
-- awal salinan pertama, posisinya di-reset ke awal. Karena kedua salinan
-- identik dan jaraknya persis, reset itu tidak terlihat sama sekali.
-- Bolak-balik (kiri lalu mundur ke kanan) sengaja TIDAK dipakai — gerakannya
-- patah dan mata ikut tersentak di tiap ujung.
--
-- Caranya: label.Text diisi "judul + jarak + judul", lalu digeser sejauh
-- (judul + jarak). Satu tween linear per label, tanpa RunService — kalau tiap
-- item library punya loop per-frame, seratus lagu berarti seratus koneksi.
-- Paling banyak hanya dua marquee hidup sekaligus: judul yang sedang diputar
-- dan satu item library yang sedang di-hover.
local MQ_SPEED = 32     -- piksel per detik
local MQ_START = 0.6    -- jeda sekali di awal supaya judul sempat terbaca
local MQ_SEP   = "        "
local marquees = {}

local function measureText(label, str)
	local ok, size = pcall(function()
		return TextService:GetTextSize(str or label.Text, label.TextSize, label.Font,
			Vector2.new(9999, 100))
	end)
	return ok and size.X or 0
end

local function restore(label, m)
	if not label.Parent then return end
	-- Hanya kembalikan teksnya kalau masih teks gandengan milik kita. Kalau
	-- lagunya sudah berganti, judul baru tidak boleh ditimpa judul lama.
	if m.doubled and label.Text == m.doubled then label.Text = m.text end
	label.Position     = m.pos
	label.Size         = m.size
	label.TextTruncate = m.trunc
end

function UI.stopMarquee(label)
	local m = label and marquees[label]
	if not m then return end
	marquees[label] = nil
	if m.tween then pcall(function() m.tween:Cancel() end) end
	if m.thread and coroutine.running() ~= m.thread then pcall(task.cancel, m.thread) end
	restore(label, m)
end

function UI.marquee(label)
	if not label or not label.Parent then return end
	UI.stopMarquee(label)

	local avail = label.AbsoluteSize.X
	if avail <= 1 then return end

	local text  = label.Text
	local width = measureText(label, text)
	if width <= avail - 2 then return end   -- muat seluruhnya, tidak perlu jalan

	local shift   = measureText(label, text .. MQ_SEP)
	local doubled = text .. MQ_SEP .. text
	local full    = measureText(label, doubled)
	if shift <= 0 then return end

	local m = {
		pos = label.Position, size = label.Size, trunc = label.TextTruncate,
		text = text, doubled = doubled,
	}
	marquees[label] = m

	label.TextTruncate = Enum.TextTruncate.None
	label.Text = doubled
	label.Size = UDim2.new(0, full + 8, m.size.Y.Scale, m.size.Y.Offset)

	local home = m.pos
	local away = UDim2.new(home.X.Scale, home.X.Offset - shift, home.Y.Scale, home.Y.Offset)
	local dur  = math.clamp(shift / MQ_SPEED, 1, 30)
	local info = TweenInfo.new(dur, Enum.EasingStyle.Linear)

	m.thread = task.spawn(function()
		task.wait(MQ_START)
		while marquees[label] == m and label.Parent do
			label.Position = home            -- reset tak kasatmata
			m.tween = TweenService:Create(label, info, { Position = away })
			m.tween:Play()
			task.wait(dur)
		end
		if marquees[label] == m then
			marquees[label] = nil
			restore(label, m)
		end
	end)
end

-- Pasang marquee saat kursor masuk / area teks disentuh.
-- `hit` = tombol transparan di atas area teks: hover untuk desktop, tap untuk
-- layar sentuh (di HP tidak ada hover sama sekali).
function UI.marqueeOnHover(hit, label)
	if not hit or not label then return end
	hit.MouseEnter:Connect(function() UI.marquee(label) end)
	hit.MouseLeave:Connect(function() UI.stopMarquee(label) end)
	hit.MouseButton1Click:Connect(function() UI.marquee(label) end)
end

function UI.stopAllMarquees()
	-- Salin dulu: UI.stopMarquee menghapus key, dan menghapus key saat tabel
	-- sedang di-pairs() itu perilaku tidak terdefinisi di Lua.
	local list = {}
	for label in pairs(marquees) do table.insert(list, label) end
	for _, label in ipairs(list) do UI.stopMarquee(label) end
	marquees = {}
end

-- ══ SLIDER ════════════════════════════════════════════════════════════════
-- hit (TextButton transparan setinggi baris) > track (batang tipis) > fill.
-- Persen dihitung dari lebar `hit`, jadi area kliknya besar.
local drag = {}

local moveConn = UIS.InputChanged:Connect(function(i)
	if not drag.bg or not drag.bg.Parent then return end
	if i.UserInputType ~= Enum.UserInputType.MouseMovement
		and i.UserInputType ~= Enum.UserInputType.Touch then return end
	local size = drag.bg.AbsoluteSize.X
	if size <= 0 then return end
	local pct = math.clamp((i.Position.X - drag.bg.AbsolutePosition.X) / size, 0, 1)
	if drag.cb then drag.cb(pct) end
end)

local endConn = UIS.InputEnded:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.MouseButton1
		and i.UserInputType ~= Enum.UserInputType.Touch then return end
	if drag.scroll and drag.scroll.Parent then drag.scroll.ScrollingEnabled = true end
	drag.bg, drag.cb, drag.scroll = nil, nil, nil
end)

function UI.slider(bg, cb, parentScroll)
	if not bg then return end
	bg.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1
			and i.UserInputType ~= Enum.UserInputType.Touch then return end
		if parentScroll and parentScroll.Parent then parentScroll.ScrollingEnabled = false end
		drag.bg, drag.cb, drag.scroll = bg, cb, parentScroll
		local size = bg.AbsoluteSize.X
		if size > 0 then
			cb(math.clamp((i.Position.X - bg.AbsolutePosition.X) / size, 0, 1))
		end
	end)
end

local function makeSlider(parent, pos, size, startPct)
	local hit = w.button({
		Size = size, Position = pos, BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, ZIndex = 4, Parent = parent,
	})
	local track = w.frame({
		Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0.5, -4),
		BackgroundColor3 = C.section, ZIndex = 4, Parent = hit,
	})
	w.corner(4).Parent = track
	local fill = w.frame({
		Size = UDim2.new(startPct or 1, 0, 1, 0), BackgroundColor3 = C.accent,
		ZIndex = 5, Parent = track,
	})
	w.corner(4).Parent = fill
	return hit, fill
end

function UI.disconnect()
	if moveConn then moveConn:Disconnect() end
	if endConn  then endConn:Disconnect()  end
	drag.bg, drag.cb, drag.scroll = nil, nil, nil
end

-- ══ NOTIFIKASI ════════════════════════════════════════════════════════════
-- Satu baris, satu warna aksen, maks 2 antre, pesan sama dalam 2 detik dibuang.
local nBar, nText
local nQueue, nShowing = {}, false
local lastMsg, lastAt = "", 0

function UI.bindNotify(bar, text) nBar, nText = bar, text end
function UI.resetNotify() nQueue, nShowing = {}, false end

local function nStep()
	if #nQueue == 0 or not (nBar and nBar.Parent) then nShowing = false; return end
	nShowing = true
	local d = table.remove(nQueue, 1)
	nBar.BackgroundColor3 = d.col
	nText.Text            = d.msg
	nText.TextColor3      = UI.textOn(d.col)
	nBar.Visible          = true
	UI.tws(nBar, { Size = UDim2.new(1, -20, 0, 28) })
	task.delay(d.dur, function()
		if not (nBar and nBar.Parent) then nShowing = false; return end
		UI.tws(nBar, { Size = UDim2.new(1, -20, 0, 0) })
		task.wait(0.18)
		if nBar and nBar.Parent then nBar.Visible = false end
		nStep()
	end)
end

function UI.notify(msg, col, dur)
	if not msg or msg == "" then return end
	local now = os.clock()
	if msg == lastMsg and (now - lastAt) < 2 then return end
	lastMsg, lastAt = msg, now
	if #nQueue >= 2 then table.remove(nQueue, 1) end
	table.insert(nQueue, { msg = msg, col = col or C.accent, dur = dur or 2 })
	if not nShowing then nStep() end
end

-- ══ BUILD ═════════════════════════════════════════════════════════════════
function UI.build()
	local container = w.frame({
		Name = "MusicContainer", Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	})

	local scroll = w.scroll({
		Size = UDim2.new(1, -6, 1, 0), Position = UDim2.new(0, 3, 0, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = container,
	})
	local content = w.frame({
		Size = UDim2.new(1, -16, 0, 0), Position = UDim2.new(0, 8, 0, 10),
		BackgroundTransparency = 1, Parent = scroll,
	})
	local layout = w.list({ padding = 10 })
	layout.Parent = content
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		content.Size      = UDim2.new(1, -16, 0, layout.AbsoluteContentSize.Y)
		scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 28)
	end)

	-- ══ NOW PLAYING ═══════════════════════════════════════════════════════
	-- Banner LIVE: muncul selama siaran (server ini atau server lain).
	local liveBanner = w.frame({ Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.bgCard, LayoutOrder = 0, Visible = false, Parent = content })
	w.corner(12).Parent = liveBanner; w.stroke(C.danger, 1).Parent = liveBanner
	local liveDot = w.frame({ Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 12, 0, 11), BackgroundColor3 = C.danger, Parent = liveBanner })
	w.corner(5).Parent = liveDot
	local liveTitle = w.text({ Size = UDim2.new(1, -40, 0, 16), Position = UDim2.new(0, 30, 0, 7), Text = "LIVE", TextColor3 = C.danger, Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = liveBanner })
	local liveSub = w.text({ Size = UDim2.new(1, -40, 0, 14), Position = UDim2.new(0, 30, 0, 25), Text = "", TextColor3 = C.gray, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = liveBanner })
	local np = w.frame({ Size = UDim2.new(1, 0, 0, 156), BackgroundColor3 = C.bgCard, LayoutOrder = 1, Parent = content })
	w.corner(12).Parent = np; w.stroke(C.border, 1).Parent = np
	local npc = w.frame({ Size = UDim2.new(1, -18, 1, -18), Position = UDim2.new(0, 9, 0, 9), BackgroundTransparency = 1, Parent = np })

	w.text({ Size = UDim2.new(1, -132, 0, 20), Position = UDim2.new(0, 0, 0, 0),
		Text = "NOW PLAYING", TextColor3 = C.accent, Font = Enum.Font.GothamBold,
		TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = npc })

	local npFavBtn = w.button({
		Size = UDim2.new(0, 28, 0, 22), Position = UDim2.new(1, -128, 0, 0),
		BackgroundColor3 = C.bgLight, Text = "♡", TextColor3 = C.gray,
		TextSize = 14, ZIndex = 4, Parent = npc,
	})
	w.corner(6).Parent = npFavBtn
	local npFavStroke = w.stroke(C.border, 1); npFavStroke.Parent = npFavBtn

	local reloadBtn = w.button({
		Size = UDim2.new(0, 94, 0, 22), Position = UDim2.new(1, -96, 0, 0),
		BackgroundColor3 = C.bgLight, Text = "⟳ Reload song", TextColor3 = C.accent,
		TextSize = 9, ZIndex = 4, Parent = npc,
	})
	w.corner(6).Parent = reloadBtn; w.stroke(C.border, 1).Parent = reloadBtn

	local albumArt = w.image({ Size = UDim2.new(0, 70, 0, 70), Position = UDim2.new(0, 0, 0, 26), BackgroundColor3 = C.section, ScaleType = Enum.ScaleType.Fit, Parent = npc })
	w.corner(10).Parent = albumArt; w.stroke(C.border, 1).Parent = albumArt

	-- Judul dibungkus frame ber-clip supaya teksnya bisa digeser (marquee)
	-- tanpa meluber keluar kartu.
	local titleClip = w.frame({ Size = UDim2.new(1, -80, 0, 20), Position = UDim2.new(0, 78, 0, 26), BackgroundTransparency = 1, ClipsDescendants = true, Parent = npc })
	local songTitle = w.text({ Size = UDim2.new(1, 0, 1, 0), Text = "Loading...", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = titleClip })
	local songArtist = w.text({ Size = UDim2.new(1, -80, 0, 12), Position = UDim2.new(0, 78, 0, 47), Text = "Connecting...", TextSize = 9, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = npc })

	local skipBtn = w.button({ Size = UDim2.new(0, 62, 0, 24), Position = UDim2.new(0, 78, 0, 66), BackgroundColor3 = C.bgLight, Text = "Skip 0/1", TextColor3 = C.accent, TextSize = 9, Font = Enum.Font.GothamBold, Parent = npc })
	w.corner(8).Parent = skipBtn; w.stroke(C.border, 1).Parent = skipBtn

	local forceSkipBtn = w.button({ Size = UDim2.new(0, 62, 0, 24), Position = UDim2.new(0, 144, 0, 66), BackgroundColor3 = C.accent, Text = "Force skip", TextColor3 = C.onAccent, TextSize = 9, Font = Enum.Font.GothamBold, Visible = false, Parent = npc })
	w.corner(8).Parent = forceSkipBtn

	-- Volume: satu baris penuh sendiri, tidak berebut tempat dengan tombol skip.
	local volRow   = w.frame({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 96), BackgroundTransparency = 1, Parent = npc })
	local volLabel = w.text({ Size = UDim2.new(0, 62, 1, 0), Text = "Volume 70%", TextColor3 = C.gray, Font = Enum.Font.GothamBold, TextSize = 8, TextXAlignment = Enum.TextXAlignment.Left, Parent = volRow })
	local volBg, volSlider = makeSlider(volRow, UDim2.new(0, 64, 0, 0), UDim2.new(1, -68, 1, 0), 0.7)

	local progBg = w.frame({ Size = UDim2.new(1, 0, 0, 5), Position = UDim2.new(0, 0, 0, 123), BackgroundColor3 = C.section, Parent = npc })
	w.corner(3).Parent = progBg
	local progressBar = w.frame({ Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.accent, Parent = progBg })
	w.corner(3).Parent = progressBar
	local currentTime = w.text({ Size = UDim2.new(0, 40, 0, 12), Position = UDim2.new(0, 0, 0, 126), Text = "0:00", TextColor3 = C.muted, TextSize = 8, TextXAlignment = Enum.TextXAlignment.Left, Parent = npc })
	local totalTime   = w.text({ Size = UDim2.new(0, 40, 0, 12), Position = UDim2.new(1, -40, 0, 126), Text = "0:00", TextColor3 = C.muted, TextSize = 8, TextXAlignment = Enum.TextXAlignment.Right, Parent = npc })

	-- ══ NOTIFIKASI ════════════════════════════════════════════════════════
	local notifBar = w.frame({ Size = UDim2.new(1, -20, 0, 0), Position = UDim2.new(0, 10, 0, 4), BackgroundColor3 = C.accent, Visible = false, ClipsDescendants = true, ZIndex = 30, Parent = container })
	w.corner(8).Parent = notifBar
	-- Font TIPIS (Gotham, bukan GothamBold): teks tebal di atas bar warna
	-- terlihat berdesakan dan sulit dibaca.
	local notifText = w.text({ Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), Text = "", TextColor3 = C.onAccent, Font = Enum.Font.Gotham, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 31, Parent = notifBar })

	-- ══ ADMIN SETTINGS ════════════════════════════════════════════════════
	local adminSettings = w.frame({ Size = UDim2.new(1, 0, 0, 348), BackgroundColor3 = C.bgCard, LayoutOrder = 3, Visible = false, Parent = content })
	w.corner(12).Parent = adminSettings; w.stroke(C.border, 1).Parent = adminSettings
	local adminCt = w.frame({ Size = UDim2.new(1, -18, 1, -18), Position = UDim2.new(0, 9, 0, 9), BackgroundTransparency = 1, Parent = adminSettings })
	-- disimpan supaya bisa diganti "DJ" untuk DJ non-admin
	local adminTitle = w.text({ Size = UDim2.new(1, 0, 0, 14), Text = "ADMIN SETTINGS", TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = adminCt })

	local function makeRow(y, lbl, def)
		local row = w.frame({ Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 0, y), BackgroundTransparency = 1, Parent = adminCt })
		w.text({ Size = UDim2.new(0.45, 0, 1, 0), Text = lbl, TextColor3 = C.gray, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local inp = w.textbox({ Size = UDim2.new(0.3, 0, 0, 23), Position = UDim2.new(0.44, 0, 0, 2), BackgroundColor3 = C.section, Text = def, TextSize = 9, Parent = row })
		w.corner(6).Parent = inp; w.padding(8).Parent = inp
		return inp
	end

	local modeRow   = w.frame({ Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 0, 18), BackgroundTransparency = 1, Parent = adminCt })
	local modeLabel = w.text({ Size = UDim2.new(0.45, 0, 1, 0), Text = "Mode: Stage", TextColor3 = C.white, Font = Enum.Font.GothamBold, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = modeRow })
	local modeBtn   = w.button({ Size = UDim2.new(0.55, 0, 0, 23), Position = UDim2.new(0.45, 0, 0, 2), BackgroundColor3 = C.accent, Text = "Switch to Global", TextColor3 = C.onAccent, TextSize = 8, Parent = modeRow })
	w.corner(6).Parent = modeBtn

	local minDistInput = makeRow(48,  "Min distance", "10")
	local maxDistInput = makeRow(78,  "Max distance", "500")
	local sizeInput    = makeRow(108, "Emitter size", "100")
	local makeupInput  = makeRow(138, "Loudness boost (dB)", "15")

	local eqRow = w.frame({ Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 0, 168), BackgroundTransparency = 1, Parent = adminCt })
	w.text({ Size = UDim2.new(0.32, 0, 1, 0), Text = "EQ low/mid/high", TextColor3 = C.gray, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = eqRow })
	local function eqBox(x, def)
		local b = w.textbox({ Size = UDim2.new(0.2, -3, 0, 23), Position = UDim2.new(x, 3, 0, 2), BackgroundColor3 = C.section, Text = def, TextSize = 9, Parent = eqRow })
		w.corner(6).Parent = b; w.padding(6).Parent = b
		return b
	end
	local eqLowInput  = eqBox(0.32, "2")
	local eqMidInput  = eqBox(0.52, "3")
	local eqHighInput = eqBox(0.72, "3")

	local loudRow = w.frame({ Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 0, 198), BackgroundTransparency = 1, Parent = adminCt })
	w.text({ Size = UDim2.new(0.45, 0, 1, 0), Text = "Loudness chain", TextColor3 = C.gray, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = loudRow })
	local loudnessToggleBtn = w.button({ Size = UDim2.new(0.55, 0, 0, 23), Position = UDim2.new(0.45, 0, 0, 2), BackgroundColor3 = C.accent, Text = "On", TextColor3 = C.onAccent, TextSize = 9, Parent = loudRow })
	w.corner(6).Parent = loudnessToggleBtn

	local gRow           = w.frame({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 228), BackgroundTransparency = 1, Parent = adminCt })
	local globalVolLabel = w.text({ Size = UDim2.new(0, 78, 1, 0), Text = "Global 100%", TextColor3 = C.gray, Font = Enum.Font.GothamBold, TextSize = 8, TextXAlignment = Enum.TextXAlignment.Left, Parent = gRow })
	local globalVolBg, globalVolSlider = makeSlider(gRow, UDim2.new(0, 80, 0, 0), UDim2.new(1, -142, 1, 0), 1)
	local applyBtn = w.button({ Size = UDim2.new(0, 54, 0, 22), Position = UDim2.new(1, -54, 0, 0), BackgroundColor3 = C.accent, Text = "Apply", TextColor3 = C.onAccent, TextSize = 9, Parent = gRow })
	w.corner(6).Parent = applyBtn

	-- Auto play On/Off (langsung terkirim, tanpa Apply)
	local apRow = w.frame({ Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 0, 258), BackgroundTransparency = 1, Parent = adminCt })
	w.text({ Size = UDim2.new(0.45, 0, 1, 0), Text = "Auto play", TextColor3 = C.gray, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = apRow })
	local autoplayBtn = w.button({ Size = UDim2.new(0.55, 0, 0, 23), Position = UDim2.new(0.45, 0, 0, 2), BackgroundColor3 = C.accent, Text = "On", TextColor3 = C.onAccent, TextSize = 9, Parent = apRow })
	w.corner(6).Parent = autoplayBtn

	-- Siaran live ke semua server (admin)
	local liveRow = w.frame({ Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 0, 288), BackgroundTransparency = 1, Parent = adminCt })
	w.text({ Size = UDim2.new(0.45, 0, 1, 0), Text = "Live (all servers)", TextColor3 = C.gray, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Parent = liveRow })
	local liveBtn = w.button({ Size = UDim2.new(0.55, 0, 0, 23), Position = UDim2.new(0.45, 0, 0, 2), BackgroundColor3 = C.bgLight, Text = "Off", TextColor3 = C.gray, TextSize = 9, Parent = liveRow })
	w.corner(6).Parent = liveBtn

	-- ══ ADD SONG ══════════════════════════════════════════════════════════
	-- Dua tombol eksplisit. Player biasa hanya melihat "My Library";
	-- "Global Library" hanya muncul untuk admin.
	local addSec = w.frame({ Size = UDim2.new(1, 0, 0, 104), BackgroundColor3 = C.bgCard, LayoutOrder = 4, Parent = content })
	w.corner(12).Parent = addSec; w.stroke(C.border, 1).Parent = addSec
	local addCt = w.frame({ Size = UDim2.new(1, -18, 1, -18), Position = UDim2.new(0, 9, 0, 9), BackgroundTransparency = 1, Parent = addSec })
	w.text({ Size = UDim2.new(1, 0, 0, 13), Text = "ADD SONG", Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = addCt })
	local input = w.textbox({ Size = UDim2.new(1, 0, 0, 32), Position = UDim2.new(0, 0, 0, 17), BackgroundColor3 = C.section, PlaceholderText = "Roblox audio ID or URL", PlaceholderColor3 = C.muted, Text = "", TextSize = 10, Parent = addCt })
	w.padding(10).Parent = input; w.corner(8).Parent = input

	local addMineBtn = w.button({
		Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 55),
		BackgroundColor3 = C.accent, Text = "Add to My Library", TextColor3 = C.onAccent,
		TextSize = 9, Parent = addCt,
	})
	w.corner(8).Parent = addMineBtn

	local addGlobalBtn = w.button({
		Size = UDim2.new(0.5, -3, 0, 26), Position = UDim2.new(0.5, 3, 0, 55),
		BackgroundColor3 = C.bgLight, Text = "Add to Global", TextColor3 = C.accent,
		TextSize = 9, Visible = false, Parent = addCt,
	})
	w.corner(8).Parent = addGlobalBtn; w.stroke(C.border, 1).Parent = addGlobalBtn

	-- ══ QUEUE ═════════════════════════════════════════════════════════════
	local queueSection = w.frame({ Size = UDim2.new(1, 0, 0, 250), BackgroundTransparency = 1, LayoutOrder = 5, Visible = false, Parent = content })
	local queueLabel   = w.text({ Size = UDim2.new(1, 0, 0, 20), Text = "QUEUE (0/30)", Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, Parent = queueSection })
	local queueScroll  = w.scroll({ Size = UDim2.new(1, 0, 0, 224), Position = UDim2.new(0, 0, 0, 26), CanvasSize = UDim2.new(0, 0, 0, 0), Parent = queueSection })
	local queueList    = w.frame({ Size = UDim2.new(1, -6, 0, 0), Position = UDim2.new(0, 3, 0, 3), BackgroundTransparency = 1, Parent = queueScroll })
	local ql = w.list({ padding = 5 })
	ql.Parent = queueList
	ql:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local h = ql.AbsoluteContentSize.Y
		queueList.Size         = UDim2.new(1, -6, 0, h)
		queueScroll.CanvasSize = UDim2.new(0, 0, 0, h + 6)
		local sh = math.clamp(h + 32, 50, 260)
		queueSection.Size = UDim2.new(1, 0, 0, sh)
		queueScroll.Size  = UDim2.new(1, 0, 0, sh - 26)
	end)

	-- ══ LIBRARY ═══════════════════════════════════════════════════════════
	local LIB_HEAD = 60
	local libSection = w.frame({ Size = UDim2.new(1, 0, 0, 300), BackgroundTransparency = 1, LayoutOrder = 6, Parent = content })
	local libHeader  = w.frame({ Size = UDim2.new(1, 0, 0, LIB_HEAD), BackgroundTransparency = 1, Parent = libSection })

	local libLabel   = w.text({ Size = UDim2.new(0.44, 0, 0, 24), Position = UDim2.new(0, 0, 0, 2), Text = "LIBRARY (0)", Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, Parent = libHeader })
	local tabAllBtn  = w.button({ Size = UDim2.new(0.27, -3, 0, 22), Position = UDim2.new(0.46, 0, 0, 2), BackgroundColor3 = C.accent, Text = "Global", TextColor3 = C.onAccent, TextSize = 8, Parent = libHeader })
	w.corner(6).Parent = tabAllBtn
	local tabMineBtn = w.button({ Size = UDim2.new(0.27, -3, 0, 22), Position = UDim2.new(0.73, 3, 0, 2), BackgroundColor3 = C.bgLight, Text = "Mine (0)", TextColor3 = C.gray, TextSize = 8, Parent = libHeader })
	w.corner(6).Parent = tabMineBtn

	local sortBtn   = w.button({ Size = UDim2.new(0.22, -2, 0, 24), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = C.bgLight, Text = "Recent", TextColor3 = C.accent, TextSize = 8, Font = Enum.Font.GothamBold, Parent = libHeader })
	w.corner(6).Parent = sortBtn
	local filterLib = w.textbox({ Size = UDim2.new(0.78, -4, 0, 24), Position = UDim2.new(0.22, 4, 0, 30), BackgroundColor3 = C.section, PlaceholderText = "Search...", PlaceholderColor3 = C.muted, Text = "", TextSize = 9, Parent = libHeader })
	w.padding(8).Parent = filterLib; w.corner(6).Parent = filterLib

	local libList = w.frame({ Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, LIB_HEAD + 4), BackgroundTransparency = 1, Parent = libSection })
	local ll = w.list({ padding = 6 })
	ll.Parent = libList
	ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		libList.Size    = UDim2.new(1, 0, 0, ll.AbsoluteContentSize.Y)
		libSection.Size = UDim2.new(1, 0, 0, LIB_HEAD + 8 + ll.AbsoluteContentSize.Y)
	end)

	return {
		container = container, scroll = scroll,
		albumArt = albumArt, songTitle = songTitle, songArtist = songArtist,
		progressBar = progressBar, currentTime = currentTime, totalTime = totalTime,
		queueLabel = queueLabel, queueList = queueList, queueSection = queueSection,
		liveBanner = liveBanner, liveTitle = liveTitle, liveSub = liveSub,
		libLabel = libLabel, libList = libList, libSection = libSection,
		tabAllBtn = tabAllBtn, tabMineBtn = tabMineBtn,
		skipBtn = skipBtn, forceSkipBtn = forceSkipBtn,
		input = input, addMineBtn = addMineBtn, addGlobalBtn = addGlobalBtn,
		npFavBtn = npFavBtn, npFavStroke = npFavStroke, reloadBtn = reloadBtn,
		volSlider = volSlider, volBg = volBg, volLabel = volLabel,
		sortBtn = sortBtn, filterLib = filterLib,
		notifBar = notifBar, notifText = notifText,
		adminSettings = adminSettings, applyBtn = applyBtn,
		minDistInput = minDistInput, maxDistInput = maxDistInput, sizeInput = sizeInput,
		makeupInput = makeupInput, eqLowInput = eqLowInput, eqMidInput = eqMidInput,
		eqHighInput = eqHighInput, loudnessToggleBtn = loudnessToggleBtn,
		globalVolSlider = globalVolSlider, globalVolBg = globalVolBg, globalVolLabel = globalVolLabel,
		modeLabel = modeLabel, modeBtn = modeBtn,
		autoplayBtn = autoplayBtn,
		liveBtn = liveBtn,
		liveRow = liveRow, adminCt = adminCt, adminTitle = adminTitle, -- DJ melihat baris Live saja
	}
end

return UI