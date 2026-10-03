require(game:GetService("ReplicatedStorage").RagdollService)

local players = game:GetService("Players")
local runService = game:GetService("RunService")

-- ── Jatuh ke void (K7) ─────────────────────────────────────
-- Di bawah workspace.FallenPartsDestroyHeight mesin menghancurkan
-- HumanoidRootPart lalu Humanoid mati. Komponen vendor RagdollOnHumanoidDied
-- memasang ragdoll saat Died tanpa cek HumanoidRootPart → merah di
-- RagdollService character:36. Tag itu dilepas SEBELUM sampai (posisi
-- diprediksi dari kecepatan jatuh) dan dipasang lagi kalau naik kembali.
-- Mati di tempat lain tetap ragdoll seperti biasa (peta terendah ±−126,
-- batas void −500).
local VOID_MARGIN    = 60  -- stud di atas FallenPartsDestroyHeight: tag dilepas
local VOID_RESUME    = 120 -- stud di atas FallenPartsDestroyHeight: tag dipasang lagi
local VOID_LOOKAHEAD = 0.5 -- detik prediksi jatuh

local watched = {} -- [Humanoid] = { root = BasePart, off = boolean }

local function predictedY(root: BasePart): number
	return root.Position.Y + math.min(root.AssemblyLinearVelocity.Y, 0) * VOID_LOOKAHEAD
end

runService.Heartbeat:Connect(function()
	local floor = workspace.FallenPartsDestroyHeight
	for hum, w in watched do
		if not hum.Parent or hum.Health <= 0 then
			watched[hum] = nil -- sudah mati / karakter diganti: tidak diurus lagi
			continue
		end
		local root = w.root
		if not w.off and (not root.Parent or predictedY(root) < floor + VOID_MARGIN) then
			w.off = true
			hum:RemoveTag("RagdollOnHumanoidDied")
		elseif w.off and root.Parent and predictedY(root) > floor + VOID_RESUME then
			w.off = false
			hum:AddTag("RagdollOnHumanoidDied")
		end
	end
end)

players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(chr)
		local hum = chr:WaitForChild("Humanoid") :: Humanoid

		hum:AddTag("Ragdollable")
		hum:AddTag("RagdollOnHumanoidFall")
		hum:AddTag("RagdollOnHumanoidDied")

		local root = chr:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			watched[hum] = { root = root, off = false }
		end
	end)
end)
