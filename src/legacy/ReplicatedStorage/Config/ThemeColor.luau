--!strict
-- ReplicatedStorage/Config/ThemeColor (ModuleScript) — tema warna UI per pemain (themeColor, claude/Rencana_ThemeColor.md).
-- Semua angka & warna yang boleh diubah ada di sini. Arti tiap token: ReplicatedStorage.Modules.ThemeColor.Rules (TOKENS).
-- Tambah tema = tambah entri `presets` + id di `order`. Rules.validate (dijalankan client & server, dan tes Lune) menjaga:
--   17 token lengkap · tiap nilai unik di SEMUA tema · bukan putih/hitam murni · kontras teks cukup.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type Preset = { label: string, free: boolean, tokens: { [string]: Color3 } }

local ThemeColor = {}

ThemeColor.default = "Default" -- tema pemain baru / tanpa pass (WAJIB gratis)
ThemeColor.order = { -- urutan di pemilih
	"Default", "ClassicGold", "Red", "Pink", "Orange", "Yellow", "Green", "LightBlue", "Blue", "Purple", "Dark",
}
ThemeColor.passName = "Themes" -- nama entri ShopConfig.gamepasses yang membuka tema berbayar (id 2006030346)

ThemeColor.store = {
	name = "ThemeColor_v1", -- kunci u_<userId> = { v = 1, id = "<tema>", at = <unix> }
	studioSuffix = "_studio",
	keyPrefix = "u_",
	loadTries = 3,
}
ThemeColor.selectCooldown = 1 -- dtk minimal antar ganti tema per pemain
ThemeColor.saveGap = 7 -- dtk minimal antar tulis DataStore per pemain (batas Roblox: 6 dtk per kunci)
ThemeColor.passWait = 15 -- dtk menunggu ShopServer (_G.ShopHasGamepass) siap
ThemeColor.repaintDelays = { 0.35, 1 } -- lukis ulang lagi sesudah tween hover/buka panel selesai
-- Garis tepi bergerak (modul ThemeColor.glow): cahaya aksen berputar mengelilingi tepi + denyut (pulse) transparansi.
ThemeColor.outline = {
	panel = { base = 0.5, amp = 0.3, speed = 50, period = 3.2 }, -- garis tepi panel utama: halus
	hover = { base = 0.05, amp = 0.3, speed = 140, period = 1.4 }, -- tombol yang di-hover / ditekan: lebih terang & cepat
	highlight = 0.45, -- campuran putih pada titik paling terang
}
-- Nama pemain (nametag di atas kepala, daftar Players, kartu pemain) = ACCENT tema pilihan pemain ITU, dilihat semua
-- pemain (Rules.nameColor). Tema di sini memakai warna nama bawaan (nametag putih seperti dulu), bukan aksennya.
ThemeColor.plainName = { Default = true }
-- Sorot hover SEMUA tombol di panel bertanda (modul ThemeColor, otomatis lewat ThemeColor.mark).
ThemeColor.hover = {
	thickness = 1.5, -- tebal garis (px), digambar di DALAM tepi tombol → tidak terpotong daftar bergulir
	minSize = 12, -- tombol yang sisi terpendeknya < ini (px) tidak disorot
	maxArea = 0.3, -- tombol seluas > 30% layar (lapisan penutup / latar redup) tidak disorot
	touchHold = 0.25, -- layar sentuh: sorot tetap sebentar setelah jari diangkat (dtk)
}

