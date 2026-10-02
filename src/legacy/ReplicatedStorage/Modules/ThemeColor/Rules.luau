--!strict
-- ReplicatedStorage/Modules/ThemeColor/Rules (ModuleScript) — aturan MURNI themeColor (tanpa GetService/Instance/yield).
-- Dipakai client (ThemeColor) & server (ServerScriptService.ThemeColor); diuji Lune. Waktu selalu disuntik (now).

local Rules = {}

-- Peran token. Nilainya per tema di Config.ThemeColor.presets[id].tokens.
Rules.TOKENS = {
	"BG", -- latar panel
	"CARD", -- kartu / baris / slot / tab tidak aktif
	"CARD_HOVER", -- hover / ditekan / slot aktif
	"CHIP", -- tab aktif & tombol nilai (teksnya ON_ACCENT)
	"TRACK", -- jalur toggle mati / slider kosong
	"SCROLL", -- scrollbar
	"BORDER", -- garis tepi opak yang halus
	"LINE", -- garis tepi tipis (dipakai dengan transparansi tinggi)
	"TEXT_STRONG", -- judul / nama / kenop toggle / tombol Menu saat terbuka
	"TEXT", -- teks utama
	"TEXT_DIM", -- teks kedua / ikon redup
	"ACCENT", -- toggle hidup, isi slider, tombol utama, sorotan
	"ON_ACCENT", -- teks di atas ACCENT / CHIP / TEXT_STRONG
	"DANGER",
	"SUCCESS",
	"INFO",
	"TOPBAR", -- tombol topbar
}

-- Nama lama `_G.MenuConfig.colors` (UltimateMenu) → token. Skrip lama yang memakai nama ini tetap jalan.
Rules.LEGACY = {
	bg = "BG",
	bgLight = "CARD",
	section = "CARD",
	hover = "CARD_HOVER",
	accent = "ACCENT",
	accentDark = "CHIP",
	white = "TEXT",
	gray = "TEXT_DIM",
	darkGray = "TRACK",
	textOnAccent = "ON_ACCENT",
	danger = "DANGER",
	success = "SUCCESS",
	blue = "INFO",
	border = "LINE",
}

-- Warna yang TIDAK boleh jadi token: putih (ImageColor3 tanpa tint / teks di atas gambar), hitam (overlay),
-- bawaan Instance.new Frame (163,162,165) & teks (27,42,53). Warna ini tidak pernah diubah saat lukis ulang.
Rules.RESERVED = { 0xFFFFFF, 0x000000, 0xA3A2A5, 0x1B2A35 }

-- Kontras minimum (rumus WCAG) per pasangan token: { teks, latar, minimum }
Rules.CONTRAST = {
	{ "TEXT", "CARD", 7 },
	{ "TEXT_STRONG", "BG", 7 },
	{ "TEXT_STRONG", "TOPBAR", 7 },
	{ "TEXT_DIM", "CARD", 4.5 },
	{ "TEXT_DIM", "CARD_HOVER", 4 },
	{ "ON_ACCENT", "ACCENT", 4.5 },
	{ "ON_ACCENT", "CHIP", 4.5 },
	{ "ON_ACCENT", "TEXT_STRONG", 4.5 },
	{ "DANGER", "CARD", 4.5 },
	{ "SUCCESS", "CARD", 4.5 },
	{ "INFO", "CARD", 4.5 },
	{ "ACCENT", "CARD", 3 },
}

-- Warna → angka 0xRRGGBB (dibulatkan ke 8 bit; nilai float Color3 bisa beda tipis)
function Rules.key(c: Color3): number
	return math.round(c.R * 255) * 65536 + math.round(c.G * 255) * 256 + math.round(c.B * 255)
end

function Rules.hex(c: Color3): string
	return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function channel(v: number): number
	return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end

function Rules.luminance(c: Color3): number
	local r, g, b = math.round(c.R * 255) / 255, math.round(c.G * 255) / 255, math.round(c.B * 255) / 255
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

function Rules.contrast(a: Color3, b: Color3): number
	local la, lb = Rules.luminance(a), Rules.luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- Urutan id: `order` dulu, lalu preset lain (urut nama) supaya hasil selalu sama.
function Rules.ids(config: any): { string }
	local list, seen = {}, {}
	for _, id in config.order do
		if config.presets[id] and not seen[id] then
			table.insert(list, id)
			seen[id] = true
		end
	end
	local extra = {}
	for id in config.presets do
		if not seen[id] then
			table.insert(extra, id)
		end
	end
	table.sort(extra)
	for _, id in extra do
		table.insert(list, id)
	end
	return list
end

