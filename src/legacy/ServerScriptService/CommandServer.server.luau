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

-- Command gratis (hanya memengaruhi diri sendiri, aman dibuka)
local FREE_CMDS = { re = true, normal = true, rejoin = true }

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
local function safeCall(fn, errLabel, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[CommandServer] %s: %s"):format(errLabel, tostring(err)))
	end
	return ok, err
end

local function withUserCache(cache, computeFn)
	return function(player)
		local uid    = player.UserId
		local cached = cache[uid]
		if cached ~= nil then return cached end
		local result = computeFn(player)
		cache[uid] = result
		return result
	end
end

-- ── Cache per userId ──────────────────────────────────────
local _passCache = {}
local _rankCache = {}
local undoStacks = {}
local stamps     = {}

local function invalidatePassCache(uid) _passCache[uid] = nil end

-- ── Access checks ─────────────────────────────────────────
local checkPassDirect = withUserCache(_passCache, function(player)
	-- pass baru ATAU pass HAVN lama
	return ShopConfig.userOwnsPass(player.UserId, COMMANDS_INFO)
end)

local getGroupRank = withUserCache(_rankCache, function(player)
	local ok, rank = pcall(player.GetRankInGroup, player, GROUP_ID)
	return (ok and type(rank) == "number") and rank or 0
end)

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

local function applyDesc(p, hum, d)
	task.spawn(function()
		local ok = safeCall(hum.ApplyDescription, "ApplyDescription gagal", hum, d)
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
end

local function resetToBaseDesc(p, char, hum)
	clearDTEffects(char)
	local base = getBaseDesc(p)
	if base and hum then applyDesc(p, hum, base) end
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

H.rejoin = function(p)
	task.spawn(function()
		safeCall(TeleportService.TeleportAsync, "Rejoin gagal (" .. p.Name .. ")",
			TeleportService, game.PlaceId, {p})
	end)
end

-- Butuh akses
H.reset = function(p)
	local hum = getHum(p)
	if hum then hum.Health = 0 end
end

H.sit   = function(p) local h = getHum(p); if h then h.Sit = true end end
H.stand = function(p) local h = getHum(p); if h then h.Sit = false; h.Jump = true end end

H.afk = function(p)
	local _, char = getHum(p); if not char then return end
	local head = char:FindFirstChild("Head"); if not head then return end
	local ex   = head:FindFirstChild("DT_AFK")
	if ex then ex:Destroy(); return end

	local bb = Instance.new("BillboardGui")
	bb.Name        = "DT_AFK"
	bb.Size        = UDim2.new(0, 52, 0, 20)
	bb.StudsOffset = Vector3.new(0, 2.8, 0)
	bb.Parent      = head

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundColor3       = Color3.fromRGB(20, 20, 26)
	lbl.BackgroundTransparency = 0.15
	lbl.BorderSizePixel        = 0
	lbl.Text                   = "AFK"
	lbl.TextColor3             = Color3.fromRGB(255, 195, 40)
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextSize               = 11
	lbl.Parent                 = bb
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)
end

H.headless = function(p) toggleDescProp(p, "DT_Headless", "Head",     ASSET.HEADLESS, ASSET.DEFAULT) end
H.korblox  = function(p) toggleDescProp(p, "DT_Korblox",  "RightLeg", ASSET.KORBLOX,  ASSET.DEFAULT) end

H.size = function(p, args)
	local n = tonumber(args[1]); if n ~= n then n = nil end -- [FIX 2c3] tolak NaN ("nan" lolos math.clamp)
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

H.nametag = function(p, args)
	local _, char = getHum(p); if not char then return end
	local head = char:FindFirstChild("Head"); if not head then return end

	local ex = head:FindFirstChild("DT_Nametag"); if ex then ex:Destroy() end
	local txt = table.concat(args, " "):sub(1, 40)
	if txt == "" then return end
	-- [FIX 2026-09-26] teks nametag terlihat semua pemain → wajib filter Roblox (fail-closed)
	local okF, filtered = pcall(function()
		return TextService:FilterStringAsync(txt, p.UserId, Enum.TextFilterContext.PublicChat)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not okF or type(filtered) ~= "string" or filtered == "" then
		warn("[CommandServer] nametag: filter gagal, tag tidak dipasang")
		return
	end
	txt = filtered
	if not char.Parent or not head.Parent then return end

	local bb = Instance.new("BillboardGui")
	bb.Name        = "DT_Nametag"
	bb.Size        = UDim2.new(0, 140, 0, 22)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.Parent      = head

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundColor3       = Color3.fromRGB(15, 15, 20)
	lbl.BackgroundTransparency = 0.2
	lbl.BorderSizePixel        = 0
	lbl.Text                   = txt
	lbl.TextColor3             = Color3.fromRGB(230, 230, 238)
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextSize               = 11
	lbl.Parent                 = bb
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)
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
local CD = {
	re=3, reset=5, rejoin=10, sit=1, stand=1, afk=2,
	headless=2, korblox=2, size=1, ghost=1, clearhats=2,
	highlight=1, sparkle=1, fire=1, smoke=1, trail=1,
	glow=1, hat=1, nametag=1, normal=2, undo=1,
}

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
			clean[#clean + 1] = v:sub(1, MAX_ARG_LEN)
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

task.delay(2, function()
	local shopRemotes = RS:FindFirstChild("ShopRemotes")
	local ownUpd = shopRemotes and shopRemotes:FindFirstChild("OwnershipUpdated")
	local target = ownUpd or RS:FindFirstChild("OwnershipUpdated")
	if target and target:IsA("RemoteEvent") then
		target.OnServerEvent:Connect(function(player, passName, owned)
			if passName == PASS_NAME and owned then
				onPassPurchased(player)
			end
		end)
	end
end)

MarketplaceSvc.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if passId ~= COMMANDS_PASS or not purchased then return end
	onPassPurchased(player)
end)

-- ── Player lifecycle ──────────────────────────────────────
local PER_USER_CACHES = {stamps, undoStacks, _rankCache, _passCache}

local function onPlayerAdded(p)
	hookChat(p)
	notifyOnJoin(p)
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(p)
	local uid = p.UserId
	for _, cache in ipairs(PER_USER_CACHES) do cache[uid] = nil end
end)

print("[CommandServer] Ready — Free: /re /normal /rejoin | Gate: Creator | rank "
	.. ADMIN_MIN_RANK .. "+ | Gamepass " .. PASS_NAME)