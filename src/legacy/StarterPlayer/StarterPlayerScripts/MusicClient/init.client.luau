-- StarterPlayerScripts/MusicClient (LocalScript)
-- Bootstrap + controller: menyambungkan UI <-> server.
-- Tidak ada kode pembuat widget maupun manipulasi Sound di sini.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

do
	local t0 = os.clock()
	while not _G.InjectMusicUI and (os.clock() - t0) < 30 do task.wait(0.2) end
	if not _G.InjectMusicUI then
		warn("[MusicClient] _G.InjectMusicUI not available, stopping.")
		return
	end
end

if _G.MusicClient then
	if _G.MusicClientUI then pcall(function() _G.MusicClientUI:Destroy() end) end
	task.wait(0.1)
end
_G.MusicClient = true

local Shared = require(RS:WaitForChild("MusicShared"))
local UI     = require(script:WaitForChild("UI"))
local Lists  = require(script:WaitForChild("Lists"))
local Audio  = require(script:WaitForChild("Audio"))

local C      = UI.C
local remote = Shared.remote

-- Palet: tema global menang, palet modul UI jadi cadangan. Hanya tiga warna
-- yang dipakai untuk notifikasi supaya panel tidak terlihat belang.
local G = _G.MenuConfig and _G.MenuConfig.theme
local P = {
	accent  = (G and G.ACCENT)     or C.accent,
	surface = (G and G.CARD)       or C.section,
	panel   = (G and G.CARD)       or C.bgLight,
	hover   = (G and G.CARD_HOVER) or C.hover,
	danger  = (G and G.DANGER)     or C.danger,
}

local S = {
	sharedLib  = {},
	myLib      = {},
	myIds      = {},
	fullQueue  = {},
	queueIds   = {},
	libBtns    = {},
	favBtns    = {},
	sortMode   = "last",
	libView    = "all",     -- "all" | "mine"
	isAdmin    = false,
	isDJ       = false, -- [FIX L1b]
	liveOn     = false,
	queueLimit = { current = 0, max = Shared.maxGlobalQueue, myLimit = 1 },
	spatial    = {},
}

local ok, ui = pcall(UI.build)
if not ok then warn("[MusicClient] build error:", ui) return end

UI.bindNotify(ui.notifBar, ui.notifText)
Lists.init({ ui = ui, state = S })

-- Dua nada notifikasi saja: aksen (info/sukses) dan merah (gagal).
local function notify(text)  UI.notify(text, P.accent, 2) end
local function notifyErr(t)  UI.notify(t,    P.danger, 2) end

-- Render library itu operasi paling mahal di panel ini. Semua permintaan
-- refresh dikumpulkan jadi satu per frame supaya burst event dari server
-- tidak me-render berkali-kali.
local refreshQueued = false
local function refreshLib()
	if refreshQueued then return end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		Lists.refreshLib()
	end)
end

-- ══ VISIBILITAS PANEL ═════════════════════════════════════════════════════
local alive    = true
local menuOpen = true

local function uiVisible()
	if not menuOpen then return false end
	local container = ui.container
	if not container.Parent or not container.Visible then return false end
	return container.Parent.Visible
end

-- Judul lagu berjalan sendiri kalau tidak muat. Ditunda satu frame karena
-- AbsoluteSize label baru valid setelah layout dihitung. Saat panel tertutup
-- marquee dihentikan supaya tidak ada tween yang jalan sia-sia.
local function applyTitleMarquee()
	task.defer(function()
		if not alive or not ui.songTitle.Parent then return end
		if uiVisible() then UI.marquee(ui.songTitle) else UI.stopMarquee(ui.songTitle) end
	end)
end

if _G.PanelCoordinator and _G.PanelCoordinator.OnChange then
	_G.PanelCoordinator.OnChange(function(active)
		menuOpen = (active == nil) or (active == "Menu_Menu")
		applyTitleMarquee()
	end)
end

-- ══ LAPORAN KE SERVER ═════════════════════════════════════════════════════
-- Server tidak me-render audio, jadi TimeLength/TimePosition/IsLoaded di sana
-- tidak bisa dipercaya. Client ini satu-satunya pihak yang benar-benar tahu:
--   len    -> durasi asli, dikirim sekali begitu audio ter-load
--   pos    -> heartbeat posisi playback, dasar keputusan akhir lagu di server
--   failed -> audio memang tidak bisa dimuat di mesin ini
local REPORT_EVERY = 3
local PROBE_AFTER  = Shared.probeDelay or 5   -- cek aset setelah sekian detik sunyi
local TICK_VISIBLE = 0.25
local TICK_HIDDEN  = 1
local TICK_IDLE    = 1

