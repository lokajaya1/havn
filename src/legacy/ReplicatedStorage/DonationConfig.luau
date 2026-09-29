-- ReplicatedStorage.DonationConfig — satu sumber setelan donasi Robux (server & client).
-- ID produk = Developer Product experience [NEW] (dibuat 2026-09-28). Harga dibaca Roblox; `robux` di sini
-- hanya cadangan kalau struk tidak membawa CurrencySpent.
-- label = nama tier di kartu panel; gap = detik jeda antrean pengumuman sebelum donasi berikutnya ditampilkan;
-- notif = detik notifikasi tampil di layar pemain; fx = efek partikel di donatur (DonationConfig.effects);
-- big = efek besar di titik tetap map (remote DonationRemotes.<big>, didengar StarterGui.DonationBigFX di Studio).
-- cam = kamera sinematik ke donatur (opsional, salah satu cinematic.modes; bawaan: tidak ada = OFF, keputusan user
-- 2026-09-29 — dinyalakan per tier lewat Admin panel).
local DonationConfig = {}

DonationConfig.tiers = {
	{ robux = 10, label = "Spark", productId = 3715195411, gap = 3, notif = 6, fx = "Level1" },
	{ robux = 50, label = "Glow", productId = 3715195435, gap = 3, notif = 6, fx = "Level2" },
	{ robux = 100, label = "Shine", productId = 3715195462, gap = 4, notif = 7, fx = "Level3" },
	{ robux = 200, label = "Blaze", productId = 3715195489, gap = 4, notif = 7, fx = "Level4" },
	{ robux = 500, label = "Aura", productId = 3715195530, gap = 5, notif = 8, fx = "Level5" },
	{ robux = 1000, label = "Nuke", productId = 3715195558, gap = 8, notif = 10, big = "FireNuke" },
	{ robux = 2000, label = "Supernova", productId = 3715195590, gap = 6, notif = 10, fx = "Level6" },
	{ robux = 3000, label = "Exotic", productId = 3715195610, gap = 8, notif = 12, fx = "Exotic" },
	{ robux = 5000, label = "Hammer", productId = 3715195634, gap = 10, notif = 14, big = "FireSmite" },
	{ robux = 10000, label = "Black Hole", productId = 3715195650, gap = 12, notif = 16, big = "FireBlackHole" },
}

-- Pesan donatur: diketik SEBELUM membeli, difilter server (PublicChat), dipakai sekali untuk struk berikutnya.
DonationConfig.message = {
	maxChars = 100, -- dipotong per karakter UTF-8
	maxBytes = 1000, -- kiriman lebih panjang dari ini ditolak tanpa difilter
	ttl = 300, -- detik pesan menunggu struk
	cooldown = 2, -- detik antar kiriman per pemain
}

-- Nama store TIDAK boleh diubah (data 364 donatur hasil migrasi). Di Studio memakai akhiran _studio.
DonationConfig.store = {
	data = "DonationData_v1", -- <uid> → { total, r = { purchaseId terakhir } }
	ordered = "PlayerDonations_v1", -- <uid> → total (cermin untuk papan)
	studioSuffix = "_studio",
	studioReadsLive = true, -- Studio: papan & baris You MEMBACA data live (tanpa menulis); beli uji tetap ke _studio
	recent = 50, -- jumlah purchaseId terakhir yang diingat per pemain (anti dobel)
	retry = { 5, 20, 60 }, -- detik coba ulang tulis ordered
}

DonationConfig.queueMax = 50 -- antrean pengumuman maksimal per server
DonationConfig.bigRecipient = "HAVN" -- teks "TO @…" di efek besar

-- Donasi tampil di SEMUA server (MessagingService). Server lain: notifikasi, papan LIST/LIVE/TOP, efek besar.
-- Partikel & LiveScreen hanya di server donatur (butuh karakternya).
DonationConfig.global = {
	enabled = true,
	topic = "DonationGlobal", -- Studio: + store.studioSuffix (beli uji tidak tampil di server live)
	minRobux = 10, -- donasi di bawah ini hanya tampil di server asal
	retry = { 2, 5 }, -- detik coba ulang PublishAsync
	resubscribe = { 5, 15, 30, 60 }, -- detik coba ulang SubscribeAsync (angka terakhir berulang)
	recent = 50, -- purchaseId terakhir yang diingat (pesan kembar dibuang)
}

