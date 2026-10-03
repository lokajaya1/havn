--!strict
-- ReplicatedStorage/Modules/DjStageRules (ModuleScript) — aturan MURNI panggung DJ (ruangan WORLD, claude/Rencana_World.md).
-- Tanpa GetService / Instance / yield. Dipakai server DjStage (validasi pilihan admin), client DjStageClient
-- (menggambar layar) dan panel DjStageAdmin (tab Live Screen & Media). Config = ReplicatedStorage.Config.DjStage.

local Rules = {}

-- ── jalur & layar (sama dengan skrip layar lama) ────────────────────────────────────────────────────────────────────

-- Pisahkan segmen jalur: "Interact*" → ("Interact", true) = semua anak bernama itu; "Animate" → ("Animate", false).
function Rules.segment(seg: string): (string, boolean)
	if string.sub(seg, -1) == "*" then
		return string.sub(seg, 1, -2), true
	end
	return seg, false
end

-- Layar samping AKTIF kalau attribute "On" bernilai true, DAN (kalau ScreenMode dipakai & ketemu) nilai ScreenMode sama
-- dengan mode aktif ("Gambar"). ScreenMode tidak ketemu → hanya attribute "On" yang menentukan.
function Rules.isActive(on: any, useScreenMode: boolean, hasScreenMode: boolean, mode: string?, activeMode: string): boolean
	if on ~= true then
		return false
	end
	if useScreenMode and hasScreenMode then
		return mode == activeMode
	end
	return true
end

-- Ukuran & posisi media (skala X) sesuai mirror: lebar NEGATIF membalik gambar, lalu posisi digeser 1 supaya tetap pas
-- menutupi layar. Hasil: sizeX, posX (Y selalu 1 & 0).
function Rules.mediaLayout(mirror: boolean): (number, number)
	if mirror then
		return -1, 1
	end
	return 1, 0
end

-- ── media per layar (Config.LAYAR_UTAMA / LAYAR_SAMPING) ─────────────────────────────────────────────────────

local function isAsset(v: any): boolean -- "rbxassetid://<angka > 0>" ("rbxassetid://0" = belum diisi)
	return type(v) == "string" and string.match(v, "^rbxassetid://[1-9]%d*$") ~= nil
end
local function isPositive(v: any): boolean
	return type(v) == "number" and v > 0 and v == v and v ~= math.huge
end
local function isCount(v: any): boolean
	return isPositive(v) and math.floor(v) == v
end
Rules.isAsset = isAsset

-- Media siap pakai untuk layar `layar` dan jenis `mediaType` ("IMAGE" | "GIF" | "VIDEO"), atau nil + alasan kalau
-- jenis itu belum diisi / salah tulis. Hasil: { id = mediaType, kind = "IMAGE"|"FRAMES"|"SPRITE"|"VIDEO", … }.
function Rules.mediaOf(layar: any, mediaType: any): (any, string?)
	if type(layar) ~= "table" then
		return nil, "layar"
	end
	if mediaType == "IMAGE" then
		if not isAsset(layar.IMAGE_ID) then
			return nil, "IMAGE_ID belum diisi"
		end
		return { id = "IMAGE", kind = "IMAGE", image = layar.IMAGE_ID }, nil
	elseif mediaType == "GIF" then
		if not isPositive(layar.FRAME_SPEED) then
			return nil, "FRAME_SPEED salah"
		end
		local sp = layar.GIF_SPRITE
		if sp ~= nil then
			local fs = type(sp) == "table" and sp.FRAME_SIZE
			local okSprite = type(sp) == "table" and isAsset(sp.IMAGE_ID) and type(fs) == "table" and isCount(fs[1])
				and isCount(fs[2]) and isCount(sp.COLUMNS) and isCount(sp.COUNT)
			if not okSprite then
				return nil, "GIF_SPRITE salah tulis"
			end
			return {
				id = "GIF",
				kind = "SPRITE",
				image = sp.IMAGE_ID,
				frameSize = { fs[1], fs[2] },
				columns = sp.COLUMNS,
				count = sp.COUNT,
				frameTime = layar.FRAME_SPEED,
			}, nil
		end
		local frames = layar.GIF_FRAMES
		if type(frames) ~= "table" or #frames == 0 then
			return nil, "GIF_FRAMES kosong"
		end
		for _, f in frames do
			if not isAsset(f) then
				return nil, "GIF_FRAMES berisi ID salah"
			end
		end
		return { id = "GIF", kind = "FRAMES", frames = frames, frameTime = layar.FRAME_SPEED }, nil
	elseif mediaType == "VIDEO" then
		if not isAsset(layar.VIDEO_ID) then
			return nil, "VIDEO_ID belum diisi"
		end
		local vol = layar.VIDEO_VOLUME
		if vol ~= nil and not (type(vol) == "number" and vol >= 0 and vol <= 1) then
			return nil, "VIDEO_VOLUME harus 0..1"
		end
		return { id = "VIDEO", kind = "VIDEO", video = layar.VIDEO_ID, volume = vol or 0 }, nil
	end
	return nil, "MEDIA_TYPE harus IMAGE / GIF / VIDEO"
