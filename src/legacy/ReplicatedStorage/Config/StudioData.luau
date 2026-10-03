--!strict
-- ReplicatedStorage/Config/StudioData (ModuleScript) — aturan data saat Play di Studio
-- (ruangan DATA-STUDIO, claude/Rencana_DataStudio.md).
--
-- DataStore & topik MessagingService yang dipakai Studio = universe LIVE yang sama
-- (dok resmi data stores "Enable Studio access"). Karena itu Play di Studio memakai
-- nama + SUFFIX. Di server live nama tetap PERSIS; kunci & format data tidak berubah,
-- tanpa migrasi. Data ber-akhiran SUFFIX mulai kosong.
--
-- MemoryStore TIDAK perlu akhiran: data MemoryStore Studio sudah dipisah Roblox dari
-- production (dok resmi memory stores "Test and debug in Studio").
--
-- Pengecualian yang DISENGAJA (Studio hanya MEMBACA live, tidak pernah menulis):
--   * papan donasi      : DonationConfig.store.studioReadsLive (PlayerDonations_v1)
--   * library musik     : MusicServer/Library — MusicLibrary_studio yang belum punya
--                         GlobalLib memakai isi MusicLibrary live sebagai salinan awal
--
-- Murni: tanpa GetService / Instance / yield. Pemanggil membaca RunService:IsStudio()
-- sekali di atas filenya lalu memberikannya ke sini.

local StudioData = {}

StudioData.SUFFIX = "_studio"

-- Akhiran untuk sesi ini: SUFFIX di Studio, "" di server live.
function StudioData.suffix(isStudio: boolean): string
	assert(type(isStudio) == "boolean", "StudioData: isStudio harus boolean (RunService:IsStudio())")
	return if isStudio then StudioData.SUFFIX else ""
end

-- Nama store / topik untuk sesi ini. Server live = base PERSIS.
function StudioData.name(base: string, isStudio: boolean): string
	assert(type(base) == "string" and base ~= "", "StudioData: nama store/topik kosong")
	return base .. StudioData.suffix(isStudio)
end

return StudioData