-- Donasi luar dari bagibagi.co (jembatan Google Apps Script: tools/bagibagi-bridge/Code.gs).
-- Satu server (lease MemoryStore) menarik donasi baru tiap `poll` detik lalu menyiarkannya ke semua server.
-- Nominal ditampilkan sebagai poin GOLD (keputusan user 2026-09-29, risiko moderasi diterima): Rupiah diubah di server
-- (rpPerGold), tanpa "Rp", tanpa nama situs/tautan; client & server lain hanya menerima Gold.
-- Nominal juga memilih tier efek (t = harga tier Robux di atas, nil = notifikasi saja).
-- Kunci baca = Roblox Secret `secret` (Creator Hub → Secrets, domain script.google.com; Studio: Local Secrets).
DonationConfig.bagibagi = {
	enabled = true,
	url = "https://script.google.com/macros/s/AKfycbxVX0QKP-6opQs3sy8jkmSEO6Jh-Wwz4GjEu_ZhvQatNLoqKsTbpSaSqZ8T4-4gB7xUGA/exec",
	secret = "bagibagi_read",
	poll = 10, -- detik antar tarikan (server pemimpin)
	lease = 30, -- detik masa pemimpin tanpa diperbarui (server mati → server lain mengambil alih)
	store = "DonationBagibagi_v1", -- DataStore { cursor, ids } (+ _studio di Studio)
	memory = "DonationBagibagi", -- MemoryStore SortedMap pemimpin (+ _studio di Studio)
	keepIds = 100, -- ID donasi terakhir yang diingat (anti dobel)
	gap = 3, -- jeda antrean untuk donasi tanpa efek
	rpPerGold = 1000, -- 1 GOLD = Rp1.000 (angka yang tampil bukan Rupiah)
	summaryEvery = 60, -- detik antar ambil peringkat Gold (?mode=summary, jembatan v3; juga segera setelah donasi baru)
	summaryTtl = 600, -- detik peringkat Gold bertahan di MemoryStore tanpa diperbarui
	tiers = { -- rp minimal → t (tier Robux yang efeknya dipakai)
		{ rp = 10000, t = 10 }, -- Level1
		{ rp = 25000, t = 50 }, -- Level2
		{ rp = 50000, t = 100 }, -- Level3
		{ rp = 100000, t = 500 }, -- Level5
		{ rp = 250000, t = 2000 }, -- Level6
		{ rp = 500000, t = 1000 }, -- Nuke
		{ rp = 1000000, t = 10000 }, -- Black Hole
	},
}

-- Papan LIVE DONATIONS = donasi HARI INI (WIB) lintas server & tahan restart (DonationServer/Feed): MemoryStore
-- `<memory>_<robux|gold>_<YYYYMMDD>` (+ _studio), ditulis server asal, dibaca tiap boards.every detik.
DonationConfig.feed = {
	enabled = true,
	memory = "DonationFeed",
	utcOffset = 7, -- jam; "hari ini" = tanggal WIB (reset 00:00 WIB)
	ttl = 172800, -- detik entri bertahan (48 jam)
	fetch = 40, -- entri terbaru yang dibaca per jenis
}

-- Murni: tanggal "YYYYMMDD" waktu `t` (detik UTC) di zona feed.utcOffset. (Roblox os.date hanya "*t"/"!*t".)
function DonationConfig.dayKey(t)
	local d = os.date("!*t", math.floor(t + DonationConfig.feed.utcOffset * 3600))
	return ("%04d%02d%02d"):format(d.year, d.month, d.day)
end

-- Menu tombol donasi di topbar: "Robux" (panel DONATE) & "💰" (popup komunitas). Keputusan user 08:28: popup TANPA kata
-- donasi/emas/"ungu" dan TANPA link (URL di dalam game dilarang) → arahkan ke Social Links resmi di halaman game.
DonationConfig.community = {
	groupId = 277580244, -- grup HAVN (sama dengan RankConfig.GROUP_ID)
	menuLabel = "Komunitas",
	title = "Komunitas HAVN",
	body = "Link resmi komunitas HAVN ada di halaman game ini, bagian Social Links (di bawah tombol Play).",
}

