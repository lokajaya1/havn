--!strict
-- ServerScriptService/DjStage/Rules (ModuleScript) — aturan MURNI efek DJ STAGE (ruangan WORLD, claude/Rencana_World.md).
-- Tanpa GetService / Instance / yield. Isinya sama dengan logika di VJScript lama, dipisah supaya bisa dites.

local Rules = {}

-- Layar VJ dianggap AKTIF kalau attribute "On" bernilai true, DAN (kalau ScreenMode dipakai & ketemu)
-- nilai ScreenMode sama dengan mode aktif. ScreenMode tidak ketemu → hanya attribute "On" yang menentukan.
function Rules.isActive(on: any, useScreenMode: boolean, hasScreenMode: boolean, mode: string?, activeMode: string): boolean
	if on ~= true then
		return false
	end
	if useScreenMode and hasScreenMode then
		return mode == activeMode
	end
	return true
end

-- Ukuran & posisi media (skala X) sesuai mirror: lebar NEGATIF membalik gambar, lalu posisi digeser 1
-- supaya gambar tetap pas menutupi layar. Hasil: sizeX, posX (Y selalu 1 & 0).
function Rules.mediaLayout(mirror: boolean): (number, number)
	if mirror then
		return -1, 1
	end
	return 1, 0
end

-- Jenis media yang dikenal (huruf besar). nil = salah tulis di Config.
function Rules.mediaType(value: string): string?
	local t = string.upper(value)
	if t == "GIF" or t == "VIDEO" or t == "IMAGE" then
		return t
	end
	return nil
end

-- Pisahkan segmen jalur: "Interact*" → ("Interact", true) = semua anak bernama itu; "Animate" → ("Animate", false).
function Rules.segment(seg: string): (string, boolean)
	if string.sub(seg, -1) == "*" then
		return string.sub(seg, 1, -2), true
	end
	return seg, false
end

return Rules
