-- DonationServer.Boards — papan donasi desain v1.5 di map (Workspace.DonationBoards, dipasang di Studio, bukan Rojo).
-- Dua set papan (nama model di DonationConfig.boards.robux / .cash):
--   Robux : TopBoard (TOP DONATION dari PlayerDonations_v1: podium #1–#3 + baris #4–#10), TopMannequins Top1–3
--           (avatar + emote dance + papan nama), FeedBoard (kartu donasi terbaru), LiveBoard (pesan donasi terakhir).
--   Gold  : donasi bagibagi (tanpa nominal): CashFeedBoard + CashLiveBoard, CashTopBoard + CashMannequins dari
--           peringkat Gold (goldSource = Bagibagi:readSummary; nama → akun Roblox → avatar patung; bukan akun → patung
--           disembunyikan, podium huruf awal).
-- Papan yang tidak ada di map dilewati diam-diam; semua panggilan web di-pcall.
-- Struktur tiap papan: <Model>.Board.SurfaceGui { Panel, RowTemplate }.

-- ── Tampilan (tanpa layanan, tanpa yield) ────────────────────
-- row  = { userId, display, handle, amount }  (baris TOP / patung; amount = teks siap tampil)
-- card = { userId, display, handle, amount, message, ts }  (kartu LIVE DONATIONS)
local Ui = {}

Ui.HEART = utf8.char(0x2764)
local FONT = "rbxasset://fonts/families/BuilderSans.json"
local WHITE = Color3.fromRGB(248, 244, 244)

function Ui.commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function Ui.robux(n)
	return "R$ " .. Ui.commas(n)
end

function Ui.initial(name)
	local ok, cp = pcall(utf8.codepoint, tostring(name or ""), 1)
	return ok and cp and string.upper(utf8.char(cp)) or ""
end

function Ui.headshot(userId, size)
	if type(userId) ~= "number" or userId <= 0 then
		return "" -- donatur luar tanpa akun Roblox → huruf awal saja
	end
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d"):format(userId, size, size)
end

-- Pesan kosong / habis disensor ("####") tidak ditampilkan besar-besar.
function Ui.hasMessage(message)
	return type(message) == "string" and not string.match(message, "^[#%s]*$")
end

-- <model>.Board.SurfaceGui → surfaceGui, panel (nil kalau papan tidak ada)
function Ui.surface(model)
	local board = model and model:FindFirstChild("Board")
	local sg = board and board:FindFirstChildOfClass("SurfaceGui")
	return sg, sg and sg:FindFirstChild("Panel")
end

local function handleText(handle)
	return (handle and handle ~= "") and ("@" .. handle) or ""
end

local function setAvatar(inner, userId, display, size)
	inner.Initial.Text = display and Ui.initial(display) or ""
	inner.Image.Image = Ui.headshot(userId, size)
end

-- ── TOP DONATION ─────────────────────────────────────────────
function Ui.fillPodium(slot, row)
	slot.Amount.Text = row and row.amount or "—"
	slot.DisplayName.Text = row and row.display or "—"
	slot.Handle.Text = row and handleText(row.handle) or ""
	setAvatar(slot.Avatar.Inner, row and row.userId, row and row.display, 420)
end

-- rows urut peringkat → podium #1–#3 + baris #4..#show dari RowTemplate.
function Ui.renderTop(sg, panel, rows, show)
	for rank = 1, 3 do
		local slot = panel.Podium:FindFirstChild("Slot" .. rank)
		if slot then
			Ui.fillPodium(slot, rows[rank])
		end
	end
	local list = panel.ListContainer
	for _, c in list:GetChildren() do
		if string.sub(c.Name, 1, 5) == "Rank_" then
			c:Destroy()
		end
	end
	for rank = 4, math.min(#rows, show) do
		local row = rows[rank]
		local frame = sg.RowTemplate:Clone()
		frame.Name = "Rank_" .. rank
		frame.LayoutOrder = rank
		frame.Visible = true
		frame.Rank.Text = "#" .. rank
		frame.DisplayName.Text = row.display
		frame.Handle.Text = handleText(row.handle)
		frame.Amount.Text = row.amount
		setAvatar(frame.Avatar.Inner, row.userId, row.display, 150)
		frame.Parent = list
	end
end

-- ── LIVE DONATIONS ───────────────────────────────────────────
-- Kartu baru di atas (LayoutOrder = −seq); lebih dari `max` kartu → yang terlama dihapus.
-- Atribut Ts (waktu server) & Handle dipakai client untuk teks "@handle · Xs ago".
function Ui.pushFeed(sg, panel, card, seq, max)
	local row = sg.RowTemplate:Clone()
	row.Name = "Feed"
	row.LayoutOrder = -seq
	row.Visible = true
	row:SetAttribute("Ts", card.ts)
	row:SetAttribute("Handle", card.handle)
	local body = row.Content.Body
	body.DonorName.Text = card.display
	body.Meta.Text = (card.handle ~= "" and (handleText(card.handle) .. " · ") or "") .. "0s ago"
	body.Amount.Text = card.amount
	setAvatar(row.Content.Avatar, card.userId, card.display, 150)
	local hasMsg = Ui.hasMessage(card.message)
	row.MessageWrap.Visible = hasMsg
	row.MessageWrap.MessageBox.Inner.MessageText.Text = hasMsg and card.message or ""
	local list = panel.ListContainer
	row.Parent = list
	local rows = {}
	for _, c in list:GetChildren() do
		if c.Name == "Feed" then
			table.insert(rows, c)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = max + 1, #rows do
		rows[i]:Destroy()
	end
end

-- ── LIVE CHAT (hanya donasi berpesan) ────────────────────────
function Ui.showLive(panel, message, name, accent)
	local msg, donor = panel.Message, panel.DonorName
	local cap = msg:FindFirstChildOfClass("UITextSizeConstraint")
	local len = utf8.len(message) or #message
	if cap then
		cap.MaxTextSize = (len <= 14 and 100) or (len <= 30 and 90) or 72
		cap.MinTextSize = 20
	end
	msg.TextColor3 = WHITE
	msg.Text = string.upper(message)
	donor.Text = name
	donor.TextColor3 = accent
	donor.TextSize = 60
	donor.FontFace = Font.new(FONT, Enum.FontWeight.ExtraBold)
	panel.LiveTag.Visible = true
end

-- ── Patung: papan nama di atas kepala ────────────────────────
function Ui.overhead(template, man, rankText, row, accent)
	local root = man:FindFirstChild("HumanoidRootPart")
	if not (root and template) then
		return
	end
	local gui = root:FindFirstChild("DonateOverhead")
	if not gui then
		gui = template:Clone()
		gui.Name = "DonateOverhead"
		gui.Parent = root
	end
	local head = man:FindFirstChild("Head") -- ApplyDescription bisa mengganti Head → Adornee diperbarui tiap kali
	if head and head:IsA("BasePart") then
		gui.Adornee = head
		gui.StudsOffset = Vector3.new(0, 3.5, 0)
	end
	gui.RankLabel.Text = rankText
	gui.NameLabel.Text = row.display
	gui.TotalLabel.Text = row.amount
	gui.TotalLabel.TextColor3 = accent
end

-- ── Data papan ───────────────────────────────────────────────
local Boards = {}
Boards.commas = Ui.commas
Boards.Ui = Ui

-- deps: { ordered, folder, services = {Players, UserService}, cfg, task, warn, now() → waktu server }
function Boards.new(deps)
	local self = setmetatable({}, { __index = Boards })
	self.deps = deps
	self.cfg = deps.cfg
	self.names = {} -- [userId] = { display, user }
	self.rigs = {} -- ["<model><rank>"] = Model patung (disimpan: patung tersembunyi tidak punya Parent)
	self.dressed = {} -- [Model] = userId yang avatarnya sedang dipakai
	self.tracks = {} -- [Model] = AnimationTrack dance
	self.sig = nil -- isi TOP terakhir yang digambar (gambar ulang hanya kalau berubah)
	self.goldSig = nil
	self.goldSource = nil -- function() → { {name, uid} } (dipasang DonationServer kalau bagibagi aktif)
	self.pending = {} -- ["robux" | "gold"] = baca ulang sudah dijadwalkan
	self.feed = {} -- donasi terakhir yang masuk papan (terbaru di depan, maks feedCount; Robux & Gold)
	self.seq = 0
	self.refreshing = false
	return self
end

function Boards:part(name)
	local f = self.deps.folder
	return f and f:FindFirstChild(name)
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

function Boards:rowFor(userId, total)
	local n = self.names[userId]
	return {
		userId = userId,
		display = n and n.display or ("User " .. tostring(userId)),
		handle = n and n.user or "",
		amount = Ui.robux(total),
	}
end

-- ── Patung ───────────────────────────────────────────────────
function Boards:rig(set, rank)
	local key = set.rigs .. rank
	if not self.rigs[key] then
		local model = self:part(set.rigs)
		self.rigs[key] = model and model:FindFirstChild("Top" .. rank) or nil
	end
	return self.rigs[key]
end

-- Telapak kaki terendah (supaya avatar setinggi apa pun tetap menapak podium).
local FEET = { LeftFoot = true, RightFoot = true, ["Left Leg"] = true, ["Right Leg"] = true }
local function feetY(man)
	local low
	for _, p in man:GetDescendants() do
		if p:IsA("BasePart") and FEET[p.Name] then
			local y = p.CFrame.Position.Y - p.Size.Y / 2
			low = low and math.min(low, y) or y
		end
	end
	return low
end

function Boards:hideRig(man)
	local track = self.tracks[man]
	if track then
		pcall(track.Stop, track)
	end
	self.tracks[man], self.dressed[man] = nil, nil
	man.Parent = nil
end

function Boards:dress(man, rank, userId)
	local hum = man:FindFirstChildOfClass("Humanoid")
	if not hum or self.dressed[man] == userId then
		return
	end
	self.dressed[man] = userId
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
			self.dressed[man] = nil -- coba lagi di refresh berikutnya
		end
	else
		self.dressed[man] = nil
	end
	local animId = self.cfg.boards.danceAnims[rank]
	local animator = hum:FindFirstChildOfClass("Animator")
	if animId and animator and not self.tracks[man] then
		local okA, track = pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. animId
			local t = animator:LoadAnimation(a)
			t.Looped = true
			t:Play()
			return t
		end)
		if okA then
			self.tracks[man] = track
		end
	end
end

-- rows[1..3] → patung tampil + papan nama; peringkat kosong / bukan akun Roblox → patung disembunyikan.
function Boards:updateRigs(set, rows)
	local model = self:part(set.rigs)
	for rank = 1, 3 do
		local man = self:rig(set, rank)
		local row = rows[rank]
		if man and model and not (row and row.userId > 0) then
			self:hideRig(man)
		elseif man and model then
			man.Parent = model
			self:dress(man, rank, row.userId)
			Ui.overhead(self:part(self.cfg.boards.overhead), man, ("#%d %s"):format(rank, set.rank), row, set.accent)
		end
	end
end

-- ── TOP DONATION (Robux) ─────────────────────────────────────
-- Baca ulang peringkat dari ordered store → papan + patung.
function Boards:refresh()
	if self.refreshing then
		return
	end
	self.refreshing = true
	local B = self.cfg.boards
	local ok, pages = pcall(function()
		return self.deps.ordered:GetSortedAsync(false, B.topCount)
	end)
	if ok and pages then
		local entries, ids = {}, {}
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		for _, e in okPage and page or {} do
			local id = tonumber(e.key)
			if id and tonumber(e.value) then
				table.insert(entries, { id = id, total = tonumber(e.value) })
				table.insert(ids, id)
			end
		end
		self:resolveNames(ids)
		local rows, sig = {}, {}
		for rank, e in entries do
			if rank > B.showCount then
				break
			end
			rows[rank] = self:rowFor(e.id, e.total)
			table.insert(sig, ("%d=%d=%s"):format(e.id, e.total, rows[rank].display))
		end
		local set = B.robux
		local sg, panel = Ui.surface(self:part(set.top))
		if panel then
			sg:SetAttribute("RefreshRate", B.every)
			sg:SetAttribute("LastRefresh", self.deps.now())
			local joined = table.concat(sig, "|")
			if joined ~= self.sig then
				Ui.renderTop(sg, panel, rows, B.showCount)
				self.sig = joined
			end
		end
		self:updateRigs(set, rows)
	end
	self.refreshing = false
end

-- ── TOP DONATION (Gold) ──────────────────────────────────────
function Boards:refreshGold()
	local src = self.goldSource
	local ok, list = pcall(function()
		return src and src()
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	local B = self.cfg.boards
	local set = B.cash
	local rows, sig = {}, {}
	for rank, e in list do
		if rank > B.showCount then
			break
		end
		rows[rank] = { userId = e.uid, display = e.name, handle = e.uid > 0 and e.name or "", amount = Ui.HEART }
		table.insert(sig, e.uid .. "=" .. e.name)
	end
	local sg, panel = Ui.surface(self:part(set.top))
	if panel then
		sg:SetAttribute("RefreshRate", B.every)
		sg:SetAttribute("LastRefresh", self.deps.now())
		local joined = table.concat(sig, "|")
		if joined ~= self.goldSig then
			Ui.renderTop(sg, panel, rows, B.showCount)
			self.goldSig = joined
		end
	end
	self:updateRigs(set, rows)
end

-- Segera baca ulang setelah donasi (digabung per jenis: robux `soon`, gold `cash.soon` detik).
function Boards:refreshSoon(kind)
	kind = kind or "robux"
	if self.pending[kind] then
		return
	end
	self.pending[kind] = true
	local B = self.cfg.boards
	self.deps.task.delay(kind == "gold" and B.cash.soon or B.soon, function()
		self.pending[kind] = nil
		if kind == "gold" then
			self:refreshGold()
		else
			self:refresh()
		end
	end)
end

-- ── Donasi baru ──────────────────────────────────────────────
-- Dipanggil DonationServer setelah donasi tersimpan (item = data pengumuman). Donasi luar (bagibagi) → set Gold.
function Boards:onDonation(item)
	local B = self.cfg.boards
	local set = item.external and B.cash or B.robux
	table.insert(self.feed, 1, item)
	while #self.feed > B.feedCount do
		table.remove(self.feed)
	end
	local sg, panel = Ui.surface(self:part(set.feed))
	if panel then
		self.seq += 1
		Ui.pushFeed(sg, panel, {
			userId = item.userId,
			display = item.displayName,
			handle = item.userId > 0 and item.name or "",
			amount = item.external and Ui.HEART or Ui.robux(item.robux),
			message = item.message,
			ts = self.deps.now(),
		}, self.seq, B.feedCount)
	end
	local _, live = Ui.surface(self:part(set.live))
	if live and Ui.hasMessage(item.message) then
		Ui.showLive(live, item.message, item.displayName, set.accent)
	end
	self:refreshSoon(item.external and "gold" or "robux")
end

-- Teks label papan dari Config (Gold: "GOLD"; LIST Robux: "LIVE" sampai feed harian ada).
function Boards:applyLabels()
	for _, set in { self.cfg.boards.robux, self.cfg.boards.cash } do
		for _, name in { set.top, set.feed } do
			local _, panel = Ui.surface(self:part(name))
			local sub = panel and panel:FindFirstChild("Header") and panel.Header:FindFirstChild("SubRow")
			if sub and set.label then
				sub.Robux.Text = set.label
			end
			if sub and name == set.feed and set.feedScope then
				sub.Scope.Text = set.feedScope
			end
		end
	end
end

function Boards:start()
	local okL, errL = pcall(function()
		self:applyLabels()
		self:updateRigs(self.cfg.boards.cash, {}) -- sampai peringkat Gold pertama terbaca
	end)
	if not okL then
		self.deps.warn("[Donation] papan Gold gagal disiapkan: " .. tostring(errL))
	end
	self.deps.task.spawn(function()
		while true do
			local ok, err = pcall(self.refresh, self)
			if not ok then
				self.refreshing = false
				self.deps.warn("[Donation] papan gagal diperbarui: " .. tostring(err))
			end
			local okG, errG = pcall(self.refreshGold, self)
			if not okG then
				self.deps.warn("[Donation] papan Gold gagal diperbarui: " .. tostring(errG))
			end
			self.deps.task.wait(self.cfg.boards.every)
		end
	end)
end

return Boards
