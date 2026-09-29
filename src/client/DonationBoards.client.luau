-- StarterPlayerScripts/DonationBoards  (LocalScript)
-- Bagian papan donasi (Workspace.DonationBoards, desain v1.5) yang berbeda per pemain atau bergerak:
--   baris "You" di TOP Robux & Gold (atribut pemain DonationRank / DonationTotal / GoldRank / GoldTotal, dari DonationServer),
--   timer + bar "NEXT REFRESH" + "UPDATED Xs AGO" (atribut SurfaceGui LastRefresh / RefreshRate),
--   "@handle · Xs ago" di kartu LIVE DONATIONS (atribut kartu Ts / Handle),
--   kilau papan nama patung (UIGradient RankShine).
-- Hanya tampilan lokal: tanpa remote, tanpa data. Papan tidak ada → skrip berhenti diam-diam.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Config = require(RS:WaitForChild("DonationConfig"))
local player = Players.LocalPlayer
local folder = workspace:WaitForChild("DonationBoards", 30)
if not folder then
	return
end

local B = Config.boards
local HAIR = utf8.char(0x200A)
local ROBUX = utf8.char(0xE002) -- ikon Robux (font Roblox)
local SHINE_SWEEP, SHINE_PAUSE = 1.2, 1.8 -- detik sapuan kilau + jeda

-- "YOUR POSITION" → huruf berjarak (gaya teks papan)
local function track(s)
	local out = {}
	for _, cp in utf8.codes(s) do
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out, HAIR)
end

local function ago(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s ago"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	end
	return math.floor(seconds / 3600) .. "h ago"
end

local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function surface(name)
	local model = folder:FindFirstChild(name)
	local board = model and model:FindFirstChild("Board")
	local sg = board and board:FindFirstChildOfClass("SurfaceGui")
	return sg, sg and sg:FindFirstChild("Panel")
end

local SETS = {
	{
		cfg = B.robux,
		rankAttr = "DonationRank",
		amount = function()
			return ROBUX .. " " .. commas(player:GetAttribute("DonationTotal"))
		end,
	},
	{
		cfg = B.cash,
		rankAttr = "GoldRank",
		amount = function(rank)
			return rank > 0 and ((commas(player:GetAttribute("GoldTotal")):gsub(",", ".")) .. " GOLD") or "—"
		end,
	},
}

local function initial(name)
	local ok, cp = pcall(utf8.codepoint, name, 1)
	return ok and cp and string.upper(utf8.char(cp)) or ""
end
local thumb = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(player.UserId)

local function updateYou(set)
	local _, panel = surface(set.cfg.top)
	local you = panel and panel:FindFirstChild("YouRow")
	if not you then
		return
	end
	local rank = tonumber(player:GetAttribute(set.rankAttr)) or 0
	you.Rank.Text = rank > 0 and ("#" .. rank) or "#—"
	you.DisplayName.Text = player.DisplayName
	you.Sub.Text = track(rank > 0 and "YOUR POSITION" or "NOT RANKED YET")
	you.Amount.Text = set.amount(rank)
	local inner = you.Avatar:FindFirstChild("Inner")
	if inner then
		inner.Initial.Text = initial(player.DisplayName)
		inner.Image.Image = thumb
	end
end

local function updateFooter(set, now)
	local sg, panel = surface(set.cfg.top)
	local footer = panel and panel:FindFirstChild("Footer")
	if not footer then
		return
	end
	local last = tonumber(sg:GetAttribute("LastRefresh")) or 0
	local rate = tonumber(sg:GetAttribute("RefreshRate")) or B.every
	if last <= 0 or rate <= 0 then
		footer.Timer.Text = "--:--"
		footer.Bar.Track.Fill.Size = UDim2.new(0, 0, 1, 0)
		footer.Updated.Text = track("UPDATED —")
		return
	end
	local elapsed = math.max(0, now - last)
	local remaining = math.max(0, rate - elapsed)
	footer.Timer.Text = ("%02d:%02d"):format(math.floor(remaining / 60), math.floor(remaining % 60))
	footer.Bar.Track.Fill.Size = UDim2.new(math.clamp(elapsed / rate, 0, 1), 0, 1, 0)
	footer.Updated.Text = track("UPDATED " .. string.upper(ago(elapsed)))
	footer.Mode.Text = track("AUTO · " .. rate .. "S")
end

local function updateFeed(set, now)
	local _, panel = surface(set.cfg.feed)
	local list = panel and panel:FindFirstChild("ListContainer")
	if not list then
		return
	end
	for _, row in list:GetChildren() do
		local ts = row:GetAttribute("Ts")
		local meta = ts and row:FindFirstChild("Meta", true)
		if meta then
			local handle = row:GetAttribute("Handle")
			local t = ago(now - ts)
			meta.Text = (type(handle) == "string" and handle ~= "") and ("@" .. handle .. " · " .. t) or t
		end
	end
end

for _, set in SETS do
	for _, attr in { set.rankAttr, "DonationTotal", "GoldTotal" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			pcall(updateYou, set)
		end)
	end
end

-- Kilau papan nama patung (template papan nama menaruh UIGradient "RankShine" di label peringkat).
local gradients = {}
local function watch(inst)
	if inst:IsA("UIGradient") and inst.Name == "RankShine" then
		gradients[inst] = true
	end
end
for _, d in folder:GetDescendants() do
	watch(d)
end
folder.DescendantAdded:Connect(watch)
folder.DescendantRemoving:Connect(function(inst)
	gradients[inst] = nil
end)
RunService.RenderStepped:Connect(function()
	local t = os.clock() % (SHINE_SWEEP + SHINE_PAUSE)
	local offset = Vector2.new(t < SHINE_SWEEP and (-1 + 2 * t / SHINE_SWEEP) or 1, 0)
	for g in gradients do
		g.Offset = offset
	end
end)

local step = 0
while true do
	local now = workspace:GetServerTimeNow()
	for _, set in SETS do
		pcall(updateFooter, set, now)
		if step % 4 == 0 then
			pcall(updateFeed, set, now)
			pcall(updateYou, set)
		end
	end
	step += 1
	task.wait(0.25)
end
