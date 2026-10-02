--!strict
-- ReplicatedStorage/Config/ThemeMap (ModuleScript) — tema map (themeMap, claude/Rencana_Tema.md): daftar tema + angka setelan.
-- Dibaca server ThemeMap, panel admin ThemeMapAdmin, dan tes. Data murni (tanpa GetService/Instance/yield).
--   Aset tema  : ServerStorage.<assetFolder>.<folder> — dibangun MapGen di Studio: G.themeMap("<id>", "JALAN")
--   Terpasang  : Workspace.<mountFolder>.<folder> — diklon server saat game jalan; Default = tanpa dekor
-- Menambah tema: zona MapGen + MapGen.themeMaps.<id> + satu baris di `list` (tes mencocokkan keduanya).
-- Nama polos "theme" TIDAK dipakai: `_G.MenuConfig.theme` = palet warna UI (UltimateMenu); warna UI nanti = themeColor.

local ThemeMap = {}

ThemeMap.default = "Default"

export type Theme = { id: string, label: string, desc: string, folder: string? }

-- Urutan = urutan di panel. `folder` = nama aset di ServerStorage.ThemeMap (nil = tanpa dekor).
ThemeMap.list = {
	{ id = "Default", label = "Default", desc = "tanpa dekor" },
	{ id = "Birthday", label = "Birthday", desc = "balon, kanopi, kue, confetti", folder = "Birthday" },
} :: { Theme }

ThemeMap.assetFolder = "ThemeMap" -- ServerStorage.ThemeMap.<folder> (tidak direplikasi → tema tidak aktif = 0 biaya client)
ThemeMap.mountFolder = "ThemeMap" -- Workspace.ThemeMap.<folder> (di luar Workspace.Map: loop sentuhan S1 & MapGen.check tetap bersih)

-- DataStore satu kunci untuk semua server; Studio memakai akhiran (pelajaran DN7: Studio = universe sungguhan).
ThemeMap.store = { name = "ThemeMap_v1", key = "active", studioSuffix = "_studio" }
ThemeMap.topic = "ThemeMap" -- MessagingService {job, rev} (+ studioSuffix)

-- Jadwal dari panel (waktu dihitung SERVER, client hanya mengirim kunci ini).
ThemeMap.starts = {
	{ key = "now", label = "Sekarang" },
	{ key = "tomorrow", label = "Besok 00:00 WIB" },
}
ThemeMap.ends = {
	{ key = "none", label = "Tanpa batas" },
	{ key = "day", label = "23:59 WIB" }, -- akhir hari mulai (WIB)
	{ key = "24h", label = "24 jam" },
}
ThemeMap.utcOffset = 7 -- jam; WIB

ThemeMap.cooldown = { admin = 5, server = 10 } -- dtk: per admin, dan antar-pergantian di satu server
ThemeMap.load = { attempts = 3, delay = 5, retry = 60 } -- baca DataStore saat mulai; gagal → Default + edit ditolak, coba lagi
ThemeMap.poll = 300 -- dtk: baca ulang DataStore (jaring pengaman pesan MessagingService yang hilang)
ThemeMap.tick = 30 -- dtk: hitung ulang tema efektif (jadwal mulai/selesai)
ThemeMap.logMax = 10 -- riwayat pergantian yang disimpan & ditampilkan

-- Pemain yang HumanoidRootPart-nya di dalam part padat tema (+margin) dipindah ke tepi terdekat + out sebelum dekor muncul
-- (T0b: tanpa ini pemain terjebak di dalam kue; T0c: dengan ini berdiri normal).
ThemeMap.push = { margin = 2, out = 3, vertical = 3 }

local byId: { [string]: Theme } = {}
for _, t in ThemeMap.list do
	byId[t.id] = t
end

function ThemeMap.find(id: any): Theme?
	return if type(id) == "string" then byId[id] else nil
end

return ThemeMap
