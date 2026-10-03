-- --GlowStickDualWieldHandler
-- Skrip ini HANYA menangani pembuatan glowstick di tangan kiri.

local tool = script.Parent
local players = game:GetService("Players")

local function getLeftHand(char)
	if char:FindFirstChild("LeftHand") then
		return char.LeftHand -- R15
	elseif char:FindFirstChild("Left Arm") then
		return char["Left Arm"] -- R6
	end
	return nil
end

-- Saat tool di-equip
tool.Equipped:Connect(function()
	local player = players:GetPlayerFromCharacter(tool.Parent)
	if not player then return end

	local character = player.Character
	if not character then return end

	local handle = tool:FindFirstChild("Handle")
	if not handle then return end

	local leftHand = getLeftHand(character)
	if not leftHand then return end

	-- Pastikan tidak ada clone sebelumnya
	if tool:FindFirstChild("LeftHandle") then
		tool.LeftHandle:Destroy()
	end

	-- Clone handle untuk tangan kiri
	local leftClone = handle:Clone()
	leftClone.Name = "LeftHandle"
	leftClone.Parent = tool

	-- Hapus attachment tangan kanan dari clone
	local rightGrip = leftClone:FindFirstChild("RightGripAttachment")
	if rightGrip then
		rightGrip:Destroy()
	end

	-- Gunakan Motor6D agar menempel dan ikut animasi
	local motor = Instance.new("Motor6D")
	motor.Name = "LeftGrip"
	motor.Part0 = leftHand
	motor.Part1 = leftClone
	motor.C0 = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, math.rad(90), 0)
	motor.Parent = leftHand
end)

-- Saat tool dilepas
tool.Unequipped:Connect(function()
	if tool:FindFirstChild("LeftHandle") then
		tool.LeftHandle:Destroy()
	end
end)

