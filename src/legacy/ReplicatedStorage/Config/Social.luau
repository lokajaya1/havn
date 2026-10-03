--!strict
-- ReplicatedStorage/Config/Social (ModuleScript) — angka ruangan SOCIAL (claude/Rencana_Social.md).
-- Data murni (tanpa GetService/Instance/yield). Aturannya ada di ReplicatedStorage.Modules.SocialRules;
-- batas terima remote memakai ToolRules.bucket/take (token bucket per pemain, sama dengan ruangan TOOLS).
-- Dibaca: Communityinfoservice + CustomUIModules/Communityinfo (komunitas di kartu pemain),
-- CarrySystemHandler + CustomUIModules/CarryManager (permintaan carry), CustomUIModules/PrivateChatManager,
-- CustomUIModules/HideAvatarManager, Sign (SignText, SignUI), CommandServer + CommandPanel (/nametag),
-- DonationServer + DonationClient (pesan donatur), tes.
--
-- Istilah:
--   batas terima = token bucket: RATE permintaan/dtk rata-rata, boleh beruntun sampai BURST. Di atas batas DIBUANG
--                  (atau dijawab "coba lagi"); pemain biasa tidak pernah sampai sini.

local Config = {}

-- ── Komunitas (ikon grup jadi background kartu pemain) ────────────────────────────────────────────────────────────
Config.COMMUNITY = {
	RATE = 1, -- GetPrimaryCommunity: permintaan/dtk per pemain (dulu: 1 per 0,4 dtk, tanpa beruntun)
	BURST = 6, -- boleh beruntun (buka beberapa kartu cepat); hasil dari cache tidak memakai kuota
	CACHE_TTL = 600, -- dtk, hasil GroupService yang berhasil (sama dengan kode lama)
	FAIL_TTL = 30, -- dtk, GroupService error → dicoba lagi sesudah ini (dulu ikut 600)
	CLEAN_EVERY = 300, -- dtk, sapu cache kedaluwarsa (sama dengan kode lama)
	PREF_RATE = 1, -- GetCommunityPref per pemain (client normal memanggil 1× saat join)
	PREF_BURST = 3,
	PREF_SET_RATE = 4, -- SetCommunityPref per pemain (sakelar di panel Players)
	PREF_SET_BURST = 8,
	CLIENT_TTL = 300, -- dtk, cache client (sama dengan kode lama)
	CLIENT_RETRY = { 2, 5 }, -- dtk, client menunggu lalu mencoba lagi kalau server menjawab "retry"
}

-- ── Carry (permintaan gendong antar pemain) ──────────────────────────────────────────────────────────────────────
Config.CARRY = {
	-- nilai lama (tidak berubah)
	ASK_COOLDOWN = 1, -- dtk antar AskCarry per peminta
	REQUEST_TIMEOUT = 17, -- dtk, server melepas permintaan yang tidak dijawab (= CLIENT_TIMEOUT + 2 jeda jaringan)
	CLIENT_TIMEOUT = 15, -- dtk, kartu permintaan di layar target
	MAX_DIST = 30, -- stud, jarak maksimal saat minta & saat menerima
	-- anti-spam ke pemain lain (baru). Bukan aturan Roblox — angka game ini, boleh diubah.
	PAIR_COOLDOWN = 10, -- dtk, peminta → target yang SAMA sesudah ditolak / kedaluwarsa / dibatalkan
	STRIKES = 3, -- penolakan ke target yang sama ...
	STRIKE_WINDOW = 60, -- ... dalam jendela ini (dtk) ...
	PAIR_BLOCK = 30, -- ... → jeda pasangan jadi ini (dtk)
	TARGET_GAP = 3, -- dtk, target menerima paling banyak 1 permintaan baru per jeda (dari siapa pun)
	PRUNE_EVERY = 60, -- dtk, buang catatan jeda yang sudah lewat
	RECEIVE = { RATE = 2, BURST = 6 }, -- event CarryRemote per pemain
}

-- ── Private chat (whisper TextChatService bawaan) ────────────────────────────────────────────────────────────────
Config.WHISPER = {
	WAIT = 5, -- dtk menunggu channel whisper muncul sesudah perintah "/w @username" (kode lama: 5)
}

-- ── Hide avatar (lokal, hanya di layar pemain yang menyembunyikan) ──────────────────────────────────────────────
-- Cara per kelas (dicek berurutan dengan IsA):
--   LTM     → LocalTransparencyModifier = 1 (khusus client ini, tidak ditimpa Transparency dari server)
--   ENABLED → Enabled = false (kelas yang tidak pernah dinyalakan-matikan server; nilai asli dipulihkan saat Show)
--   DETACH  → dilepas sementara dari karakter (Parent = nil lokal) lalu dikembalikan saat Show. Untuk efek yang
--             dinyalakan-matikan server (WaterGun, Money Gun, Broom): status Enabled dari server tetap benar saat Show.
Config.HIDE = {
	LTM = { "BasePart", "Decal" }, -- Decal mencakup Texture
	ENABLED = { "BillboardGui", "SurfaceGui" },
	DETACH = { "ParticleEmitter", "Beam", "Trail", "Fire", "Smoke", "Sparkles", "Light", "Highlight" },
}

-- ── Teks pemain yang dilihat pemain lain (Sign, /nametag, pesan donasi) ─────────────────────────────────────────
-- ATURAN RESMI ROBLOX (creator-docs chat/guidelines.md, wajib sejak 3 Jun 2026): teks yang bisa diedit pemain dan
-- dilihat pemain lain dibatasi paling sering 1× per menit per pemain. COOLDOWN jangan diturunkan di bawah 60.
-- Waktu terakhir disimpan di atribut Player (waktu server, workspace:GetServerTimeNow()) → tahan respawn & ganti
-- tool, client bisa menampilkan hitung mundur. Keluar-masuk server me-reset (sama dengan contoh resmi Roblox).
Config.PUBLIC_TEXT = {
	COOLDOWN = 60,
	ATTR = {
		SIGN = "PublicTextSign",
		NAMETAG = "PublicTextNametag",
		DONATION = "PublicTextDonation",
	},
}

return Config
