-- DanceHandler/State — satu state per pemain (rig, track, favorit, watchdog, kuota).

local DancePlayer = require(script.Parent.Parent.DancePlayer)
local CONFIG      = require(script.Parent.Config)

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local states = {}

local function getState(player)
	local userId = player.UserId
	local s = states[userId]
	if not s then
		s = {
			userId     = userId,
			rig        = nil,   -- { humanoid, animator, character }
			slot       = DancePlayer.newSlot(), -- track yang sedang diputar
			tracks     = {},    -- danceName -> { track, used }
			trackCount = 0,
			clock      = 0,
			dance      = nil,
			speed      = 1.0,
			walkSpeed  = CONFIG.DEFAULT_WALKSPEED,
			favorites  = {},
			dirty      = false,
			-- Perubahan favorit yang dibuat sebelum data lama termuat; digabung
			-- ke data DataStore begitu terbaca (load atau UpdateAsync).
			pendingAdd    = {},
			pendingRemove = {},
			writing       = false,
			watchToken = 0,
			lastRequest = 0,
			requestSeq  = 0,     -- permintaan terakhir yang menang (lihat playDance)
			buckets     = {},
			initialized = false,
		}
		states[userId] = s
	end
	return s
end

return {
	states   = states,
	getState = getState,
}
