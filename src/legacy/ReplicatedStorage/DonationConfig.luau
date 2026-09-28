-- ReplicatedStorage.DonationConfig — satu sumber setelan donasi Robux (server & client).
-- ID produk = Developer Product experience [NEW] (dibuat 2026-09-28). Harga dibaca Roblox; `robux` di sini
-- hanya cadangan kalau struk tidak membawa CurrencySpent.
-- label = nama tier di kartu panel; gap = detik jeda antrean pengumuman sebelum donasi berikutnya ditampilkan;
-- notif = detik notifikasi tampil di layar pemain; fx = efek partikel di donatur (DonationConfig.effects);
-- big = efek besar di titik tetap map (remote DonationRemotes.<big>, didengar StarterGui.DonationBigFX di Studio).
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

-- Papan di map (Workspace.DonationBoards: TopBoard, FeedBoard, LiveBoard, TopMannequins/Top1–3; diatur di Studio).
DonationConfig.boards = {
	every = 60, -- detik baca ulang peringkat
	soon = 5, -- detik tunda baca ulang setelah donasi
	topCount = 50, -- baris di TOP DONATORS
	feedCount = 10, -- baris di LIST DONATIONS
	danceAnims = { 507771019, 507772104, 507776043 }, -- emote dance resmi Roblox untuk manekin #1–#3
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

local byProduct = {}
for _, tier in DonationConfig.tiers do
	byProduct[tier.productId] = tier
end

function DonationConfig.tierForProduct(productId)
	return byProduct[productId]
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
