-- ═══════════════════════════════════════════════════════════
-- AdminTitleService — ServerScriptService
--
-- SATU DATASTORE: "AdminTitles". Titik.
-- Tidak ada store cadangan, tidak ada migrasi antar store, dan jangan
-- pernah bikin nama store baru lagi. Pengecualian: Play di Studio memakai
-- "AdminTitles_studio" supaya uji tidak menulis title live.
--
-- Kalau nanti ada field baru, cukup tambahkan di normalize() dengan
-- nilai default — data lama tetap kebaca dari store yang sama.
-- ═══════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TextService      = game:GetService("TextService")
local SSS              = game:GetService("ServerScriptService")
local RunService       = game:GetService("RunService")

local TitleStyle
do
	local folder = RS:FindFirstChild("CustomUIModules")
	local module = (folder and folder:FindFirstChild("TitleStyle"))
		or RS:FindFirstChild("TitleStyle")
	if not (module and module:IsA("ModuleScript")) then
		warn("[AdminTitle] ModuleScript 'TitleStyle' tidak ada di ReplicatedStorage. Service dimatikan.")
		return
	end
	TitleStyle = require(module)
end

local RankConfig      = require(SSS:WaitForChild("RankConfig"))
local RankRules       = require(SSS:WaitForChild("RankRules"))
local attributesReady = SSS:WaitForChild("PlayerAttributesReady", 30)

-- ── DATASTORE ──────────────────────────────────────────────

local STORE_NAME = "AdminTitles" .. (RunService:IsStudio() and "_studio" or "")
local store      = DataStoreService:GetDataStore(STORE_NAME)

-- [userId] = data | false (sudah dicek, tidak punya title)
-- Cegah GetAsync ditembak dua kali untuk player yang sama.
local cache = {}

local MANAGE_RANK = RankConfig.ADMIN_MIN_RANK -- sama dengan atribut IsAdmin
local COOLDOWN    = 0.75
local MAX_CHARS   = 30
local ACCESS_GAP  = 1    -- detik antar CheckAccess per pemain (lebih cepat → jawab tanpa menunggu)
local LIST_GAP    = 0.5  -- detik antar GetPlayers per admin (lebih cepat → daftar terakhir)
local LOAD_RETRY_AT    = { 5, 15, 30, 60 } -- detik; GetAsync title gagal saat join → coba lagi
local LOAD_RETRY_EVERY = 60                -- lalu tiap sekian detik selama pemain masih di server

local DEFAULTS = {
	text       = "",
	color      = "FFFFFF",
	plate      = "Fade",
	plateColor = "121215",
	font       = "Builder",
	effect     = "None",
	outline    = true,
}

-- Nama font/efek lama yang pernah tersimpan di store ini.
local FONT_ALIAS = {
	GothamBlack = "Gotham", GothamBold = "Bold", Gotham = "Bold",
	SourceSans = "Source", SourceSansBold = "Source",
	Arial = "Source", ArialBold = "Source", Creepster = "Creepy",
}
local EFFECT_ALIAS = { Shimmer = "Pulse", Wave = "None" }

-- ── remotes ────────────────────────────────────────────────

local folder = RS:FindFirstChild("AdminTitles")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "AdminTitles"
	folder.Parent = RS
end

local function remote(class, name)
	local found = folder:FindFirstChild(name)
	if not found then
		found = Instance.new(class)
		found.Name = name
		found.Parent = folder
	end
	return found
end

local checkAccess  = remote("RemoteFunction", "CheckAccess")
local getPlayers   = remote("RemoteFunction", "GetPlayers")
local setTitle     = remote("RemoteEvent",    "SetTitle")
local clearTitle   = remote("RemoteEvent",    "ClearTitle")
local titleUpdated = remote("RemoteEvent",    "TitleUpdated")
-- Jawaban SetTitle/ClearTitle ke admin pengirim:
-- (aksi "set"/"clear", targetId, ok, alasan, nomor permintaan dari client).
-- Alasan: access, cooldown, invalid, target, empty, filter, save.
-- Dulu panel selalu bilang "Tersimpan" walau server menolak.
local titleResult  = remote("RemoteEvent",    "TitleResult")