local progTask
local songId                 -- raw id lagu sekarang
local songFullId             -- "rbxassetid://..." untuk favorit
local songSeq    = 0
local songAt     = 0
local durSent    = false
local failSent   = false
local rescuedFor = nil
local lastPos    = 0
local currentNP  = nil

local function reportLen(len)
	if durSent then return end
	durSent = true
	remote:FireServer("ReportDuration", { id = songId, len = len })
end

local function reportPos(pos, len)
	if os.clock() - lastPos < REPORT_EVERY then return end
	lastPos = os.clock()
	remote:FireServer("ReportDuration", { id = songId, pos = pos, len = len })
end

-- Kalau audio belum berbunyi setelah PROBE_AFTER detik, cari tahu SEBABNYA
-- lebih dulu, jangan langsung menuduh lagunya rusak:
--
--   aset sehat  -> berarti instance Sound di mesin ini yang nyangkut.
--                  Salinan lokal langsung dibuat (asetnya sudah di cache,
--                  jadi bunyinya kembali dalam hitungan detik, bukan 20 detik).
--   aset gagal  -> laporkan ke server supaya server mengulang :Play() untuk
--                  semua orang, dan tetap dicoba lokal sekali.
local function watchLoadFailure(myId, seq)
	task.delay(PROBE_AFTER, function()
		if not alive or songSeq ~= seq or songId ~= myId or durSent then return end

		local snd = Audio.get() or Audio.find()
		if snd then
			local okRead, len, loaded = pcall(function()
				return snd.TimeLength, snd.IsLoaded
			end)
			if okRead and ((len and len > 0) or loaded == true) then return end
		end

		local assetOk = Audio.probe(myId)          -- memblokir, sudah di thread sendiri
		if not alive or songSeq ~= seq or songId ~= myId or durSent then return end

		if not assetOk and not failSent then
			failSent = true
			remote:FireServer("ReportDuration", { id = myId, failed = true })
		end

		if rescuedFor ~= myId and not Audio.isEmergency() then
			rescuedFor = myId
			local elapsed = (os.clock() - songAt) + ((currentNP and currentNP.Elapsed) or 0)
			Audio.hardResync({ Id = myId, Elapsed = elapsed }, true)
		end

		-- Aset sehat tapi tetap sunyi setelah salinan lokal? Baru laporkan gagal.
		if assetOk then
			task.delay(8, function()
				if not alive or songSeq ~= seq or durSent or failSent then return end
				failSent = true
				remote:FireServer("ReportDuration", { id = myId, failed = true })
			end)
		end
	end)
end

-- ══ PROGRESS BAR ══════════════════════════════════════════════════════════
local function stopProg()
	if progTask then task.cancel(progTask) progTask = nil end
	ui.progressBar.Size = UDim2.new(0, 0, 1, 0)
	ui.currentTime.Text = "0:00"
	ui.totalTime.Text   = "0:00"
end

-- Satu loop untuk progress UI sekaligus pelaporan ke server. Saat panel
-- tertutup, loop melambat 4x dan tidak menulis properti UI sama sekali.
-- [FIX M7] PENYEMBUH OTOMATIS. Dulu penyelamat hanya jalan SEKALI di detik ke-5
-- tiap lagu; kalau CDN audio Roblox sedang HTTP 502/Timedout, salinan lokal ikut
-- gagal dan pemain itu sunyi sampai lagu berganti (bisa 5 menit). Sekarang:
--   * audio belum termuat > HEAL_AFTER dtk → coba salinan lokal baru (instance
--     Sound baru = unduhan ulang), maks HEAL_MAX kali per lagu;
--   * pengali fade tertahan di 0 padahal lagu jalan > 3 dtk → dinaikkan lagi.
local HEAL_AFTER, HEAL_GAP, HEAL_MAX = 12, 12, 8
local heal = { seq = -1, silentSince = nil, lastAt = 0, count = 0, zeroSince = nil }

local function healTick(_snd, loaded)
	if heal.seq ~= songSeq then
		heal.seq, heal.silentSince, heal.lastAt, heal.count, heal.zeroSince = songSeq, nil, 0, 0, nil
	end
	local now = os.clock()
	if loaded then
		heal.silentSince = nil
		if Audio.getFade() < 0.05 and not Audio.isFading() then
			heal.zeroSince = heal.zeroSince or now
			if now - heal.zeroSince > 3 then
				heal.zeroSince = nil
				warn("[MusicClient] self-heal: volume fade stuck at 0, fading in")
				Audio.fadeTo(1, Shared.fadeIn)
			end
		else
			heal.zeroSince = nil
		end
		return
	end
	heal.silentSince = heal.silentSince or now
	if now - heal.silentSince < HEAL_AFTER or now - heal.lastAt < HEAL_GAP or heal.count >= HEAL_MAX then return end
	heal.lastAt = now
	heal.count += 1
	local elapsed = (now - songAt) + ((currentNP and currentNP.Elapsed) or 0)
	warn(("[MusicClient] self-heal #%d: audio %s not loaded after %.0fs, retrying locally")
		:format(heal.count, tostring(songId), now - heal.silentSince))
	Audio.hardResync({ Id = songId, Elapsed = elapsed }, true, true)
