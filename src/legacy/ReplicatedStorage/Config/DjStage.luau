--!strict
-- ReplicatedStorage/Config/DjStage (ModuleScript) — panggung DJ Workspace["DJ STAGE"] (ruangan WORLD, claude/Rencana_World.md).
-- Data murni (tanpa GetService/Instance/yield). Dibaca: ServerScriptService.DjStage (siapkan part + remote admin),
-- StarterPlayerScripts.DjStageClient (menggambar LED & layar di perangkat tiap pemain), StarterPlayerScripts.DjStageAdmin
-- (panel "Layar panggung": tab Live Screen + tab Media), tes.
--
-- ══ CARA GANTI ISI LAYAR ══════════════════════════════════════════════════════════════════════════════════════
--   1. Isi ID di LAYAR_UTAMA / LAYAR_SAMPING di bawah:
--        IMAGE_ID   = 1 gambar diam                      ("rbxassetid://0" = belum diisi)
--        GIF_FRAMES = daftar gambar yang bergantian (GIF) — tiap frame 1 tekstur, makin banyak makin berat di HP
--        VIDEO_ID   = video loop (upload 2.000 Robux/video, akun 13+ terverifikasi; "rbxassetid://0" = belum diisi)
--   2. MEDIA_TYPE = yang tampil saat server mulai: "IMAGE" (gambar) | "GIF" | "VIDEO".
--   3. Di game, admin bisa ganti tanpa publish: Menu › Settings › ADMIN › "Layar panggung" › tab Media (hanya jenis yang
--      ID-nya sudah diisi). Pilihan admin berlaku di server itu saja; server baru kembali ke MEDIA_TYPE di sini.
--   Batas Roblox: maks 2 video diputar bersamaan → VIDEO hanya boleh di SATU layar (layar samping = 2 layar = 2 video).
--   GIF ringan (opsional): GIF_SPRITE = 1 gambar berisi banyak frame (dibaca kiri→kanan lalu baris berikutnya); kalau
--   diisi, GIF_FRAMES diabaikan. Contoh:
--     GIF_SPRITE = { IMAGE_ID = "rbxassetid://…", FRAME_SIZE = { 256, 256 }, COLUMNS = 4, COUNT = 16 },
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

local Config = {}

Config.STAGE_NAME = "DJ STAGE"
Config.FIND_TIMEOUT = 10 -- detik menunggu Workspace["DJ STAGE"]

-- Jalur di dalam DJ STAGE. Segmen berakhiran "*" = SEMUA anak bernama itu (nama part kembar di Studio).
-- ── LED berkedip (dulu: Script di dalam tiap LED, while true … wait()) ─────────────────────────────────
Config.LED_GROUPS = {
	{
		name = "BaseLED",
		path = { "dj", "Interact*", "Animate", "BaseLED" },
		colors = { "Institutional white", "Really black" },
		interval = 0.5,
	},
	{
		name = "USBLed",
		path = { "dj", "BaseCDJ*", "DecorationButtons", "USBButtons", "USBLed" },
		colors = { "Really black", "Lime green" },
		interval = 0.8,
	},
}

-- 25 frame layar utama (dari skrip lama layar utama/EntranceScreenC — yang selama ini tampil).
local FRAMES_UTAMA = {
	"rbxassetid://84248986508963",   -- 0000
	"rbxassetid://101152582668997",  -- 0001
	"rbxassetid://100792631146306",  -- 0002
	"rbxassetid://84536337829093",   -- 0004
	"rbxassetid://88164573833435",   -- 0005
	"rbxassetid://122251300499294",  -- 0006
	"rbxassetid://79417757590002",   -- 0007
	"rbxassetid://94224511697715",   -- 0008
	"rbxassetid://133432222875159",  -- 0009
	"rbxassetid://132630180409871",  -- 0010
	"rbxassetid://83495591269985",   -- 0011
	"rbxassetid://75699828378240",   -- 0012
	"rbxassetid://118234096907791",  -- 0013
	"rbxassetid://121304085648351",  -- 0014
	"rbxassetid://94146454704084",   -- 0015
	"rbxassetid://102814273353650",  -- 0016
	"rbxassetid://101205776736298",  -- 0017
	"rbxassetid://83448127781194",   -- 0018
	"rbxassetid://101054547946464",  -- 0020
	"rbxassetid://96432631784492",   -- 0021
	"rbxassetid://114577546879254",  -- 0022
	"rbxassetid://104815770489246",  -- 0023
	"rbxassetid://126824009432399",  -- 0024
	"rbxassetid://75972414160892",   -- 0025
	"rbxassetid://98250413525748",   -- 0026
}

