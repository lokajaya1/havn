
-- Version 2.29

local module = {}

function module.Init()
	print("ListQueue_Mobile Module Loaded!")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local MusicRequest = ReplicatedStorage:WaitForChild("MusicRequest")
	local MusicNotify = ReplicatedStorage:WaitForChild("MusicNotify")

	-- GUI Notifikasi
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MusicNotifyGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local notifyFrame = Instance.new("Frame")
	notifyFrame.AnchorPoint = Vector2.new(0.5, 0)
	notifyFrame.Position = UDim2.new(0.5, 0, 0, -50)
	notifyFrame.Size = UDim2.new(0, 350, 0, 50)
	notifyFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	notifyFrame.BackgroundTransparency = 0.2
	notifyFrame.Visible = false
	notifyFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = notifyFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ""
	label.Parent = notifyFrame


	local musicPanel = playerGui:WaitForChild("MusicPlayerGui"):WaitForChild("MusicPanel")
	-- Cari atau buat panel queue berdampingan (konsisten dengan MusicPlayllist_Mobile)
	local mainPanel = musicPanel:FindFirstChild("MainPanel")
	local queueFrame
	if mainPanel then
		queueFrame = mainPanel:FindFirstChild("QueueFrame")
		if not queueFrame then
			queueFrame = Instance.new("Frame")
			queueFrame.Name = "QueueFrame"
			queueFrame.Size = UDim2.new(0.34, -4, 1, 0)
			queueFrame.BackgroundColor3 = Color3.fromRGB(18,18,50)
			queueFrame.BorderSizePixel = 0
			queueFrame.ZIndex = 6
			queueFrame.Parent = mainPanel
			local queueCorner = Instance.new("UICorner")
			queueCorner.CornerRadius = UDim.new(0, 10)
			queueCorner.Parent = queueFrame
			local queueTitle = Instance.new("TextLabel")
			queueTitle.Name = "QueueTitle"
			queueTitle.Size = UDim2.new(1, 0, 0, 18)
			queueTitle.Position = UDim2.new(0, 0, 0, 0)
			queueTitle.BackgroundTransparency = 1
			queueTitle.Text = "QUEUE"
			queueTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
			queueTitle.TextSize = 12
			queueTitle.Font = Enum.Font.GothamBold
			queueTitle.TextXAlignment = Enum.TextXAlignment.Center
			queueTitle.ZIndex = 8
			queueTitle.Parent = queueFrame
		end
	else
		-- fallback lama jika mainPanel tidak ada
		queueFrame = Instance.new("Frame")
		queueFrame.Name = "QueueFrame"
		queueFrame.Size = UDim2.new(0.5, -4, 0, 110)
		queueFrame.Position = UDim2.new(0.5, 4, 0, 28)
		queueFrame.BackgroundTransparency = 1
		queueFrame.ZIndex = 7
		queueFrame.Parent = musicPanel
	end

	-- Scroll untuk queue
	local queueScroll = queueFrame:FindFirstChild("QueueList")
	if not queueScroll then
		queueScroll = Instance.new("ScrollingFrame")
		queueScroll.Name = mainPanel and "QueueList" or "QueueScroll"
		queueScroll.Size = UDim2.new(1, -6, 1, -22)
		queueScroll.Position = UDim2.new(0, 3, 0, mainPanel and 20 or 6)
		queueScroll.BackgroundTransparency = 1
		queueScroll.ZIndex = 7
		queueScroll.ClipsDescendants = true
		queueScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		queueScroll.ScrollBarThickness = 4
		queueScroll.Parent = queueFrame
	end

	local qLayout = queueScroll:FindFirstChildOfClass("UIListLayout")
	if not qLayout then
		qLayout = Instance.new("UIListLayout")
		qLayout.SortOrder = Enum.SortOrder.LayoutOrder
		qLayout.Padding = UDim.new(0, 4)
		qLayout.Parent = queueScroll
	end
	qLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		queueScroll.CanvasSize = UDim2.new(0, 0, 0, qLayout.AbsoluteContentSize.Y)
	end)

	local function updateQueue(list)
		for _, v in ipairs(queueScroll:GetChildren()) do
			if v:IsA("TextLabel") or v:IsA("Frame") then
				v:Destroy()
			end
		end

		for i, track in ipairs(list) do
			local itemFrame = Instance.new("Frame")
			itemFrame.Name = "QueueItem_"..i
			itemFrame.Size = UDim2.new(1, 0, 0, 18)
			itemFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
			itemFrame.BackgroundTransparency = 0.2
			itemFrame.ZIndex = 8
			itemFrame.Parent = queueScroll

			local lbl = Instance.new("TextLabel")
			lbl.Name = "SongLabel"
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Text = ("%d. %s [%s]"):format(track.position, track.Name or "Unknown", (track.Requester and track.Requester.Name) or "Unknown")
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.Font = Enum.Font.Gotham
			lbl.TextSize = 10
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextYAlignment = Enum.TextYAlignment.Top
			lbl.TextWrapped = false
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.ZIndex = 9
			lbl.Parent = itemFrame

			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 6)
			pad.PaddingRight = UDim.new(0, 6)
			pad.PaddingTop = UDim.new(0, 2)
			pad.PaddingBottom = UDim.new(0, 2)
			pad.Parent = lbl

			local cCorner = Instance.new("UICorner")
			cCorner.CornerRadius = UDim.new(0, 6)
			cCorner.Parent = itemFrame

			-- Garis pemisah tipis bawah
			if i < #list then
				local sep = Instance.new("Frame")
				sep.Size = UDim2.new(1, -12, 0, 1)
				sep.Position = UDim2.new(0, 6, 1, -1)
				sep.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
				sep.BorderSizePixel = 0
				sep.BackgroundTransparency = 0.3
				sep.Parent = itemFrame
			end
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