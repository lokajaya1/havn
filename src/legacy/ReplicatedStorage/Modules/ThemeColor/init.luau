--!strict
-- ReplicatedStorage/Modules/ThemeColor (ModuleScript) — SATU sumber warna semua UI HAVN (themeColor, claude/Rencana_ThemeColor.md).
--
-- Cara pakai di skrip UI (client):
--   local ThemeColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ThemeColor"))
--   local T = ThemeColor.tokens        -- T.BG, T.CARD, … tabel BERSAMA yang diisi ulang saat tema diganti:
--                                      -- baca T.X saat melukis/hover, JANGAN salin ke variabel lokal
--   ThemeColor.mark(screenGui)         -- ScreenGui milik kita → ikut dilukis ulang saat tema diganti
--   ThemeColor.skip(instance)          -- warna KONTEN (pilihan warna, gambar) → tidak disentuh, beserta isinya
--   ThemeColor.live(color)             -- warna yang tersimpan dari tema lama → warna yang sama di tema sekarang
--   ThemeColor.view({ NAMA = "TOKEN" }, { NAMA_TETAP = Color3 })  -- palet bernama yang membaca token saat dipakai
--   ThemeColor.onChanged(fn)           -- fn(idBaru, idLama) sesudah tema diganti
--   ThemeColor.glow(uiStroke, "panel")  -- garis tepi BERGERAK: cahaya aksen berputar + denyut (Config.outline.panel/hover)
--   Sorot hover: SEMUA tombol di ScreenGui bertanda otomatis bergaris tepi bergerak saat di-hover / ditekan (Config.hover);
--   kecualikan tombol / kontainer dengan atribut ThemeColor.NO_HOVER ("ThemeNoHover").
--   ThemeColor.hoverHost(tombol, bentuk) -- tombol = lapisan klik di atas bentuk lain (mis. teks di dalam pil) → garis di bentuk
--
-- Tema aktif = atribut Player "ThemeColor" (diset server ServerScriptService.ThemeColor; client hanya tampilan).
-- Ganti tema: isi ulang tabel token di tempat → lukis ulang ScreenGui bertanda (warna yang PERSIS token tema mana pun →
-- token yang sama di tema baru; nilai token unik di semua tema, dijaga Rules.validate) → diulang Config.repaintDelays.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ThemeColor"))
local Rules = require(script:WaitForChild("Rules"))

local ThemeColor = {}
ThemeColor.Config = Config
ThemeColor.Rules = Rules
ThemeColor.ATTR = "ThemeColor" -- atribut Player: id tema aktif (server)
ThemeColor.PASS_ATTR = "ThemeColorPass" -- atribut Player: boleh memakai tema berbayar (server)
ThemeColor.MARK = "Themed" -- atribut ScreenGui: ikut dilukis ulang
ThemeColor.SKIP = "ThemeSkip" -- atribut instance: warna konten, dilewati beserta isinya

local tokens: { [string]: Color3 } = {}
local legacy: { [string]: Color3 } = {}
ThemeColor.tokens = tokens
ThemeColor.legacy = legacy
ThemeColor.current = ""

local roleOf = Rules.roleIndex(Config)
local listeners: { (string, string) -> () } = {}

local function fill(id: string)
	local preset = Config.presets[id]
	for _, role in Rules.TOKENS do
		tokens[role] = preset.tokens[role]
	end
	for name, role in Rules.LEGACY do
		legacy[name] = tokens[role]
	end
	ThemeColor.current = id
end

-- ── membaca ───────────────────────────────────────────────────────────────────────────────────────────────────────

-- Warna token tema mana pun → token yang sama di tema sekarang. Warna lain (konten) dikembalikan apa adanya.
function ThemeColor.live(c: Color3): Color3
	if typeof(c) ~= "Color3" then
		return c
	end
	local role = roleOf[Rules.key(c)]
	return if role then tokens[role] else c
end

