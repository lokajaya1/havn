--!strict
-- ReplicatedStorage/Config/Inventory (ModuleScript) — tas / inventory HAVN (claude/Rencana_Inventory.md).
-- Semua angka yang boleh diubah ada di sini. Logika: ReplicatedStorage.Modules.Inventory. UI: StarterPlayerScripts.CustomBackpackUI.

local Inventory = {}

-- ── hotbar ─────────────────────────────────────────────────────────────────────────────────────────────────────────
Inventory.slotsMax = 10 -- desktop / tablet: tombol 1–9, 0 (sama dengan backpack Roblox)
Inventory.slotsPhoneMin = 3 -- HP: slot sebanyak yang muat di tengah layar, 3…6
Inventory.slotsPhoneMax = 6
Inventory.phoneSide = 0.22 -- HP: 22% kiri & kanan layar dicadangkan untuk thumbstick & tombol lompat Roblox
Inventory.slot = 52 -- px sisi slot (HP: slotPhone)
Inventory.slotPhone = 46
Inventory.gap = 6 -- px antar slot
Inventory.bottom = 12 -- px hotbar dari bawah layar
Inventory.hideH = 14 -- px tombol sembunyikan (˅) di bawah ikon tas
Inventory.equipGlow = { base = 0, amp = 0.25, speed = 90, period = 2.4 } -- garis tepi bergerak slot yang dipakai

-- ── jendela inventory ──────────────────────────────────────────────────────────────────────────────────────────────
Inventory.cell = 76 -- px lebar kartu tool
Inventory.cellH = 84 -- px tinggi kartu tool
Inventory.cellGap = 8
Inventory.columnsMax = 6 -- desktop; HP: columnsMaxPhone
Inventory.columnsMaxPhone = 4
Inventory.rowsVisible = 3 -- baris kartu yang terlihat sebelum digulir (HP: rowsVisiblePhone)
Inventory.rowsVisiblePhone = 2

-- ── input ──────────────────────────────────────────────────────────────────────────────────────────────────────────
Inventory.toggleKeys = { "Backquote" } -- nama Enum.KeyCode: ` (kiri angka 1, Mac & Windows) seperti Roblox
Inventory.dragThreshold = 6 -- px gerak mouse sebelum kartu/slot dianggap diseret
Inventory.touchHoldDrag = 0.35 -- dtk tekan-tahan sebelum seret di layar sentuh (gerak lebih cepat = gulir)
Inventory.respawnHold = 15 -- dtk slot tetap dipesan untuk tool yang hilang sementara (mati / respawn)

return Inventory