-- ── helpers ────────────────────────────────────────────────

local lastAction = {}
local lastAccess = {}
local lastList   = {} -- [userId] = { at = os.clock(), list = {...} }

local function reply(plr, action, targetId, ok, reason, req)
	if plr and plr.Parent then
		titleResult:FireClient(plr, action,
			type(targetId) == "number" and targetId or nil, ok, reason,
			type(req) == "number" and req or nil)
	end
end

local function canManage(plr)
	return plr and (plr:GetAttribute("EffectiveRank") or 0) >= MANAGE_RANK
end

local function onCooldown(plr)
	local now = os.clock()
	if now - (lastAction[plr.UserId] or 0) < COOLDOWN then return true end
	lastAction[plr.UserId] = now
	return false
end

local function clampChars(str, max)
	local ok, count = pcall(utf8.len, str)
	if not ok or not count then return str:sub(1, max) end
	if count <= max then return str end
	local offset = utf8.offset(str, max + 1)
	return offset and str:sub(1, offset - 1) or str:sub(1, max)
end

local function validHex(hex, fallback)
	if type(hex) ~= "string" then return fallback end
	hex = hex:gsub("#", ""):upper()
	if #hex == 6 and hex:match("^%x+$") then return hex end
	return fallback
end

local function filterText(str, fromUserId)
	local ok, result = pcall(function()
		return TextService
			:FilterStringAsync(str, fromUserId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)
	return ok and result or nil
end

-- ── bentuk data ────────────────────────────────────────────
-- Store ini pernah diisi dua bentuk:
--   lama : title, colorHex, stroke, badgeColor
--   baru : text, color, outline, plate, plateColor
-- Keduanya dibaca di sini, disimpan ulang dalam bentuk baru.

local function normalize(data)
	if type(data) ~= "table" then return nil end

	local text = data.text or data.title
	if type(text) ~= "string" or text == "" then return nil end

	local font = data.font
	font = TitleStyle.VALID_FONT[font] and font or FONT_ALIAS[font] or DEFAULTS.font

	local effect = data.effect
	effect = TitleStyle.VALID_EFFECT[effect] and effect or EFFECT_ALIAS[effect] or DEFAULTS.effect

	local outline
	if data.outline ~= nil then
		outline = data.outline ~= false
	elseif data.stroke ~= nil then
		outline = data.stroke == true
	else
		outline = DEFAULTS.outline
	end

	-- Data bentuk lama belum mengenal plate: tampilkan sebagai teks polos,
	-- persis seperti tampilannya dulu.
	local plate = data.plate
	if not TitleStyle.VALID_PLATE[plate] then
		plate = data.title and "None" or DEFAULTS.plate
	end

	return {
		text       = text,
		color      = validHex(data.color or data.colorHex, DEFAULTS.color),
		plate      = plate,
		plateColor = validHex(data.plateColor or data.badgeColor, DEFAULTS.plateColor),
		font       = font,
		effect     = effect,
		outline    = outline,
		assignedBy = data.assignedBy or data.by,
		assignedAt = data.assignedAt or data.at,
	}
end

-- ── baca / tulis ───────────────────────────────────────────

-- onDone(ok): dipanggil setelah tulisan berhasil / semua percobaan gagal.
local function save(userId, data, onDone)
	cache[userId] = data or false

	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				if data then
					store:SetAsync(tostring(userId), data)
				else
					store:RemoveAsync(tostring(userId))
				end
			end)
			if ok then
				print(("[AdminTitle] tersimpan untuk %d%s"):format(
					userId, data and "" or " (dihapus)"))
				if onDone then onDone(true) end
				return
			end
			warn(("[AdminTitle] percobaan %d gagal: %s"):format(attempt, tostring(err)))
			task.wait(attempt * 2)
		end
		warn("[AdminTitle] gagal menyimpan data untuk " .. userId
			.. " — di Studio, aktifkan Game Settings > Security > Enable Studio Access to API Services.")
		if onDone then onDone(false) end
	end)
end