-- Palet bernama lokal: view.NAMA = token sekarang (dibaca saat dipakai). `fixed` = warna konten yang tidak ikut tema.
-- Catatan: view tidak bisa di-pairs (isinya dibaca lewat __index).
function ThemeColor.view(map: { [string]: string }, fixed: { [string]: Color3 }?): { [string]: Color3 }
	for name, role in map do
		assert(table.find(Rules.TOKENS, role), ("ThemeColor.view: token %s tidak dikenal (%s)"):format(role, name))
	end
	local proxy = setmetatable({}, {
		__index = function(_, name)
			local role = map[name]
			if role then
				return tokens[role]
			end
			return if fixed then fixed[name] else nil
		end,
	})
	return proxy :: any
end

function ThemeColor.label(id: string): string
	local p = Config.presets[id]
	return if p then p.label else tostring(id)
end

function ThemeColor.isFree(id: string): boolean
	local p = Config.presets[id]
	return p ~= nil and p.free == true
end

function ThemeColor.ids(): { string }
	return Rules.ids(Config)
end

-- Warna nama pemain lain/sendiri = ACCENT tema pilihannya (atribut Player "ThemeColor", tereplikasi), atau nil = warna
-- nama bawaan tempat itu (tema polos Config.plainName). Label yang memakai ini WAJIB ThemeColor.skip (bukan token kita).
function ThemeColor.nameColor(player: Player): Color3?
	return Rules.nameColor(Config, player:GetAttribute(ThemeColor.ATTR))
end

-- ── lukis ulang ───────────────────────────────────────────────────────────────────────────────────────────────────
local propCache: { [string]: { string } } = {}

local function propsOf(inst: Instance): { string }
	local list = propCache[inst.ClassName]
	if list then
		return list
	end
	list = {}
	if inst:IsA("GuiObject") then
		table.insert(list, "BackgroundColor3")
		table.insert(list, "BorderColor3")
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		table.insert(list, "TextColor3")
		table.insert(list, "TextStrokeColor3")
	end
	if inst:IsA("TextBox") then
		table.insert(list, "PlaceholderColor3")
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		table.insert(list, "ImageColor3")
	end
	if inst:IsA("ScrollingFrame") then
		table.insert(list, "ScrollBarImageColor3")
	end
	if inst:IsA("UIStroke") then
		table.insert(list, "Color")
	end
	propCache[inst.ClassName] = list
	return list
end

local function paint(inst: Instance)
	if inst:GetAttribute(ThemeColor.SKIP) then
		return
	end
	local obj = inst :: any
	for _, prop in propsOf(inst) do
		local c = obj[prop]
		local n = ThemeColor.live(c)
		if n ~= c then
			obj[prop] = n
		end
	end
	if inst:IsA("UIGradient") then
		local changed = false
		local points = {}
		for i, kp in obj.Color.Keypoints do
			local n = ThemeColor.live(kp.Value)
			changed = changed or n ~= kp.Value
			points[i] = ColorSequenceKeypoint.new(kp.Time, n)
		end
		if changed then
			obj.Color = ColorSequence.new(points)
		end
	end
	for _, child in inst:GetChildren() do
		paint(child)
	end
end

-- Lukis ulang satu pohon UI sekarang (mis. UI yang dibangun dari warna tersimpan).
function ThemeColor.repaint(root: Instance)
	paint(root)
end

-- Lukis ulang semua ScreenGui bertanda di PlayerGui.
function ThemeColor.repaintAll()
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	for _, gui in pg:GetChildren() do
		if gui:GetAttribute(ThemeColor.MARK) then
			paint(gui)
		end
	end
end

local hookGui: (Instance) -> () -- sorot hover (di bawah)

function ThemeColor.mark(gui: Instance): Instance
	gui:SetAttribute(ThemeColor.MARK, true)
	hookGui(gui)
	return gui
end

function ThemeColor.skip(inst: Instance): Instance
	inst:SetAttribute(ThemeColor.SKIP, true)
	return inst
