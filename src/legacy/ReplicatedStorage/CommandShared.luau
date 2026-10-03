-- ═══════════════════════════════════════════════════════════
-- CommandShared — ReplicatedStorage > CommandShared (ModuleScript)
--
-- SATU sumber daftar perintah "/" untuk CommandServer (server) dan
-- CommandPanel (client): nama, argumen, deskripsi, perintah gratis,
-- dan cooldown per perintah. Tambah/ubah perintah cukup di sini, lalu
-- tulis handler-nya di CommandServer (H.<id>) atau CommandPanel (CLIENT.<id>).
-- ═══════════════════════════════════════════════════════════

local CommandShared = {}

-- Gratis untuk semua pemain (hanya memengaruhi diri sendiri).
CommandShared.FREE = { re = true, normal = true, rejoin = true }

-- Urutan = urutan di panel. s = "client" → dijalankan di client saja.
CommandShared.LIST = {
	{ id="re",        cmd="/re",        args="",          desc="Refresh ke tampilan karakter asli"        },
	{ id="headless",  cmd="/headless",  args="",          desc="Toggle Headless Head"                     },
	{ id="korblox",   cmd="/korblox",   args="",          desc="Toggle kaki kanan Korblox Deathspeaker"   },
	{ id="size",      cmd="/size",      args="<0.1–1>",   desc="Skala karakter, contoh: /size 0.5"        },
	{ id="ghost",     cmd="/ghost",     args="",          desc="Toggle karakter semi-transparan"          },
	{ id="clearhats", cmd="/clearhats", args="",          desc="Hapus semua aksesoris (restore: /re)"     },
	{ id="hat",       cmd="/hat",       args="",          desc="Toggle sembunyikan/tampilkan aksesoris"   },
	{ id="highlight", cmd="/highlight", args="<color>",   desc="Toggle outline highlight"                 },
	{ id="sparkle",   cmd="/sparkle",   args="<color>",   desc="Toggle partikel sparkle"                  },
	{ id="fire",      cmd="/fire",      args="<color>",   desc="Toggle efek api"                          },
	{ id="smoke",     cmd="/smoke",     args="<color>",   desc="Toggle efek asap"                         },
	{ id="trail",     cmd="/trail",     args="",          desc="Toggle trail pelangi"                     },
	{ id="glow",      cmd="/glow",      args="<color>",   desc="Toggle cahaya PointLight"                 },
	{ id="nametag",   cmd="/nametag",   args="<teks>",    desc="Teks di kepala — kosong = hapus"          },
	{ id="afk",       cmd="/afk",       args="",          desc="Toggle label AFK di kepala"               },
	{ id="sit",       cmd="/sit",       args="",          desc="Duduk"                                    },
	{ id="stand",     cmd="/stand",     args="",          desc="Berdiri"                                  },
	{ id="normal",    cmd="/normal",    args="",          desc="Reset SEMUA modifikasi karakter"          },
	{ id="undo",      cmd="/undo",      args="",          desc="Batalkan perubahan terakhir"              },
	{ id="reset",     cmd="/reset",     args="",          desc="Respawn"                                  },
	{ id="rejoin",    cmd="/rejoin",    args="",          desc="Keluar & masuk kembali ke server"         },
	{ id="fps",  cmd="/fps",  args="",          desc="Toggle overlay FPS & ping",      s="client" },
	{ id="cam",  cmd="/cam",  args="<5–128>",   desc="Jarak kamera: /cam 30 · /cam = bawaan", s="client" },
	{ id="fov",  cmd="/fov",  args="<30–120>",  desc="Field of view, contoh: /fov 90", s="client" },
	{ id="time", cmd="/time", args="",          desc="Waktu in-game saat ini",         s="client" },
}

-- Jeda per perintah per pemain (detik) di server. Tidak ada di sini = 2 dtk.
CommandShared.COOLDOWN = {
	re=3, reset=5, rejoin=10, sit=1, stand=1, afk=2,
	headless=2, korblox=2, size=1, ghost=1, clearhats=2,
	highlight=1, sparkle=1, fire=1, smoke=1, trail=1,
	glow=1, hat=1, nametag=1, normal=2, undo=1,
}

-- Rentang /cam (sama dengan teks argumen di LIST). hold = detik kamera
-- dikunci sesaat di jarak tujuan supaya modul kamera melompat ke sana.
CommandShared.CAM = { min = 5, max = 128, hold = 0.1 }

-- Kata perintah dari teks kotak cari: tanpa spasi depan & "/", huruf kecil.
function CommandShared.word(raw)
	return string.lower(string.match(raw or "", "^%s*/?%s*(%S*)") or "")
end

-- Argumen dari teks kotak cari: kata pertama (perintah) dibuang, sisanya
-- dipecah per spasi. Spasi di depan tidak menggeser argumen (sama dengan word).
function CommandShared.args(raw)
	local rest = string.match(raw or "", "^%s*/?%s*%S*(.*)$") or ""
	local out = {}
	for a in string.gmatch(rest, "%S+") do
		table.insert(out, a)
	end
	return out
end

-- Pesan chat → perintah panel yang dijalankan di CLIENT (s = "client": /fps /cam /fov /time), atau nil.
-- Hanya pesan berawalan "/" (spasi depan boleh) dengan kata perintah PERSIS. Perintah server tetap lewat
-- Player.Chatted di CommandServer (pesan tetap terkirim ke chat seperti biasa).
function CommandShared.chatClient(text)
	if type(text) ~= "string" or not string.match(text, "^%s*/") then
		return nil
	end
	local word = CommandShared.word(text)
	for _, c in ipairs(CommandShared.LIST) do
		if c.id == word then
			if c.s == "client" then
				return c.id, CommandShared.args(text)
			end
			return nil
		end
	end
	return nil
end

-- Hasil cari panel "/" berurutan: id PERSIS → id berawalan kata → id
-- mengandung kata → deskripsi mengandung kata. Dalam satu tingkat urutan LIST
-- dipertahankan; kata kosong = semua perintah urutan LIST. Baris pertama hasil
-- adalah yang dijalankan Enter, jadi "/hat" menjalankan hat (bukan clearhats)
-- dan "/reset" menjalankan reset (bukan normal yang deskripsinya "Reset…").
function CommandShared.search(raw)
	local word = CommandShared.word(raw)
	local found = {}
	for index, c in ipairs(CommandShared.LIST) do
		local tier
		if word == "" or c.id == word then
			tier = 1
		elseif string.sub(c.id, 1, #word) == word then
			tier = 2
		elseif string.find(c.id, word, 1, true) then
			tier = 3
		elseif string.find(string.lower(c.desc), word, 1, true) then
			tier = 4
		end
		if tier then
			table.insert(found, { cmd = c, tier = tier, index = index })
		end
	end
	table.sort(found, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		return a.index < b.index
	end)
	return found, word
end

-- /cam tanpa mengunci zoom. Dengan angka: kamera lompat ke jarak itu, lalu zoom
-- bebas lagi (maks dinaikkan kalau angkanya di atas maks bawaan). Tanpa angka:
-- kembali ke rentang bawaan place. Kembalian: { jump = jarak|nil, min, max }.
function CommandShared.camZoom(arg, defaultMin, defaultMax)
	local n = tonumber(arg)
	if n ~= n then n = nil end -- tolak NaN ("nan" lolos math.clamp)
	if not n then
		return { jump = nil, min = defaultMin, max = defaultMax }
	end
	n = math.clamp(n, CommandShared.CAM.min, CommandShared.CAM.max)
	return { jump = n, min = defaultMin, max = math.max(defaultMax, n) }
end

return CommandShared
