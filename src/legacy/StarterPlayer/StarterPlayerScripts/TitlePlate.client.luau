-- ═══════════════════════════════════════════════════════════
-- TitlePlate — StarterPlayer > StarterPlayerScripts
--
-- Menggambar plate title ke dalam "TitleSlot" milik OverheadTag.
--
-- Plate dibangun dalam mode scale (argumen ketiga Build = lebar acuan
-- tag). Semua ukurannya jadi pecahan dari billboard, dan billboard itu
-- sendiri diukur dalam stud — jadi plate ikut mengecil saat zoom out,
-- sama seperti nama dan karakternya. Tidak ada yang dihitung ulang
-- per frame, dan loop animasi mati total kalau tidak ada yang pakai efek.
-- ═══════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local function waitForTitleStyle(timeout)
	local deadline = os.clock() + timeout
	repeat
		local folder = RS:FindFirstChild("CustomUIModules")
		local module = (folder and folder:FindFirstChild("TitleStyle"))
			or RS:FindFirstChild("TitleStyle")
		if module and module:IsA("ModuleScript") then return require(module) end
		task.wait(0.25)
	until os.clock() > deadline
	return nil
end

local TitleStyle = waitForTitleStyle(15)
if not TitleStyle then
	warn("[TitlePlate] ModuleScript 'TitleStyle' tidak ketemu. Plate title dimatikan.")
	return
end

-- Efek dijalankan 30x per detik, bukan tiap frame. Untuk gradient dan
-- pergeseran warna, bedanya tidak kelihatan.
local ANIM_STEP = 1 / 30

local plates   = {}   -- [player] = { tag, slot, refs, style, animated }
local watchers = {}   -- [player] = RBXScriptConnection
local dirty    = {}   -- [player] = true (menunggu repaint)

local renderConn
local clock, accum = 0, 0

-- ── loop animasi ───────────────────────────────────────────

local function step(dt)
	clock += dt
	accum += dt
	if accum < ANIM_STEP then return end
	accum = 0

	for plr, entry in pairs(plates) do
		if not entry.slot.Parent then
			plates[plr] = nil
		elseif entry.animated and entry.tag.Enabled then
			TitleStyle.Animate(entry.refs, entry.style, clock)
		end
	end
end

local function syncLoop()
	local any = false
	for _, entry in pairs(plates) do
		if entry.animated then
			any = true
			break
		end
	end

	if any and not renderConn then
		renderConn = RunService.RenderStepped:Connect(step)
	elseif not any and renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

-- ── gambar ─────────────────────────────────────────────────

local function repaint(plr)
	local entry = plates[plr]
	if not entry then return end
	if not entry.slot.Parent then
		plates[plr] = nil
		syncLoop()
		return
	end

	local style = TitleStyle.Read(plr)

	if not style then
		entry.refs.plate.Visible = false
		entry.animated = false
	else
		entry.refs.plate.Visible = true
		entry.style    = style
		entry.animated = style.effect ~= "None"
		TitleStyle.Paint(entry.refs, style)
		TitleStyle.Animate(entry.refs, style, clock)
	end

	syncLoop()
end

-- Ganti satu title menulis 7 attribute sekaligus. Tanpa antrian ini,
-- Paint jalan 7 kali untuk satu perubahan.
local function queueRepaint(plr)
	if dirty[plr] then return end
	dirty[plr] = true
	task.defer(function()
		dirty[plr] = nil
		repaint(plr)
	end)
end

local function bind(plr, tag, slot)
	local entry = plates[plr]
	if entry and entry.slot == slot then
		repaint(plr)
		return
	end

	plates[plr] = {
		tag  = tag,
		slot = slot,
		-- Argumen ketiga = mode scale. Ini yang bikin plate ikut skala dunia.
		refs = TitleStyle.Build(slot, TitleStyle.TEXT_SIZE, TitleStyle.TAG_W),
	}
	repaint(plr)
end

-- ── ikuti character ────────────────────────────────────────

local function attach(plr, inst)
	if inst.Name ~= "OverheadTag" or not inst:IsA("BillboardGui") then return end
	task.spawn(function()
		local slot = inst:WaitForChild("TitleSlot", 5)
		if slot and inst.Parent then bind(plr, inst, slot) end
	end)
end

-- DescendantAdded, bukan CharacterAdded: Head bisa diganti instance baru
-- oleh ApplyDescription (/headless, /size) tanpa character ikut ganti.
local function watchCharacter(plr, char)
	if watchers[plr] then watchers[plr]:Disconnect() end
	watchers[plr] = char.DescendantAdded:Connect(function(d) attach(plr, d) end)
	for _, d in ipairs(char:GetDescendants()) do attach(plr, d) end
end

local function watch(plr)
	for _, attribute in ipairs(TitleStyle.ATTRIBUTES) do
		plr:GetAttributeChangedSignal(attribute):Connect(function()
			queueRepaint(plr)
		end)
	end

	plr.CharacterAdded:Connect(function(char)
		watchCharacter(plr, char)
	end)

	if plr.Character then watchCharacter(plr, plr.Character) end
end

local function remove(plr)
	plates[plr] = nil
	dirty[plr]  = nil
	if watchers[plr] then
		watchers[plr]:Disconnect()
		watchers[plr] = nil
	end
	syncLoop()
end

for _, plr in ipairs(Players:GetPlayers()) do watch(plr) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(remove)