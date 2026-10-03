-- DanceHandler/Config — setelan DanceHandler (dipakai semua modulnya).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DanceShared = require(ReplicatedStorage.Modules.DanceShared)

local CONFIG = {
	DANCE_WALKSPEED   = DanceShared.WALKSPEED.dance,
	DEFAULT_WALKSPEED = DanceShared.WALKSPEED.default,

	FADE_IN          = 0.12,
	FADE_OUT         = 0.18,
	STOP_FADE        = 0.22,
	REASSERT_FADE    = 0.1,
	SPEED_TRANSITION = 0.12,

	LOAD_TIMEOUT = 0.6,  -- batas tunggu asset dingin sebelum tetap diputar
	BROKEN_CHECK = 10,   -- baru dianggap rusak kalau selama ini tetap tidak termuat

	MIN_SPEED = 0.5,
	MAX_SPEED = 2.0,

	MAX_TRACKS       = 48,   -- jauh di bawah batas 256 track per Animator
	REQUEST_COOLDOWN = 0.05, -- jeda antar permintaan yang DIJALANKAN (yang datang lebih cepat menunggu, tidak dibuang)

	-- Kuota GANTI dance (tiap dance baru = LoadAnimation di server + semua
	-- client mengunduh animasinya). Ubah speed dance yang sama tidak dihitung.
	-- Kuota habis → permintaan TERAKHIR menunggu token berikutnya (init: runPending).
	SWITCH_BURST  = 6,
	SWITCH_REFILL = 3,       -- token per detik

	-- Kuota remote favorit: "load" menjawab dari memori, tambah/hapus
	-- mengirim ulang seluruh daftar.
	FAV_LOAD_GAP   = 2,
	FAV_EDIT_BURST = 10,
	FAV_EDIT_REFILL = 5,

	WARMUP_DELAY        = 0.4,
	SERVER_WARMUP_DELAY = 2,
	-- Sesudah POPULAR_DANCES, semua dance lain dipanaskan bertahap di server:
	-- SERVER_WARMUP_CHUNK nama tiap SERVER_WARMUP_STEP dtk (±50 dtk untuk ±190 dance).
	SERVER_WARMUP_REST_DELAY = 8,
	SERVER_WARMUP_CHUNK      = 4,
	SERVER_WARMUP_STEP       = 1,
	-- Nama harus sama persis dengan key di DanceAssets.dances (case-sensitive).
	-- Nama yang salah akan di-warn saat warm-up, tidak diam-diam dilewati.
	POPULAR_DANCES = {
		"Fresh", "Floss", "Gangnam Style", "Electro Shuffle",
		"Get Griddy", "Sturdy", "Breakdance", "Macarena",
		"Salsa", "Party", "Hip Hop Dancing", "Boogie Down",
	},

	-- Watchdog: jaga dance tetap hidup selama di-carry, lalu verifikasi
	-- sebentar setelah drop (Stop dari cleanup bisa pakai fade & telat).
	CARRY_INTERVAL = 0.15,
	DROP_INTERVAL  = 0.1,
	DROP_STEPS     = 10,

	FAVORITES_LIMIT   = 250,
	AUTOSAVE_INTERVAL = 60,
	DATASTORE_NAME    = "DanceFavorites",

	-- DataStore bisa gagal sementara (InternalServerError, throttle): tiap
	-- panggilan diulang, dan load yang gagal total dicoba lagi di latar.
	DS_TRIES       = 3,
	DS_RETRY_DELAY = 1,                  -- detik × nomor percobaan
	RELOAD_DELAYS  = { 5, 15, 30, 60 },  -- lalu tetap tiap 60 dtk
	CLOSE_WAIT     = 25,                 -- batas tunggu tulisan saat server tutup
}

return CONFIG
