# tools/checks

| Perintah | Di mana | Guna |
|---|---|---|
| `lune run tools/checks/syntax` | CI + lokal | semua `.luau` di `src/` & `tools/` terkompilasi, semua JSON valid |
| `lune run tools/checks/dances` | CI + lokal | DanceAssets: tidak ada id kembar, nama kembar beda kapital, id tidak valid; semua `poseNames` & `POPULAR_DANCES` (DanceHandler/Config) ada di daftar |
| `lune run tools/checks/place <place.rbxl>` | lokal saja | simulasi Connect Rojo: GAGAL kalau ada pasangan ambigu atau instance yang akan dihapus (anak node `$ignoreUnknownInstances: true` tidak dihitung, sama seperti Rojo); daftar BARU/DIUBAH; **ASET WAJIB** (`assets.luau`): Tool tanpa Handle/bagian wajib, rujukan `script.X` / `script["X"]` / `:WaitForChild("X")` yang anaknya tidak ada di place maupun repo |
| `tools/checks/studio/cek_aset.luau` | Command Bar Studio (mode Edit) | **HITUNG + CEK ASET**: JUMLAH SKRIP + aturan aset wajib yang sama, di place yang sedang terbuka (tidak mengubah apa pun) |

`place` dijalankan SEBELUM Connect Rojo tiap PR. Daftar DIUBAH harus persis berisi skrip yang memang diubah PR itu
(dibandingkan dengan file place yang dipakai — biasanya backup terakhir). Setelah Connect, jalankan `studio/cek_aset.luau`
di Command Bar (JUMLAH SKRIP harus sesuai rencana PR, CEK ASET OK) — juga sebelum Publish.

`rojo serve` WAJIB mati saat `default.project.json` berubah: Rojo hanya memasangkan instance Studio (Nama+Kelas) saat sinkron
awal; node baru yang datang lewat sinkron langsung dibuat sebagai instance BARU → kembar, dan aset Studio bisa ikut hilang
saat kembarannya dirapikan (kejadian WORLD, claude/Rencana_Tools.md T0). Patch `*_patch.py` menolak jalan kalau `rojo serve` hidup.

Belum dinyalakan: StyLua & Selene untuk `src/legacy/**` (kode lama tidak boleh terformat ulang). Kode baru di luar
`src/legacy` akan diberi format + lint saat pertama kali ada.
