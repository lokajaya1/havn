-- ═══════════════════════════════════════════════════════════
-- COMMAND SERVER
-- Location : ServerScriptService > CommandServer  (Script)
--
-- Gate akses per-command:
--   • FREE_CMDS (/re /normal /rejoin) → semua player, tanpa gamepass.
--   • Command lain → Creator | rank group Admin+ | gamepass Commands.
-- Semua path (RemoteEvent & chat) lewat tryExec yang sama.
-- ApplyDescription memancarkan "PlayerAppearanceApplied" agar
-- OverheadTag/BillboardGui bisa dipasang ulang setelah Head diganti.
-- ═══════════════════════════════════════════════════════════

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MarketplaceSvc  = game:GetService("MarketplaceService")
local RS              = game:GetService("ReplicatedStorage")
local SSS             = game:GetService("ServerScriptService")
local TextService     = game:GetService("TextService")

local RankConfig = require(SSS:WaitForChild("RankConfig", 15))
if not RankConfig then
	error("[CommandServer] RankConfig tidak ditemukan!")
end

local GROUP_ID       = RankConfig.GROUP_ID
local ADMIN_MIN_RANK = RankConfig.ADMIN_MIN_RANK
local PASS_NAME      = "Commands"
local ShopConfig     = require(RS:WaitForChild("ShopConfig"))
local COMMANDS_INFO  = ShopConfig.getGamepassByName(PASS_NAME)
local COMMANDS_PASS  = COMMANDS_INFO.id
local UNDO_MAX       = 5
local MAX_ARGS       = 8
local MAX_ARG_LEN    = 50

-- Daftar perintah, perintah gratis & cooldown: satu sumber dengan CommandPanel
local CommandShared = require(RS:WaitForChild("CommandShared"))
local FREE_CMDS     = CommandShared.FREE

-- Tunggu ShopServer (opsional)
do
	local t = 0
	while type(_G.ShopHasGamepass) ~= "function" and t < 15 do
		task.wait(0.5); t += 0.5
	end
	if type(_G.ShopHasGamepass) ~= "function" then
		warn("[CommandServer] ShopServer tidak ditemukan. Fallback ke MarketplaceService.")
	end
end

-- ── Helpers umum ──────────────────────────────────────────
-- Potong maks n KARAKTER tanpa membelah huruf UTF-8 (sub() memotong byte).
local function utf8Prefix(s, n)
	local ok, cut = pcall(utf8.offset, s, n + 1)
	if ok and cut then return s:sub(1, cut - 1) end
	return s
end