-- 75 frame layar samping (dari skrip lama layar samping; dulu dikomentari karena layar samping memakai gambar).
-- Cek di Studio dulu semua frame masih ada sebelum dipakai; 75 tekstur = berat di HP.
local FRAMES_SAMPING = {
	"rbxassetid://102056083179463",
	"rbxassetid://104474718440926",
	"rbxassetid://136205159112104",
	"rbxassetid://86837321377154",
	"rbxassetid://130687043803981",
	"rbxassetid://125935538790230",
	"rbxassetid://106859226931819",
	"rbxassetid://94125593465874",
	"rbxassetid://132159987057788",
	"rbxassetid://114232567626965",
	"rbxassetid://112994750498849",
	"rbxassetid://85190941281907",
	"rbxassetid://76878019498890",
	"rbxassetid://92772945766087",
	"rbxassetid://92089357693271",
	"rbxassetid://83199206302453",
	"rbxassetid://123837287175864",
	"rbxassetid://123320656757813",
	"rbxassetid://83970013622112",
	"rbxassetid://126254429361783",
	"rbxassetid://78903582333058",
	"rbxassetid://134656999525384",
	"rbxassetid://110691579943760",
	"rbxassetid://131556984249969",
	"rbxassetid://93631716649844",
	"rbxassetid://80186987958223",
	"rbxassetid://137552637070195",
	"rbxassetid://76186871951312",
	"rbxassetid://125095092545761",
	"rbxassetid://80088489972102",
	"rbxassetid://116073277006599",
	"rbxassetid://93995627998487",
	"rbxassetid://100253538758446",
	"rbxassetid://94153065156955",
	"rbxassetid://93490617417124",
	"rbxassetid://105093958297087",
	"rbxassetid://128000893144138",
	"rbxassetid://135335456372534",
	"rbxassetid://139683761524931",
	"rbxassetid://101262975231059",
	"rbxassetid://106435818352766",
	"rbxassetid://103933079243127",
	"rbxassetid://117029020900749",
	"rbxassetid://82537332263984",
	"rbxassetid://89205703617973",
	"rbxassetid://101666382765471",
	"rbxassetid://115958455509248",
	"rbxassetid://109643742163274",
	"rbxassetid://126605684200749",
	"rbxassetid://74300814868108",
	"rbxassetid://83619422276261",
	"rbxassetid://99570889977787",
	"rbxassetid://85218926818757",
	"rbxassetid://122197389613093",
	"rbxassetid://124578973770621",
	"rbxassetid://80095223263292",
	"rbxassetid://76592498463186",
	"rbxassetid://119936532636251",
	"rbxassetid://138841517889683",
	"rbxassetid://83619945870278",
	"rbxassetid://126958433728685",
	"rbxassetid://76678533523203",
	"rbxassetid://87260585013120",
	"rbxassetid://123648199491781",
	"rbxassetid://88546148486694",
	"rbxassetid://92714718328638",
	"rbxassetid://125170932746450",
	"rbxassetid://82902248014037",
	"rbxassetid://123042163415834",
	"rbxassetid://89151399668359",
	"rbxassetid://78904821056700",
	"rbxassetid://75330519115404",
	"rbxassetid://86450484040590",
	"rbxassetid://122267516763313",
	"rbxassetid://95547819241975",
}