end

-- ── garis tepi bergerak (glow) ────────────────────────────────────────────────────────────────────────────────────
-- UIStroke diberi UIGradient warna aksen (ujung redup → tengah terang) yang BERPUTAR mengelilingi tepi, dan transparansi
-- garis berdenyut (pulse). Satu Heartbeat untuk semua glow; dilewati kalau panelnya tidak terlihat. Warna ikut tema.
local GLOW_NAME = "ThemeGlow"
-- Tabel KUAT (bukan weak): kunci Instance di tabel weak bisa hilang walau instance masih ada (wrapper Lua di-GC).
-- Entri dihapus saat stroke dihancurkan (Destroying) atau dilepas dari pohon setelah pernah terpasang.
local glows: { [UIStroke]: any } = {}
local glowConn: RBXScriptConnection? = nil
-- Stroke yang sudah punya koneksi Destroying (sekali per stroke; glow/unglow berulang tidak menumpuk koneksi).
-- Weak aman: closure koneksi memegang stroke-nya.
local destroyHooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function glowSequence(): ColorSequence
	local a = tokens.ACCENT
	local hi = a:Lerp(Color3.new(1, 1, 1), Config.outline.highlight)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, a),
		ColorSequenceKeypoint.new(0.5, hi),
		ColorSequenceKeypoint.new(1, a),
	})
end

local hoverCheck: () -> () -- sorot hover (di bawah): tombol yang disorot masih terlihat?

local function glowStep()
	hoverCheck() -- sebelum loop: bisa menambah/menghapus entri glows
	local t = os.clock()
	local alive = false
	for stroke, g in glows do
		alive = true
		local host = stroke.Parent
		if host == nil then
			if g.seen then
				glows[stroke] = nil -- sudah pernah terpasang lalu dilepas / dihancurkan
			end
			continue
		end
		g.seen = true
		if host:IsA("GuiObject") and not host.Visible then
			continue
		end
		local layer = g.layer or stroke:FindFirstAncestorWhichIsA("LayerCollector")
		g.layer = layer
		if layer and layer:IsA("ScreenGui") and not layer.Enabled then
			continue
		end
		g.grad.Rotation = (t * g.speed) % 360
		stroke.Transparency = g.base + g.amp * (0.5 + 0.5 * math.sin(t * g.omega))
	end
	if not alive and glowConn then
		glowConn:Disconnect()
		glowConn = nil
	end
end

-- Pasang garis tepi bergerak pada UIStroke. style = "panel" (halus) | "hover" (sorotan) | tabel {base, amp, speed, period}.
function ThemeColor.glow(stroke: UIStroke, style: any?): UIStroke
	local o = if type(style) == "table" then style else Config.outline[style or "panel"] or Config.outline.panel
	stroke.Color = Color3.new(1, 1, 1) -- warna dari gradient (putih = tanpa tint, tidak dilukis ulang)
	local grad = stroke:FindFirstChild(GLOW_NAME) :: UIGradient?
	if not grad then
		local g = Instance.new("UIGradient")
		g.Name = GLOW_NAME
		g:SetAttribute(ThemeColor.SKIP, true) -- dikelola glow sendiri, bukan lukis ulang
		grad = g
	end
	local gradient = grad :: UIGradient
	gradient.Color = glowSequence()
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	gradient.Parent = stroke
	if not destroyHooked[stroke] then
		destroyHooked[stroke] = true
		pcall(function() -- (pcall: Lune / tes tidak punya event Destroying)
			stroke.Destroying:Once(function()
				glows[stroke] = nil
			end)
		end)
	end
	glows[stroke] = {
		grad = gradient,
		base = o.base or 0.5,
		amp = o.amp or 0.3,
		speed = o.speed or 50,
		omega = 2 * math.pi / (o.period or 3),
	}
	stroke.Transparency = o.base or 0.5
	if RunService:IsClient() and not glowConn then
		glowConn = RunService.Heartbeat:Connect(glowStep)
	end
	return stroke
