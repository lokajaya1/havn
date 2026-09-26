local RS = game:GetService("ReplicatedStorage")

local function ensureRemote(className, name)
	local inst = RS:FindFirstChild(name)
	if not inst then inst = Instance.new(className); inst.Name = name; inst.Parent = RS end
	return inst
end

local requestGiant = ensureRemote("RemoteFunction", "RequestGiantAvatar")
local activateGiant = ensureRemote("RemoteFunction", "ActivateGiantAvatar")

requestGiant.OnServerInvoke = function() return nil end
activateGiant.OnServerInvoke = function() return true end