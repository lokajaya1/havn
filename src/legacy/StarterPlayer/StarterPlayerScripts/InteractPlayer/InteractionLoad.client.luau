-- ═══════════════════════════════════════════════════════════
-- InteractionLoad — bootstrap: deteksi klik/tap pemain + init sistem
-- Path: StarterPlayer > StarterPlayerScripts (LocalScript)
-- ═══════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RS               = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local modules = RS:WaitForChild("CustomUIModules", 10)
if not modules then
	warn("[Interact] CustomUIModules tidak ditemukan")
	return
end

local function safeRequire(name)
	local mod = modules:FindFirstChild(name)
	if not mod then
		warn("[Interact] Modul tidak ada:", name)
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[Interact] Gagal require " .. name .. ":", result)
		return nil
	end
	return result
end

-- CarryUI di-require lebih dulu supaya GUI carry sudah ada sebelum
-- UIManager.Init() mencari "CarrySelectGui".
safeRequire("CarryUI")

local UIManager    = safeRequire("UIManager")
local MenuBinder   = safeRequire("MenuBinder")
local CarryManager = safeRequire("CarryManager")
local SyncManager  = safeRequire("SyncManager")

-- ════════════════════════════════════════════════════════════
-- INIT
-- ════════════════════════════════════════════════════════════

local ready = false

local function initializeSystem()
	if CarryManager then pcall(CarryManager.Initialize, CarryManager) end
	if SyncManager  then pcall(SyncManager.Initialize,  SyncManager)  end

	if not (UIManager and MenuBinder) then
		warn("[Interact] UIManager / MenuBinder tidak tersedia")
		return false
	end

	if not UIManager.IsReady() then
		pcall(UIManager.Init)
	end

	local ok, result = pcall(MenuBinder.BindAll)
	ready = ok and result == true
	return ready
end

-- ════════════════════════════════════════════════════════════
-- DETEKSI PEMAIN
-- ════════════════════════════════════════════════════════════

local function getPlayerFromPart(part)
	if not part then return nil end

	local current = part
	for _ = 1, 15 do
		if not current or current == workspace then break end
		if current:FindFirstChildOfClass("Humanoid") then
			return Players:GetPlayerFromCharacter(current)
		end
		current = current.Parent
	end
	return nil
end

local function getTargetFromPosition(pos)
	local cam = workspace.CurrentCamera
	if not cam then return nil end

	local ray = cam:ScreenPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1500, params)
	return result and result.Instance or nil
end

-- ════════════════════════════════════════════════════════════
-- KLIK / TAP
-- ════════════════════════════════════════════════════════════

local MENU_FRAMES = {
	PlayerMenu   = "MenuFrame",
	CarrySelect  = "CarrySelectFrame",
}

local function isClickInsideMenu(pos)
	if not (UIManager and UIManager.Get) then return false end

	for guiName, frameName in pairs(MENU_FRAMES) do
		local gui = UIManager.Get(guiName)
		local frame = gui and gui.Enabled and gui:FindFirstChild(frameName)
		if frame and frame.Visible then
			local fp, fs = frame.AbsolutePosition, frame.AbsoluteSize
			if pos.X >= fp.X and pos.X <= fp.X + fs.X
				and pos.Y >= fp.Y and pos.Y <= fp.Y + fs.Y then
				return true
			end
		end
	end
	return false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	local target, inputPos

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = player:GetMouse()
		target   = mouse.Target
		inputPos = Vector2.new(mouse.X, mouse.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		target   = getTargetFromPosition(input.Position)
		inputPos = Vector2.new(input.Position.X, input.Position.Y)
	else
		return
	end

	if isClickInsideMenu(inputPos) then return end

	local targetPlayer = getPlayerFromPart(target)

	if targetPlayer and targetPlayer ~= player and MenuBinder then
		MenuBinder.SetMenuPlayer(targetPlayer)
	elseif UIManager and UIManager.HideAll then
		UIManager.HideAll()
	end
end)

-- ════════════════════════════════════════════════════════════
-- RESPAWN
-- ════════════════════════════════════════════════════════════

player.CharacterAdded:Connect(function()
	if UIManager then
		UIManager.SetTargetPlayer(nil)
		UIManager.HideAll()
	end
	if CarryManager then
		CarryManager:OnCharacterRespawned()
	end
	if not ready then
		task.wait(2)
		initializeSystem()
	end
end)

-- ════════════════════════════════════════════════════════════
-- MAIN
-- ════════════════════════════════════════════════════════════

if initializeSystem() then
	print("[Interact] Sistem interaksi siap")
else
	warn("[Interact] Sistem UI belum siap — klik pemain mungkin tidak merespon")
end
