# tools/extract — Tahap 1: pindahkan skrip apa adanya

```bash
lune run tools/extract/extract ~/Documents/HAVN_backup_2026-09-26.rbxl
lune run tools/extract/verify  ~/Documents/HAVN_backup_2026-09-26.rbxl   # harus: "OK: 109 skrip identik…"
```

`extract` membaca place dan menulis `src/legacy/<Service>/…`, `default.project.json`,
`tools/extract/manifest.json` (md5 tiap skrip), dan `tools/extract/report.md` (apa yang diekstrak
dan apa yang ditinggal, beserta alasannya). Isi skrip TIDAK diubah satu byte pun.

## Aturan ekstraksi
Skrip diekstrak hanya kalau SEMUA syarat ini terpenuhi (selain itu tetap tinggal di place, tetap jalan):

| Syarat | Alasan |
|---|---|
| Ada di ServerScriptService, ReplicatedStorage, StarterGui, atau StarterPlayer | Workspace/StarterPack/ServerStorage berisi map & Tool; dipindah di tahap `feat/world` |
| Semua leluhurnya Folder / StarterPlayerScripts | Skrip di dalam ScreenGui/Model/Tool ikut asetnya |
| Isinya hanya skrip dan Folder | Node `$path` membuat Rojo menghapus anak yang tidak ada di file (Value, Frame, PackageLink…) |
| Tidak ada saudara bernama sama (tanpa beda besar/kecil) | Rojo memasangkan instance lewat Nama+ClassName; disk Mac case-insensitive |
| Nama aman jadi nama file, bukan `init`/`*.server`/… | Rojo mengartikan nama itu secara khusus |

Skrip `Disabled` disimpan lewat `Nama.meta.json` → `{"properties":{"Disabled":true}}`
(terverifikasi di Rojo 7.7: meta bernama `Nama.server.meta.json` dan properti `Enabled` diabaikan diam-diam).

## Peta Rojo (partially managed)
- Service dan folder campuran → `$className` tanpa `$path` → Rojo **tidak menghapus** isi lain.
- Hanya skrip/folder-skrip bersih yang diberi `$path`.
- Rojo memasangkan skrip yang sudah ada di Studio lewat Nama+ClassName (plugin `hydrate.lua`) dan
  hanya membandingkan properti yang disebut di file (`diff.lua`) → tidak ada skrip dobel, properti lain utuh.

`verify` membuktikan semua itu terhadap `rojo build` sebelum kamu menekan Connect.
