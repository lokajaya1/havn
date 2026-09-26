--!strict
-- Migrasi DataStore HAVN lama → [NEW] HAVN.
-- Pemakaian:
--   lune run tools/migrate/copy                 uji kering: baca semua, hitung rencana, TIDAK menulis
--   lune run tools/migrate/copy --limit=20      uji kering cepat (20 kunci per aturan)
--   lune run tools/migrate/copy --apply         tulis ke universe baru (rules.target) saja
--   opsi: --only=shop,likes   --interval=0.25
-- Key dari env ROBLOX_API_KEY (tidak pernah dicetak / disimpan).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Copy = require("./lib/copy")
local Http = require("./lib/http")
local rules = require("./rules")

local OUT_DIR = "tools/migrate/out"

local base = "https://apis.roblox.com"
local override = process.env.ROBLOX_API_BASE
if override and override ~= "" then
	assert(string.match(override, "^http://127%.0%.0%.1:%d+$"), "ROBLOX_API_BASE hanya boleh http://127.0.0.1:<port>")
	base = override
end

local key = process.env.ROBLOX_API_KEY
if not key or key == "" then
	print('ROBLOX_API_KEY kosong. Jalankan dulu:  read -s "ROBLOX_API_KEY?API key: "  lalu  export ROBLOX_API_KEY')
	process.exit(1)
end

local apply, limit, only, interval = false, nil, nil, 0.25
for _, a in process.args do
	local v = string.match(a, "^%-%-limit=(%d+)$")
	local o = string.match(a, "^%-%-only=(.+)$")
	local iv = string.match(a, "^%-%-interval=([%d%.]+)$")
	if a == "--apply" then
		apply = true
	elseif v then
		limit = tonumber(v)
	elseif o then
		local set: { [string]: boolean } = {}
		for n in string.gmatch(o, "[^,]+") do
			set[n] = true
		end
		only = set
	elseif iv then
		interval = math.max(0.2, tonumber(iv) or 0.25)
	else
		print("Argumen tidak dikenal: " .. a)
		process.exit(1)
	end
end

if not fs.isDir(OUT_DIR) then
	fs.writeDir(OUT_DIR)
end

local stamp = os.date("!%Y%m%dT%H%M%SZ") :: string
local report = Copy.run({
	http = Http.new(base, key :: string, interval),
	rules = rules,
	source = rules.source,
	target = rules.target,
	apply = apply,
	only = only,
	limit = limit,
	outDir = OUT_DIR,
	stamp = stamp,
	log = print,
})
local text = Copy.summary(report)
print(text)
local path = OUT_DIR .. "/copy_" .. (if apply then "apply_" else "dry_") .. stamp .. ".json"
fs.writeFile(path, serde.encode("json", report, true))
print("Laporan: " .. path)
if report.backupFile then
	print("Cadangan nilai target sebelum digabung: " .. report.backupFile)
end
if not apply then
	print("UJI KERING: tidak ada yang ditulis ke Roblox.")
end