local function safeCall(fn, errLabel, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[CommandServer] %s: %s"):format(errLabel, tostring(err)))
	end
	return ok, err
end

-- ── Cache per userId ──────────────────────────────────────
local _passCache = {}
local _rankCache = {}
local undoStacks = {}
local stamps     = {}
local buckets    = {}

-- Kuota bersama semua perintah (remote + chat) per pemain, di atas cooldown per
-- perintah: 5 perintah beruntun, lalu terisi 2 per detik.
local BUCKET_MAX  = 5
local BUCKET_RATE = 2

local function invalidatePassCache(uid) _passCache[uid] = nil end

-- ── Access checks ─────────────────────────────────────────
-- Hasil hanya dicache kalau API tidak error; error = coba lagi di perintah berikutnya.
local function checkPassDirect(player)
	local uid = player.UserId
	if _passCache[uid] ~= nil then return _passCache[uid] end
	-- pass baru ATAU pass HAVN lama
	local owned, errored = ShopConfig.userOwnsPass(uid, COMMANDS_INFO)
	if owned or not errored then _passCache[uid] = owned == true end
	return owned == true
end

local function getGroupRank(player)
	local uid = player.UserId
	if _rankCache[uid] ~= nil then return _rankCache[uid] end
	local ok, rank = pcall(player.GetRankInGroup, player, GROUP_ID)
	if not ok or type(rank) ~= "number" then return 0 end
	_rankCache[uid] = rank
	return rank
end

local function hasGamepass(player)
	if type(_G.ShopHasGamepass) == "function" then
		local ok, result = pcall(_G.ShopHasGamepass, player, PASS_NAME)
		if ok then return result end
	end
	return checkPassDirect(player)
end

local function isCreator(player)
	return game.CreatorType == Enum.CreatorType.User
		and player.UserId == game.CreatorId
end

local function hasAccess(player)
	return isCreator(player)
		or getGroupRank(player) >= ADMIN_MIN_RANK
		or hasGamepass(player)
end

-- ── Remote / Bindable events ──────────────────────────────
local function getOrCreate(class, name, parent)
	local ex = parent:FindFirstChild(name)
	if ex and ex:IsA(class) then return ex end
	local inst = Instance.new(class)
	inst.Name   = name
	inst.Parent = parent
	return inst
end

local event             = getOrCreate("RemoteEvent",  "QuickCommandExec",       RS)
local accessEvent       = getOrCreate("RemoteEvent",  "CommandAccessUpdated",   RS)
local appearanceApplied = getOrCreate("BindableEvent", "PlayerAppearanceApplied", SSS)

-- ── Asset & warna ─────────────────────────────────────────
local ASSET = { HEADLESS = 134082579, KORBLOX = 139607718, DEFAULT = 0 }

local COLORS = {
	red    = Color3.fromRGB(255, 60,  60),
	blue   = Color3.fromRGB(60,  160, 255),
	green  = Color3.fromRGB(60,  220, 80),
	yellow = Color3.fromRGB(255, 220, 50),
	purple = Color3.fromRGB(180, 80,  255),
	pink   = Color3.fromRGB(255, 120, 180),
	white  = Color3.fromRGB(255, 255, 255),
	orange = Color3.fromRGB(255, 140, 30),
	cyan   = Color3.fromRGB(50,  230, 220),
	gold   = Color3.fromRGB(255, 195, 40),
	black  = Color3.fromRGB(30,  30,  30),
	teal   = Color3.fromRGB(0,   200, 180),
}

-- ── Helpers karakter ──────────────────────────────────────
local function getHum(p)
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h, c
end

local function getBaseDesc(p)
	local ok, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, p.UserId)
	return ok and d or nil
end

local function getCurrentDesc(p)
	local hum = getHum(p); if not hum then return nil end
	local ok, d = pcall(hum.GetAppliedDescription, hum)
	return ok and d or nil
end

-- reset = true → ApplyDescriptionReset: karakter disamakan PENUH dengan
-- deskripsi walau sudah diubah di luar sistem deskripsi (mis. /clearhats
-- menghapus aksesoris langsung). ApplyDescription biasa hanya menerapkan
-- SELISIH dari deskripsi terakhir, jadi aksesoris yang dihapus tidak kembali.
local function applyDesc(p, hum, d, reset)
	task.spawn(function()
		local method = reset and hum.ApplyDescriptionReset or hum.ApplyDescription
		local ok = safeCall(method, "ApplyDescription gagal", hum, d)
		if ok and p and p.Parent then
			appearanceApplied:Fire(p)
		end
	end)
end

local function fixAccVisibility(char)
	task.defer(function()
		if not char or not char.Parent then return end
		for _, v in ipairs(char:GetChildren()) do
			if v:IsA("Accessory") then
				local h = v:FindFirstChild("Handle")
				if h then h.Transparency = 0 end
			end
		end
	end)
end

local function parseColor(s, def)
	if type(s) ~= "string" then return def end
	if s == "rainbow" then return Color3.fromHSV(math.random(), 0.9, 1) end
	return COLORS[s:lower()] or def
end

-- ── Undo stack ────────────────────────────────────────────
local function pushUndo(p)
	local d = getCurrentDesc(p); if not d then return end
	local uid = p.UserId
	undoStacks[uid] = undoStacks[uid] or {}
	local stack = undoStacks[uid]
	table.insert(stack, d)
	if #stack > UNDO_MAX then table.remove(stack, 1) end
end