-- Tes donasi admin (panel donasi → tombol TES): rank grup >= RankConfig.ADMIN_MIN_RANK.
-- Tanpa Marketplace & tanpa menulis data; papan LIST/LIVE tidak diisi; pesan diberi awalan agar tidak dikira asli.
DonationConfig.test = {
	cooldown = 3, -- detik antar tes per pemain (juga membatasi non-admin yang men-spam remote)
	prefix = "[TES]",
}

-- Papan di map desain v1.5 (Workspace.DonationBoards, dipasang di Studio; posisi bebas digeser, NAMA jangan diubah).
-- Dua set: Robux dan Gold (donasi bagibagi, nominal tidak ditampilkan; peringkat dari jembatan v3 per nama,
-- patung memakai avatar akun Roblox yang namanya sama). Nama di bawah = nama model di folder itu.
DonationConfig.boards = {
	every = 60, -- detik baca ulang peringkat (juga atribut RefreshRate papan TOP untuk timer)
	soon = 5, -- detik tunda baca ulang setelah donasi
	topCount = 50, -- peringkat yang dibaca dari PlayerDonations_v1
	showCount = 10, -- tampil di TOP DONATION: podium #1–#3 + baris #4–#10
	feedCount = 10, -- kartu di LIVE DONATIONS
	danceAnims = { 507771019, 507772104, 507776043 }, -- emote dance resmi Roblox untuk patung #1–#3
	overhead = "OverheadTemplate", -- BillboardGui papan nama patung
	robux = {
		top = "TopBoard",
		feed = "FeedBoard",
		live = "LiveBoard",
		rigs = "TopMannequins", -- Top1–Top3 + Decoration
		rank = "Robux", -- papan nama patung "#1 Robux"
		feedScope = "T O D A Y   ·   L I V E", -- label LIVE DONATIONS (donasi hari ini WIB, DonationServer/Feed)
		accent = Color3.fromRGB(255, 157, 0),
	},
	cash = {
		top = "CashTopBoard",
		feed = "CashFeedBoard",
		live = "CashLiveBoard",
		rigs = "CashMannequins",
		rank = "Gold",
		label = "GOLD", -- teks di bawah judul papan (file: CASH) + satuan nominal ("100.000 GOLD")
		feedScope = "T O D A Y   ·   L I V E",
		soon = 20, -- detik tunda baca ulang peringkat Gold setelah donasi (pemimpin perlu mengambilnya dulu)
		accent = Color3.fromRGB(139, 255, 42),
	},
}

-- Efek partikel (template di ReplicatedStorage.DonationEffects = assets/DonationEffects.rbxm).
-- time = detik emitter menyala; sound = audio Group SOLA's (izin [NEW] terbukti AU0 2026-09-29), diputar 3D di donatur.
-- Exotic = Model utuh di kaki donatur (atribut WholeAtBase).
DonationConfig.effects = {
	Level1 = { time = 3, sound = 104845267087700 },
	Level2 = { time = 3.5, sound = 135305758310152 },
	Level3 = { time = 4, sound = 120395434013332 },
	Level4 = { time = 5, sound = 71849034801132 },
	Level5 = { time = 8, sound = 116929164684637 },
	Level6 = { time = 10, sound = 99477588070937 },
	Exotic = { time = 10, sound = 99477588070937 },
}
DonationConfig.fx = {
	maxActive = 3, -- efek bersamaan per pemain (lebih dari ini dilewati)
	volume = 0.5,
	hearDistance = 10000, -- RollOffMaxDistance suara efek
	fadeOut = 1, -- detik suara dipudar setelah efek selesai
	cleanup = 3, -- detik sisa partikel memudar sebelum dihapus
}

-- Kamera sinematik (tier dengan `cam`, atau pilihan admin di Test Effect): letterbox + vignette, kamera mengikuti
-- donatur dari depan lalu kembali. Server mengirim mode di DonationRemotes.Effect(userId, robux, cam).
-- Dilewati kalau Effects OFF, kamera pemain sedang Scriptable (FreeCam/360/LiveScreen), atau donatur tidak di server.
DonationConfig.cinematic = {
	hold = 6, -- detik kamera bergerak
	back = 0.8, -- detik kembali ke kamera pemain
	fade = 0.6, -- detik letterbox/vignette masuk-keluar
	bars = 0.12, -- tinggi letterbox (bagian layar)
	vignette = 0.35, -- transparansi vignette saat tampil (kecil = gelap)
	modes = { "Hero", "Push", "Arc", "Crane", "Orbit" }, -- src/client/DonationCinematic
}