-- Kembalian: data (atau nil), terbaca? (false = GetAsync gagal).
local function load(userId)
	local cached = cache[userId]
	if cached ~= nil then return cached or nil, true end

	local ok, data = pcall(store.GetAsync, store, tostring(userId))
	-- Admin bisa memasang/menghapus title selama GetAsync menunggu: nilai
	-- itu yang terbaru, jangan ditimpa data lama dari store.
	local fresh = cache[userId]
	if fresh ~= nil then return fresh or nil, true end
	if not ok then
		-- Gagal baca BUKAN berarti tidak punya title. Jangan di-cache dan
		-- jangan ditimpa, supaya data yang ada tidak ketutup default kosong.
		warn(("[AdminTitle] gagal membaca %d: %s"):format(userId, tostring(data)))
		return nil, false
	end

	local current = normalize(data)
	cache[userId] = current or false
	return current, true
end

-- ── apply ──────────────────────────────────────────────────

local function apply(plr, data)
	if not (plr and plr.Parent) then return end

	local has = data and type(data.text) == "string" and data.text ~= ""
	if not has then data = nil end

	-- Field boolean tidak boleh lewat pola `a and b or c`: kalau b bernilai
	-- false, hasilnya jatuh ke c dan nilainya terbalik.
	local outline = DEFAULTS.outline
	if data then outline = data.outline ~= false end

	plr:SetAttribute("TitleText",       data and data.text       or DEFAULTS.text)
	plr:SetAttribute("TitleColor",      data and data.color      or DEFAULTS.color)
	plr:SetAttribute("TitlePlate",      data and data.plate      or DEFAULTS.plate)
	plr:SetAttribute("TitlePlateColor", data and data.plateColor or DEFAULTS.plateColor)
	plr:SetAttribute("TitleFont",       data and data.font       or DEFAULTS.font)
	plr:SetAttribute("TitleEffect",     data and data.effect     or DEFAULTS.effect)
	plr:SetAttribute("TitleOutline",    outline)

	table.clear(lastList) -- daftar GetPlayers yang ditahan sudah basi
	titleUpdated:FireAllClients(plr.UserId)
end

local retrying = {} -- [player] = true selama coba-baca ulang

-- GetAsync gagal saat join → title kosong dulu, lalu dibaca ulang di latar
-- (LOAD_RETRY_AT, lalu tiap LOAD_RETRY_EVERY). Dulu title hilang sepanjang sesi.
local function retryLoad(plr)
	if retrying[plr] then return end
	retrying[plr] = true
	task.spawn(function()
		local attempt = 0
		while plr.Parent and retrying[plr] do
			attempt += 1
			task.wait(RankRules.waitBefore(LOAD_RETRY_AT, LOAD_RETRY_EVERY, attempt))
			if not (plr.Parent and retrying[plr]) then break end
			local data, ok = load(plr.UserId)
			if ok then
				retrying[plr] = nil
				apply(plr, data)
				return
			end
		end
		retrying[plr] = nil
	end)
end

local function restore(plr)
	local data, ok = load(plr.UserId)
	apply(plr, data)
	if not ok then retryLoad(plr) end
end

-- ── handlers ───────────────────────────────────────────────

checkAccess.OnServerInvoke = function(plr)
	-- Rate limit: panggilan beruntun dijawab langsung tanpa menunggu (satu
	-- pemain tidak bisa menahan banyak thread server 5 dtk sekaligus).
	local now = os.clock()
	if lastAccess[plr.UserId] and now - lastAccess[plr.UserId] < ACCESS_GAP then
		return canManage(plr)
	end
	lastAccess[plr.UserId] = now

	local waited = 0
	while plr:GetAttribute("EffectiveRank") == nil and waited < 5 do
		task.wait(0.2)
		waited += 0.2
	end
	return canManage(plr)
end

