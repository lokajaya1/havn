-- ServerScriptService/DjStage (Script) — panggung DJ Workspace["DJ STAGE"] (ruangan WORLD, claude/Rencana_World.md).
-- Yang MENGGAMBAR (LED, layar utama, layar samping) adalah client StarterPlayerScripts.DjStageClient → server tidak
-- mengirim perubahan frame/warna ke pemain. Server hanya:
--   1. menyiapkan part SEKALI: layar utama & samping transparan + tidak bisa ditabrak, attribute "On" bawaan
--      (Config.LAYAR_SAMPING.START_ON) di layar samping — properti fisik/attribute harus milik server;
--   2. menerima pilihan media dari admin: ReplicatedStorage.DjStageRemotes.SetMedia (RemoteFunction) (layarId, mediaType)
--      → jeda per pemain (dicatat sebelum cek admin), IsAdmin, layar & jenis yang ada di Config, jenis harus sudah diisi,
--      video maks Config.VIDEO_LAYAR_MAX layar → { ok, reason?, wait? }. Pilihan = atribut folder itu: Utama, Samping
--      ("IMAGE" | "GIF" | "VIDEO"), ChangedBy (nama admin). Berlaku di server ini saja; server baru mulai dari MEDIA_TYPE.
-- Config = ReplicatedStorage.Config.DjStage · aturan murni = ReplicatedStorage.Modules.DjStageRules.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Config = require(RS:WaitForChild("Config"):WaitForChild("DjStage"))
local Rules = require(RS:WaitForChild("Modules"):WaitForChild("DjStageRules"))

-- ── remote & pilihan media ───────────────────────────────────────────────────────────────────────────────────
local remotes = RS:FindFirstChild("DjStageRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "DjStageRemotes"
	remotes.Parent = RS
end
local setFn = remotes:FindFirstChild("SetMedia") :: RemoteFunction?
if not setFn then
	local fn = Instance.new("RemoteFunction")
	fn.Name = "SetMedia"
	fn.Parent = remotes
	setFn = fn
end

local current: { [string]: string? } = {}
for _, id in Config.LAYAR_URUTAN do
	local layar = Config.LAYAR[id]
	local start, why = Rules.startType(Config, layar)
	if why then
		warn(("[DjStage] %s: MEDIA_TYPE = %s tidak bisa dipakai (%s) — pakai %s"):format(layar.label, tostring(layar.MEDIA_TYPE), why, tostring(start)))
	end
	current[id] = start
	remotes:SetAttribute(id, start)
end

local lastAsk: { [Player]: number } = {}
local warned: { [Player]: boolean } = {}
;(setFn :: RemoteFunction).OnServerInvoke = function(player: Player, layarId: any, mediaType: any)
	local now = os.clock()
	local res = Rules.decide(Config, {
		admin = player:GetAttribute("IsAdmin") == true,
		last = lastAsk[player],
		now = now,
		current = current,
	}, layarId, mediaType)
	if res.reason ~= "cooldown" then
		lastAsk[player] = now -- semua pemain dibatasi, admin atau bukan
	end
	if res.reason == "admin" and not warned[player] then
		warned[player] = true -- dicatat sekali per pemain (remote bisa di-spam)
		warn("[DjStage] bukan admin mencoba ganti media layar: " .. player.Name)
	end
	if res.ok and res.reason ~= "same" then
		current[layarId] = mediaType
		remotes:SetAttribute(layarId, mediaType)
		remotes:SetAttribute("ChangedBy", player.DisplayName)
		print(("[DjStage] %s → %s (oleh %s)"):format(Config.LAYAR[layarId].label, Config.MEDIA_LABEL[mediaType], player.Name))
	end
	return { ok = res.ok, reason = res.reason, wait = res.wait }
end

Players.PlayerRemoving:Connect(function(player)
	lastAsk[player] = nil
	warned[player] = nil
end)

-- ── siapkan part (sekali) ────────────────────────────────────────────────────────────────────────────────────
-- Semua instance di jalur `path` (segmen "Nama*" = semua anak bernama itu, selain itu anak pertama).
local function collect(root: Instance, path: { string }): { Instance }
	local currentList = { root }
	for _, seg in path do
		local name, all = Rules.segment(seg)
		local found = {}
		for _, inst in currentList do
			if all then
				for _, child in inst:GetChildren() do
					if child.Name == name then
						table.insert(found, child)
					end
				end
			else
				local child = inst:FindFirstChild(name)
				if child then
					table.insert(found, child)
				end
			end
		end
		currentList = found
	end
	return currentList
end

local stage = workspace:WaitForChild(Config.STAGE_NAME, Config.FIND_TIMEOUT)
if not stage then
	warn("[DjStage] Workspace." .. Config.STAGE_NAME .. " tidak ada — efek panggung dilewati")
	return
end

local UTAMA, SAMPING = Config.LAYAR_UTAMA, Config.LAYAR_SAMPING
local nUtama = 0
for _, part in collect(stage, UTAMA.path) do
	if part:IsA("BasePart") then
		nUtama += 1
		if UTAMA.HIDE_PART then
			part.Transparency = 1 -- hanya SurfaceGui yang terlihat
		end
		part.CanCollide = false
	end
end
if nUtama == 0 then
	warn("[DjStage] layar utama tidak ketemu di " .. table.concat(UTAMA.path, "/"))
end

local nSamping = 0
for _, folder in collect(stage, SAMPING.folder) do
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			nSamping += 1
			if SAMPING.HIDE_PART then
				part.Transparency = 1
			end
			part.CanCollide = false
			if part:GetAttribute("On") == nil then
				part:SetAttribute("On", SAMPING.START_ON) -- saklar manual (Studio / skrip lain)
			end
		end
	end
end
if nSamping == 0 then
	warn("[DjStage] layar samping tidak ketemu di " .. table.concat(SAMPING.folder, "/"))
end

print(("[DjStage] ✅ layar utama %d · layar samping %d · media: utama=%s, samping=%s (digambar di client)"):format(
	nUtama,
	nSamping,
	tostring(current.Utama),
	tostring(current.Samping)
))
