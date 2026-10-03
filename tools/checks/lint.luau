-- tools/checks/lint.luau — jalankan: lune run tools/checks/lint
-- Selene (lihat selene.toml) di dua tingkat:
--   STRICT : kode baru + ruangan yang SUDAH direnovasi. Satu warning/error = gagal.
--   REPORT : sisa src/legacy. Hanya dilaporkan (tidak menggagalkan) sampai ruangannya
--            direnovasi; saat itu pindahkan foldernya ke STRICT.
local process = require("@lune/process")

local NL = string.char(10)

local STRICT = {
	"src/server",
	"src/client",
	"src/mapgen",
	"src/legacy/ServerScriptService/MusicServer",
	"src/legacy/StarterPlayer/StarterPlayerScripts/MusicClient",
	"src/legacy/ReplicatedStorage/MusicShared.luau",
	-- ruangan DANCE
	"src/legacy/ServerScriptService/Misc",
	"src/legacy/ReplicatedStorage/Modules/DanceShared.luau",
	"src/legacy/ReplicatedStorage/Modules/AnimationWarmup.luau",
	"src/legacy/ReplicatedStorage/Config/DanceConfig.luau",
	"src/legacy/StarterPlayer/StarterPlayerScripts/DanceClient.client.luau",
	"src/legacy/ReplicatedStorage/CustomUIModules/SyncManager.luau",
	-- ruangan SHOP
	"src/legacy/ServerScriptService/ShopServer.server.luau",
	"src/legacy/ServerScriptService/ReceiptHandler.luau",
	"src/legacy/ReplicatedStorage/ShopConfig.luau",
	"src/legacy/StarterGui/ShopClient.client.luau",
	-- ruangan ADMIN
	"src/legacy/ServerScriptService/CommandServer.server.luau",
	"src/legacy/StarterGui/CommandPanel.client.luau",
	"src/legacy/ReplicatedStorage/CommandShared.luau",
	"src/legacy/ServerScriptService/AnnouncementHandler.server.luau",
	"src/legacy/StarterPlayer/StarterPlayerScripts/AnnouncementClient.client.luau",
	"src/legacy/ServerScriptService/LiveScreenServer.server.luau",
	-- ruangan DONASI
	"src/legacy/ServerScriptService/DonationServer",
	"src/legacy/ReplicatedStorage/DonationConfig.luau",
	-- ruangan TEMA (themeMap + themeColor)
	"src/legacy/ReplicatedStorage/Config/ThemeMap.luau",
	"src/legacy/ReplicatedStorage/Config/ThemeColor.luau",
	"src/legacy/ReplicatedStorage/Modules/ThemeColor",
	-- ruangan TAS (inventory)
	"src/legacy/ReplicatedStorage/Config/Inventory.luau",
	"src/legacy/ReplicatedStorage/Modules/Inventory.luau",
	"src/legacy/StarterPlayer/StarterPlayerScripts/CustomBackpackUI.client.luau",
	-- ruangan TITLES & RANK
	"src/legacy/ServerScriptService/UnifiedRankManager.server.luau",
	"src/legacy/ServerScriptService/RankRules.luau",
	"src/legacy/ServerScriptService/RankConfig.luau",
	"src/legacy/ServerScriptService/RoleManagerServer.server.luau",
	"src/legacy/StarterGui/RoleManagerClient.client.luau",
	"src/legacy/ServerScriptService/RagDollTag.server.luau",
	-- ruangan WORLD (panggung DJ)
	"src/legacy/ReplicatedStorage/Config/DjStage.luau",
	"src/legacy/ReplicatedStorage/Modules/DjStageRules.luau",
	-- ruangan TOOLS
	"src/legacy/ReplicatedStorage/Config/Tools.luau",
	"src/legacy/ReplicatedStorage/Modules/ToolRules.luau",
	"src/legacy/ServerScriptService/GlowStickServer.server.luau",
	"src/legacy/ServerScriptService/FlyingbroomServer.server.luau",
	"src/legacy/ServerScriptService/ToolGiver.server.luau",
	"src/legacy/StarterPack/GlowStick",
	"src/legacy/StarterPack/Sign",
	"src/legacy/ServerStorage/MoneyGun",
	"src/legacy/ServerStorage/WaterGun",
	"src/legacy/ServerStorage/FlyingBroom",
	"src/legacy/StarterGui/GlowStickUI.client.luau",
	"src/legacy/StarterGui/MoneyGunUI.client.luau",
	"src/legacy/StarterGui/WaterGunUI.client.luau",
	"src/legacy/StarterGui/Flyingbroomui.client.luau",
}
local REPORT = { "src/legacy" }

local function selene(paths)
	local args = { "--display-style", "quiet", "--no-summary" }
	for _, p in paths do
		table.insert(args, p)
	end
	local r = process.exec("selene", args)
	local out = (r.stdout or "") .. (r.stderr or "")
	local issues = {}
	for l in string.gmatch(out, "[^" .. NL .. "]+") do
		if string.find(l, "warning%[") or string.find(l, "error%[") or string.find(l, "ERROR") then
			table.insert(issues, l)
		end
	end
	return issues
end

local strictSet = {}
local strict = selene(STRICT)
for _, l in strict do
	strictSet[l] = true
end

local report = {}
for _, l in selene(REPORT) do
	if not strictSet[l] then
		local path = string.match(l, "^([^:]+):")
		local inStrict = false
		for _, s in STRICT do
			if path and string.sub(path, 1, #s) == s then
				inStrict = true
			end
		end
		if not inStrict then
			table.insert(report, l)
		end
	end
end

local counts = {}
for _, l in report do
	local kind = string.match(l, "(%a+%[[%w_]+%])") or "lain"
	counts[kind] = (counts[kind] or 0) + 1
end
local kinds = {}
for k, n in counts do
	table.insert(kinds, ("%s x%d"):format(k, n))
end
table.sort(kinds)
print(("LAPORAN legacy (belum direnovasi, tidak menggagalkan): %d temuan"):format(#report))
for _, k in kinds do
	print("  " .. k)
end

if #strict > 0 then
	print("")
	print(("GAGAL: %d temuan di kode STRICT:"):format(#strict))
	for _, l in strict do
		print("  " .. l)
	end
	process.exit(1)
end
print("")
print("OK: kode STRICT bersih (selene)")