end
local function startProg()
	if progTask then task.cancel(progTask) end
	progTask = task.spawn(function()
		local snd
		while alive do
			if not songId then
				task.wait(TICK_IDLE)
			else
				local visible = uiVisible()
				task.wait(visible and TICK_VISIBLE or TICK_HIDDEN)

				local live = Audio.get()
				if live and live ~= snd then snd = live end
				if not snd or not snd.Parent then snd = Audio.get() or Audio.find() end

				if snd then
					local okRead, playing, pos, len, loaded = pcall(function()
						return snd.IsPlaying, snd.TimePosition, snd.TimeLength, snd.IsLoaded
					end)

					pcall(healTick, snd, okRead and (loaded == true or (len and len > 1)) or false) -- [FIX M7]
					if okRead and loaded and len and len > 1 then
						reportLen(len)
						if playing then
							reportPos(pos, len)
							if visible then
								ui.progressBar.Size = UDim2.new(math.clamp(pos / len, 0, 1), 0, 1, 0)
								ui.currentTime.Text = UI.fmtTime(pos)
								ui.totalTime.Text   = UI.fmtTime(len)
							end
						end
					end
				end
			end
		end
	end)
end

-- ══ NOW PLAYING ═══════════════════════════════════════════════════════════
local function updateSectionVis()
	ui.queueSection.Visible  = #S.fullQueue > 0
	-- [FIX L1b] DJ non-admin: kotak "DJ" yang hanya berisi tombol Live.
	local djOnly = (not S.isAdmin) and S.isDJ
	ui.adminSettings.Visible = S.isAdmin or S.isDJ
	for _, ch in ipairs(ui.adminCt:GetChildren()) do
		if ch:IsA("GuiObject") and ch ~= ui.liveRow and ch ~= ui.adminTitle then ch.Visible = not djOnly end
	end
	ui.adminTitle.Text       = djOnly and "DJ" or "ADMIN SETTINGS"
	ui.liveRow.Position      = djOnly and UDim2.new(0, 0, 0, 18) or UDim2.new(0, 0, 0, 288)
	ui.adminSettings.Size    = djOnly and UDim2.new(1, 0, 0, 66) or UDim2.new(1, 0, 0, 348)
	-- [FIX M6b] saat live hanya DJ siaran yang melihat Force skip
	if S.liveOn or S.liveFollow then ui.forceSkipBtn.Visible = S.liveOn == true and S.liveDjId == player.UserId
	else ui.forceSkipBtn.Visible = S.isAdmin or S.isDJ end
	-- Library global: hanya admin yang bisa menambah/menghapus isinya.
	ui.addGlobalBtn.Visible  = S.isAdmin
	ui.addMineBtn.Size = S.isAdmin and UDim2.new(0.5, -3, 0, 26) or UDim2.new(1, 0, 0, 26)

	-- [FIX M6] Banner LIVE + kunci request (tombol ▶ redup, antrian "ON HOLD").
	local wasAny, wasLocked = S.liveAny, S.liveLocked
	S.liveAny    = S.liveOn == true or S.liveFollow == true
	S.liveLocked = S.liveAny and not S.isDJ
	ui.liveBanner.Visible = S.liveAny
	if S.liveAny then
		local dj = tostring(S.liveDj or "?")
		ui.liveTitle.Text = S.liveFollow and ("LIVE  ·  DJ " .. dj .. "  ·  another server") or ("LIVE  ·  DJ " .. dj)
		local sub
		local me = S.liveOn and S.liveDjId == player.UserId -- [FIX M6b]
		if S.liveFollow then
			sub = "Playing from another server - the local queue is on hold"
		elseif me then
			sub = "You are the DJ - only your requests play"
		elseif S.liveLocked then
			sub = "Song requests are paused until the live ends"
		else
			sub = "Your requests wait until the live ends"
		end
		local held = 0
		for _, q in ipairs(S.fullQueue) do
			if S.liveFollow or q.RequesterId ~= S.liveDjId then held += 1 end
		end
		if held > 0 then sub ..= ("  ·  %d on hold"):format(held) end
		ui.liveSub.Text = sub
	end
	if S.liveLocked ~= wasLocked then Lists.repaintQueueBtns() end
	if S.liveAny ~= wasAny then Lists.updateQueue(S.fullQueue) end
