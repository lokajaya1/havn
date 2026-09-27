-- DanceShared — ReplicatedStorage > Modules
-- Setelan & helper yang dipakai bersama DanceHandler dan SyncCommand, supaya
-- cara memuat, mengenali, dan menghentikan track dance hanya ada di satu tempat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DanceAssets = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)

local DanceShared = {}

-- Nama dance → id animasi (sumber: DanceAssets, dicek tools/checks/dances).
DanceShared.dances = DanceAssets.dances

-- WalkSpeed saat menari / setelah berhenti. CarrySystemHandler masih punya
-- salinan angka yang sama (ruangan Carry belum direnovasi).
DanceShared.WALKSPEED = {
	dance   = 6,
	default = 16,
}

function DanceShared.assetUri(id)
	return "rbxassetid://" .. tostring(id)
end

function DanceShared.isDanceName(name)
	return name ~= nil and DanceShared.dances[name] ~= nil
end

-- Humanoid & Animator karakter pemain (nil kalau belum lengkap).
function DanceShared.getRig(player)
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	local animator  = humanoid and humanoid:FindFirstChildOfClass("Animator")
	return humanoid, animator
end

-- Track yang sedang main, dari Humanoid atau Animator.
-- (Humanoid:GetPlayingAnimationTracks sudah usang; yang dipakai milik Animator.)
function DanceShared.playingTracks(rigPart)
	local animator = rigPart
	if rigPart and rigPart.ClassName ~= "Animator" then
		animator = rigPart:FindFirstChildOfClass("Animator")
	end
	if not animator then return {} end
	return animator:GetPlayingAnimationTracks()
end

-- Track dance yang benar-benar sedang main (IsPlaying).
function DanceShared.playingDanceTracks(rigPart)
	local list = {}
	for _, track in ipairs(DanceShared.playingTracks(rigPart)) do
		local animation = track.Animation
		if track.IsPlaying and animation and DanceShared.dances[animation.Name] then
			list[#list + 1] = track
		end
	end
	return list
end

-- Id animasi dance (angka sebagai string) → true. Dipakai isDanceTrack.
local danceIds = {}
for _, id in pairs(DanceShared.dances) do
	danceIds[tostring(id)] = true
end

-- Track ini dance dari DanceAssets? Nama Animation dicek dulu; di client nama
-- track milik server belum tentu terbawa, jadi id animasi juga dicek.
function DanceShared.isDanceTrack(track)
	local animation = track and track.Animation
	if not animation then return false end
	if DanceShared.dances[animation.Name] then return true end
	local id = string.match(animation.AnimationId or "", "%d+")
	return id ~= nil and danceIds[id] == true
end

-- WalkSpeed yang benar untuk pemain saat ini (menari / sync = lambat).
function DanceShared.walkSpeedFor(player)
	if player and (player:GetAttribute("IsDancing") or player:GetAttribute("IsSyncing")) then
		return DanceShared.WALKSPEED.dance
	end
	return DanceShared.WALKSPEED.default
end

-- Hentikan semua track dance kecuali `except`.
function DanceShared.stopDanceTracks(rigPart, except, fade)
	for _, track in ipairs(DanceShared.playingTracks(rigPart)) do
		local animation = track.Animation
		if track ~= except and animation and DanceShared.dances[animation.Name] then
			pcall(function() track:Stop(fade) end)
		end
	end
end

-- LoadAnimation satu dance: prioritas Action4, looped. nil kalau gagal.
function DanceShared.loadTrack(animator, danceName)
	local animationId = DanceShared.dances[danceName]
	if not animationId then return nil end

	local animation       = Instance.new("Animation")
	animation.Name        = danceName
	animation.AnimationId = DanceShared.assetUri(animationId)

	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok or not track then return nil end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true
	return track
end

-- RemoteEvent di ReplicatedStorage (dibuat kalau belum ada).
function DanceShared.remote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote then return remote end
	remote        = Instance.new("RemoteEvent")
	remote.Name   = name
	remote.Parent = ReplicatedStorage
	return remote
end

return DanceShared
