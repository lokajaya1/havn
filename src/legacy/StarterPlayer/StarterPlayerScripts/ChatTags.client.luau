-- ═══════════════════════════════════════════════════════════
-- CHAT TAGS — LocalScript
-- Location: StarterPlayer > StarterPlayerScripts > ChatTags
-- ═══════════════════════════════════════════════════════════

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local NO_TAG = { Member=true, Guest=true }

local function colorToHex(c)
	return string.format("%02X%02X%02X",
		math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
end

TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	if not message.TextSource then return props end
	local p = Players:GetPlayerByUserId(message.TextSource.UserId)
	if not p then return props end

	local roleKey     = p:GetAttribute("Role")
	local roleDisplay = p:GetAttribute("RoleDisplay")
	local roleColor   = p:GetAttribute("RoleColor")

	if not roleKey or NO_TAG[roleKey] then return props end
	if not roleDisplay or roleDisplay=="" then return props end

	local hex = roleColor and colorToHex(roleColor) or "FFFFFF"
	props.PrefixText = string.format(
		"<font color='#%s'>[%s]</font> %s", hex, roleDisplay, message.PrefixText)
	return props
end

print("✅ [CLIENT] Chat Tags - Ready!")