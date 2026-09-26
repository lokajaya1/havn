-- BroomEffectServer | Script → ServerScriptService
-- v2: Hapus warning spam "Flying Broom tidak ada di karakter"
--     (normal terjadi saat stopFly dipanggil tepat saat unequip)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Buat RemoteEvent ──────────────────────────────────────
local BroomEffectSync = Instance.new("RemoteEvent")
BroomEffectSync.Name   = "BroomEffectSync"
BroomEffectSync.Parent = ReplicatedStorage

-- ── Validasi Color3 ───────────────────────────────────────
local function isValidColor3(v)
	return typeof(v) == "Color3"
		and v.R >= 0 and v.R <= 1
		and v.G >= 0 and v.G <= 1
		and v.B >= 0 and v.B <= 1
end

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
			if color then obj.Color = color end
		end
	end
end

-- ── Handler ───────────────────────────────────────────────
BroomEffectSync.OnServerEvent:Connect(function(player, action, enabled, color)

	-- Validasi tipe
	if type(action) ~= "string" then return end
	if typeof(enabled) ~= "boolean" then return end
	if color ~= nil and not isValidColor3(color) then return end

	-- Cari tool di karakter
	local char = player.Character
	if not char then return end

	local tool = char:FindFirstChild("Flying Broom")
	if not tool then
		-- Ini normal: bisa terjadi saat stopFly() tepat bersamaan dengan unequip
		-- Client sudah guard tool.Parent == player.Character, tapi race condition kecil bisa terjadi
		-- Silent return — tidak perlu warn
		return
	end

	-- Update di server → auto-replicate ke semua client
	applyToTool(tool, enabled, color)
end)

print("[BroomEffectServer] Ready — BroomEffectSync event aktif")