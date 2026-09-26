local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MusicRequest = ReplicatedStorage:WaitForChild("MusicRequest")
local StarterGui = game:GetService("StarterGui")

local module = {}

function module.Create(parent, sound)
	local eqFrame = Instance.new("Frame")
	eqFrame.Name = "EqualizerFrame"
	-- Ukuran dan posisi proporsional untuk panel playlist mobile
	eqFrame.Size = UDim2.new(0.60, 0, 0, 130)
	eqFrame.Position = UDim2.new(0.42, 0, 0, 165)
	eqFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	eqFrame.BorderSizePixel = 0
	eqFrame.ZIndex = 10
	eqFrame.Parent = parent

	local eqCorner = Instance.new("UICorner")
	eqCorner.CornerRadius = UDim.new(0, 8)
	eqCorner.Parent = eqFrame

	local eqStroke = Instance.new("UIStroke")
	eqStroke.Thickness = 1
	eqStroke.Color = Color3.fromRGB(255, 255, 255)
	eqStroke.Transparency = 0.1
	eqStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	eqStroke.Parent = eqFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 10)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "Equalizer"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = false
	title.TextSize = 8
	title.Font = Enum.Font.GothamBold
	title.ZIndex = 21
	title.Parent = eqFrame

	local sliders = {
		{label = "Pitch (Octave)", property = "Octave", min = 0.5, max = 2.0, effect = "PitchEffect", y = 16, step = 0.01, default = 1},
		{label = "Bass", property = "LowGain", min = -80, max = 200, effect = "EQEffect", y = 36, step = 1, default = 0},
		{label = "Mid", property = "MidGain", min = -80, max = 200, effect = "EQEffect", y = 56, step = 1, default = 0},
		{label = "Treble", property = "HighGain", min = -80, max = 200, effect = "EQEffect", y = 76, step = 1, default = 0},
		{label = "Speed", property = "PlaybackSpeed", min = 0.5, max = 2.0, effect = "GlobalMusic", y = 96, step = 0.01, default = 1},
	}

	local hasPermission = false

	local function updateProperty(effectName, prop, value)
		MusicRequest:FireServer("UpdateEQ", {
			effect = effectName,
			property = prop,
			value = value
		})
	end

	local sliderRefs = {}

	for _, s in ipairs(sliders) do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.22, 0, 0, 14)
		label.Position = UDim2.new(0.02, 0, 0, s.y)
		label.BackgroundTransparency = 1
		label.Text = s.label
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = false
		label.TextSize = 8
		label.Font = Enum.Font.GothamBold
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 23
		label.Parent = eqFrame

		local sliderBG = Instance.new("Frame")
		sliderBG.Size = UDim2.new(0.60, 0, 0, 10)
		sliderBG.Position = UDim2.new(0.30, 0, 0, s.y+2)
		sliderBG.BackgroundColor3 = Color3.fromRGB(32,32,64)
		sliderBG.BorderSizePixel = 0
		sliderBG.ZIndex = 24
		sliderBG.Parent = eqFrame
		local sliderCorner = Instance.new("UICorner")
		sliderCorner.CornerRadius = UDim.new(0,3)
		sliderCorner.Parent = sliderBG

		local initVal = s.default
		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 12, 0, 12)
		local function getKnobOffset(pct)
			return math.floor((sliderBG.AbsoluteSize.X - 12) * pct)
		end
		knob.Position = UDim2.new(0, getKnobOffset((initVal-s.min)/(s.max-s.min)), 0.5, -6)
		knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		knob.ZIndex = 25
		knob.Parent = sliderBG
		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(1,0)
		knobCorner.Parent = knob

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0.13, 0, 0, 10)
		valueLabel.Position = UDim2.new(0.87, 0, 0, s.y+1)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = tostring(initVal)
		valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		valueLabel.TextScaled = false
		valueLabel.TextSize = 9
		valueLabel.Font = Enum.Font.Gotham
		valueLabel.ZIndex = 23
		valueLabel.Parent = eqFrame

		sliderRefs[s.effect .. "_" .. s.property] = {
			knob = knob,
			label = valueLabel,
			config = s
		}

		local dragging = false
		local UserInputService = game:GetService("UserInputService")

		local function updateFromMouse(mouseX)
			local barPos = sliderBG.AbsolutePosition.X
			local barSize = sliderBG.AbsoluteSize.X
			local pct = math.clamp((mouseX - barPos)/barSize,0,1)
			local val = s.min + pct*(s.max-s.min)
			if s.step == 1 then val = math.floor(val) end

			updateProperty(s.effect, s.property, val)

			local knobOffset = math.floor((barSize - 12) * pct)
			knob.Position = UDim2.new(0, knobOffset, 0.5, -6)
			valueLabel.Text = tostring(math.floor(val*100)/100)
		end

		local function showNoPermission()
			StarterGui:SetCore("SendNotification", {
				Title = "Equalizer",
				Text = "You don't have permission",
				Duration = 3
			})
		end

		knob.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not hasPermission then
					showNoPermission()
					return
				end
				dragging = true
				if input.UserInputType == Enum.UserInputType.Touch then
					updateFromMouse(input.Position.X)
				end
			end
		end)

		knob.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)

		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)

		sliderBG.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not hasPermission then
					showNoPermission()
					return
				end
				dragging = true
				updateFromMouse(input.Position.X)
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				updateFromMouse(input.Position.X)
			end
		end)
	end

	MusicRequest.OnClientEvent:Connect(function(action, data)
		if action == "EQUpdate" and data then
			local key = data.effect .. "_" .. data.property
			local ref = sliderRefs[key]
			if ref then
				local s = ref.config
				local pct = (data.value - s.min) / (s.max - s.min)
				ref.knob.Position = UDim2.new(pct, -8, 0.5, -8)
				ref.label.Text = tostring(math.floor(data.value*100)/100)
			end
		elseif action == "EQSync" and data then
			for key, value in pairs(data) do
				local ref = sliderRefs[key]
				if ref then
					local s = ref.config
					local pct = (value - s.min) / (s.max - s.min)
					ref.knob.Position = UDim2.new(pct, -8, 0.5, -8)
					ref.label.Text = tostring(math.floor(value*100)/100)
				end
			end
		elseif action == "EQPermission" and data then
			hasPermission = data.allowed
		end
	end)

	return eqFrame
end

return module