getPlayers.OnServerInvoke = function(plr)
	if not canManage(plr) then return {} end
	local now = os.clock()
	local last = lastList[plr.UserId]
	if last and now - last.at < LIST_GAP then return last.list end

	local list = {}
	for _, target in ipairs(Players:GetPlayers()) do
		local roleName = target:GetAttribute("Role") or "Guest"
		local rank = RankConfig.RANKS[roleName] or RankConfig.RANKS.Guest
		local text = target:GetAttribute("TitleText") or ""

		table.insert(list, {
			UserId        = target.UserId,
			Name          = target.Name,
			DisplayName   = target.DisplayName,
			RoleDisplay   = (rank and rank.displayText) or "GUEST",
			EffectiveRank = target:GetAttribute("EffectiveRank") or 0,
			HasTitle      = text ~= "",
			Title         = text,
			Color         = target:GetAttribute("TitleColor")      or DEFAULTS.color,
			Plate         = target:GetAttribute("TitlePlate")      or DEFAULTS.plate,
			PlateColor    = target:GetAttribute("TitlePlateColor") or DEFAULTS.plateColor,
			Font          = target:GetAttribute("TitleFont")       or DEFAULTS.font,
			Effect        = target:GetAttribute("TitleEffect")     or DEFAULTS.effect,
			Outline       = target:GetAttribute("TitleOutline")    ~= false,
		})
	end

	table.sort(list, function(a, b)
		if a.EffectiveRank == b.EffectiveRank then
			return a.DisplayName < b.DisplayName
		end
		return a.EffectiveRank > b.EffectiveRank
	end)
	lastList[plr.UserId] = { at = now, list = list }
	return list
end

setTitle.OnServerEvent:Connect(function(sender, targetId, payload)
	local req = type(payload) == "table" and payload.req or nil
	local function answer(ok, reason) reply(sender, "set", targetId, ok, reason, req) end

	if not canManage(sender) then return answer(false, "access") end
	if onCooldown(sender) then return answer(false, "cooldown") end
	if type(targetId) ~= "number" or type(payload) ~= "table" then return answer(false, "invalid") end

	local target = Players:GetPlayerByUserId(targetId)
	if not target then return answer(false, "target") end

	local raw = clampChars(tostring(payload.text or ""):match("^%s*(.-)%s*$"), MAX_CHARS)
	if raw == "" then return answer(false, "empty") end

	local safe = filterText(raw, sender.UserId)
	if not safe or safe == "" then
		warn("[AdminTitle] title ditolak filter untuk " .. target.Name)
		return answer(false, "filter")
	end

	local data = {
		text       = safe,
		color      = validHex(payload.color, DEFAULTS.color),
		plateColor = validHex(payload.plateColor, DEFAULTS.plateColor),
		plate      = TitleStyle.VALID_PLATE[payload.plate]   and payload.plate  or DEFAULTS.plate,
		font       = TitleStyle.VALID_FONT[payload.font]     and payload.font   or DEFAULTS.font,
		effect     = TitleStyle.VALID_EFFECT[payload.effect] and payload.effect or DEFAULTS.effect,
		outline    = payload.outline ~= false,
		assignedBy = sender.UserId,
		assignedAt = os.time(),
	}

	save(targetId, data, function(ok)
		answer(ok, not ok and "save" or nil)
	end)
	apply(target, data)
end)

clearTitle.OnServerEvent:Connect(function(sender, targetId, req)
	local function answer(ok, reason) reply(sender, "clear", targetId, ok, reason, req) end

	if not canManage(sender) then return answer(false, "access") end
	if onCooldown(sender) then return answer(false, "cooldown") end
	if type(targetId) ~= "number" then return answer(false, "invalid") end

	local target = Players:GetPlayerByUserId(targetId)
	if not target then return answer(false, "target") end

	save(targetId, nil, function(ok)
		answer(ok, not ok and "save" or nil)
	end)
	apply(target, nil)
end)

-- ── lifecycle ──────────────────────────────────────────────

if attributesReady then
	attributesReady.Event:Connect(function(plr)
		task.spawn(restore, plr)
	end)
end

Players.PlayerRemoving:Connect(function(plr)
	lastAction[plr.UserId] = nil
	lastAccess[plr.UserId] = nil
	lastList[plr.UserId]   = nil
	cache[plr.UserId]      = nil
	retrying[plr]          = nil
end)

for _, plr in ipairs(Players:GetPlayers()) do
	if plr:GetAttribute("EffectiveRank") ~= nil then
		task.spawn(restore, plr)
	end
end

print("[AdminTitle] Ready — store: " .. STORE_NAME)