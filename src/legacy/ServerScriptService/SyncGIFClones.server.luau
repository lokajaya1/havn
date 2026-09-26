-- ============================================
-- SyncGIFClones (ServerScriptService)
-- Sinkronisasi layar GIF_Animation2 dengan GIF_Animation utama
-- ============================================

local workspace = game:GetService("Workspace")

-- Layar utama
local mainModel = workspace:WaitForChild("GIF_Animation", 15)
if not mainModel then warn("❌ SyncGIFClones: GIF_Animation tidak ditemukan!") return end
local mainPart = mainModel:WaitForChild("GIF_Part", 10)
if not mainPart then warn("❌ SyncGIFClones: GIF_Part tidak ditemukan!") return end
local mainGui = mainPart:FindFirstChildOfClass("SurfaceGui") or mainPart:WaitForChild("SurfaceGui", 10)
if not mainGui then warn("❌ SyncGIFClones: SurfaceGui tidak ditemukan di GIF_Part!") return end
local mainText = mainGui:WaitForChild("TextDisplay", 10)
local mainSender = mainGui:WaitForChild("SenderDisplay", 10)

-- Layar clone
local cloneModel = workspace:WaitForChild("GIF_Animation2", 15)
if not cloneModel then warn("❌ SyncGIFClones: GIF_Animation2 tidak ditemukan!") return end
local clonePart = cloneModel:WaitForChild("GIF_Part2", 10)
if not clonePart then warn("❌ SyncGIFClones: GIF_Part2 tidak ditemukan!") return end
local cloneGui = clonePart:FindFirstChildOfClass("SurfaceGui") or clonePart:WaitForChild("SurfaceGui2", 10)
if not cloneGui then warn("❌ SyncGIFClones: SurfaceGui2 tidak ditemukan di GIF_Part2!") return end
local cloneText = cloneGui:WaitForChild("TextDisplay2", 10)
local cloneSender = cloneGui:WaitForChild("SenderDisplay2", 10)

if not mainText or not mainSender or not cloneText or not cloneSender then
	warn("❌ SyncGIFClones: TextDisplay/SenderDisplay tidak lengkap!")
	return
end

-- Sync terus menerus
task.spawn(function()
	while task.wait(0.1) do
		cloneText.Text = mainText.Text
		cloneSender.Text = mainSender.Text
	end
end)

print("✅ SyncGIFClones loaded!")