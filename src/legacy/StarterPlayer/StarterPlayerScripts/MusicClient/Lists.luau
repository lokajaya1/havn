-- MusicClient/Lists  (ModuleScript)
-- Render daftar library (Global: dikelompokkan per kreator | Mine: daftar
-- datar) + daftar antrian, termasuk antrian pengambilan thumbnail.
--
-- Semua akses ke state dibungkus fallback ({} kalau nil): satu field yang
-- belum ada tidak boleh menjatuhkan seluruh render library.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Shared = require(RS:WaitForChild("MusicShared"))
local UI     = require(script.Parent:WaitForChild("UI"))

local player  = Players.LocalPlayer
local w, C    = UI.w, UI.C
local tw, tws = UI.tw, UI.tws

local L = {}
local ui, S
local remote = Shared.remote

function L.init(ctx)
	ui, S = ctx.ui, ctx.state
	S.sharedLib  = S.sharedLib  or {}
	S.myLib      = S.myLib      or {}
	S.myIds      = S.myIds      or {}
	S.queueIds   = S.queueIds   or {}
	S.libBtns    = S.libBtns    or {}
	S.favBtns    = S.favBtns    or {}
	S.libView    = S.libView    or "all"
	S.sortMode   = S.sortMode   or "last"
	S.queueLimit = S.queueLimit or { max = Shared.maxGlobalQueue }
end

-- ══ THUMBNAIL ═════════════════════════════════════════════════════════════
local MAX_QUEUE   = Shared.thumbQueueMax -- [FIX R7]
local NEG_TTL     = Shared.thumbFailTTL -- kegagalan hanya di-cache sebentar, lalu dicoba lagi
local tCache, tQueue, tRunning = {}, {}, false

-- Cache sukses disimpan permanen; cache GAGAL kedaluwarsa setelah NEG_TTL.
-- Dulu kegagalan sementara (HTTP 429/502) tersimpan selamanya sebagai "" dan
-- thumbnail lagu itu tidak pernah muncul lagi sampai rejoin.
local function cacheGet(rawId)
	local c = tCache[rawId]
	if not c then return nil end
	if c.img == "" and (os.clock() - c.at) > NEG_TTL then
		tCache[rawId] = nil
		return nil
	end
	return c.img
end

local function cacheSet(rawId, img)
	tCache[rawId] = { img = img, at = os.clock() }
end

-- [FIX R6] Info aset (jaga jarak 0.15 dtk + ulang 3x) & URL thumbnail kreator
-- memakai helper MusicShared yang sama dengan server.
local function resolve(rawId)
	local num = tonumber(rawId)
	if not num then return "" end
	local info = Shared.productInfo(num)
	if not (info and info.Creator) then return "" end
	return Shared.creatorThumb(info.Creator)
end

local function pump()
	if tRunning or #tQueue == 0 then return end
	tRunning = true
	task.spawn(function()
		while #tQueue > 0 do
			local req    = table.remove(tQueue, 1)
			local cached = cacheGet(req.rawId)
			if cached ~= nil then
				if req.cb then task.spawn(req.cb, cached) end
			else
				local img = resolve(req.rawId)
				cacheSet(req.rawId, img)
				if req.cb then task.spawn(req.cb, img) end
			end
		end
		tRunning = false
	end)
end

-- front = true -> masuk depan antrian (avatar header seksi kreator)
function L.thumb(rawId, cb, front)
	if not rawId then if cb then cb("") end return end
	local cached = cacheGet(rawId)
	if cached ~= nil then if cb then cb(cached) end return end
	if #tQueue >= MAX_QUEUE then return end
	local req = { rawId = rawId, cb = cb }
	if front then table.insert(tQueue, 1, req) else table.insert(tQueue, req) end
	pump()
end

function L.thumbForSong(song, cb)
	if not cb then return end
	if song and song.thumbnailUrl and song.thumbnailUrl ~= "" then cb(song.thumbnailUrl); return end
	L.thumb(song and (song.RawId or Shared.rawId(song.Id)), cb)
end

function L.resetThumbs() tCache, tQueue = {}, {} end

