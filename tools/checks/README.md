# tools/checks

| Perintah | Di mana | Guna |
|---|---|---|
| `lune run tools/checks/syntax` | CI + lokal | semua `.luau` di `src/` & `tools/` terkompilasi, semua JSON valid |
| `lune run tools/checks/dances` | CI + lokal | DanceAssets: tidak ada id kembar, nama kembar beda kapital, id tidak valid; semua `poseNames` & `POPULAR_DANCES` (DanceHandler/Config) ada di daftar |
| `lune run tools/checks/place <place.rbxl>` | lokal saja | simulasi Connect Rojo: GAGAL kalau ada pasangan ambigu atau instance yang akan dihapus; daftar BARU/DIUBAH |

`place` dijalankan SEBELUM Connect Rojo tiap PR. Daftar DIUBAH harus persis berisi skrip yang memang diubah PR itu
(dibandingkan dengan file place yang dipakai — biasanya backup terakhir). Setelah Connect, tetap jalankan snippet
hitung skrip di command bar Studio (jumlah harus sama dengan sebelum Connect).

Belum dinyalakan: StyLua & Selene untuk `src/legacy/**` (kode lama tidak boleh terformat ulang). Kode baru di luar
`src/legacy` akan diberi format + lint saat pertama kali ada.
