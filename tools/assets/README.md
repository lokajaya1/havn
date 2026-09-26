# tools/assets — izin aset untuk experience

Roblox hanya memuat aset privat (animasi, audio, image/decal, mesh, model, video) di experience yang
**diberi izin**. Experience baru HAVN tidak mewarisi izin experience lama → banyak `access permission`/`could not fetch`.

```bash
ROBLOX_API_KEY=xxxx lune run tools/assets/grant <universeId> tools/assets/legacy_asset_ids.txt tools/assets/extra_asset_ids.txt
```
- `<universeId>`: di Studio → `print(game.GameId)`.
- API key: Creator Hub → Open Cloud → API Keys → buat key milik akun yang **mengelola** aset & experience,
  tambahkan API **Asset Permissions** dengan operasi **write** (scope `asset-permissions:write`).
- Hasil: `tools/assets/out/grant_report.md` (sukses + id gagal per kode).
  - `CannotManageAsset`: aset milik orang lain → minta izin pemiliknya atau ganti aset.
  - `AssetTypeNotEnabled`: tipe tidak didukung (mis. TexturePack) → ganti cara (lihat Handoff).
  - `PublicAssetCannotBeGrantedTo`: aset publik, tidak perlu izin.
- Izin experience **tidak bisa dicabut**. Rate limit 100 request/menit (tool menjeda otomatis).

Sumber: skema resmi `Roblox/creator-docs` → `reference/cloud/asset-permissions-api/v1.json`
(PATCH /asset-permissions-api/v1/assets/permissions, subjectType Universe, action Use).
`legacy_asset_ids.txt` = daftar 1.100 aset dari skrip lama `AssetPermissionGran` (skrip itu memanggil
`AssetService:GrantAssetPermission` yang tidak ada di API Roblox, jadi tidak pernah berhasil).