ThemeColor.presets = ({
	Default = { -- netral hangat (nuansa contoh 14:36)
		label = "Default",
		free = true,
		tokens = {
			BG = rgb(21, 17, 15),
			CARD = rgb(31, 28, 25),
			CARD_HOVER = rgb(44, 40, 36),
			CHIP = rgb(150, 146, 141),
			TRACK = rgb(96, 93, 89),
			SCROLL = rgb(74, 71, 67),
			BORDER = rgb(56, 52, 48),
			LINE = rgb(255, 248, 240),
			TEXT_STRONG = rgb(214, 210, 205),
			TEXT = rgb(196, 192, 187),
			TEXT_DIM = rgb(140, 136, 131),
			ACCENT = rgb(186, 182, 177),
			ON_ACCENT = rgb(24, 21, 18),
			DANGER = rgb(226, 104, 96),
			SUCCESS = rgb(120, 198, 140),
			INFO = rgb(120, 166, 230),
			TOPBAR = rgb(27, 26, 28),
		},
	},
	ClassicGold = { -- tampilan HAVN lama
		label = "Classic Gold",
		free = true,
		tokens = {
			BG = rgb(16, 16, 17),
			CARD = rgb(26, 26, 28),
			CARD_HOVER = rgb(36, 36, 39),
			CHIP = rgb(168, 138, 44),
			TRACK = rgb(62, 62, 68),
			SCROLL = rgb(80, 80, 86),
			BORDER = rgb(44, 44, 52),
			LINE = rgb(254, 254, 255),
			TEXT_STRONG = rgb(245, 245, 247),
			TEXT = rgb(238, 238, 240),
			TEXT_DIM = rgb(148, 148, 154),
			ACCENT = rgb(212, 175, 55),
			ON_ACCENT = rgb(18, 18, 20),
			DANGER = rgb(226, 96, 96),
			SUCCESS = rgb(96, 196, 132),
			INFO = rgb(96, 152, 236),
			TOPBAR = rgb(22, 22, 24),
		},
	},
	Red = {
		label = "Red",
		free = false,
		tokens = {
			BG = rgb(22, 16, 16),
			CARD = rgb(32, 22, 21),
			CARD_HOVER = rgb(46, 31, 31),
			CHIP = rgb(221, 83, 76),
			TRACK = rgb(89, 66, 64),
			SCROLL = rgb(96, 40, 36),
			BORDER = rgb(57, 41, 40),
			LINE = rgb(254, 239, 238),
			TEXT_STRONG = rgb(225, 214, 214),
			TEXT = rgb(205, 194, 193),
			TEXT_DIM = rgb(152, 135, 134),
			ACCENT = rgb(236, 88, 80),
			ON_ACCENT = rgb(26, 11, 10),
			DANGER = rgb(246, 122, 150),
			SUCCESS = rgb(110, 200, 140),
			INFO = rgb(120, 166, 236),
			TOPBAR = rgb(28, 23, 23),
		},
	},
	Pink = {
		label = "Pink",
		free = false,
		tokens = {
			BG = rgb(22, 16, 19),
			CARD = rgb(32, 21, 27),
			CARD_HOVER = rgb(46, 31, 38),
			CHIP = rgb(211, 99, 154),
			TRACK = rgb(89, 64, 76),
			SCROLL = rgb(96, 36, 66),
			BORDER = rgb(57, 40, 48),
			LINE = rgb(254, 238, 246),
			TEXT_STRONG = rgb(225, 214, 219),
			TEXT = rgb(205, 193, 199),
			TEXT_DIM = rgb(152, 134, 143),
			ACCENT = rgb(242, 112, 176),
			ON_ACCENT = rgb(26, 10, 18),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(112, 200, 140),
			INFO = rgb(120, 166, 236),
			TOPBAR = rgb(28, 23, 25),
		},
	},
	Orange = {
		label = "Orange",
		free = false,
		tokens = {
			BG = rgb(22, 19, 16),
			CARD = rgb(32, 26, 21),
			CARD_HOVER = rgb(46, 38, 31),
			CHIP = rgb(213, 129, 57),
			TRACK = rgb(89, 75, 64),
			SCROLL = rgb(96, 64, 36),
			BORDER = rgb(57, 48, 40),
			LINE = rgb(254, 245, 238),
			TEXT_STRONG = rgb(225, 219, 214),
			TEXT = rgb(205, 198, 193),
			TEXT_DIM = rgb(152, 142, 134),
			ACCENT = rgb(245, 146, 62),
			ON_ACCENT = rgb(26, 17, 10),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(112, 200, 140),
			INFO = rgb(120, 166, 236),
			TOPBAR = rgb(28, 25, 23),
		},
	},
	Yellow = {
		label = "Yellow",
		free = false,
		tokens = {
			BG = rgb(22, 21, 16),
			CARD = rgb(32, 30, 21),
			CARD_HOVER = rgb(46, 43, 31),
			CHIP = rgb(212, 180, 65),
			TRACK = rgb(89, 83, 64),
			SCROLL = rgb(96, 83, 36),
			BORDER = rgb(57, 53, 40),
			LINE = rgb(254, 250, 238),
			TEXT_STRONG = rgb(225, 222, 214),
			TEXT = rgb(205, 202, 193),
			TEXT_DIM = rgb(152, 148, 134),
			ACCENT = rgb(244, 206, 72),
			ON_ACCENT = rgb(26, 22, 10),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(112, 200, 140),
			INFO = rgb(120, 166, 236),
			TOPBAR = rgb(28, 27, 23),
		},
	},
	Green = {
		label = "Green",
		free = false,
		tokens = {
			BG = rgb(16, 22, 18),
			CARD = rgb(21, 32, 25),
			CARD_HOVER = rgb(31, 46, 36),
			CHIP = rgb(74, 180, 112),
			TRACK = rgb(64, 89, 73),
			SCROLL = rgb(36, 96, 58),
			BORDER = rgb(40, 57, 46),
			LINE = rgb(238, 254, 244),
			TEXT_STRONG = rgb(214, 225, 218),
			TEXT = rgb(193, 205, 197),
			TEXT_DIM = rgb(134, 152, 140),
			ACCENT = rgb(82, 206, 126),
			ON_ACCENT = rgb(10, 26, 16),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(150, 226, 120),
			INFO = rgb(120, 166, 236),
			TOPBAR = rgb(23, 28, 25),
		},
	},
	LightBlue = {
		label = "Light Blue",
		free = false,
		tokens = {
			BG = rgb(16, 20, 22),
			CARD = rgb(21, 29, 32),
			CARD_HOVER = rgb(31, 41, 46),
			CHIP = rgb(87, 175, 214),
			TRACK = rgb(64, 81, 89),
			SCROLL = rgb(36, 78, 96),
			BORDER = rgb(40, 52, 57),
			LINE = rgb(238, 249, 254),
			TEXT_STRONG = rgb(214, 221, 225),
			TEXT = rgb(193, 201, 205),
			TEXT_DIM = rgb(134, 146, 152),
			ACCENT = rgb(98, 200, 246),
			ON_ACCENT = rgb(10, 21, 26),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(112, 200, 140),
			INFO = rgb(150, 180, 250),
			TOPBAR = rgb(23, 26, 28),
		},
	},
	Blue = {
		label = "Blue",
		free = false,
		tokens = {
			BG = rgb(16, 18, 22),
			CARD = rgb(21, 25, 32),
			CARD_HOVER = rgb(31, 36, 46),
			CHIP = rgb(87, 130, 217),
			TRACK = rgb(64, 72, 89),
			SCROLL = rgb(36, 56, 96),
			BORDER = rgb(40, 45, 57),
			LINE = rgb(238, 243, 254),
			TEXT_STRONG = rgb(214, 217, 225),
			TEXT = rgb(193, 197, 205),
			TEXT_DIM = rgb(134, 140, 152),
			ACCENT = rgb(98, 148, 250),
			ON_ACCENT = rgb(10, 15, 26),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(112, 200, 140),
			INFO = rgb(120, 200, 240),
			TOPBAR = rgb(23, 25, 28),
		},
	},
	Purple = {
		label = "Purple",
		free = false,
		tokens = {
			BG = rgb(18, 16, 22),
			CARD = rgb(25, 21, 32),
			CARD_HOVER = rgb(36, 31, 46),
			CHIP = rgb(147, 109, 217),
			TRACK = rgb(73, 64, 89),
			SCROLL = rgb(57, 36, 96),
			BORDER = rgb(46, 40, 57),
			LINE = rgb(244, 238, 254),
			TEXT_STRONG = rgb(218, 214, 225),
			TEXT = rgb(197, 193, 205),
			TEXT_DIM = rgb(140, 134, 152),
			ACCENT = rgb(168, 124, 250),
			ON_ACCENT = rgb(15, 10, 26),
			DANGER = rgb(230, 100, 98),
			SUCCESS = rgb(112, 200, 140),
			INFO = rgb(120, 166, 236),
			TOPBAR = rgb(25, 23, 28),
		},
	},
	Dark = { -- hitam pekat, aksen putih
		label = "Dark",
		free = false,
		tokens = {
			BG = rgb(9, 9, 10),
			CARD = rgb(17, 17, 19),
			CARD_HOVER = rgb(27, 27, 30),
			CHIP = rgb(196, 196, 202),
			TRACK = rgb(70, 70, 77),
			SCROLL = rgb(58, 58, 64),
			BORDER = rgb(38, 38, 43),
			LINE = rgb(250, 250, 253),
			TEXT_STRONG = rgb(240, 240, 243),
			TEXT = rgb(222, 222, 226),
			TEXT_DIM = rgb(142, 142, 150),
			ACCENT = rgb(232, 232, 238),
			ON_ACCENT = rgb(12, 12, 14),
			DANGER = rgb(232, 94, 94),
			SUCCESS = rgb(98, 204, 134),
			INFO = rgb(104, 160, 242),
			TOPBAR = rgb(16, 16, 18),
		},
	},
} :: { [string]: Preset })

return ThemeColor
