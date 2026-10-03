--!strict
-- ServerScriptService/DjStage/Config (ModuleScript) — semua angka & ID aset efek DJ STAGE (ruangan WORLD,
-- claude/Rencana_World.md). Nilai di sini SAMA PERSIS dengan 11 skrip Studio lama yang digantikan DjStage:
--   VJScript stage/EntranceScreenC (GIF), VJScript stage/StageScreens/EntranceScreen ×2 (VJ),
--   Script dj/Interact/Animate/BaseLED ×4 dan dj/BaseCDJ/DecorationButtons/USBButtons/USBLed ×4 (LED).

local Config = {}

Config.STAGE_NAME = "DJ STAGE"
Config.FIND_TIMEOUT = 10 -- detik menunggu Workspace["DJ STAGE"] (di server biasanya sudah ada)

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

-- ── Layar tengah: GIF selalu jalan (dulu: VJScript di EntranceScreenC) ───────────────────────────────
Config.GIF_SCREEN = {
	path = { "stage", "EntranceScreenC" },
	frameTime = 0.05, -- detik per frame
	hidePart = true, -- Part transparan, hanya SurfaceGui yang terlihat
	frames = {
		--video 1
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
	},
}

-- ── Layar samping: media VJ, ikut ScreenMode & attribute "On" (dulu: VJScript di tiap EntranceScreen) ──
Config.VJ_SCREENS = {
	folder = { "stage", "StageScreens" }, -- tiap BasePart di folder ini (saat server mulai)
	MEDIA_TYPE = "IMAGE", -- "GIF" | "VIDEO" | "IMAGE"
	IMAGE_ID = "rbxassetid://129949575767241", -- [IMAGE] satu gambar diam
	VIDEO_ID = "rbxassetid://0", -- [VIDEO] video loop (harus sudah lolos moderasi)
	VIDEO_VOLUME = 0, -- 0 = mute, 1 = full
	FRAME_SPEED = 0.05, -- [GIF] detik antar frame
	START_ON = true, -- nilai attribute "On" kalau belum ada
	USE_SCREENMODE = true, -- layar hanya nyala saat ReplicatedStorage.LiveSystem.ScreenMode == ACTIVE_ON_MODE
	ACTIVE_ON_MODE = "VJ",
	LIVE_SYSTEM = "LiveSystem",
	SCREEN_MODE = "ScreenMode",
	MODE_WAIT = 10, -- detik menunggu LiveSystem & ScreenMode
	USE_FADE = true, -- fade hitam saat ON/OFF
	FADE_TIME = 0.4,
	FADE_ZINDEX = 100,
	HIDE_PART = true, -- Part transparan, hanya SurfaceGui yang terlihat
	MIRROR_HORIZONTAL = false, -- true = gambar dibalik kiri-kanan (GIF / VIDEO / IMAGE)
	GIF_FRAMES = { -- [GIF] daftar frame; daftar lama di bawah dikomentari (tidak dipakai saat MEDIA_TYPE = "IMAGE")
		--"rbxassetid://102056083179463",
		--"rbxassetid://104474718440926",
		--"rbxassetid://136205159112104",
		--"rbxassetid://86837321377154",
		--"rbxassetid://130687043803981",
		--"rbxassetid://125935538790230",
		--"rbxassetid://106859226931819",
		--"rbxassetid://94125593465874",
		--"rbxassetid://132159987057788",
		--"rbxassetid://114232567626965",
		--"rbxassetid://112994750498849",
		--"rbxassetid://85190941281907",
		--"rbxassetid://76878019498890",
		--"rbxassetid://92772945766087",
		--"rbxassetid://92089357693271",
		--"rbxassetid://83199206302453",
		--"rbxassetid://123837287175864",
		--"rbxassetid://123320656757813",
		--"rbxassetid://83970013622112",
		--"rbxassetid://126254429361783",
		--"rbxassetid://78903582333058",
		--"rbxassetid://134656999525384",
		--"rbxassetid://110691579943760",
		--"rbxassetid://131556984249969",
		--"rbxassetid://93631716649844",
		--"rbxassetid://80186987958223",
		--"rbxassetid://137552637070195",
		--"rbxassetid://76186871951312",
		--"rbxassetid://125095092545761",
		--"rbxassetid://80088489972102",
		--"rbxassetid://116073277006599",
		--"rbxassetid://93995627998487",
		--"rbxassetid://100253538758446",
		--"rbxassetid://94153065156955",
		--"rbxassetid://93490617417124",
		--"rbxassetid://105093958297087",
		--"rbxassetid://128000893144138",
		--"rbxassetid://135335456372534",
		--"rbxassetid://139683761524931",
		--"rbxassetid://101262975231059",
		--"rbxassetid://106435818352766",
		--"rbxassetid://103933079243127",
		--"rbxassetid://117029020900749",
		--"rbxassetid://82537332263984",
		--"rbxassetid://89205703617973",
		--"rbxassetid://101666382765471",
		--"rbxassetid://115958455509248",
		--"rbxassetid://109643742163274",
		--"rbxassetid://126605684200749",
		--"rbxassetid://74300814868108",
		--"rbxassetid://83619422276261",
		--"rbxassetid://99570889977787",
		--"rbxassetid://85218926818757",
		--"rbxassetid://122197389613093",
		--"rbxassetid://124578973770621",
		--"rbxassetid://80095223263292",
		--"rbxassetid://76592498463186",
		--"rbxassetid://119936532636251",
		--"rbxassetid://138841517889683",
		--"rbxassetid://83619945870278",
		--"rbxassetid://126958433728685",
		--"rbxassetid://76678533523203",
		--"rbxassetid://87260585013120",
		--"rbxassetid://123648199491781",
		--"rbxassetid://88546148486694",
		--"rbxassetid://92714718328638",
		--"rbxassetid://125170932746450",
		--"rbxassetid://82902248014037",
		--"rbxassetid://123042163415834",
		--"rbxassetid://89151399668359",
		--"rbxassetid://78904821056700",
		--"rbxassetid://75330519115404",
		--"rbxassetid://86450484040590",
		--"rbxassetid://122267516763313",
		--"rbxassetid://95547819241975",
	},
}

return Config
