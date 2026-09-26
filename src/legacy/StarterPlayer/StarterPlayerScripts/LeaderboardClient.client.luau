-- LEADERBOARD CLIENT
-- StarterPlayer > StarterPlayerScripts (LocalScript)

local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local playerGui    = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

-- ── Remote Setup ────────────────────────────────────────────────────────────
local Remotes = RS:WaitForChild("DonationRemotes", 15)
if not Remotes then
	warn("[Leaderboard] DonationRemotes tidak ditemukan!")
	return
end

local evUpdate = Remotes:WaitForChild("UpdateLeaderboard", 15)
if not evUpdate then
	warn("[Leaderboard] UpdateLeaderboard event tidak ditemukan!")
	return
end

-- ── Helper: Format Rupiah ────────────────────────────────────────────────────
local function fmt(n)
	n = math.floor(n or 0)
	if n >= 1_000_000 then
		return string.format("Rp%.1fJt", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("Rp%.0fRb", n / 1_000)
	end
	return "Rp" .. tostring(n)
end

-- ── Toast Notifikasi ─────────────────────────────────────────────────────────
local function showToast(donorName, amount)
	local old = playerGui:FindFirstChild("LBToast")
	if old then old:Destroy() end

	-- Container
	local sg       = Instance.new("ScreenGui")
	sg.Name         = "LBToast"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 150
	sg.Parent       = playerGui

	-- Frame
	local box                    = Instance.new("Frame")
	box.Size                     = UDim2.new(0, 300, 0, 48)
	box.AnchorPoint              = Vector2.new(0.5, 0)
	box.Position                 = UDim2.new(0.5, 0, 0, -60)
	box.BackgroundColor3         = Color3.fromRGB(10, 10, 8)
	box.BackgroundTransparency   = 0.08
	box.BorderSizePixel          = 0
	box.Parent                   = sg

	local corner         = Instance.new("UICorner")
	corner.CornerRadius  = UDim.new(0, 10)
	corner.Parent        = box

	local stroke         = Instance.new("UIStroke")
	stroke.Color         = Color3.fromRGB(212, 160, 28)
	stroke.Thickness     = 1
	stroke.Parent        = box

	-- Label
	local lbl                    = Instance.new("TextLabel")
	lbl.Size                     = UDim2.new(1, -14, 1, 0)
	lbl.Position                 = UDim2.new(0, 7, 0, 0)
	lbl.BackgroundTransparency   = 1
	lbl.Text                     = "🌟  " .. donorName .. " donasi " .. fmt(amount)
	lbl.TextSize                 = 12
	lbl.Font                     = Enum.Font.GothamSemibold
	lbl.TextColor3               = Color3.fromRGB(212, 160, 28)
	lbl.TextXAlignment           = Enum.TextXAlignment.Left
	lbl.TextTruncate             = Enum.TextTruncate.AtEnd
	lbl.Parent                   = box

	-- Animasi masuk
	TweenService:Create(box,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 14) }
	):Play()

	-- Animasi keluar setelah 4 detik
	task.delay(4, function()
		local tweenOut = TweenService:Create(box,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -70) }
		)
		tweenOut:Play()
		tweenOut.Completed:Connect(function() sg:Destroy() end)
	end)
end

-- ── State Tracking ───────────────────────────────────────────────────────────
local lastDonors = {}

local function getKey(donor)
	return donor.name .. "_" .. tostring(donor.amount)
end

-- ── Event Handler ────────────────────────────────────────────────────────────
evUpdate.OnClientEvent:Connect(function(donors)
	if type(donors) ~= "table" then return end

	-- Deteksi donatur baru atau amount bertambah
	if #lastDonors > 0 then
		for _, donor in ipairs(donors) do
			local isNew = true
			for _, old in ipairs(lastDonors) do
				if getKey(old) == getKey(donor) then
					isNew = false
					break
				end
			end
			if isNew then
				showToast(donor.name, donor.amount)
				break -- Tampilkan satu toast per update
			end
		end
	end

	lastDonors = donors
end)