-- ══ FILTER / SORT / GROUP ═════════════════════════════════════════════════
local function filterSongs(list, q)
	list = list or {}
	if not q or q == "" then return list end
	q = q:lower()
	local out = {}
	for _, s in ipairs(list) do
		if (s.Name or ""):lower():find(q, 1, true)
			or (s.Requester or ""):lower():find(q, 1, true)
			or (s.AudioCreator or ""):lower():find(q, 1, true) then
			table.insert(out, s)
		end
	end
	return out
end

local function sortSongs(list)
	local s = table.clone(list or {})
	local mode = S.sortMode or "last"
	if mode == "last" then
		table.sort(s, function(a, b) return (a.AddedTime or 0) > (b.AddedTime or 0) end)
	elseif mode == "asc" then
		table.sort(s, function(a, b) return (a.Name or ""):lower() < (b.Name or ""):lower() end)
	elseif mode == "desc" then
		table.sort(s, function(a, b) return (a.Name or ""):lower() > (b.Name or ""):lower() end)
	end
	return s
end

local function groupByCreator(songs)
	local INDIE = UI.INDIE_KEY
	local groups, order = {}, {}
	for _, song in ipairs(songs) do
		local key = song.creatorType == "Group" and (song.AudioCreator or "Unknown") or INDIE
		if not groups[key] then groups[key] = {}; table.insert(order, key) end
		table.insert(groups[key], song)
	end
	table.sort(order, function(a, b)
		if a == INDIE then return true end
		if b == INDIE then return false end
		return a:lower() < b:lower()
	end)
	local result = {}
	for _, name in ipairs(order) do
		table.insert(result, { creator = name, songs = groups[name], isIndie = (name == INDIE) })
	end
	return result
end

-- ══ TOMBOL ANTRIAN & FAVORIT ══════════════════════════════════════════════
local function paintQueueBtn(songId, btn)
	if not btn or not btn.Parent then return end
	local status = (S.queueIds or {})[songId]
	if status == "sedangDiputar" then
		btn.BackgroundColor3 = C.playing; btn.TextColor3 = C.onAccent
		btn.Text = "♪"; btn.TextSize = 12
	elseif status == "diAntrian" then
		btn.BackgroundColor3 = C.inQueue; btn.TextColor3 = C.white
		btn.Text = "✓"; btn.TextSize = 12
	elseif S.liveLocked then -- [FIX M6] live: request dikunci
		btn.BackgroundColor3 = C.bgLight; btn.TextColor3 = C.muted
		btn.Text = "▶"; btn.TextSize = 10
	else
		btn.BackgroundColor3 = C.accent; btn.TextColor3 = C.onAccent
		btn.Text = "▶"; btn.TextSize = 10
	end
end

function L.repaintQueueBtns()
	for songId, btn in pairs(S.libBtns or {}) do
		if btn and btn.Parent then paintQueueBtn(songId, btn) else S.libBtns[songId] = nil end
	end
end

-- Favorit bergaya OUTLINE: hati merah + garis tepi merah di atas kartu gelap.
-- Bukan isian emas — supaya jelas ini "love", bukan tombol aksi biasa.
local function paintFavBtn(btn, fav)
	if not btn or not btn.Parent then return end
	btn.Text             = fav and "♥" or "♡"
	btn.TextColor3       = fav and C.love or C.gray
	btn.BackgroundColor3 = C.bgLight
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = fav and C.love or C.border end
end

function L.repaintFavBtns()
	local ids = S.myIds or {}
	for songId, btn in pairs(S.favBtns or {}) do
		if btn and btn.Parent then paintFavBtn(btn, ids[songId] == true)
		else S.favBtns[songId] = nil end
	end
end

