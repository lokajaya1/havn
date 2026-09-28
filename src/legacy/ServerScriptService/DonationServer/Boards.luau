-- DonationServer.Boards — papan donasi di map (Workspace.DonationBoards, diatur di Studio, bukan Rojo):
--   TopBoard      : peringkat donatur dari PlayerDonations_v1 (cermin total), dibaca ulang berkala
--   TopMannequins : Top1–Top3 memakai avatar donatur teratas + emote dance resmi Roblox
--   FeedBoard     : donasi terakhir di server ini (terbaru di atas)
--   LiveBoard     : donasi terakhir besar (avatar, nama, jumlah, pesan terfilter)
-- Papan yang tidak ada di map dilewati diam-diam; semua panggilan web di-pcall.
local Boards = {}

local ROBUX = utf8.char(0xE002)

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
Boards.commas = commas

local function headshot(userId, size)
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d"):format(userId, size, size)
end

-- deps: { ordered, folder, services = {Players, UserService}, cfg, task, warn }
function Boards.new(deps)
	local self = setmetatable({}, { __index = Boards })
	self.deps = deps
	self.cfg = deps.cfg
	self.names = {} -- [userId] = { display, user }
	self.feed = {}
	self.top = {} -- [rank] = userId sedang dipakai manekin
	self.refreshing = false
	return self
end

function Boards:part(name)
	local f = self.deps.folder
	return f and f:FindFirstChild(name)
end

function Boards:gui(boardName)
	local b = self:part(boardName)
	local board = b and b:FindFirstChild("Board")
	return board and board:FindFirstChild("SurfaceGui")
end

-- Nama tampilan untuk daftar userId (GetUserInfosByUserIdsAsync, di-cache per sesi server).
function Boards:resolveNames(ids)
	local need = {}
	for _, id in ids do
		if not self.names[id] then
			table.insert(need, id)
		end
	end
	if #need > 0 then
		local ok, infos = pcall(function()
			return self.deps.services.UserService:GetUserInfosByUserIdsAsync(need)
		end)
		if ok and type(infos) == "table" then
			for _, info in infos do
				self.names[info.Id] = { display = info.DisplayName, user = info.Username }
			end
		end
	end
end

function Boards:nameOf(id)
	local n = self.names[id]
	return n and n.display or ("User " .. tostring(id))
end

local RANK_COLORS = {
	Color3.fromRGB(255, 210, 77),
	Color3.fromRGB(210, 215, 225),
	Color3.fromRGB(215, 140, 80),
}

function Boards:renderTop(rows)
	local gui = self:gui("TopBoard")
	local list = gui and gui:FindFirstChild("Background") and gui.Background:FindFirstChild("ListContainer")
	local template = gui and gui:FindFirstChild("Template")
	if not list or not template then
		return
	end
	for _, c in list:GetChildren() do
		if c.Name:sub(1, 4) == "Row_" then
			c:Destroy()
		end
	end
	for i, row in rows do
		local r = template:Clone()
		r.Name = "Row_" .. i
		r.LayoutOrder = i
		r.Visible = true
		r.Rank.Text = "#" .. i
		r.Rank.TextSize = 52
		if RANK_COLORS[i] then
			r.Rank.TextColor3 = RANK_COLORS[i]
		end
		r.PlayerName.Text = self:nameOf(row.userId)
		r.Level.Text = ROBUX .. " " .. commas(row.total)
		r.AvatarImage.Image = headshot(row.userId, 150)
		r.Parent = list
	end
end

-- Telapak kaki terendah (supaya avatar setinggi apa pun tetap menapak podium).
local FEET = { LeftFoot = true, RightFoot = true, ["Left Leg"] = true, ["Right Leg"] = true }
local function feetY(man)
	local low
	for _, p in man:GetDescendants() do
		if p:IsA("BasePart") and FEET[p.Name] then
			local y = p.Position.Y - p.Size.Y / 2
			low = low and math.min(low, y) or y
		end
	end
	return low
end

