-- ═══════════════════════════════════════════════════════════
-- AdminTitleService — ServerScriptService
--
-- SATU DATASTORE: "AdminTitles". Titik.
-- Tidak ada store cadangan, tidak ada migrasi antar store, dan jangan
-- pernah bikin nama store baru lagi.
--
-- Kalau nanti ada field baru, cukup tambahkan di normalize() dengan
-- nilai default — data lama tetap kebaca dari store yang sama.
-- ═══════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TextService      = game:GetService("TextService")
local SSS              = game:GetService("ServerScriptService")

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
local attributesReady = SSS:WaitForChild("PlayerAttributesReady", 30)

-- ── DATASTORE ──────────────────────────────────────────────

local STORE_NAME = "AdminTitles"
local store      = DataStoreService:GetDataStore(STORE_NAME)

-- [userId] = data | false (sudah dicek, tidak punya title)
-- Cegah GetAsync ditembak dua kali untuk player yang sama.
local cache = {}

local MANAGE_RANK = 250
local COOLDOWN    = 0.75
local MAX_CHARS   = 30

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

-- ── helpers ────────────────────────────────────────────────

local lastAction = {}

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

local function save(userId, data)
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
				return
			end
			warn(("[AdminTitle] percobaan %d gagal: %s"):format(attempt, tostring(err)))
			task.wait(attempt * 2)
		end
		warn("[AdminTitle] gagal menyimpan data untuk " .. userId
			.. " — di Studio, aktifkan Game Settings > Security > Enable Studio Access to API Services.")
	end)
end

local function load(userId)
	local cached = cache[userId]
	if cached ~= nil then return cached or nil end

	local ok, data = pcall(store.GetAsync, store, tostring(userId))
	if not ok then
		-- Gagal baca BUKAN berarti tidak punya title. Jangan di-cache dan
		-- jangan ditimpa, supaya data yang ada tidak ketutup default kosong.
		warn(("[AdminTitle] gagal membaca %d: %s"):format(userId, tostring(data)))
		return nil
	end

	local current = normalize(data)
	cache[userId] = current or false
	return current
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

	titleUpdated:FireAllClients(plr.UserId)
end

local function restore(plr)
	apply(plr, load(plr.UserId))
end

-- ── handlers ───────────────────────────────────────────────

checkAccess.OnServerInvoke = function(plr)
	local waited = 0
	while plr:GetAttribute("EffectiveRank") == nil and waited < 5 do
		task.wait(0.2)
		waited += 0.2
	end
	return canManage(plr)
end

getPlayers.OnServerInvoke = function(plr)
	if not canManage(plr) then return {} end

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
	return list
end

setTitle.OnServerEvent:Connect(function(sender, targetId, payload)
	if not canManage(sender) then return end
	if onCooldown(sender) then return end
	if type(targetId) ~= "number" or type(payload) ~= "table" then return end

	local target = Players:GetPlayerByUserId(targetId)
	if not target then return end

	local raw = clampChars(tostring(payload.text or ""):match("^%s*(.-)%s*$"), MAX_CHARS)
	if raw == "" then return end

	local safe = filterText(raw, sender.UserId)
	if not safe or safe == "" then
		warn("[AdminTitle] title ditolak filter untuk " .. target.Name)
		return
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

	save(targetId, data)
	apply(target, data)
end)

clearTitle.OnServerEvent:Connect(function(sender, targetId)
	if not canManage(sender) then return end
	if onCooldown(sender) then return end
	if type(targetId) ~= "number" then return end

	local target = Players:GetPlayerByUserId(targetId)
	if not target then return end

	save(targetId, nil)
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
	cache[plr.UserId]      = nil
end)

for _, plr in ipairs(Players:GetPlayers()) do
	if plr:GetAttribute("EffectiveRank") ~= nil then
		task.spawn(restore, plr)
	end
end

print("[AdminTitle] Ready — store: " .. STORE_NAME)