-- [FIX R6] ID angka lagu: Shared.rawId (dulu UI.extractId).
-- ══ ITEM LIBRARY ══════════════════════════════════════════════════════════
-- mineView = true -> item berasal dari "My Library"
local function libItem(song, parent, lo, mineView)
	local item = w.frame({
		Name = "S_" .. (Shared.rawId(song.Id) or tostring(lo)),
		Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = C.bgCard,
		LayoutOrder = lo, Parent = parent,
	})
	w.corner(8).Parent = item
	w.stroke(C.border, 1).Parent = item

	local ct = w.frame({ Size = UDim2.new(1, -12, 1, -10), Position = UDim2.new(0, 6, 0, 5), BackgroundTransparency = 1, Parent = item })
	local thumb = w.image({ Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 0, 0, 3), BackgroundColor3 = C.section, ScaleType = Enum.ScaleType.Fit, Parent = ct })
	w.corner(6).Parent = thumb

	L.thumbForSong(song, function(img)
		if thumb.Parent then
			thumb.Image = img
			if img ~= "" then tws(thumb, { BackgroundTransparency = 1 }) end
		end
	end)

	local textW = -140

	-- Judul di dalam frame ber-clip supaya bisa berjalan saat di-hover/ditap.
	local nameClip = w.frame({
		Size = UDim2.new(1, textW, 0, 15), Position = UDim2.new(0, 50, 0, 4),
		BackgroundTransparency = 1, ClipsDescendants = true, Parent = ct,
	})
	local nameLbl = w.text({ Size = UDim2.new(1, 0, 1, 0),
		Text = song.Name or "Unknown", Font = Enum.Font.GothamBold, TextSize = 10,
		TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = nameClip })

	local sub = song.AudioCreator or song.Requester or ""
	if mineView then
		sub = (song.source == "own" and "Added by you · " or "Favorite · ") .. sub
	end
	w.text({ Size = UDim2.new(1, textW, 0, 11), Position = UDim2.new(0, 50, 0, 21),
		Text = sub, TextSize = 8,
		TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = ct })

	-- Tombol transparan di atas area teks. Hover untuk desktop, tap untuk
	-- layar sentuh. Tidak menutupi tombol ♥ / ▶ / × yang ada di sisi kanan.
	local nameHit = w.button({
		Size = UDim2.new(1, textW, 0, 30), Position = UDim2.new(0, 50, 0, 2),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = ct,
	})
	UI.marqueeOnHover(nameHit, nameLbl)

	local unavail = song.unavailable == true

	-- favorit (♡ / ♥) — hati langsung berubah saat diklik, server menyusul
	-- Favorit di paling kanan: tombol ini SELALU ada untuk semua pemain.
	-- Tombol hapus (hanya admin/pemilik) ditaruh di kiri, jadi tata letak
	-- pemain biasa tidak menyisakan lubang di ujung baris.
	local favBtn = w.button({
		Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -32, 0, 7),
		BackgroundColor3 = C.bgLight, Text = "♡", TextColor3 = C.gray,
		Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 3, Parent = ct,
	})
	w.corner(15).Parent = favBtn
	w.stroke(C.border, 1).Parent = favBtn
	paintFavBtn(favBtn, (S.myIds or {})[song.Id] == true)
	S.favBtns[song.Id] = favBtn
	favBtn.MouseButton1Click:Connect(function()
		local wasFav = (S.myIds or {})[song.Id] == true
		paintFavBtn(favBtn, not wasFav)
		if mineView and song.source == "own" then
			remote:FireServer("RemoveMySong", song.Id)
		else
			remote:FireServer("ToggleFavorite", song.Id)
		end
	end)

	-- antrian
	local qBtn = w.button({
		Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(1, -68, 0, 6),
		BackgroundColor3 = unavail and C.muted or C.accent,
		Text = unavail and "✕" or "▶",
		TextColor3 = unavail and C.white or C.onAccent,
		TextSize = 10, Parent = ct,
	})
	w.corner(16).Parent = qBtn

	if unavail then
		w.text({ Size = UDim2.new(1, textW, 0, 10), Position = UDim2.new(0, 50, 0, 34),
			Text = "Unavailable", TextColor3 = C.danger, TextSize = 8,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = ct })
		qBtn.MouseButton1Click:Connect(function()
			UI.notify("Song unavailable", C.danger, 2)
		end)
	else
		S.libBtns[song.Id] = qBtn
		paintQueueBtn(song.Id, qBtn)

		qBtn.MouseButton1Click:Connect(function()
			local status = (S.queueIds or {})[song.Id]
			if status == "sedangDiputar" then
				UI.notify("Already playing", C.playing, 2); return
			elseif status == "diAntrian" then
				UI.notify("Already in the queue", C.inQueue, 2); return
			elseif S.liveLocked then -- [FIX M6]
				UI.notify("Live: song requests are paused", C.danger, 2); return
			end
			remote:FireServer("AddToQueue", song.Id)
		end)
		qBtn.MouseEnter:Connect(function()
			if not (S.queueIds or {})[song.Id] and not S.liveLocked then tws(qBtn, { BackgroundColor3 = C.accentDk }) end -- [FIX M6]
		end)
		qBtn.MouseLeave:Connect(function()
			if not (S.queueIds or {})[song.Id] then paintQueueBtn(song.Id, qBtn) end
		end)
	end

	-- hapus
	local canDelete
	if mineView then
		canDelete = true
	else
		canDelete = (song.RequesterId == player.UserId)
			or (not song.RequesterId and song.Requester == player.Name)
			or S.isAdmin == true
	end

	if canDelete then
		local rm = w.button({
			Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -104, 0, 7),
			BackgroundColor3 = C.bgLight, Text = "×", TextColor3 = C.gray,
			Font = Enum.Font.GothamBold, TextSize = 15, Parent = ct,
		})
		w.corner(15).Parent = rm
		rm.MouseButton1Click:Connect(function()
			if mineView then remote:FireServer("RemoveMySong", song.Id)
			else remote:FireServer("RemoveSong", song.Id) end
		end)
		rm.MouseEnter:Connect(function() tws(rm, { BackgroundColor3 = C.danger,  TextColor3 = C.white }) end)
		rm.MouseLeave:Connect(function() tws(rm, { BackgroundColor3 = C.bgLight, TextColor3 = C.gray  }) end)
	end