function Boards:dress(rank, userId)
	local tm = self:part("TopMannequins")
	local man = tm and tm:FindFirstChild("Top" .. rank)
	local hum = man and man:FindFirstChildOfClass("Humanoid")
	if not hum or self.top[rank] == userId then
		return
	end
	self.top[rank] = userId
	hum.DisplayName = "#" .. rank .. " " .. self:nameOf(userId)
	local ok, desc = pcall(function()
		return self.deps.services.Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if ok and desc then
		if man:GetAttribute("FootY") == nil then
			local y0 = feetY(man)
			if y0 then
				man:SetAttribute("FootY", y0)
			end
		end
		local okApply = pcall(function()
			hum:ApplyDescription(desc)
		end)
		local footY = man:GetAttribute("FootY")
		local y1 = okApply and footY and feetY(man)
		if y1 then
			man:PivotTo(man:GetPivot() + Vector3.new(0, footY - y1, 0))
		end
		if not okApply then
			self.top[rank] = nil -- coba lagi di refresh berikutnya
		end
	else
		self.top[rank] = nil
	end
	local animId = self.cfg.boards.danceAnims[rank]
	local animator = hum:FindFirstChildOfClass("Animator")
	if animId and animator and not man:GetAttribute("Dancing") then
		local okA = pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. animId
			local track = animator:LoadAnimation(a)
			track.Looped = true
			track:Play()
		end)
		if okA then
			man:SetAttribute("Dancing", true)
		end
	end
end

-- Baca ulang peringkat dari ordered store → papan + manekin.
function Boards:refresh()
	if self.refreshing then
		return
	end
	self.refreshing = true
	local ok, pages = pcall(function()
		return self.deps.ordered:GetSortedAsync(false, self.cfg.boards.topCount)
	end)
	if ok and pages then
		local rows, ids = {}, {}
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		for _, e in okPage and page or {} do
			local id = tonumber(e.key)
			if id and tonumber(e.value) then
				table.insert(rows, { userId = id, total = tonumber(e.value) })
				table.insert(ids, id)
			end
		end
		self:resolveNames(ids)
		self:renderTop(rows)
		for rank = 1, 3 do
			if rows[rank] then
				self:dress(rank, rows[rank].userId)
			end
		end
	end
	self.refreshing = false
end

-- Segera baca ulang setelah donasi (digabung: paling cepat tiap `soon` detik).
function Boards:refreshSoon()
	if self.pending then
		return
	end
	self.pending = true
	self.deps.task.delay(self.cfg.boards.soon, function()
		self.pending = false
		self:refresh()
	end)
end

function Boards:renderFeed()
	local gui = self:gui("FeedBoard")
	local list = gui and gui:FindFirstChild("Background") and gui.Background:FindFirstChild("ListContainer")
	local template = gui and gui:FindFirstChild("RowTemplate")
	if not list or not template then
		return
	end
	for _, c in list:GetChildren() do
		if c.Name:sub(1, 5) == "Feed_" then
			c:Destroy()
		end
	end
	for i, item in self.feed do
		local r = template:Clone()
		r.Name = "Feed_" .. i
		r.LayoutOrder = i
		r.Visible = true
		local text = ("%s donated %s %s"):format(item.displayName, ROBUX, commas(item.robux))
		if item.message ~= "" then
			text ..= '\n"' .. item.message .. '"'
		end
		r.Msg.Text = text
		r.Avatar.Image = headshot(item.userId, 150)
		r.Parent = list
	end
end

function Boards:renderLive(item)
	local gui = self:gui("LiveBoard")
	local content = gui and gui:FindFirstChild("Background") and gui.Background:FindFirstChild("Content")
	if not content then
		return
	end
	content.Avatar.Image = headshot(item.userId, 420)
	content.NameLabel.Text = ("%s (@%s)"):format(item.displayName, item.name)
	content.AmountLabel.Text = "donated " .. ROBUX .. " " .. commas(item.robux)
	content.MessageHolder.MessageLabel.Text = item.message ~= "" and ('"' .. item.message .. '"') or ""
end

-- Dipanggil DonationServer setelah donasi tersimpan (item = data pengumuman).
function Boards:onDonation(item)
	table.insert(self.feed, 1, item)
	while #self.feed > self.cfg.boards.feedCount do
		table.remove(self.feed)
	end
	pcall(self.renderFeed, self)
	pcall(self.renderLive, self, item)
	self:refreshSoon()
end

function Boards:start()
	self.deps.task.spawn(function()
		while true do
			local ok, err = pcall(self.refresh, self)
			if not ok then
				self.refreshing = false
				self.deps.warn("[Donation] papan gagal diperbarui: " .. tostring(err))
			end
			self.deps.task.wait(self.cfg.boards.every)
		end
	end)
end

return Boards
