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
	{ id="cam",  cmd="/cam",  args="<5–128>",   desc="Jarak kamera, contoh: /cam 30",  s="client" },
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

return CommandShared
