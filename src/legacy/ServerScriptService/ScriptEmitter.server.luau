-- StageParticleServer Script
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StageEvent = ReplicatedStorage:WaitForChild("StageEvent")

-- ⚙️ CONFIG
local config = {
	AudioFadeOutTime = 0.8,      -- lama fade out audio
	AutoTriggerEnabled = true,   -- aktifkan / matikan auto trigger
	AutoTriggerInterval = 30,    -- setiap berapa detik otomatis nyala
	AutoTriggerDuration = 3,     -- berapa detik emitter nyala
}

-- 🔊 Fade out helper
local function fadeOutSound(sound, fadeTime)
	if not sound or not sound:IsA("Sound") or not sound.IsPlaying then return end
	local tween = TweenService:Create(
		sound,
		TweenInfo.new(fadeTime or config.AudioFadeOutTime, Enum.EasingStyle.Linear),
		{Volume = 0}
	)
	tween:Play()
	tween.Completed:Wait()
	sound:Stop()
end

-- 🔥 Aktif/nonaktif emitter + sound berdasarkan tag
local function setEmitterAndSoundEnabled(tagName, state)
	for _, emitter in ipairs(CollectionService:GetTagged(tagName)) do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = state

			local part = emitter.Parent
			if part and part:IsA("BasePart") then
				local soundName = (tagName == "Smoke") and "White" or tagName
				local sound = part:FindFirstChild(soundName)

				if sound and sound:IsA("Sound") then
					if state then
						if not sound.IsPlaying then
							sound.Volume = 1
							sound.TimePosition = 0
							sound:Play()
						end
					else
						task.spawn(function()
							fadeOutSound(sound, config.AudioFadeOutTime)
						end)
					end
				end
			end
		end
	end
end

-- 🌈 Aktifkan semua tag sekaligus
local function setAll(state)
	setEmitterAndSoundEnabled("Fire", state)
	setEmitterAndSoundEnabled("Smoke", state)
	setEmitterAndSoundEnabled("Confetti", state)
end

-- 📡 Terima sinyal dari client
StageEvent.OnServerEvent:Connect(function(player, tag, state)
	if tag == "All" then
		setAll(state)
	else
		setEmitterAndSoundEnabled(tag, state)
	end
end)

-- 🕒 AUTO TRIGGER SYSTEM (server-side, agar semua player lihat)
if config.AutoTriggerEnabled then
	task.spawn(function()
		while true do
			task.wait(config.AutoTriggerInterval)
			setAll(true)
			task.wait(config.AutoTriggerDuration)
			setAll(false)
		end
	end)
end