-- Urutan partikel di Admin panel (kunci DonationConfig.effects) & efek besar (nama remote → label).
DonationConfig.effectOrder = { "Level1", "Level2", "Level3", "Level4", "Level5", "Level6", "Exotic" }
DonationConfig.bigList = {
	{ name = "FireNuke", label = "Nuke" },
	{ name = "FireSmite", label = "Hammer" },
	{ name = "FireBlackHole", label = "Black Hole" },
}

-- Setelan per Developer Product yang diubah admin di Admin panel (tab Produk): nama, partikel, kamera, efek besar,
-- tampil/sembunyi, tambah produk baru (dibuat di Creator Hub → tempel ID; harga dibaca dari Roblox).
-- Disimpan di DataStore `store` (+ _studio di Studio), disiarkan ke server lain lewat `topic`. Tier bawaan di atas =
-- cadangan kalau store kosong / gagal dibaca. Hanya rank grup >= `rank` (keputusan user 2026-09-29).
DonationConfig.tierEdit = {
	rank = 254,
	store = "DonationSettings_v1",
	key = "tiers",
	topic = "DonationSettings",
	maxTiers = 20,
	labelChars = 20,
	saveDelay = 2, -- detik jeda sebelum menyimpan (klik beruntun = satu tulisan)
	cooldown = 0.25, -- detik antar perubahan per admin
}

-- Daftar efek untuk tab Test Effect: partikel & efek besar { name, label }.
function DonationConfig.effectList()
	local fx = {}
	for _, name in DonationConfig.effectOrder do
		if DonationConfig.effects[name] then
			table.insert(fx, { name = name, label = name })
		end
	end
	return fx, DonationConfig.bigList
end

function DonationConfig.isBig(name)
	for _, b in DonationConfig.bigList do
		if b.name == name then
			return true
		end
	end
	return false
end

function DonationConfig.isCamMode(cam)
	for _, m in DonationConfig.cinematic.modes do
		if m == cam then
			return true
		end
	end
	return false
end

-- Salinan tier bawaan (sebelum diubah admin) — dasar penggabungan setelan tersimpan.
DonationConfig.defaultTiers = {}
for _, tier in DonationConfig.tiers do
	table.insert(DonationConfig.defaultTiers, table.clone(tier))
end

local byProduct = {}
for _, tier in DonationConfig.tiers do
	byProduct[tier.productId] = tier
end

-- Ganti isi DonationConfig.tiers (tabel yang sama, jadi semua pemakai ikut) dengan daftar baru, urut harga.
-- Dipakai server (setelan admin) & client (atribut DonationRemotes.Tiers).
function DonationConfig.applyTiers(list)
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		if a.robux ~= b.robux then
			return a.robux < b.robux
		end
		return a.productId < b.productId
	end)
	table.clear(DonationConfig.tiers)
	table.clear(byProduct)
	for _, tier in sorted do
		table.insert(DonationConfig.tiers, tier)
		byProduct[tier.productId] = tier
	end
end

function DonationConfig.tierForProduct(productId)
	return byProduct[productId]
end

-- Tier untuk harga `robux` (bagibagi.tiers t / tier dari server lain): harga sekarang, atau produk bawaan yang di
-- Config berharga itu (harga di Creator Hub boleh berubah tanpa memutus pemetaan bagibagi).
function DonationConfig.tierForPrice(robux)
	local found
	for _, tier in DonationConfig.tiers do
		if tier.robux == robux then
			found = tier
		end
	end
	if found then
		return found
	end
	for _, d in DonationConfig.defaultTiers do
		if d.robux == robux then
			return byProduct[d.productId]
		end
	end
	return nil
end

-- Tier tertinggi yang harganya <= robux (CurrencySpent bisa beda dari harga tier).
function DonationConfig.tierForRobux(robux)
	local best
	for _, tier in DonationConfig.tiers do
		if robux >= tier.robux then
			best = tier
		end
	end
	return best
end

return DonationConfig