end

-- Favorit bergaya outline merah, konsisten dengan tombol ♥ di daftar lagu.
local function paintNpFav(forceFav)
	local fav = forceFav
	if fav == nil then fav = songFullId ~= nil and S.myIds[songFullId] == true end
	ui.npFavBtn.Text             = fav and "♥" or "♡"
	ui.npFavBtn.TextColor3       = fav and C.love or C.gray
	ui.npFavBtn.BackgroundColor3 = P.panel
	if ui.npFavStroke then ui.npFavStroke.Color = fav and C.love or C.border end
	ui.npFavBtn.Visible          = songFullId ~= nil
end

local function updateNowPlaying(data)
	data = data or {}
	currentNP = data

	-- Kalau masih pakai clone darurat TAPI server sudah ganti lagu, clone lama
	-- masih memutar lagu LAMA -> dua audio tabrakan. Balik ke Sound server.
	if Audio.isEmergency() then
		local newId = data.Id and tostring(data.Id):match("%d+")
		if newId and Audio.emergencySoundId() ~= newId then
			Audio.track(Audio.lastPath())
		end
	end

	ui.songTitle.Text  = data.Name or "No song playing"
	ui.songArtist.Text = (data.Requester and data.Requester ~= "")
		and ("by " .. data.Requester) or "Add a song to the queue"
	applyTitleMarquee()

	if not data.Id then
		songId, songFullId = nil, nil
		songSeq = songSeq + 1
		Audio.onNowPlaying(nil)
		ui.albumArt.Image = ""
		ui.albumArt.BackgroundTransparency = 0
		ui.albumArt.ImageTransparency      = 0
		paintNpFav()
		stopProg()
		return
	end

	local newId  = tostring(data.Id):match("%d+")
	local sameId = (newId == songId)

	songSeq = songSeq + 1
	songId, songFullId = newId, "rbxassetid://" .. newId
	durSent, failSent, lastPos = false, false, 0
	songAt = os.clock()
	if not sameId then rescuedFor = nil end
	watchLoadFailure(newId, songSeq)
	Audio.onNowPlaying(newId)
	paintNpFav()

	-- Thumbnail hanya di-fetch ulang kalau lagunya memang ganti.
	if not sameId then
		UI.tws(ui.albumArt, { ImageTransparency = 1 })
		task.delay(0.08, function()
			if not alive or songId ~= newId then return end
			Lists.thumbForSong(data, function(img)
				if not alive or songId ~= newId then return end
				ui.albumArt.Image = img
				UI.tws(ui.albumArt, {
					BackgroundTransparency = img ~= "" and 1 or 0,
					ImageTransparency      = 0,
				})
			end)
		end)
	end

	startProg()
end

-- ══ ADD SONG ══════════════════════════════════════════════════════════════
local function readId()
	local text = ui.input.Text:match("^%s*(.-)%s*$")
	if text == "" then return nil end
	return text:match("rbxassetid://(%d+)")
		or text:match("/(%d+)/")
		or (text:match("^%d+$") and text)
end

local function flash(btn, color)
	local base = btn.BackgroundColor3
	btn.BackgroundColor3 = color
	task.delay(0.25, function()
		if btn.Parent then UI.tws(btn, { BackgroundColor3 = base }) end
	end)
end

ui.addMineBtn.MouseButton1Click:Connect(function()
	local id = readId()
	if not id then return notifyErr("Invalid ID") end
	flash(ui.addMineBtn, C.white)
	remote:FireServer("AddMySong", { Id = id })
	ui.input.Text = ""
end)

ui.addGlobalBtn.MouseButton1Click:Connect(function()
	if not S.isAdmin then return notifyErr("Admins only") end
	local id = readId()
	if not id then return notifyErr("Invalid ID") end
	flash(ui.addGlobalBtn, C.white)
	remote:FireServer("AddSong", { Id = id })
	ui.input.Text = ""
end)

-- Enter di kolom input = tambah ke My Library (aksi paling umum).
ui.input.FocusLost:Connect(function(enter)
	if not enter then return end
	local id = readId()
	if not id then return end
	remote:FireServer("AddMySong", { Id = id })
	ui.input.Text = ""
end)

