-- tools/checks/dances.luau — jalankan: lune run tools/checks/dances
-- Memeriksa daftar dance (DanceAssets) sebelum masuk ke game:
--   • id animasi harus angka bulat positif dan tidak kembar
--     (dua nama dengan id sama membuat pengecekan "dance masih jalan" salah)
--   • nama tidak boleh kembar beda huruf besar/kecil
--     (SmoothDanceManager mencari nama tanpa membedakan kapital → dance salah diputar)
--   • semua nama di poseNames & POPULAR_DANCES (DanceHandler) harus ada
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ASSETS = "src/legacy/ReplicatedStorage/Assets/Animations/Dances/DanceAssets.luau"
local HANDLER = "src/legacy/ServerScriptService/Misc/DanceHandler.server.luau"

local DanceAssets = luau.load(fs.readFile(ASSETS), { debugName = "DanceAssets" })()
local dances = DanceAssets.dances

local errors = {}
local function bad(msg) table.insert(errors, msg) end

local count, byId, byLower = 0, {}, {}
for name, id in dances do
	count += 1
	if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
		bad(("id tidak valid: %s = %s"):format(name, tostring(id)))
	else
		local key = tostring(id)
		if byId[key] then bad(("id kembar %s: %s & %s"):format(key, byId[key], name)) end
		byId[key] = name
	end
	local low = string.lower(name)
	if byLower[low] then bad(("nama kembar beda kapital: %s & %s"):format(byLower[low], name)) end
	byLower[low] = name
end

for _, name in DanceAssets.poseNames or {} do
	if not dances[name] then bad("poseNames berisi nama yang tidak ada: " .. name) end
end

local handler = fs.readFile(HANDLER)
local block = string.match(handler, "POPULAR_DANCES%s*=%s*(%b{})")
if not block then
	bad("POPULAR_DANCES tidak ditemukan di " .. HANDLER)
else
	for name in string.gmatch(block, '"([^"]+)"') do
		if not dances[name] then bad("POPULAR_DANCES berisi nama yang tidak ada: " .. name) end
	end
end

print(("DanceAssets: %d dance, %d pose"):format(count, #(DanceAssets.poseNames or {})))
if #errors > 0 then
	for _, e in errors do print("GAGAL " .. e) end
	process.exit(1)
end
print("OK: daftar dance bersih")