end

-- Lepas glow (garis kembali statis dengan warna & transparansi yang diberikan).
function ThemeColor.unglow(stroke: UIStroke, color: Color3?, transparency: number?)
	glows[stroke] = nil
	local grad = stroke:FindFirstChild(GLOW_NAME)
	if grad then
		grad:Destroy()
	end
	stroke.Color = color or tokens.LINE
	stroke.Transparency = transparency or 0.9
end

local function refreshGlows()
	local seq = glowSequence()
	for _, g in glows do
		g.grad.Color = seq
	end
end

-- ── sorot hover tombol ────────────────────────────────────────────────────────────────────────────────────────────
-- Semua GuiButton di ScreenGui bertanda (mark) disorot garis tepi bergerak (glow "hover") saat kursor di atasnya; layar
-- sentuh: selama ditekan + Config.hover.touchHold. Garis = UIStroke "ThemeHover" di DALAM tepi tombol
-- (BorderStrokePosition.Inner → tidak terpotong ScrollingFrame / ClipsDescendants), hanya ada selama disorot lalu
-- dihancurkan, Archivable = false (tidak ikut Clone). Tombol teks transparan tanpa UICorner diberi sudut pil sementara.
-- Tidak disorot: tombol tak terlihat (latar & garis transparan, tanpa teks), sisi < minSize, luas > maxArea layar
-- (lapisan penutup), di dalam ScreenGui tanpa mark, atau di bawah instance beratribut ThemeColor.NO_HOVER.
ThemeColor.NO_HOVER = "ThemeNoHover"
local HOVER_NAME = "ThemeHover"
local HOVER_CORNER = "ThemeHoverCorner"
local hoverStack: { GuiObject } = {} -- tombol yang sedang di bawah kursor (terakhir masuk = paling atas)
local hoverOn: GuiObject? = nil -- tombol yang sedang bergaris sorot
local hoverStroke: UIStroke? = nil -- garis sorot sekarang
local hoverCorner: UICorner? = nil -- sudut pil sementara (tombol teks transparan)
local touchGen = 0
-- Weak key aman di sini: koneksi event tombol memegang tombolnya, jadi entri hidup selama tombol hidup.
local hookedButtons: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local hookedGuis: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local hostOf: { [Instance]: GuiObject } = setmetatable({}, { __mode = "k" }) :: any -- tombol → bentuk visualnya
local UIS: any = nil

-- Tombol yang hanya lapisan klik di atas bentuk lain (mis. teks "Donate" di dalam pil ber-UICorner): garis sorot
-- digambar di bentuk itu supaya pas dengan tepinya (bukan kotak tombol yang lebih kecil).
function ThemeColor.hoverHost(button: GuiObject, host: GuiObject): GuiObject
	hostOf[button] = host
	return button
end

-- ScreenGui bertanda yang sedang menampilkan obj (semua leluhur Visible, ScreenGui Enabled), atau nil.
local function shownIn(obj: Instance): any
	local o: Instance? = obj
	while o do
		if o:GetAttribute(ThemeColor.NO_HOVER) then
			return nil
		end
		if o:IsA("GuiObject") then
			if not (o :: any).Visible then
				return nil
			end
		elseif o:IsA("ScreenGui") then
			return if (o :: any).Enabled and o.Parent ~= nil and o:GetAttribute(ThemeColor.MARK) then o else nil
		elseif o:IsA("LayerCollector") then
			return nil -- SurfaceGui / BillboardGui: bukan panel
		end
		o = o.Parent
	end
	return nil
end

