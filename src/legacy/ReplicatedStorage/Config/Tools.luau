--!strict
-- ReplicatedStorage/Config/Tools (ModuleScript) — angka & aturan tool (ruangan TOOLS, claude/Rencana_Tools.md).
-- Data murni (tanpa GetService/Instance/yield). Dibaca: GlowStickServer, FlyingbroomServer, ToolGiver (server),
-- skrip di dalam Sign / Money Gun / WaterGun, panel GlowStickUI / MoneyGunUI / WaterGunUI (client), tes.
-- Aturannya (bucket, gate, cek warna, pilih angka) ada di ReplicatedStorage.Modules.ToolRules.
--
-- Istilah:
--   batas terima = token bucket per pemain per remote: RATE event/dtk rata-rata, boleh beruntun sampai BURST.
--                  Event di atas batas DIBUANG (client sah tidak pernah sampai sini — slider dibatasi di client).
--   jeda terapkan = perubahan diterapkan ke instance paling sering 1× per jeda; permintaan di tengah jeda
--                  digabung → yang TERAKHIR diterapkan di ujung jeda (keadaan akhir selalu = klik terakhir).

local Config = {}

-- ── batas terima remote (per pemain, per remote) ──────────────────────────────────────────────────────────────────
Config.RECEIVE = { RATE = 10, BURST = 20 }

-- ── GlowStick (ServerScriptService.GlowStickServer + StarterGui.GlowStickUI) ────────────────────────────────────────
Config.GLOWSTICK = {
	TOOL_NAME = "GlowStick",
	APPLY_EVERY = 0.1, -- dtk, jeda terapkan warna ke tool + atribut pemain
	REAPPLY_DELAY = 0.1, -- dtk, jeda sebelum warna tersimpan dipasang ke GlowStick yang baru di-equip (sama dengan kode lama)
	SEND_EVERY = 0.1, -- dtk, slider/tombol warna di client mengirim paling sering 1× per jeda (+ nilai terakhir)
}

-- ── Flying Broom (ServerScriptService.FlyingbroomServer) ──────────────────────────────────────────────────────
Config.BROOM = {
	TOOL_NAME = "Flying Broom",
	APPLY_EVERY = 0.25, -- dtk, jeda terapkan nyala/warna efek sapu
}

-- ── Sign (StarterPack.Sign › LocalScript › BGColor/TextColor › Script) ──────────────────────────────────────────
Config.SIGN = {
	APPLY_EVERY = 0.25, -- dtk, jeda terapkan warna papan/teks per Sign
}

-- ── Money Gun & WaterGun (Serverscript di dalam tool + panel MoneyGunUI / WaterGunUI) ───────────────────────────
-- RATE/BURST = rentang stepper panel (angka sama dengan panel lama). Server memakai angka dari panel, dipaksa masuk
-- rentang & kelipatan STEP; angka tidak sah → DEFAULT (= angka tetap server lama).
Config.MONEY_GUN = {
	STATE_EVERY = 0.25, -- dtk, jeda terapkan mulai/berhenti semprot
	BURST_COOLDOWN = 0.15, -- dtk antar-burst (sama dengan kode lama)
	RATE = { MIN = 10, MAX = 100, STEP = 10, DEFAULT = 50 },
	BURST = { MIN = 3, MAX = 30, STEP = 1, DEFAULT = 12 },
}
Config.WATER_GUN = {
	STATE_EVERY = 0.25,
	BURST_COOLDOWN = 0.15,
	BURST_SOUND = 0.4, -- dtk suara burst (sama dengan kode client lama)
	RATE = { MIN = 5, MAX = 100, STEP = 5, DEFAULT = 20 },
	BURST = { MIN = 3, MAX = 50, STEP = 1, DEFAULT = 15 },
}

-- ── ToolGiver (ServerScriptService.ToolGiver) ─────────────────────────────────────────────────────────────────
-- Tool di ServerStorage yang diberikan ke Backpack: punya pass ATAU rank komunitas ≥ MIN_RANK (sama dengan kode lama).
-- pass: "VIP" = gamepass "VIP Access", "VVIP" = "VVIP Access" (ShopConfig).
Config.GIVER = {
	SPAWN_DELAY = 1, -- dtk sesudah karakter muncul (sama dengan kode lama)
	OWNERSHIP_DELAY = 0.5, -- dtk sesudah gamepass dibeli/diberi (sama dengan kode lama)
	RANK_ATTRIBUTE = "RankInGroup", -- atribut Player dari UnifiedRankManager
	RANK_WAIT = 15, -- dtk menunggu atribut itu; tidak muncul → cara lama (IsInGroup/GetRankInGroup)
	RULES = {
		{ names = { "Money Gun", "WaterGun" }, pass = "VIP", minRank = 1 },
		{ names = { "Flying Broom" }, pass = "VVIP", minRank = 10 },
	},
}

-- Tool HAVN: dicek saat server mulai (Handle hilang → warn) dan dihapus kalau tergeletak di Workspace (dijatuhkan).
Config.HAVN_TOOLS = {
	{ name = "GlowStick", where = "StarterPack" },
	{ name = "Sign", where = "StarterPack" },
	{ name = "Money Gun", where = "ServerStorage" },
	{ name = "WaterGun", where = "ServerStorage" },
	{ name = "Flying Broom", where = "ServerStorage" },
}

return Config