-- ══ KONTROL ═══════════════════════════════════════════════════════════════
ui.skipBtn.MouseButton1Click:Connect(function() remote:FireServer("VoteSkip") end)
ui.forceSkipBtn.MouseButton1Click:Connect(function() remote:FireServer("ForceSkip") end)

ui.npFavBtn.MouseButton1Click:Connect(function()
	if not songFullId then return end
	local wasFav = S.myIds[songFullId] == true
	paintNpFav(not wasFav)          -- respons instan, server menyusul
	if wasFav then
		remote:FireServer("RemoveMySong", songFullId)
	else
		remote:FireServer("ToggleFavorite", songFullId)
	end
end)

local function paintTabs()
	local mine = (S.libView == "mine")
	ui.tabAllBtn.BackgroundColor3  = mine and P.panel  or P.accent
	ui.tabAllBtn.TextColor3        = mine and C.gray   or C.onAccent
	ui.tabMineBtn.BackgroundColor3 = mine and P.accent or P.panel
	ui.tabMineBtn.TextColor3       = mine and C.onAccent or C.gray
end
paintTabs()

local function setView(v)
	if S.libView == v then return end
	S.libView = v
	paintTabs()
	refreshLib()
	if v == "mine" then remote:FireServer("RequestMyLibrary") end
end

ui.tabAllBtn.MouseButton1Click:Connect(function()  setView("all")  end)
ui.tabMineBtn.MouseButton1Click:Connect(function() setView("mine") end)

-- Reload song: 1x segarkan, 2x dalam 5 detik = putar salinan lokal.
local lastClick, awaitingResync = 0, false
ui.reloadBtn.MouseButton1Click:Connect(function()
	local now    = os.clock()
	local double = (now - lastClick) < 5
	lastClick = now

	flash(ui.reloadBtn, P.accent)
	Audio.track(Audio.lastPath())
	remote:FireServer("RequestState", "reload") -- [FIX R2] tanpa library

	if double then
		awaitingResync = true
		notify("Local playback mode")
	else
		notify("Music refreshed")
	end
end)

-- ══ SLIDER & PENGATURAN ═══════════════════════════════════════════════════
local volTimer, volPending
local function pushVolume(pct)
	volPending = pct
	if volTimer then return end
	volTimer = task.delay(0.35, function()
		volTimer = nil
		if alive then remote:FireServer("SetVolume", volPending) end
	end)
end

UI.slider(ui.volBg, function(pct)
	ui.volSlider.Size = UDim2.new(pct, 0, 1, 0)
	ui.volLabel.Text  = "Volume " .. math.floor(pct * 100) .. "%"
	Audio.setVolume(pct)
	pushVolume(pct)
end, ui.scroll)

UI.slider(ui.globalVolBg, function(pct)
	ui.globalVolSlider.Size = UDim2.new(pct, 0, 1, 0)
	ui.globalVolLabel.Text  = "Global " .. math.floor(pct * 100) .. "%"
	S.spatial.volume = pct
end, ui.scroll)

local loudOn = Shared.loudness.enabled
local function paintLoud()
	ui.loudnessToggleBtn.Text             = loudOn and "On" or "Off"
	ui.loudnessToggleBtn.BackgroundColor3 = loudOn and P.accent or P.panel
	ui.loudnessToggleBtn.TextColor3       = loudOn and C.onAccent or C.gray
end
paintLoud()
ui.loudnessToggleBtn.MouseButton1Click:Connect(function()
	loudOn = not loudOn
	paintLoud()
end)

-- [FIX A1] Auto play On/Off (admin). Status asli datang lewat SpatialSettings.
local autoOn = Shared.spatial.autoplay ~= false
local function paintAuto()
	ui.autoplayBtn.Text             = autoOn and "On" or "Off"
	ui.autoplayBtn.BackgroundColor3 = autoOn and P.accent or P.panel
	ui.autoplayBtn.TextColor3       = autoOn and C.onAccent or C.gray
end
paintAuto()
ui.autoplayBtn.MouseButton1Click:Connect(function()
	autoOn = not autoOn
	paintAuto()
	remote:FireServer("SetSpatialSettings", { autoplay = autoOn })
	notify(autoOn and "Auto play on" or "Auto play off") -- [FIX A1]
end)

-- [FIX L1] Siaran live (admin). Status resmi datang dari server lewat LiveState.
local liveOn = false
local function paintLive()
	ui.liveBtn.Text             = liveOn and "LIVE - On" or "Off"
	ui.liveBtn.BackgroundColor3 = liveOn and P.danger or P.panel
	ui.liveBtn.TextColor3       = liveOn and C.white or C.gray