end

-- Jenis media yang sudah diisi untuk layar ini (urutan Config.MEDIA_TYPES).
function Rules.available(cfg: any, layar: any): { string }
	local out = {}
	for _, t in cfg.MEDIA_TYPES do
		if Rules.mediaOf(layar, t) then
			table.insert(out, t)
		end
	end
	return out
end

-- Jenis yang tampil saat server mulai: MEDIA_TYPE kalau sudah diisi, kalau tidak jenis pertama yang tersedia (nil =
-- layar ini tidak punya media sama sekali). Alasan dikembalikan untuk warn di Output.
function Rules.startType(cfg: any, layar: any): (string?, string?)
	local m, why = Rules.mediaOf(layar, layar.MEDIA_TYPE)
	if m then
		return m.id, nil
	end
	return Rules.available(cfg, layar)[1], why
end

-- ── permintaan admin (RemoteFunction DjStageRemotes.SetMedia(layarId, mediaType)) ──────────────────────────────
-- state = { admin = bool, last = dtk jam permintaan terakhir pemain ini (nil = belum), now = dtk jam sekarang,
--           current = { [layarId] = mediaType } }
-- → { ok, reason?, wait? }. reason: "cooldown" | "admin" | "invalid" | "empty" | "video" | "same" (ok = true, tak berubah).
-- Jeda dicek PALING DULU dan berlaku untuk semua pemain (server mencatat jam setiap permintaan, admin atau bukan).
function Rules.decide(cfg: any, state: any, layarId: any, mediaType: any): any
	if state.last ~= nil then
		local waitFor = cfg.COOLDOWN - (state.now - state.last)
		if waitFor > 0 then
			return { ok = false, reason = "cooldown", wait = math.ceil(waitFor) }
		end
	end
	if state.admin ~= true then
		return { ok = false, reason = "admin" }
	end
	local layar = type(layarId) == "string" and cfg.LAYAR[layarId] or nil
	if not layar or type(mediaType) ~= "string" or not table.find(cfg.MEDIA_TYPES, mediaType) then
		return { ok = false, reason = "invalid" }
	end
	if not Rules.mediaOf(layar, mediaType) then
		return { ok = false, reason = "empty" }
	end
	if state.current[layarId] == mediaType then
		return { ok = true, reason = "same" }
	end
	if mediaType == "VIDEO" then
		local others = 0
		for id in cfg.LAYAR do
			if id ~= layarId and state.current[id] == "VIDEO" then
				others += 1
			end
		end
		if others + 1 > cfg.VIDEO_LAYAR_MAX then
			return { ok = false, reason = "video" }
		end
	end
	return { ok = true }
