-- Water Gun Client | LocalScript → Tool/WaterGun
-- [TOOLS] Efek semprot diatur server (Serverscript di tool ini) supaya terlihat semua pemain; client hanya mengirim
-- "start" (+ rate panel) / "stop" / "burst" (+ jumlah panel) lewat RemoteEvent tool — pola sama dengan Money Gun.
local Players = game:GetService("Players")
local Tool    = script.Parent
local Remote  = Tool:WaitForChild("RemoteEvent")
local mouse   = Players.LocalPlayer:GetMouse()

local AUTO_DURATION = 3
local function mode() return _G.WaterGunMode   or "auto"                    end
local function cfg()  return _G.WaterGunConfig or { rate = 20, burst = 15 } end

local firing     = false
local equipped   = false
local autoThread = nil

local function stopSpray()
	if not firing then return end
	firing        = false
	if autoThread then task.cancel(autoThread); autoThread = nil end
	Remote:FireServer("stop")
end

local function startSpray()
	if not equipped or firing then return end
	firing        = true
	Remote:FireServer("start", cfg().rate)
end

local function doBurst()
	Remote:FireServer("burst", cfg().burst)
end

-- Hold: pakai Button1Down/Up agar spray aktif selama tombol ditahan
mouse.Button1Down:Connect(function()
	if not equipped or mode() ~= "hold" then return end
	startSpray()
end)
mouse.Button1Up:Connect(function()
	if mode() == "hold" then stopSpray() end
end)

-- Burst & Auto: pakai Activated (fired on click/tap complete)
Tool.Activated:Connect(function()
	local m = mode()
	if m == "burst" then
		doBurst()
	elseif m == "auto" then
		if firing then stopSpray() else
			startSpray()
			autoThread = task.delay(AUTO_DURATION, function()
				autoThread = nil
				stopSpray()
			end)
		end
	end
end)

-- Deactivated hanya relevan untuk hold — tapi hold sudah pakai Button1Up,
-- jadi guard ini cukup untuk edge-case drag keluar window
Tool.Deactivated:Connect(function()
	if mode() == "hold" then stopSpray() end
end)

Tool.Equipped:Connect(function()    equipped = true  end)
Tool.Unequipped:Connect(function()  equipped = false; stopSpray() end)
