
-- Version 2.29

local module = {}

function module.Init()
	print("ListQueue_Dekstop Module Loaded!")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local MusicRequest = ReplicatedStorage:WaitForChild("MusicRequest")
	local MusicNotify = ReplicatedStorage:WaitForChild("MusicNotify")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MusicNotifyGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local notifyFrame = Instance.new("Frame")
	notifyFrame.AnchorPoint = Vector2.new(0.5, 0)
	notifyFrame.Position = UDim2.new(0.5, 0, 0, -50)
	notifyFrame.Size = UDim2.new(0, 350, 0, 50)
	notifyFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	notifyFrame.BackgroundTransparency = 0.7
	notifyFrame.Visible = false
	notifyFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = notifyFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ""
	label.Parent = notifyFrame

	local musicPanel = playerGui:WaitForChild("MusicPlayerGui"):WaitForChild("MusicPanel")
	local queueContainer = Instance.new("Frame")
	queueContainer.Name = "QueueContainer"
	queueContainer.Size = UDim2.new(0.33, -8, 0, 240)
	queueContainer.Position = UDim2.new(0.63, 40, 0, 120) 

	local queueTitle = Instance.new("TextLabel")
	queueTitle.Name = "QueueListTitle"
	queueTitle.Size = UDim2.new(1, 0, 0, 28)
	queueTitle.Position = UDim2.new(0, 0, 0, -28)
	queueTitle.BackgroundTransparency = 1
	queueTitle.Text = "QUEUE LIST"
	queueTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	queueTitle.TextSize = 18
	queueTitle.Font = Enum.Font.GothamBold
	queueTitle.TextXAlignment = Enum.TextXAlignment.Center
	queueTitle.ZIndex = 8
	queueTitle.Parent = queueContainer
	queueContainer.BackgroundTransparency = 1
	queueContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	queueContainer.ZIndex = 5
	queueContainer.Parent = musicPanel

	local queueCorner = Instance.new("UICorner")
	queueCorner.CornerRadius = UDim.new(0, 8)
	queueCorner.Parent = queueContainer

	local queueStroke = Instance.new("UIStroke")
	queueStroke.Thickness = 2
	queueStroke.Color = Color3.fromRGB(255, 255, 255)
	queueStroke.Transparency = 0.1
	queueStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	queueStroke.Parent = queueContainer

	local queueScroll = Instance.new("ScrollingFrame")
	queueScroll.Size = UDim2.new(1, -10, 1, -10)
	queueScroll.Position = UDim2.new(0, 5, 0, 5)
	queueScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	queueScroll.ScrollBarThickness = 6
	queueScroll.BackgroundTransparency = 1
	queueScroll.ZIndex = 7
	queueScroll.Parent = queueContainer

	local qLayout = Instance.new("UIListLayout")
	qLayout.SortOrder = Enum.SortOrder.LayoutOrder
	qLayout.Padding = UDim.new(0, 8)
	qLayout.Parent = queueScroll

	qLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		queueScroll.CanvasSize = UDim2.new(0, 0, 0, qLayout.AbsoluteContentSize.Y)
	end)

	local function updateQueue(list)
		for _, v in ipairs(queueScroll:GetChildren()) do
			if v:IsA("TextLabel") then
				print("Updating queue with "..#list.." songs")
				v:Destroy()
			end
		end

		for i, track in ipairs(list) do
			local lbl = Instance.new("TextLabel")
			lbl.Name = "Song_"..i
			lbl.Size = UDim2.new(1, 0, 0, 28)
			lbl.BackgroundTransparency = 0
			lbl.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			lbl.Text = ("%d. %s [%s]"):format(track.position, track.Name or "Unknown", track.Requester.Name or "Unknown")
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.Font = Enum.Font.GothamBold
			lbl.TextSize = 16
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextWrapped = true
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 10)
			pad.PaddingRight = UDim.new(0, 10)
			pad.PaddingTop = UDim.new(0, 4)
			pad.PaddingBottom = UDim.new(0, 4)
			pad.Parent = lbl
			local lblCorner = Instance.new("UICorner")
			lblCorner.CornerRadius = UDim.new(0, 8)
			lblCorner.Parent = lbl
			local lblStroke = Instance.new("UIStroke")
			lblStroke.Thickness = 2
			lblStroke.Color = Color3.fromRGB(255, 255, 255)
			lblStroke.Transparency = 0.1
			lblStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			lblStroke.Parent = lbl
			lbl.Parent = queueScroll

			task.wait()
			local textHeight = math.max(lbl.TextBounds.Y + 6, 30)
			lbl.Size = UDim2.new(1, 0, 0, textHeight)
		end
	end

	local function showNotification(text)
		label.Text = text
		notifyFrame.Visible = true
		local tweenIn = TweenService:Create(notifyFrame, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, 20) })
		tweenIn:Play()
		tweenIn.Completed:Wait()

		task.wait(3)

		local tweenOut = TweenService:Create(notifyFrame, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -50) })
		tweenOut:Play()
		tweenOut.Completed:Wait()

		notifyFrame.Visible = false
	end

	local lastQueueUpdate = 0

	MusicRequest.OnClientEvent:Connect(function(action, data)
		if action == "QueueUpdate" then
			if tick() - lastQueueUpdate < 0.1 then return end 
			lastQueueUpdate = tick()
			updateQueue(data)
		elseif action == "NowPlaying" then
			print("Now Playing: " .. data.Name)
		elseif action == "SongError" then
			showNotification(data)
		end
	end)


	MusicNotify.OnClientEvent:Connect(function(username, songName, position)
		showNotification(string.format("%s added %s in queue position %d", username, songName, position))
	end)

end

return module
