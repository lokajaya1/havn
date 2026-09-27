--!strict
-- Beri izin "Use" banyak aset sekaligus ke satu experience (Universe) lewat Open Cloud.
--   ROBLOX_API_KEY=... lune run tools/assets/grant <universeId> <file-id> [file-id ...]
-- File id: satu angka per baris (atau dipisah koma/spasi). Baris diawali "#" diabaikan.
--
-- API resmi: PATCH https://apis.roblox.com/asset-permissions-api/v1/assets/permissions
--   body: { subjectType = "Universe", subjectId = "<universeId>", action = "Use", requests = { { assetId = n } ... } }
--   respons: { successAssetIds = {...}, errors = { { assetId, code } ... } }
--   scope API key: asset-permissions:write · batas 100 request/menit per pemilik key.
-- Tipe yang didukung: Animation, Audio, Decal, Image, Mesh, MeshPart, Model, Video (TexturePack TIDAK).
-- Izin experience TIDAK bisa dicabut — jalankan hanya untuk aset milik sendiri/grup sendiri.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local BATCH = 50
local PAUSE = tonumber(process.env.HAVN_GRANT_PAUSE or "") or 0.8 -- detik antar request (≈75/menit, di bawah batas 100)
local URL = process.env.HAVN_ASSET_PERMISSIONS_URL or "https://apis.roblox.com/asset-permissions-api/v1/assets/permissions"

local key = process.env.ROBLOX_API_KEY
local universeId = process.args[1]
if not key or key == "" or not universeId or not tonumber(universeId) or #process.args < 2 then
	print("Pakai: ROBLOX_API_KEY=... lune run tools/assets/grant <universeId> <file-id> [file-id ...]")
	process.exit(1)
end
assert(key and universeId)

local ids: { number } = {}
local seen: { [number]: boolean } = {}
for i = 2, #process.args do
	for line in string.gmatch(fs.readFile(process.args[i]), "[^\n]+") do
		if not string.match(line, "^%s*#") then
			for num in string.gmatch(line, "%d+") do
				local n = tonumber(num) :: number
				if n >= 1000 and not seen[n] then
					seen[n] = true
					table.insert(ids, n)
				end
			end
		end
	end
end
print(`Universe {universeId} · {#ids} aset unik · {math.ceil(#ids / BATCH)} batch`)

local ok: { number } = {}
local failed: { [string]: { number } } = {}
local function addFail(code: string, id: number)
	failed[code] = failed[code] or {}
	table.insert(failed[code], id)
end

for start = 1, #ids, BATCH do
	local requests = {}
	for i = start, math.min(start + BATCH - 1, #ids) do
		table.insert(requests, { assetId = ids[i] })
	end
	local body = serde.encode("json", {
		subjectType = "Universe",
		subjectId = universeId,
		action = "Use",
		requests = requests,
	})
	local res
	for attempt = 1, 6 do
		-- [FIX retry] koneksi putus / timeout → coba lagi, bukan berhenti
		local okReq, r = pcall(net.request, {
			url = URL,
			method = "PATCH",
			headers = { ["x-api-key"] = key, ["content-type"] = "application/json" },
			body = body,
		})
		if okReq then
			res = r
			if res.statusCode ~= 429 and res.statusCode ~= 408 and res.statusCode < 500 then
				break
			end
		else
			print(`  koneksi gagal (percobaan {attempt}/6): {r}`)
			res = { statusCode = 0, body = tostring(r) }
		end
		task.wait(5 * attempt)
	end
	if res.statusCode == 200 then
		local data = serde.decode("json", res.body)
		for _, id in data.successAssetIds or {} do
			table.insert(ok, id)
		end
		for _, e in data.errors or {} do
			addFail(tostring(e.code), e.assetId)
		end
	else
		print(`Batch {start}: HTTP {res.statusCode} {string.sub(res.body, 1, 200)}`)
		if res.statusCode == 401 or res.statusCode == 403 then
			print("GAGAL: API key tidak berhak (cek scope asset-permissions:write dan akses ke experience).")
			process.exit(1)
		end
		for _, r in requests do
			addFail(`HTTP{res.statusCode}`, r.assetId)
		end
	end
	print(`  batch {math.ceil(start / BATCH)}: sukses total {#ok}`)
	task.wait(PAUSE)
end

local lines = { `# Laporan izin aset · universe {universeId}`, `sukses: {#ok}` }
for code, list in failed do
	table.insert(lines, `{code}: {#list}`)
end
for code, list in failed do
	local s = {}
	for _, id in list do
		table.insert(s, tostring(id))
	end
	table.insert(lines, "")
	table.insert(lines, `## {code}`)
	table.insert(lines, table.concat(s, ","))
end
fs.writeDir("tools/assets/out")
fs.writeFile("tools/assets/out/grant_report.md", table.concat(lines, "\n") .. "\n")
print(table.concat(lines, "\n", 1, 2))
for code, list in failed do
	print(`{code}: {#list}`)
end
print("Laporan lengkap: tools/assets/out/grant_report.md")