-- key warna → peran, dari SEMUA tema. Dipakai lukis ulang & live(): warna tema mana pun → warna tema sekarang.
function Rules.roleIndex(config: any): { [number]: string }
	local idx = {}
	for _, id in Rules.ids(config) do
		for role, c in config.presets[id].tokens do
			local k = Rules.key(c)
			if idx[k] == nil then
				idx[k] = role
			end
		end
	end
	return idx
end

-- Semua masalah Config (kosong = sah).
function Rules.validate(config: any): { string }
	local problems = {}
	local function add(s: string)
		table.insert(problems, s)
	end
	if type(config.presets) ~= "table" then
		add("presets tidak ada")
		return problems
	end
	local def = config.presets[config.default]
	if not def then
		add(("default %s tidak ada di presets"):format(tostring(config.default)))
	elseif def.free ~= true then
		add(("default %s harus gratis"):format(tostring(config.default)))
	end
	for _, id in config.order or {} do
		if not config.presets[id] then
			add(("order: %s tidak ada di presets"):format(tostring(id)))
		end
	end
	for id in config.plainName or {} do
		if not config.presets[id] then
			add(("plainName: %s tidak ada di presets"):format(tostring(id)))
		end
	end
	local reserved = {}
	for _, k in Rules.RESERVED do
		reserved[k] = true
	end
	local global: { [number]: string } = {}
	for _, id in Rules.ids(config) do
		local p = config.presets[id]
		if type(p.label) ~= "string" or p.label == "" then
			add(id .. ": label kosong")
		end
		if type(p.free) ~= "boolean" then
			add(id .. ": free harus true/false")
		end
		local tokens = p.tokens or {}
		local seen: { [number]: string } = {}
		for _, role in Rules.TOKENS do
			local c = tokens[role]
			if typeof(c) ~= "Color3" then
				add(("%s.%s: bukan Color3"):format(id, role))
			else
				local k = Rules.key(c)
				if reserved[k] then
					add(("%s.%s: warna %s dicadangkan (putih/hitam/bawaan)"):format(id, role, Rules.hex(c)))
				end
				if seen[k] then
					add(("%s.%s: sama dengan %s (%s)"):format(id, role, seen[k], Rules.hex(c)))
				end
				seen[k] = role
				local g = global[k]
				if g and string.match(g, "^[^.]+%.(.+)$") ~= role then
					add(("%s.%s: sama dengan %s (%s) — lukis ulang jadi rancu"):format(id, role, g, Rules.hex(c)))
				end
				global[k] = global[k] or (id .. "." .. role)
			end
		end
		for role in tokens do
			if not table.find(Rules.TOKENS, role) then
				add(("%s.%s: token tidak dikenal"):format(id, tostring(role)))
			end
		end
		for _, pair in Rules.CONTRAST do
			local a, b = tokens[pair[1]], tokens[pair[2]]
			if typeof(a) == "Color3" and typeof(b) == "Color3" then
				local cr = Rules.contrast(a, b)
				if cr < pair[3] then
					add(("%s: kontras %s/%s %.1f < %s"):format(id, pair[1], pair[2], cr, tostring(pair[3])))
				end
			end
		end
	end
	return problems
end

-- Tema yang benar-benar dipakai: id ada dan (gratis atau punya pass) → id; selain itu default.
function Rules.effective(config: any, id: any, ownsPass: boolean): string
	if type(id) == "string" then
		local p = config.presets[id]
		if p and (p.free or ownsPass) then
			return id
		end
	end
	return config.default
end

-- Permintaan pemain mengganti tema → ok, alasan ("tema" | "pass" | "jeda" | "sama").
function Rules.checkSelect(config: any, id: any, current: string?, ownsPass: boolean, now: number, last: number?): (boolean, string?)
	if type(id) ~= "string" or #id > 32 or not config.presets[id] then
		return false, "tema"
	end
	if last and now - last < config.selectCooldown then
		return false, "jeda"
	end
	if id == current then
		return false, "sama"
	end
	if not config.presets[id].free and not ownsPass then
		return false, "pass"
	end
	return true, nil
end

-- Rekaman DataStore
-- Warna NAMA pemain bertema id (nametag di atas kepala, daftar Players, kartu pemain): ACCENT tema itu.
-- nil = pakai warna nama bawaan tempat itu (tema di config.plainName, mis. Default; id tidak dikenal).
function Rules.nameColor(config: any, id: any): Color3?
	if type(id) ~= "string" or (config.plainName and config.plainName[id]) then
		return nil
	end
	local p = config.presets[id]
	return if p then p.tokens.ACCENT else nil
end

function Rules.record(id: string, now: number): { v: number, id: string, at: number }
	return { v = 1, id = id, at = now }
end

-- Baca rekaman tersimpan apa pun dengan aman → id tema yang masih ada, atau nil.
function Rules.readRecord(config: any, raw: any): string?
	if type(raw) == "table" and type(raw.id) == "string" and config.presets[raw.id] then
		return raw.id
	end
	return nil
end

return Rules