end
paintLive()
ui.liveBtn.MouseButton1Click:Connect(function()
	remote:FireServer("SetLive", not liveOn)
	notify(liveOn and "Stopping live..." or "Starting live...")
end)

local function numFrom(box, lo, hi)
	local v = tonumber(box.Text)
	return v and math.clamp(v, lo, hi) or nil
end

ui.applyBtn.MouseButton1Click:Connect(function()
	local mn = tonumber(ui.minDistInput.Text)
	local mx = tonumber(ui.maxDistInput.Text)
	local sz = tonumber(ui.sizeInput.Text)
	if not (mn and mx and sz) then return notifyErr("Invalid input") end
	if mn >= mx then return notifyErr("Min must be lower than Max") end

	remote:FireServer("SetSpatialSettings", {
		min             = math.clamp(mn, 1, 10000),
		max             = math.clamp(mx, 10, 10000),
		size            = math.clamp(sz, 1, 1000),
		volume          = S.spatial.volume or 1,
		loudnessEnabled = loudOn,
		compMakeupGain  = numFrom(ui.makeupInput, 0, 30),
		eqLow           = numFrom(ui.eqLowInput,  -12, 12),
		eqMid           = numFrom(ui.eqMidInput,  -12, 12),
		eqHigh          = numFrom(ui.eqHighInput, -12, 12),
	})
	notify("Settings applied")
end)

local mode = "stage"
local function paintMode(m)
	mode = m
	local isGlobal = (m == "global")
	ui.modeLabel.Text = isGlobal and "Mode: Global" or "Mode: Stage"
	ui.modeBtn.Text   = isGlobal and "Switch to Stage" or "Switch to Global"
end

ui.modeBtn.MouseButton1Click:Connect(function()
	remote:FireServer("SetSpatialSettings", { mode = (mode == "stage") and "global" or "stage" })
end)

local filterTimer
ui.filterLib:GetPropertyChangedSignal("Text"):Connect(function()
	if filterTimer then task.cancel(filterTimer) end
	filterTimer = task.delay(0.25, function()
		filterTimer = nil
		refreshLib()
	end)
end)

local sortLabels = { last = "Recent", asc = "A-Z", desc = "Z-A" }
local sortCycle  = { last = "asc", asc = "desc", desc = "last" }
ui.sortBtn.MouseButton1Click:Connect(function()
	S.sortMode      = sortCycle[S.sortMode] or "last"
	ui.sortBtn.Text = sortLabels[S.sortMode]
	refreshLib()
end)

-- Hover hanya untuk tombol tanpa status. Tombol berstatus (tab, favorit,
-- loudness) diwarnai fungsi paint-nya sendiri, jadi tidak boleh diganggu.
for _, e in ipairs({
	{ ui.skipBtn,      P.panel,  P.hover },
	{ ui.applyBtn,     P.accent, P.hover },
	{ ui.modeBtn,      P.accent, P.hover },
	{ ui.forceSkipBtn, P.accent, P.hover },
	{ ui.reloadBtn,    P.panel,  P.hover },
	{ ui.addMineBtn,   P.accent, P.hover },
	{ ui.addGlobalBtn, P.panel,  P.hover },
	{ ui.sortBtn,      P.panel,  P.hover },
	}) do
	if e[1] then UI.hover(e[1], e[2], e[3]) end
end

ui.input.Focused:Connect(function()   UI.tws(ui.input, { BackgroundColor3 = P.panel }) end)
ui.input.FocusLost:Connect(function() UI.tws(ui.input, { BackgroundColor3 = P.surface }) end)

-- ══ HANDLER DARI SERVER ═══════════════════════════════════════════════════
local H = {}

H.SoundLocation = function(data) Audio.track(data) end

H.MusicFade = function(data)
	if type(data) == "table" then Audio.fadeTo(data.to or 0, data.dur or Shared.fadeOut) end
end

H.NowPlaying = function(data)
	updateNowPlaying(data)
	if awaitingResync then
		awaitingResync = false
		Audio.hardResync(data)
	end
end

H.SongStopped = function()
	Audio.fadeTo(0, Shared.fadeOut)
	stopProg()
end

H.SongDuration = function(data)
	if data and data > 0 then ui.totalTime.Text = UI.fmtTime(data) end
end

H.SongRetry = function() notify("Reloading song") end

-- [FIX R1] Daftar lengkap (saat join / diminta) membawa nomor versi.
H.SharedLibrary = function(data)
	if type(data) ~= "table" then return end
	S.sharedLib = data.full or data
	S.libVer = data.ver
	if S.libView == "all" then refreshLib() end
end

