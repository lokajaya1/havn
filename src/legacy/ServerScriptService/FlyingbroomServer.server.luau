-- BroomEffectServer | Script → ServerScriptService
-- Efek sapu (partikel + lampu) dari client Flying Broom → diterapkan di server supaya terlihat semua pemain.
-- v2: Hapus warning spam "Flying Broom tidak ada di karakter"
--     (normal terjadi saat stopFly dipanggil tepat saat unequip)
-- [TOOLS] action wajib "effect" + batas terima per pemain + jeda terapkan (keadaan terakhir selalu diterapkan).
-- Angka: ReplicatedStorage.Config.Tools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Cfg = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Tools"))
local ToolRules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolRules"))

-- ── Buat RemoteEvent ──────────────────────────────────────
local BroomEffectSync = Instance.new("RemoteEvent")
BroomEffectSync.Name = "BroomEffectSync"
BroomEffectSync.Parent = ReplicatedStorage

-- ── Apply ke semua descendants tool ──────────────────────
local function applyToTool(tool, enabled, color)
	for _, obj in ipairs(tool:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			obj.Enabled = enabled
			if color then
				obj.Color = ColorSequence.new(color)
			end
		elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
			obj.Enabled = enabled
			if color then
				obj.Color = color
			end
		end
	end
end

-- Dipanggil lewat gate: cari tool di karakter SAAT diterapkan.
local function applyPlayer(player, state)
	local char = player.Parent and player.Character
	if not char then
		return
	end
	local tool = char:FindFirstChild(Cfg.BROOM.TOOL_NAME)
	if not tool then
		-- Ini normal: bisa terjadi saat stopFly() tepat bersamaan dengan unequip — silent return
		return
	end
	-- Update di server → auto-replicate ke semua client
	applyToTool(tool, state.enabled, state.color)
end

local buckets = {}
local gates = {}

-- ── Handler ───────────────────────────────────────────────
BroomEffectSync.OnServerEvent:Connect(function(player, action, enabled, color)
	-- Validasi tipe
	if action ~= "effect" then
		return
	end
	if typeof(enabled) ~= "boolean" then
		return
	end
	if color ~= nil and not ToolRules.isColor(color) then
		return
	end

	local bucket = buckets[player]
	if not bucket then
		bucket = ToolRules.bucket(Cfg.RECEIVE.RATE, Cfg.RECEIVE.BURST)
		buckets[player] = bucket
	end
	if not ToolRules.take(bucket, os.clock()) then
		return
	end
	local push = gates[player]
	if not push then
		push = ToolRules.gate(Cfg.BROOM.APPLY_EVERY, function(state)
			applyPlayer(player, state)
		end, os.clock, task.delay)
		gates[player] = push
	end
	push({ enabled = enabled, color = color })
end)

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	gates[player] = nil
end)