-- nil = tidak disorot · "solid" (latar terlihat) · "line" (punya garis tepi) · "text" (tombol teks transparan)
local function hoverKind(b: GuiObject): string?
	if b.Parent == nil then
		return nil -- dilepas / dihancurkan
	end
	local gui = shownIn(b)
	if not gui then
		return nil
	end
	local cfg = Config.hover
	local size, screen = b.AbsoluteSize, gui.AbsoluteSize
	if math.min(size.X, size.Y) < cfg.minSize or size.X * size.Y > cfg.maxArea * screen.X * screen.Y then
		return nil
	end
	if b.BackgroundTransparency < 0.95 then
		return "solid"
	end
	for _, c in b:GetChildren() do
		if c:IsA("UIStroke") and c.Name ~= HOVER_NAME and c.Enabled and c.Transparency < 0.95 then
			return "line"
		end
	end
	local any = b :: any
	if b:IsA("TextButton") and any.Text ~= "" and any.TextTransparency < 0.95 then
		return "text"
	end
	return nil
end

local function clearRing()
	local s, c = hoverStroke, hoverCorner
	hoverStroke, hoverCorner = nil, nil
	if s then
		glows[s] = nil
		if s.Parent then -- Parent nil = sudah ikut hancur bersama tombolnya
			s:Destroy()
		end
	end
	if c and c.Parent then
		c:Destroy()
	end
end

local function ring(b: GuiObject, kind: string)
	local s = Instance.new("UIStroke")
	s.Name = HOVER_NAME
	s.Archivable = false
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = Config.hover.thickness
	pcall(function() -- garis di dalam tepi (properti UIStroke 2025); gagal → garis di luar tepi (bawaan)
		(s :: any).BorderStrokePosition = (Enum :: any).BorderStrokePosition.Inner
	end)
	s:SetAttribute(ThemeColor.SKIP, true)
	ThemeColor.glow(s, "hover")
	hoverStroke = s
	if kind == "text" and not b:FindFirstChildOfClass("UICorner") then
		local c = Instance.new("UICorner")
		c.Name = HOVER_CORNER
		c.Archivable = false
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = b
		hoverCorner = c
	end
	s.Parent = b
end

-- Garis sorot pindah ke tombol teratas tumpukan yang masih layak; tombol yang tidak layak lagi dibuang.
local function render()
	local target: GuiObject? = nil
	local kind: string? = nil
	for i = #hoverStack, 1, -1 do
		kind = hoverKind(hoverStack[i])
		if kind then
			target = hoverStack[i]
			break
		end
		table.remove(hoverStack, i)
	end
	if target == hoverOn then
		return
	end
	clearRing()
	hoverOn = target
	if target and kind then
		local host, hostKind = target, kind
		local h = hostOf[target]
		local hk = h and hoverKind(h)
		if h and hk then
			host, hostKind = h, hk
		end
		ring(host, hostKind)
	end
end

local function hoverEnter(b: GuiObject)
	local i = table.find(hoverStack, b)
	if i then
		table.remove(hoverStack, i)
	end
	table.insert(hoverStack, b)
	render()
end

local function hoverLeave(b: GuiObject)
	local i = table.find(hoverStack, b)
	if i then
		table.remove(hoverStack, i)
		render()
	end
end

local function touchBegan(b: GuiObject)
	touchGen += 1
	hoverEnter(b)
end

-- Jari diangkat (di mana pun) → sorot hilang sesudah touchHold, kecuali ada sentuhan baru.
local function touchEnded()
	touchGen += 1
	local gen = touchGen
	task.delay(Config.hover.touchHold, function()
		if gen == touchGen then
			table.clear(hoverStack)
			render()
		end
	end)
end

function hoverCheck()
	if hoverOn and hoverKind(hoverOn) == nil then -- disembunyikan / dipindah / dihancurkan tanpa MouseLeave
		render()
	end
end

local function lastIsTouch(): boolean
	return UIS ~= nil and UIS:GetLastInputType() == Enum.UserInputType.Touch
end

-- Sumber utama: GuiObject.GuiState (Idle/Hover/Press, dihitung mesin seperti AutoButtonColor → hanya tombol TERATAS
-- yang Hover; sentuhan = Press selama ditekan). Cadangan kalau properti itu tidak ada: MouseEnter/MouseLeave + sentuh.
local hasGuiState: boolean? = nil

