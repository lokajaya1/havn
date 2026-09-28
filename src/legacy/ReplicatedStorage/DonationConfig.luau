-- ReplicatedStorage.DonationConfig — satu sumber setelan donasi Robux (server & client).
-- ID produk = Developer Product experience [NEW] (dibuat 2026-09-28). Harga dibaca Roblox; `robux` di sini
-- hanya cadangan kalau struk tidak membawa CurrencySpent.
-- label = nama tier di kartu panel; gap = detik jeda antrean pengumuman sebelum donasi berikutnya ditampilkan.
local DonationConfig = {}

DonationConfig.tiers = {
	{ robux = 10, label = "Spark", productId = 3715195411, gap = 3 },
	{ robux = 50, label = "Glow", productId = 3715195435, gap = 3 },
	{ robux = 100, label = "Shine", productId = 3715195462, gap = 4 },
	{ robux = 200, label = "Blaze", productId = 3715195489, gap = 4 },
	{ robux = 500, label = "Aura", productId = 3715195530, gap = 5 },
	{ robux = 1000, label = "Nuke", productId = 3715195558, gap = 8 },
	{ robux = 2000, label = "Supernova", productId = 3715195590, gap = 6 },
	{ robux = 3000, label = "Exotic", productId = 3715195610, gap = 8 },
	{ robux = 5000, label = "Hammer", productId = 3715195634, gap = 10 },
	{ robux = 10000, label = "Black Hole", productId = 3715195650, gap = 12 },
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

local byProduct = {}
for _, tier in DonationConfig.tiers do
	byProduct[tier.productId] = tier
end

function DonationConfig.tierForProduct(productId)
	return byProduct[productId]
end

return DonationConfig