end

-- [FIX R3] RENDER BERTAHAP. Dulu semua baris dibuat dalam satu frame: cari "a"
-- = ±500 baris x ±14 instance sekaligus → HP patah-patah. Sekarang BATCH baris
-- pertama langsung, sisanya BATCH per frame. Render baru (ketik lagi, ganti tab,
-- library ter-update) membatalkan sisa render lama lewat renderGen.
local BATCH = Shared.renderBatch
local renderGen = 0

local function renderRows(songs, parent, mineView)
	local gen, n = renderGen, #songs
	for i = 1, math.min(n, BATCH) do libItem(songs[i], parent, i, mineView) end
	if n <= BATCH then return end
	task.spawn(function()
		for start = BATCH + 1, n, BATCH do
			task.wait()
			if gen ~= renderGen or not parent.Parent then return end
			for i = start, math.min(n, start + BATCH - 1) do libItem(songs[i], parent, i, mineView) end
		end
	end)
end

-- ══ SEKSI KREATOR (accordion) ═════════════════════════════════════════════
local sections = {}
-- [FIX R3] Grup yang sedang dibuka diingat, jadi tetap terbuka saat library
-- ter-update (dulu setiap tambah/hapus lagu menutup semua grup).
local openCreator = nil

local function creatorSection(group, parent, lo)
	local creator, songs, isIndie = group.creator, group.songs, group.isIndie
	local totalH = math.max(#songs * 64 - 4, 10)

	local section = w.frame({
		Name = "Sec_" .. creator:sub(1, 20), Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1, LayoutOrder = lo, Parent = parent,
		ClipsDescendants = false,
	})
	local header = w.button({
		Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.bgCard, Text = "",
		AutoButtonColor = false, Font = Enum.Font.Gotham, TextSize = 1, Parent = section,
	})
	w.corner(8).Parent = header
	w.stroke(isIndie and C.accent or C.border, 1).Parent = header

	local avatar = w.image({
		Size = UDim2.new(0, 24, 0, 24), Position = UDim2.new(0, 8, 0, 6),
		BackgroundColor3 = C.section, BackgroundTransparency = 0,
		ScaleType = Enum.ScaleType.Fit, Parent = header,
	})
	w.corner(12).Parent = avatar

	if isIndie then
		local r1 = songs[1] and (songs[1].RawId or Shared.rawId(songs[1].Id))
		if r1 then
			avatar.Image = "rbxthumb://type=Asset&id=" .. r1 .. "&w=150&h=150"
			avatar.BackgroundTransparency = 1
		end
	else
		local found = ""
		for _, s in ipairs(songs) do
			if s.thumbnailUrl and s.thumbnailUrl ~= "" then found = s.thumbnailUrl; break end
		end
		if found ~= "" then
			avatar.Image = found; avatar.BackgroundTransparency = 1
		elseif songs[1] then
			L.thumb(songs[1].RawId or Shared.rawId(songs[1].Id), function(img)
				if avatar.Parent and img ~= "" then
					avatar.Image = img
					tws(avatar, { BackgroundTransparency = 1 })
				end
			end, true)
		end
	end

	w.text({
		Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 38, 0, 0),
		Text = (isIndie and UI.INDIE_KEY or creator) .. "  (" .. #songs .. ")",
		Font = Enum.Font.GothamBold, TextSize = 10,
		TextColor3 = isIndie and C.accent or C.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = header,
	})

	local arrow = w.text({
		Size = UDim2.new(0, 22, 1, 0), Position = UDim2.new(1, -24, 0, 0),
		Text = "▼", TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 8,
		TextXAlignment = Enum.TextXAlignment.Center, Parent = header,
	})

	local songList = w.frame({
		Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, 40),
		BackgroundTransparency = 1, ClipsDescendants = true, Parent = section,
	})
	w.list({ padding = 4 }).Parent = songList

	local rendered, isOpen = false, false

	local function setOpen(open, animate)
		isOpen = open
		if open and not rendered then
			rendered = true
			renderRows(songs, songList, false) -- [FIX R3]
		end
		arrow.Text  = open and "▲" or "▼"
		local bg    = open and C.bgLight or C.bgCard
		local listH = open and totalH or 0
		if animate then
			tw(header,   UI.SEC_TW, { BackgroundColor3 = bg })
			tw(songList, UI.SEC_TW, { Size = UDim2.new(1, 0, 0, listH) })
			tw(section,  UI.SEC_TW, { Size = UDim2.new(1, 0, 0, 40 + listH) })
		else
			header.BackgroundColor3 = bg
			songList.Size = UDim2.new(1, 0, 0, listH)
			section.Size  = UDim2.new(1, 0, 0, 40 + listH)
		end
	end

	sections[creator] = setOpen

	header.MouseButton1Click:Connect(function()
		local willOpen = not isOpen
		openCreator = willOpen and creator or nil -- [FIX R3]
		if willOpen then
			for key, ctrl in pairs(sections) do
				if key ~= creator then ctrl(false, true) end
			end
		end
		setOpen(willOpen, true)
	end)

	UI.hover(header, C.bgCard, C.bgLight)
	if openCreator == creator then setOpen(true, false) end -- [FIX R3]