local function hookButton(b: GuiButton)
	if hookedButtons[b] then
		return
	end
	hookedButtons[b] = true
	if hasGuiState == nil then
		hasGuiState = pcall(function()
			return (b :: any).GuiState
		end)
	end
	if hasGuiState then
		local States = (Enum :: any).GuiState
		b:GetPropertyChangedSignal("GuiState"):Connect(function()
			local st = (b :: any).GuiState
			if st == States.Press then
				if lastIsTouch() then
					touchBegan(b) -- dilepas oleh UIS.TouchEnded (+ touchHold)
				else
					hoverEnter(b)
				end
			elseif st == States.Hover then
				if not lastIsTouch() then -- sesudah ketukan, sentuhan tidak "hover"
					hoverEnter(b)
				end
			elseif not lastIsTouch() then
				hoverLeave(b)
			end
		end)
		b.MouseLeave:Connect(function() -- jaring pengaman: kursor keluar dari kotak tombol = pasti bukan hover
			hoverLeave(b)
		end)
		return
	end
	b.MouseEnter:Connect(function()
		if not lastIsTouch() then -- layar sentuh: lewat InputBegan (MouseEnter dari sentuhan tidak pernah "keluar")
			hoverEnter(b)
		end
	end)
	b.MouseLeave:Connect(function()
		hoverLeave(b)
	end)
	b.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchBegan(b)
		end
	end)
end

function hookGui(gui: Instance)
	if not RunService:IsClient() or hookedGuis[gui] then
		return
	end
	local ok = pcall(function() -- (pcall: Lune / tes tidak punya event)
		gui.DescendantAdded:Connect(function(d)
			hookedGuis[gui] = true -- (closure memegang gui → kunci weak tetap hidup selama koneksi ada)
			if d:IsA("GuiButton") then
				hookButton(d)
			end
		end)
	end)
	if not ok then
		return
	end
	hookedGuis[gui] = true
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiButton") then
			hookButton(d)
		end
	end
end

-- Untuk tes (Lune tanpa event): jalankan logika hover langsung.
ThemeColor._hover = {
	enter = hoverEnter,
	leave = hoverLeave,
	touch = touchBegan,
	release = touchEnded,
	check = function()
		hoverCheck()
	end,
	on = function(): GuiObject?
		return hoverOn
	end,
}

-- ── ganti tema ────────────────────────────────────────────────────────────────────────────────────────────────────
function ThemeColor.onChanged(fn: (string, string) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end

-- Pasang tema id (client: dipanggil otomatis dari atribut Player). → true kalau berubah.
function ThemeColor.apply(id: string): boolean
	if type(id) ~= "string" or not Config.presets[id] or id == ThemeColor.current then
		return false
	end
	local old = ThemeColor.current
	fill(id)
	refreshGlows()
	if RunService:IsClient() then
		ThemeColor.repaintAll()
		for _, d in Config.repaintDelays do
			task.delay(d, ThemeColor.repaintAll)
		end
	end
	for _, fn in table.clone(listeners) do
		task.spawn(fn, id, old)
	end
	return true
end

-- ── mulai ─────────────────────────────────────────────────────────────────────────────────────────────────────────
for _, problem in Rules.validate(Config) do
	warn("[ThemeColor] Config: " .. problem)
end
fill(Config.default)

if RunService:IsClient() then
	UIS = game:GetService("UserInputService")
	UIS.TouchEnded:Connect(touchEnded)
	local lp = Players.LocalPlayer
	if lp then
		local function follow()
			local id = lp:GetAttribute(ThemeColor.ATTR)
			if type(id) == "string" then
				ThemeColor.apply(id)
			end
		end
		follow()
		lp:GetAttributeChangedSignal(ThemeColor.ATTR):Connect(follow)
	end
end

return ThemeColor