-- ── LAYAR UTAMA (tengah, stage/EntranceScreenC) — selalu menyala ─────────────────────────────────────────
Config.LAYAR_UTAMA = {
	label = "Layar utama",
	path = { "stage", "EntranceScreenC" },
	MEDIA_TYPE = "GIF", -- yang tampil saat server mulai: "IMAGE" | "GIF" | "VIDEO"
	IMAGE_ID = "rbxassetid://0", -- [IMAGE] belum diisi
	GIF_FRAMES = FRAMES_UTAMA, -- [GIF]
	FRAME_SPEED = 0.05, -- [GIF] detik per frame
	VIDEO_ID = "rbxassetid://0", -- [VIDEO] belum diisi
	VIDEO_VOLUME = 0, -- [VIDEO] 0 = bisu, 1 = penuh
	HIDE_PART = true, -- Part transparan, hanya SurfaceGui yang terlihat
}

-- ── LAYAR SAMPING (kiri-kanan, tiap BasePart di stage/StageScreens) — menyala saat mode Gambar ────────────
Config.LAYAR_SAMPING = {
	label = "Layar samping",
	folder = { "stage", "StageScreens" },
	MEDIA_TYPE = "IMAGE", -- yang tampil saat server mulai: "IMAGE" | "GIF" | "VIDEO"
	IMAGE_ID = "rbxassetid://129949575767241", -- [IMAGE]
	GIF_FRAMES = FRAMES_SAMPING, -- [GIF]
	FRAME_SPEED = 0.05, -- [GIF] detik per frame
	VIDEO_ID = "rbxassetid://0", -- [VIDEO] belum diisi
	VIDEO_VOLUME = 0, -- [VIDEO] 0 = bisu, 1 = penuh
	START_ON = true, -- nilai attribute "On" di part kalau belum ada (saklar manual dari Studio)
	USE_SCREENMODE = true, -- menyala hanya saat ReplicatedStorage.LiveSystem.ScreenMode == ACTIVE_ON_MODE
	ACTIVE_ON_MODE = "Gambar", -- mode "🖼️ Gambar" di panel Layar panggung › Live Screen (lawannya "Live" = avatar pemain)
	LIVE_SYSTEM = "LiveSystem",
	SCREEN_MODE = "ScreenMode",
	MODE_WAIT = 10, -- detik menunggu LiveSystem & ScreenMode
	USE_FADE = true, -- fade hitam saat nyala/mati dan saat media diganti
	FADE_TIME = 0.4,
	FADE_ZINDEX = 100,
	HIDE_PART = true, -- Part transparan, hanya SurfaceGui yang terlihat
	MIRROR_HORIZONTAL = false, -- true = gambar dibalik kiri-kanan
}

-- id layar (atribut ReplicatedStorage.DjStageRemotes & panel admin) → tabel di atas, urutan tampil di panel
Config.LAYAR = { Utama = Config.LAYAR_UTAMA, Samping = Config.LAYAR_SAMPING }
Config.LAYAR_URUTAN = { "Utama", "Samping" }
Config.MEDIA_TYPES = { "IMAGE", "GIF", "VIDEO" } -- urutan tombol di panel
Config.MEDIA_LABEL = { IMAGE = "Gambar", GIF = "GIF", VIDEO = "Video" }

Config.VIDEO_LAYAR_MAX = 1 -- layar (grup) yang boleh memutar video bersamaan (lihat batas Roblox di atas)
Config.COOLDOWN = 2 -- detik antar-permintaan ganti media per pemain (pemain biasa juga dihitung)

-- Hemat di client: GIF & video berhenti kalau kamera lebih jauh dari `distance` stud dari layar (bawaan = jarak tampil
-- SurfaceGui layar, 1000); video juga berhenti kalau layar tidak terlihat kamera. Dicek tiap `interval` dtk.
Config.PAUSE = { distance = 1000, interval = 0.5 }

return Config
