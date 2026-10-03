-- Money Gun Client | LocalScript → Tool/Money Gun
local Players = game:GetService("Players")
local Tool    = script.Parent
local Remote  = Tool:WaitForChild("RemoteEvent")
local mouse   = Players.LocalPlayer:GetMouse()

local AUTO_DURATION = 3
local function mode() return _G.MoneyGunMode   or "auto"               end
local function cfg()  return _G.MoneyGunConfig or { rate=50, burst=12 } end

local firing     = false
local equipped   = false
local autoThread = nil

local function stopSpray()
	if not firing then return end
	firing = false
	if autoThread then task.cancel(autoThread); autoThread = nil end
	Remote:FireServer("stop")
end

local function startSpray()
	if not equipped or firing then return end
	firing = true
	Remote:FireServer("start", cfg().rate)
end

-- Hold: Button1Down/Up agar spray aktif selama tombol ditahan
mouse.Button1Down:Connect(function()
	if not equipped or mode() ~= "hold" then return end
	startSpray()
end)
mouse.Button1Up:Connect(function()
	if mode() == "hold" then stopSpray() end
end)

-- Burst & Auto: Activated (fired on click complete)
Tool.Activated:Connect(function()
	local m = mode()
	if m == "burst" then
		Remote:FireServer("burst", cfg().burst)
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

-- Guard edge-case drag keluar window saat hold
Tool.Deactivated:Connect(function()
	if mode() == "hold" then stopSpray() end
end)

Tool.Equipped:Connect(function()   equipped = true  end)
Tool.Unequipped:Connect(function() equipped = false; stopSpray() end)