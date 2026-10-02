local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = script.Parent -- GendongGUI
local uiScale = screenGui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", screenGui)

-- resolusi dasar
local baseX, baseY = 1280, 720

-- fungsi update scale
local function updateScale()
	local screenSize = workspace.CurrentCamera.ViewportSize
	local scaleX = screenSize.X / baseX
	local scaleY = screenSize.Y / baseY
	local scale = math.min(scaleX, scaleY)

	-- logika scaling
	if scale < 0.5 then
		-- layar sangat kecil (HP kecil) → perbesar agar tidak terlalu kecil
		uiScale.Scale = scale * 1.4
	elseif scale < 0.8 then
		-- layar kecil-sedang (HP biasa) → tingkatkan sedikit
		uiScale.Scale = scale * 1.2
	elseif scale < 1 then
		-- layar mendekati base → scaling minimal
		uiScale.Scale = scale * 1.05
	elseif scale > 1 then
		-- layar lebih besar dari base → PERKECIL
		uiScale.Scale = scale * 0.85
	else
		-- tepat di ukuran base
		uiScale.Scale = 1
	end
end

-- panggil pertama kali
updateScale()

-- update ketika layar berubah ukuran (rotate hp, resize window, dll)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)