-- [FIX R1] Perubahan kecil library. Belum punya daftar lengkap → abaikan (menyusul).
-- Versi melompat (ada delta terlewat) → tetap diterapkan, lalu minta daftar lengkap.
H.LibDelta = function(d)
	if type(d) ~= "table" or type(d.ver) ~= "number" or type(S.libVer) ~= "number" then return end
	if d.ver <= S.libVer then return end
	if d.base ~= S.libVer then remote:FireServer("RequestLibrary") end
	Shared.libApply(S.sharedLib, d)
	S.libVer = d.ver
	if S.libView == "all" then refreshLib() end
end

-- My Library: kalau sedang melihat tab Global, cukup cat ulang hatinya.
-- Render penuh hanya saat tab "Mine" yang aktif.
H.MyLibrary = function(data)
	S.myLib = data or {}
	S.myIds = {}
	for _, song in ipairs(S.myLib) do
		if song and song.Id then S.myIds[tostring(song.Id)] = true end
	end
	ui.tabMineBtn.Text = ("Mine (%d)"):format(#S.myLib)
	paintNpFav()
	if S.libView == "mine" then refreshLib() else Lists.repaintFavBtns() end
end

H.FavUpdate = function(data)
	if type(data) ~= "table" then return end
	local name = tostring(data.name or "?")
	notify(data.added and ("Saved: " .. name) or ("Removed: " .. name))
end

H.MySongAdded = function(data) notify("Saved: " .. tostring(data or "?")) end
H.MyLibError  = function(data) notifyErr(tostring(data or "Failed")) end
H.SongAdded   = function(data) notify("Added to global: " .. tostring(data or "?")) end
H.SongError   = function(data) notifyErr(tostring(data or "Failed")) end
H.SongValidating = function() notify("Checking audio...") end

H.QueueUpdate = function(data)
	S.fullQueue = data or {}
	Lists.updateQueue(S.fullQueue)
	updateSectionVis()
	-- Muat dua lagu berikutnya selagi lagu sekarang masih jalan. Inilah yang
	-- mencegah "HTTP 502" muncul tepat pada detik pergantian lagu.
	for i = 1, math.min(2, #S.fullQueue) do
		local q = S.fullQueue[i]
		if q then Audio.preload(q.RawId or q.Id) end
	end
end

H.QueueIds = function(data)
	S.queueIds = data or {}
	Lists.repaintQueueBtns()
end

H.QueueLimit = function(data)
	S.queueLimit = data or S.queueLimit
end

H.SkipVoteUpdate = function(data)
	data = data or {}
	ui.skipBtn.Text = ("Skip %d/%d"):format(data.current or 0, data.required or 1)
end

H.SongUnavailable = function(data)
	local name = (type(data) == "table" and data.name) or tostring(data or "?")
	notifyErr("Unavailable: " .. name)
	Audio.onNowPlaying(nil)
	stopProg()
	ui.songTitle.Text  = "Unavailable"
	ui.songArtist.Text = name
	ui.albumArt.Image  = ""
	applyTitleMarquee()
end

H.GlobalVolumeUpdate = function(data)
	if not data then return end
	local pct = math.clamp(data, 0, 1)
	Audio.setGlobalVolume(pct) -- [FIX M5] pribadi × global
	ui.globalVolSlider.Size = UDim2.new(pct, 0, 1, 0)
	ui.globalVolLabel.Text  = "Global " .. math.floor(pct * 100) .. "%"
end

H.VolumeUpdate = function(data)
	if not data then return end
	local v = math.clamp(data, 0, 1)
	Audio.setVolume(v)
	ui.volSlider.Size = UDim2.new(v, 0, 1, 0)
	ui.volLabel.Text  = "Volume " .. math.floor(v * 100) .. "%"
end

H.IsDJ = function(data)
	S.isDJ = (data == true)
	updateSectionVis()
end
H.IsAdmin = function(data)
	local was = S.isAdmin
	S.isAdmin = (data == true)
	updateSectionVis()
	if S.isAdmin ~= was then
		refreshLib()
		if #S.fullQueue > 0 then Lists.updateQueue(S.fullQueue) end
	end
end

H.SpatialSettings = function(data)
	if not data then return end
	Audio.setSpatial(data)          -- dipakai salinan lokal agar terdengar sama
	Audio.setGlobalVolume(data.volume) -- [FIX M5] pemain baru join langsung tahu volume global
	if not S.isAdmin then return end
	S.spatial = data
	ui.minDistInput.Text = tostring(math.floor(data.min  or 10))
	ui.maxDistInput.Text = tostring(math.floor(data.max  or 500))
	ui.sizeInput.Text    = tostring(math.floor(data.size or 100))
	local v = math.clamp(data.volume or 1, 0, 1)
	ui.globalVolSlider.Size = UDim2.new(v, 0, 1, 0)
	ui.globalVolLabel.Text  = "Global " .. math.floor(v * 100) .. "%"
	paintMode(data.mode == "global" and "global" or "stage")
	if data.autoplay ~= nil then autoOn = data.autoplay == true; paintAuto() end -- [FIX A1]
end

H.LiveState = function(data) -- [FIX L1]
	if type(data) ~= "table" then return end
	local was = liveOn
	liveOn = data.active == true
	S.liveOn = liveOn -- [FIX L1b]
	S.liveDj = data.dj -- [FIX M6]
	S.liveDjId = data.djId -- [FIX M6b]
	paintLive()
	if liveOn ~= was then notify(liveOn and ("LIVE - DJ " .. tostring(data.dj)) or "Live ended") end
	local wasF = S.liveFollow -- [FIX L2] server ini ikut siaran server lain
	S.liveFollow = data.following == true
	if S.liveFollow ~= (wasF == true) then
		notify(S.liveFollow and ("LIVE from another server - DJ " .. tostring(data.dj)) or "Live ended")
	end
	updateSectionVis() -- [FIX M6] setelah liveOn/liveFollow/liveDj terisi
end
H.LoudnessSync = function(data)
	if not data then return end
	Audio.syncLoudness(data)
	if not S.isAdmin then return end
	if data.compMakeupGain ~= nil then ui.makeupInput.Text = tostring(data.compMakeupGain) end
	if data.eqLow  ~= nil then ui.eqLowInput.Text  = tostring(data.eqLow)  end
	if data.eqMid  ~= nil then ui.eqMidInput.Text  = tostring(data.eqMid)  end
	if data.eqHigh ~= nil then ui.eqHighInput.Text = tostring(data.eqHigh) end
	if data.enabled ~= nil then
		loudOn = data.enabled
		paintLoud()
	end
end

-- Handler yang isinya cuma notifikasi.
for _, def in ipairs({
	{ "SkipError",          P.danger, fallback = "Cannot skip" },
	{ "QueueError",         P.danger, fallback = "Cannot queue" },
	{ "SettingsError",      P.danger, fallback = "Cannot save" },
	{ "SongAutoRemoved",    P.danger, fallback = "Song marked unavailable" },
	{ "SongRemoved",        P.accent, prefix   = "Removed: " },
	{ "QueueRemoved",       P.accent, fallback = "Removed from queue" },
	{ "AdminSkipped",       P.accent, suffix   = " force-skipped", fallback = "Admin" },
	{ "QueueRemoveSuccess", P.accent, fallback = "Removed" },
	}) do
	local action, color = def[1], def[2]
	H[action] = function(data)
		UI.notify((def.prefix or "") .. tostring(data or def.fallback or "?") .. (def.suffix or ""), color, 2)
	end
end

remote.OnClientEvent:Connect(function(action, data)
	local handler = H[action]
	if not handler then return end
	local okh, err = pcall(handler, data)
	if not okh then warn("[MusicClient] handler '" .. tostring(action) .. "':", err) end
end)

-- ══ INJECT + CLEANUP ══════════════════════════════════════════════════════
local okInject, errInject = pcall(_G.InjectMusicUI, ui.container)
if not okInject then warn("[MusicClient] inject error:", errInject) return end

_G.MusicClientUI = ui.container
updateSectionVis()

task.wait(0.2)
remote:FireServer("RequestState")
remote:FireServer("RequestMyLibrary")

-- Jaring pengaman kalau paket pertama hilang; berhenti begitu data masuk.
task.spawn(function()
	for _, delay in ipairs({ 3, 8, 20 }) do
		task.wait(delay)
		if not alive or S.libVer ~= nil then return end -- [FIX R2] berhenti begitu daftar lengkap diterima (library kosong juga)
		remote:FireServer("RequestState")
		remote:FireServer("RequestMyLibrary") -- [FIX R2] requestState tidak lagi membawa My Library
	end
end)

Players.PlayerRemoving:Connect(function(p)
	if p ~= player then return end
	alive = false
	if volTimer then task.cancel(volTimer) volTimer = nil end
	if filterTimer then task.cancel(filterTimer) filterTimer = nil end
	stopProg()
	UI.stopAllMarquees()
	Lists.reset()
	UI.resetNotify()
	UI.cancelTweens()
	UI.disconnect()
	Audio.cleanup()
	if _G.MusicClientUI then pcall(function() _G.MusicClientUI:Destroy() end) end
	_G.MusicClient, _G.MusicClientUI = nil, nil
end)