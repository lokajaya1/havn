-- AnimationWarmup — ReplicatedStorage > Modules
-- Memanaskan cache asset animasi dengan cara yang benar-benar bekerja:
-- LoadAnimation pada Animator boneka, tunggu sampai Length > 0, lalu Destroy.
--
-- ContentProvider:PreloadAsync tidak dipakai karena tidak memanaskan animasi.
-- Modul ini dipakai server maupun client, jadi logikanya hanya ada satu tempat.

local RunService = game:GetService("RunService")

local CONFIG = {
	BATCH   = 4,    -- animasi yang dipanaskan sekaligus
	DELAY   = 0.06, -- jeda antar batch supaya frame tidak tersendat
	TIMEOUT = 2.5,  -- batas tunggu per batch kalau asset gagal/lambat
}

local AnimationWarmup = {}

local queue   = {}
local cursor  = 1
local queued  = {}
local failed  = {}   -- asset yang tidak pernah selesai dimuat: jangan diulang
local done    = {}   -- asset yang sudah panas: cache asset tetap ada, jangan diulang
local running = false
local animator

local function toAssetUri(id)
	if type(id) == "string" then
		return (id:find("://", 1, true) and id) or ("rbxassetid://" .. id)
	end
	return "rbxassetid://" .. tostring(id)
end

local function getAnimator()
	if animator and animator.Parent and animator.Parent.Parent then
		return animator
	end

	local controller = Instance.new("AnimationController")
	controller.Name = RunService:IsServer() and "AnimationWarmupServer" or "AnimationWarmupClient"

	animator = Instance.new("Animator")
	animator.Parent = controller
	controller.Parent = workspace
	return animator
end

local function releaseAnimator()
	if animator and animator.Parent then
		animator.Parent:Destroy()
	end
	animator = nil
end

-- Load + Play dengan weight & speed 0: tidak terlihat, tapi memaksa data
-- keyframe benar-benar diminta.
local function beginLoad(id)
	local animation = Instance.new("Animation")
	animation.AnimationId = toAssetUri(id)

	local ok, track = pcall(function()
		return getAnimator():LoadAnimation(animation)
	end)
	animation:Destroy()

	if not ok or not track then return nil end
	pcall(function() track:Play(0, 0, 0) end)
	return track
end

local function finish(track)
	pcall(function()
		track:Stop(0)
		track:Destroy()
	end)
end

local function drain()
	running = true

	while cursor <= #queue do
		local batch = {}
		for _ = 1, CONFIG.BATCH do
			local id = queue[cursor]
			if not id then break end
			cursor += 1
			queued[id] = nil

			local track = beginLoad(id)
			if track then batch[#batch + 1] = { id = id, track = track } end
		end

		local deadline = os.clock() + CONFIG.TIMEOUT
		while os.clock() < deadline do
			local pending = false
			for _, entry in ipairs(batch) do
				if entry.track.Length == 0 then
					pending = true
					break
				end
			end
			if not pending then break end
			task.wait()
		end

		for _, entry in ipairs(batch) do
			if entry.track.Length > 0 then done[entry.id] = true end
			if entry.track.Length == 0 and not failed[entry.id] then
				failed[entry.id] = true
				warn("[AnimationWarmup] asset gagal dimuat, dilewati: " .. tostring(entry.id))
			end
			finish(entry.track)
		end
		task.wait(CONFIG.DELAY)
	end

	queue, cursor = {}, 1
	running = false
	releaseAnimator()
end

-- ids: array asset id (angka atau string).
-- urgent: taruh di depan antrean, dipakai saat pemain benar-benar menekan dance.
function AnimationWarmup.add(ids, urgent)
	for _, id in ipairs(ids) do
		if id ~= nil and not queued[id] and not failed[id] and not done[id] then
			queued[id] = true
			if urgent then
				table.insert(queue, cursor, id)
			else
				queue[#queue + 1] = id
			end
		end
	end

	if not running and cursor <= #queue then
		task.spawn(drain)
	end
end

-- Panaskan sekumpulan nama saja. Memanaskan seluruh koleksi (ratusan animasi)
-- justru membanjiri asset request, jadi pemanggil yang menentukan daftarnya.
function AnimationWarmup.addByName(map, names, urgent)
	local ids = {}
	for _, name in ipairs(names) do
		local id = map[name]
		if id then ids[#ids + 1] = id end
	end
	AnimationWarmup.add(ids, urgent)
end

function AnimationWarmup.isFailed(id)
	return failed[id] == true
end

return AnimationWarmup