end

-- ══ UPDATE VIEW ═══════════════════════════════════════════════════════════
local function emptyRow(text)
	w.text({
		Size = UDim2.new(1, 0, 0, 44), Text = text,
		TextColor3 = C.muted, TextSize = 10, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 1, LayoutOrder = 1, Parent = ui.libList,
	})
end

function L.refreshLib()
	if not ui or not S then return end

	local sharedLib = S.sharedLib or {}
	local myLib     = S.myLib or {}
	local q         = ui.filterLib.Text or ""
	local isSearch  = q ~= ""
	local mineView  = (S.libView == "mine")

	renderGen += 1 -- [FIX R3] hentikan sisa render sebelumnya
	sections  = {}
	S.libBtns = {}
	S.favBtns = {}
	UI.clearList(ui.libList)

	if ui.tabMineBtn then
		ui.tabMineBtn.Text = ("Mine (%d)"):format(#myLib)
	end

	if mineView then
		local songs = sortSongs(filterSongs(myLib, q))
		ui.libLabel.Text = isSearch
			and ("RESULTS (" .. #songs .. "/" .. #myLib .. ")")
			or  ("MY LIBRARY (" .. #myLib .. ")")

		if #myLib == 0 then
			emptyRow("Your library is empty.\nTap ♡ on any song, or add an audio ID above.")
		elseif #songs == 0 then
			emptyRow("No songs found")
		else
			renderRows(songs, ui.libList, true)
		end
		return
	end

	local songs = filterSongs(sharedLib, q)
	local total = #sharedLib

	if isSearch then
		ui.libLabel.Text = "RESULTS (" .. #songs .. "/" .. total .. ")"
		if #songs == 0 then
			emptyRow("No songs found")
		else
			renderRows(sortSongs(songs), ui.libList, false)
		end
	else
		ui.libLabel.Text = "LIBRARY (" .. total .. ")"
		if total == 0 then
			emptyRow("The global library is empty")
		else
			for i, group in ipairs(groupByCreator(sortSongs(songs))) do
				creatorSection(group, ui.libList, i)
			end
		end
	end
end

function L.updateQueue(songs)
	if not ui then return end
	songs = songs or {}
	UI.clearList(ui.queueList)

	local max = (S.queueLimit and S.queueLimit.max) or Shared.maxGlobalQueue
	local n   = #songs
	ui.queueLabel.Text = ("QUEUE (%d/%d)"):format(n, max) .. (S.liveAny and "  ·  LIVE" or "") -- [FIX M6] [FIX M6b]
	ui.queueLabel.TextColor3 =
		n >= max * 0.8 and C.danger or n >= max * 0.6 and C.accent or C.white

	for idx, song in ipairs(songs) do
		local item = w.frame({
			Name = "Q_" .. idx, Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = C.bgCard, LayoutOrder = idx, Parent = ui.queueList,
		})
		w.corner(8).Parent = item; w.stroke(C.border, 1).Parent = item

		local ct = w.frame({ Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, Parent = item })

		local badge = w.frame({ Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0, 0, 0, 10), BackgroundColor3 = C.accent, Parent = ct })
		w.corner(6).Parent = badge
		w.text({ Size = UDim2.new(1, 0, 1, 0), Text = tostring(idx), TextColor3 = C.onAccent, Font = Enum.Font.GothamBold, TextSize = 10, Parent = badge })

		local thumb = w.image({ Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 26, 0, 3), BackgroundColor3 = C.section, ScaleType = Enum.ScaleType.Fit, Parent = ct })
		w.corner(6).Parent = thumb
		L.thumbForSong(song, function(img)
			if thumb.Parent then
				thumb.Image = img
				if img ~= "" then tws(thumb, { BackgroundTransparency = 1 }) end
			end
		end)

		-- Admin ATAU pemilik antrian boleh menghapus.
		local canRemove = (S.isAdmin == true) or (song.RequesterId == player.UserId)
			or (S.liveOn == true and S.liveDjId == player.UserId) -- [FIX M6c] DJ live kelola antrian
		local nameW = canRemove and -108 or -74

		w.text({ Size = UDim2.new(1, nameW, 0, 13), Position = UDim2.new(0, 72, 0, 3),
			Text = song.Name or "?", Font = Enum.Font.GothamBold, TextSize = 10,
			TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = ct })
		w.text({ Size = UDim2.new(1, nameW, 0, 10), Position = UDim2.new(0, 72, 0, 18),
			Text = "by " .. (song.Requester or "?") .. ((S.liveAny and (S.liveFollow or song.RequesterId ~= S.liveDjId)) and "  ·  ON HOLD" or ""), TextSize = 8, -- [FIX M6b]
			TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left, Parent = ct })

		if canRemove then
			local rm = w.button({
				Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -28, 0, 12),
				BackgroundColor3 = C.bgLight, Text = "×", TextColor3 = C.gray,
				Font = Enum.Font.GothamBold, TextSize = 14, Parent = ct,
			})
			w.corner(13).Parent = rm
			-- Kirim index + id: server verifikasi id-nya, jadi kalau antrian
			-- bergeser sebelum request sampai, yang dihapus tetap lagu ini.
			local myIdx, myId = idx, song.Id
			rm.MouseButton1Click:Connect(function()
				remote:FireServer("RemoveFromQueue", { index = myIdx, id = myId })
			end)
			rm.MouseEnter:Connect(function() tws(rm, { BackgroundColor3 = C.danger,  TextColor3 = C.white }) end)
			rm.MouseLeave:Connect(function() tws(rm, { BackgroundColor3 = C.bgLight, TextColor3 = C.gray  }) end)
		end
	end
end

function L.reset()
	sections = {}
	openCreator = nil -- [FIX R3]
	renderGen += 1
	UI.stopAllMarquees()
	L.resetThumbs()
end

return L