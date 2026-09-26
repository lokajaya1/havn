-- ═══════════════════════════════════════════════════════════
-- SHOP CONFIG (Production)
-- Location: ReplicatedStorage > ShopConfig (ModuleScript)
-- ═══════════════════════════════════════════════════════════

local ShopConfig = {}

-- ═══════════════════════════════════════════════════════════
-- GAMEPASSES
-- ═══════════════════════════════════════════════════════════
ShopConfig.gamepasses = {
	{
		id                  = 1891084979,
		name                = "VIP Access",
		desc                = "Exclusive perks, place & features",
		icon                = "rbxassetid://103867908310819",
		color               = Color3.fromRGB(255, 195, 40),
		giftProduct         = 3606572123,
		giftProductRegional = 0,
	},
	{
		id                  = 1891384972,
		name                = "VVIP Access",
		desc                = "Exclusive tool, Exclusive feature",
		icon                = "rbxassetid://103867908310819",
		color               = Color3.fromRGB(163, 0, 255),
		giftProduct         = 3606572100,
		giftProductRegional = 0,
	},
	{
		id                  = 1889855059,
		name                = "Commands",
		desc                = "Akses semua command",
		icon                = "rbxassetid://103867908310819",
		color               = Color3.fromRGB(50, 200, 255),
		giftProduct         = 3606572063,
		giftProductRegional = 0,
	},
}

-- ═══════════════════════════════════════════════════════════
-- GROUP & ADMIN CONFIG
-- rank >= adminRankMin → semua pass dianggap owned +
-- bisa free gift ke player lain tanpa bayar Robux
-- ═══════════════════════════════════════════════════════════
ShopConfig.group = {
	id           = 277580244,
	adminRankMin = 254,   -- rank 254 & 255 = Owner tier
}

-- ═══════════════════════════════════════════════════════════
-- UI SETTINGS
-- ═══════════════════════════════════════════════════════════
ShopConfig.ui = {
	cardHeight      = 75,  cardMargin  = 8,  cardSpacing = 6,
	iconSize        = 50,  iconInnerSize = 32,
	buyButtonWidth  = 70,  buyButtonHeight = 30,
	giftButtonWidth = 70,  headerHeight    = 40,
	scrollPadding   = 4,   modalWidth      = 350,
	modalHeight     = 280, playerListHeight = 140, playerCardHeight = 45,
	fontSize = {
		header=14, subheader=10, cardName=13,
		cardDesc=10, cardStatus=9, buyButton=11,
	},
}

-- ═══════════════════════════════════════════════════════════
-- COLORS
-- ═══════════════════════════════════════════════════════════
ShopConfig.colors = {
	success = Color3.fromRGB(46, 204, 113),
	warning = Color3.fromRGB(230, 126, 34),
	error   = Color3.fromRGB(231, 76,  60),
}

-- ═══════════════════════════════════════════════════════════
-- DATASTORE & MESSAGING
-- ═══════════════════════════════════════════════════════════
ShopConfig.dataStore = {
	name          = "ShopData",
	retryAttempts = 5,
	retryCooldown = 1,
}

ShopConfig.messaging = {
	giftTopic = "GamepassGift",
}

-- ═══════════════════════════════════════════════════════════
-- LOOKUP HELPERS
-- ═══════════════════════════════════════════════════════════
local function findPass(pred)
	for _, p in ipairs(ShopConfig.gamepasses) do
		if pred(p) then return p end
	end
end

function ShopConfig.getGamepassById(id)
	return findPass(function(p) return p.id == id end)
end

function ShopConfig.getGamepassByName(name)
	return findPass(function(p) return p.name == name end)
end

function ShopConfig.getGamepassByProduct(productId)
	for _, p in ipairs(ShopConfig.gamepasses) do
		if p.giftProduct == productId then return p, false end
		if p.giftProductRegional ~= 0 and p.giftProductRegional == productId then return p, true end
	end
	return nil, false
end

-- ═══════════════════════════════════════════════════════════
-- STARTUP VALIDATION
-- ═══════════════════════════════════════════════════════════
task.spawn(function()
	local errors, seenIds, seenProds = {}, {}, {}
	for i, p in ipairs(ShopConfig.gamepasses) do
		local tag = ("Gamepass #%d (%s)"):format(i, p.name or "?")
		if type(p.id) ~= "number"          then table.insert(errors, tag..": invalid 'id'")
		elseif seenIds[p.id]               then table.insert(errors, tag..": duplicate id "..p.id)
		else seenIds[p.id] = true end
		if type(p.name) ~= "string"        then table.insert(errors, tag..": invalid 'name'") end
		if type(p.giftProduct) ~= "number" then table.insert(errors, tag..": invalid 'giftProduct'")
		elseif seenProds[p.giftProduct]    then table.insert(errors, tag..": duplicate giftProduct "..p.giftProduct)
		else seenProds[p.giftProduct] = true end
	end
	if #errors > 0 then for _, e in ipairs(errors) do warn("[ShopConfig]", e) end
	else print(("[ShopConfig] OK | %d gamepasses | adminRankMin=%d"):format(
		#ShopConfig.gamepasses, ShopConfig.group.adminRankMin)) end
end)

return ShopConfig