local function popUndo(p)
	local stack = undoStacks[p.UserId]
	return (stack and #stack > 0) and table.remove(stack) or nil
end

-- ── Effect helpers ────────────────────────────────────────
local function toggleAttr(char, key)
	local v = char:GetAttribute(key) ~= true
	char:SetAttribute(key, v)
	return v
end

local function toggleDescProp(p, attrKey, propKey, assetOn, assetOff)
	local hum, char = getHum(p); if not hum then return end
	pushUndo(p)
	local on   = toggleAttr(char, attrKey)
	local desc = getCurrentDesc(p); if not desc then return end
	if on then
		desc[propKey] = assetOn
	else
		local base = getBaseDesc(p)
		local orig = base and base[propKey] or ASSET.DEFAULT
		desc[propKey] = (orig == assetOn) and assetOff or orig
	end
	applyDesc(p, hum, desc)
	fixAccVisibility(char)
end

local function toggleHRPEffect(p, name, creator)
	local _, char = getHum(p); if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local ex  = hrp:FindFirstChild(name)
	if ex then ex:Destroy(); return end
	local inst = creator()
	inst.Name   = name
	inst.Parent = hrp
end

local DT_ATTRS = {"DT_Headless", "DT_Korblox", "DT_Ghost", "DT_NoHat"}

local function clearDTEffects(char)
	for _, v in ipairs(char:GetDescendants()) do
		if v.Name:sub(1, 3) == "DT_" then pcall(v.Destroy, v) end
	end
	for _, k in ipairs(DT_ATTRS) do char:SetAttribute(k, false) end
	char:SetAttribute("DT_Status", nil)
	char:SetAttribute("DT_StatusKind", nil)
end

-- Reset hanya kalau Humanoid sudah punya HumanoidDescription (Reset tanpa
-- deskripsi pernah membuat server crash, DevForum 1819128) dan pemain tidak
-- sedang carry (CarryWeld menempel di UpperTorso; Reset membangun ulang
-- karakter — belum terbukti aman untuk las carry). Selain itu cara lama.
local function canReset(p, hum)
	return hum:FindFirstChildOfClass("HumanoidDescription") ~= nil
		and p:GetAttribute("InCarry") ~= true
		and p:GetAttribute("Carried") ~= true
end

local function resetToBaseDesc(p, char, hum)
	clearDTEffects(char)
	local base = getBaseDesc(p)
	if base and hum then applyDesc(p, hum, base, canReset(p, hum)) end
	fixAccVisibility(char)
end

-- ═══════════════════════════════════════════════════════════
-- COMMAND HANDLERS
-- ═══════════════════════════════════════════════════════════
local H = {}

-- Gratis
H.re = function(p)
	local hum, char = getHum(p); if not char then return end
	resetToBaseDesc(p, char, hum)
end

H.normal = function(p)
	local hum, char = getHum(p); if not char then return end
	resetToBaseDesc(p, char, hum)
	for _, v in ipairs(char:GetDescendants()) do
		if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
			v.Transparency = 0
		end
	end
end

-- /rejoin kembali ke server YANG SAMA kalau server ini publik
-- (TeleportOptions.ServerInstanceId = JobId). Server privat/reserved tidak bisa
-- dituju begitu → cara lama (server publik mana saja). Gagal ke server yang
-- sama (mis. penuh) → sekali coba cara lama.
local rejoinSame = {}

local function rejoinAny(p)
	safeCall(TeleportService.TeleportAsync, "Rejoin gagal (" .. p.Name .. ")",
		TeleportService, game.PlaceId, {p})
end

H.rejoin = function(p)
	task.spawn(function()
		if game.PrivateServerId ~= "" or game.JobId == "" then
			rejoinAny(p)
			return
		end
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = game.JobId
		rejoinSame[p.UserId] = true
		local ok = safeCall(TeleportService.TeleportAsync, "Rejoin ke server sama gagal (" .. p.Name .. ")",
			TeleportService, game.PlaceId, {p}, options)
		if not ok and rejoinSame[p.UserId] then
			rejoinSame[p.UserId] = nil
			rejoinAny(p)
		end
	end)
end

TeleportService.TeleportInitFailed:Connect(function(p)
	if not (p and rejoinSame[p.UserId]) then return end
	rejoinSame[p.UserId] = nil
	if p.Parent then rejoinAny(p) end
end)

-- Butuh akses
H.reset = function(p)
	local hum = getHum(p)
	if hum then hum.Health = 0 end
end

H.sit   = function(p) local h = getHum(p); if h then h.Sit = true end end
H.stand = function(p) local h = getHum(p); if h then h.Sit = false; h.Jump = true end end

-- Status di atas kepala (/afk, /nametag) = SATU slot di OverheadTag (di antara
-- title dan nama). Server hanya menulis atribut character; OverheadTag yang
-- menggambar pill-nya (lebar ikut teks). /nametag menimpa AFK dan sebaliknya.
-- Atribut di CHARACTER: hilang saat respawn (sama seperti label lama), tetap
-- ada saat Head diganti ApplyDescription (/headless, /size).
local STATUS_MAX_CHARS = 40

local function setStatus(char, text, kind)
	char:SetAttribute("DT_StatusKind", kind)
	char:SetAttribute("DT_Status", text)
end

H.afk = function(p)
	local _, char = getHum(p); if not char then return end
	if char:GetAttribute("DT_StatusKind") == "afk" then
		setStatus(char, nil, nil) -- toggle mati
	else
		setStatus(char, "AFK", "afk")
	end
end

H.headless = function(p) toggleDescProp(p, "DT_Headless", "Head",     ASSET.HEADLESS, ASSET.DEFAULT) end
H.korblox  = function(p) toggleDescProp(p, "DT_Korblox",  "RightLeg", ASSET.KORBLOX,  ASSET.DEFAULT) end

H.size = function(p, args)
	local n = tonumber(args[1]); if n ~= n then n = nil end -- tolak NaN ("nan" lolos math.clamp)
	n = math.clamp(n or 1, 0.1, 1)
	local hum = getHum(p); if not hum then return end
	pushUndo(p)
	local desc = getCurrentDesc(p); if not desc then return end
	desc.HeightScale = n
	desc.WidthScale  = n
	desc.DepthScale  = n
	desc.HeadScale   = math.clamp(n + 0.1, 0.25, 1)
	applyDesc(p, hum, desc)
end

H.ghost = function(p)
	local _, char = getHum(p); if not char then return end
	local on = toggleAttr(char, "DT_Ghost")
	for _, v in ipairs(char:GetDescendants()) do
		if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
			v.Transparency = on and 0.7 or 0
		end
	end
	if not on then fixAccVisibility(char) end
end

H.clearhats = function(p)
	local _, char = getHum(p); if not char then return end
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Accessory") then v:Destroy() end
	end
end

H.hat = function(p)
	local _, char = getHum(p); if not char then return end
	local hide = toggleAttr(char, "DT_NoHat")
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Accessory") then
			local h = v:FindFirstChild("Handle")
			if h then h.Transparency = hide and 1 or 0 end
		end
	end
end

H.highlight = function(p, args)
	local _, char = getHum(p); if not char then return end
	local ex = char:FindFirstChild("DT_Highlight")
	if ex and ex:IsA("Highlight") then ex:Destroy(); return end
	local color = parseColor(args[1], Color3.fromRGB(255, 255, 255))
	local hi    = Instance.new("Highlight")
	hi.Name                = "DT_Highlight"
	hi.FillColor           = color
	hi.OutlineColor        = color
	hi.FillTransparency    = 0.75
	hi.OutlineTransparency = 0
	hi.Adornee             = char
	hi.Parent              = char
end

H.sparkle = function(p, args)
	local color = parseColor(args[1], Color3.fromRGB(255, 255, 255))
	toggleHRPEffect(p, "DT_Sparkle", function()
		local pe = Instance.new("ParticleEmitter")
		pe.Color          = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
		pe.LightEmission  = 1
		pe.LightInfluence = 0.1
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Speed       = NumberRange.new(2, 6)
		pe.Rate        = 25
		pe.Lifetime    = NumberRange.new(1, 2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rotation    = NumberRange.new(0, 360)
		pe.RotSpeed    = NumberRange.new(-90, 90)
		return pe
	end)
end

H.fire = function(p, args)
	local color = parseColor(args[1], Color3.fromRGB(255, 120, 30))
	toggleHRPEffect(p, "DT_Fire", function()
		local fire = Instance.new("Fire")
		fire.Color          = color
		fire.SecondaryColor = color:Lerp(Color3.new(1, 0, 0), 0.4)
		fire.Size           = 3
		fire.Heat           = 6
		return fire
	end)
end

H.smoke = function(p, args)
	local color = parseColor(args[1], Color3.fromRGB(160, 160, 160))
	toggleHRPEffect(p, "DT_Smoke", function()
		local smoke = Instance.new("Smoke")
		smoke.Color        = color
		smoke.Size         = 2
		smoke.RiseVelocity = 4
		smoke.Opacity      = 0.3
		return smoke
	end)
end

H.glow = function(p, args)
	local color = parseColor(args[1], Color3.fromRGB(255, 200, 100))
	toggleHRPEffect(p, "DT_Glow", function()
		local pl = Instance.new("PointLight")
		pl.Brightness = 4
		pl.Range      = 20
		pl.Color      = color
		return pl
	end)
end

H.trail = function(p)
	local _, char = getHum(p); if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end

	if hrp:FindFirstChild("DT_Trail") then
		for _, n in ipairs({"DT_Trail", "DT_TrailA0", "DT_TrailA1"}) do
			local v = hrp:FindFirstChild(n); if v then v:Destroy() end
		end
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name     = "DT_TrailA0"
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent   = hrp

	local a1 = Instance.new("Attachment")
	a1.Name     = "DT_TrailA1"
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent   = hrp

	local tr = Instance.new("Trail")
	tr.Name        = "DT_Trail"
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime    = 0.6
	tr.MinLength   = 0
	tr.FaceCamera  = true
	tr.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(math.random(), 0.85, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(math.random(), 0.85, 1)),
	})
	tr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	tr.Parent = hrp