end

-- ── client ──────────────────────────────────────────────────────────────────────────────────────────────────────

-- Frame ke-`index` (1 = kiri atas) sprite sheet: offset piksel x, y (dibaca kiri→kanan lalu baris berikutnya).
function Rules.spriteOffset(index: number, columns: number, frameW: number, frameH: number): (number, number)
	local i = index - 1
	return (i % columns) * frameW, math.floor(i / columns) * frameH
end

-- GIF / video boleh jalan? Lebih jauh dari maxDistance → berhenti (semua jenis). Video juga berhenti kalau layar tidak
-- terlihat kamera (dekode video paling berat). Gambar diam tidak memakai aturan ini.
function Rules.awake(kind: string, distance: number, maxDistance: number, visible: boolean): boolean
	if distance > maxDistance then
		return false
	end
	if kind == "VIDEO" then
		return visible
	end
	return true
end

-- ── panel admin "Layar panggung" (DjStageAdmin) ─────────────────────────────────────────────────────────────────
-- Tab Live Screen = panel Live Screen lama (StarterGui.LiveScreen) dengan perilaku yang sama: daftar urut nama tampilan,
-- cari, pilih langsung / ◀ ▶, Tampilkan, Stop. Pemain = { Name, DisplayName } (tabel biasa, bukan Instance).

-- Urut nama tampilan (huruf kecil), seperti panel lama.
function Rules.sortPlayers(list: { any }): { any }
	local out = table.clone(list)
	table.sort(out, function(a, b)
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	return out
end

-- Cocok dengan kotak cari? Kosong = semua; selain itu bagian dari nama tampilan (huruf kecil, teks biasa).
function Rules.matches(p: any, text: string): boolean
	if text == "" then
		return true
	end
	return string.find(string.lower(p.DisplayName), string.lower(text), 1, true) ~= nil
end

-- Pemain dari teks kotak cari: Name persis → DisplayName persis → bagian DisplayName (huruf kecil, urutan `list`).
function Rules.findPlayer(list: { any }, text: string): any
	if text == "" then
		return nil
	end
	local t = string.lower(text)
	for _, p in list do
		if string.lower(p.Name) == t then
			return p
		end
	end
	for _, p in list do
		if string.lower(p.DisplayName) == t then
			return p
		end
	end
	for _, p in list do
		if string.find(string.lower(p.DisplayName), t, 1, true) then
			return p
		end
	end
	return nil
end

-- ◀ ▶ di daftar yang terlihat (`names`): belum ada pilihan / pilihan tidak terlihat → yang pertama; berputar di ujung.
function Rules.navigate(names: { string }, selected: string, direction: string): string?
	local n = #names
	if n == 0 then
		return nil
	end
	local idx = if selected ~= "" then table.find(names, selected) else nil
	if not idx then
		return names[1]
	end
	if direction == "next" then
		return names[(idx % n) + 1]
	end
	return names[((idx - 2) % n) + 1]
end

-- Ukuran panel (piksel) di layar GUI vpW × guiH (guiH = tinggi di bawah topbar): lebar HP 92% / lainnya 32%
-- (300..400, selalu ≤ layar − 16), tinggi = isi (contentH, termasuk header & tab), maks 80% layar dan tidak menembus
-- hotbar (`bottom`) atau sisi atas (8 px). Panel ditaruh di tengah area antara sisi atas dan hotbar.
function Rules.panelSize(vpW: number, guiH: number, mobile: boolean, bottom: number, contentH: number): (number, number)
	local w = math.min(math.clamp(math.floor(vpW * (if mobile then 0.92 else 0.32)), 300, 400), vpW - 16)
	local maxH = math.max(guiH - bottom - 8, 120)
	local h = math.min(math.floor(contentH), math.clamp(math.floor(guiH * 0.8), 240, 600), maxH)
	return math.max(w, 0), math.max(h, 120)
end

return Rules