end

-- [SOCIAL] /nametag berisi teks = teks publik → 1× per menit per pemain (pedoman resmi Roblox, Config/Social
-- PUBLIC_TEXT; atribut Player, tahan respawn). /nametag kosong (hapus) & /afk tetap bebas. Teks yang sama dengan
-- tag terakhir tidak dihitung (dipasang lagi tanpa filter ulang).
local PUBLIC      = require(RS:WaitForChild("Config"):WaitForChild("Social")).PUBLIC_TEXT
local SocialRules = require(RS:WaitForChild("Modules"):WaitForChild("SocialRules"))
local lastNametag = {} -- [player] = { raw, filtered }

H.nametag = function(p, args)
	local _, char = getHum(p); if not char then return end

	local txt = utf8Prefix(table.concat(args, " "), STATUS_MAX_CHARS):match("^%s*(.-)%s*$")
	if txt == "" then
		setStatus(char, nil, nil) -- /nametag kosong = hapus status
		return
	end
	local last = lastNametag[p]
	if last and last.raw == txt then
		setStatus(char, last.filtered, "tag")
		return
	end
	local now = workspace:GetServerTimeNow()
	local previous = p:GetAttribute(PUBLIC.ATTR.NAMETAG)
	if SocialRules.textWait(previous, now, PUBLIC.COOLDOWN) > 0 then
		return
	end
	p:SetAttribute(PUBLIC.ATTR.NAMETAG, now) -- pesan slot sebelum filter (yield)
	-- teks terlihat semua pemain → wajib filter Roblox (fail-closed)
	local okF, filtered = pcall(function()
		return TextService:FilterStringAsync(txt, p.UserId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not okF or type(filtered) ~= "string" or filtered == "" then
		warn("[CommandServer] nametag: filter gagal, tag tidak dipasang")
		p:SetAttribute(PUBLIC.ATTR.NAMETAG, previous) -- slot dikembalikan
		return
	end
	if not char.Parent then
		p:SetAttribute(PUBLIC.ATTR.NAMETAG, previous)
		return
	end
	lastNametag[p] = { raw = txt, filtered = filtered }
	setStatus(char, filtered, "tag")
end

H.undo = function(p)
	local hum, char = getHum(p); if not hum then return end
	local snap = popUndo(p); if not snap then return end
	applyDesc(p, hum, snap)
	fixAccVisibility(char)
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN
-- ═══════════════════════════════════════════════════════════
local CD = CommandShared.COOLDOWN

local function takeToken(player)
	local now = os.clock()
	local b = buckets[player.UserId]
	if not b then
		b = { tokens = BUCKET_MAX, at = now }
		buckets[player.UserId] = b
	end
	b.tokens = math.min(BUCKET_MAX, b.tokens + (now - b.at) * BUCKET_RATE)
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

local function isOnCooldown(player, id)
	local uid  = player.UserId
	stamps[uid] = stamps[uid] or {}
	local now  = os.clock()
	local last = stamps[uid][id]
	if last and now - last < (CD[id] or 2) then return true end
	stamps[uid][id] = now
	return false
end

-- ═══════════════════════════════════════════════════════════
-- EXECUTE
-- ═══════════════════════════════════════════════════════════
local function sanitizeArgs(args)
	if type(args) ~= "table" then return {} end
	local clean = {}
	for i = 1, math.min(#args, MAX_ARGS) do
		local v = args[i]
		if type(v) == "string" then
			clean[#clean + 1] = utf8Prefix(v, MAX_ARG_LEN)
		elseif type(v) == "number" then
			clean[#clean + 1] = tostring(v)
		end
	end
	return clean
end

local function tryExec(player, id, args)
	if type(id) ~= "string" or #id > 24 then return end
	id = id:lower():match("^%s*(.-)%s*$")
	local h = H[id]; if not h then return end
	if not takeToken(player) then return end
	if not FREE_CMDS[id] and not hasAccess(player) then return end
	if isOnCooldown(player, id) then return end
	safeCall(h, ("Error '%s' (%s)"):format(id, player.Name), player, sanitizeArgs(args))
end

event.OnServerEvent:Connect(function(player, id, args)
	tryExec(player, id, args)
end)

-- ── Chat commands ─────────────────────────────────────────
local function parseChatCommand(text)
	local parts = text:gsub("^%s+", ""):lower():split(" ")
	local id    = parts[1]:sub(2)
	local args  = {}
	for i = 2, #parts do
		if parts[i] ~= "" then args[#args + 1] = parts[i] end
	end
	return id, args
end

local function hookChat(player)
	player.Chatted:Connect(function(msg)
		if msg:gsub("^%s+", ""):sub(1, 1) ~= "/" then return end
		local id, args = parseChatCommand(msg)
		tryExec(player, id, args)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- ACCESS SYNC
-- ═══════════════════════════════════════════════════════════
local function syncAccess(player, isPurchase)
	if not player or not player.Parent then return end
	accessEvent:FireClient(player, hasAccess(player), isPurchase)
end

local function notifyOnJoin(player)
	task.delay(1.5, function() syncAccess(player, false) end)
end

local function onPassPurchased(player)
	if not player then return end
	invalidatePassCache(player.UserId)
	syncAccess(player, true)
end

MarketplaceSvc.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if passId ~= COMMANDS_PASS or not purchased then return end
	onPassPurchased(player)
end)

-- ── Player lifecycle ──────────────────────────────────────
local PER_USER_CACHES = {stamps, undoStacks, _rankCache, _passCache, buckets, rejoinSame}

local function onPlayerAdded(p)
	hookChat(p)
	notifyOnJoin(p)
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(p)
	local uid = p.UserId
	for _, cache in ipairs(PER_USER_CACHES) do cache[uid] = nil end
	lastNametag[p] = nil
end)

print("[CommandServer] Ready — Free: /re /normal /rejoin | Gate: Creator | rank "
	.. ADMIN_MIN_RANK .. "+ | Gamepass " .. PASS_NAME)