-- ═══════════════════════════════════════════════════════════
-- MenuBinder — menyambungkan tombol PlayerMenuGui ke manager-nya
-- Path: ReplicatedStorage.CustomUIModules.MenuBinder
--
-- MenuBinder TIDAK menggambar apa pun. Visual PlayerMenu dibuat
-- MenuSystemInit, visual carry dibuat CarryUI. Di sini murni wiring.
-- Baris statistik ("# connections # followers") disembunyikan: remote
-- GetPlayerStats tidak punya server lagi dan Roblox tidak punya API follower
-- (ruangan SOCIAL K7, claude/Rencana_Social.md). Baris "Hide avatar" menjadi
-- "Show avatar" kalau pemain yang dibuka sedang disembunyikan.
-- ═══════════════════════════════════════════════════════════

local RS = game:GetService("ReplicatedStorage")

local modules = RS:WaitForChild("CustomUIModules")

local UIManager          = require(modules:WaitForChild("UIManager"))
local CarryUI            = require(modules:WaitForChild("CarryUI"))
local CarryManager       = require(modules:WaitForChild("CarryManager"))
local SyncManager        = require(modules:WaitForChild("SyncManager"))
local ViewProfileManager = require(modules:WaitForChild("ViewProfileManager"))
local AddFriendManager   = require(modules:WaitForChild("AddFriendManager"))
local PrivateChatManager = require(modules:WaitForChild("PrivateChatManager"))

-- Modul opsional: FindFirstChild dulu, baru pcall(require). Kalau di-index
-- pakai titik dan modulnya tidak ada, error terjadi saat argumen dievaluasi
-- (sebelum pcall jalan) dan seluruh file ini gagal dimuat.
local function optionalRequire(name: string)
	local mod = modules:FindFirstChild(name)
	if not mod then return nil end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[MenuBinder] Gagal require " .. name .. ":", result)
		return nil
	end
	return result
end

local ShowAvatarModule  = optionalRequire("ShowAvatarModule")
local HideAvatarManager = optionalRequire("HideAvatarManager")

-- ── State ───────────────────────────────────────────────────

local MenuBinder     = {}
local currentPlayer  = nil
local hideDebounce   = false
local bound          = false

local connections: { RBXScriptConnection } = {}

-- ── Utility ─────────────────────────────────────────────────

local function find(root, path)
	local cur = root
	for seg in path:gmatch("[^%.]+") do
		cur = cur and cur:FindFirstChild(seg)
	end
	return cur
end

local function setText(el, text)
	if el and el:IsA("TextLabel") then el.Text = text end
end

local function isValid(plr)
	return plr ~= nil and plr:IsA("Player") and plr.Parent ~= nil
end

local function track(conn)
	table.insert(connections, conn)
end

-- ── Update player info ──────────────────────────────────────

local function updatePlayerInfo(target)
	if not isValid(target) then return end

	local gui = UIManager.Get("PlayerMenu")
	if not gui then return end

	local profile = find(gui, "MenuFrame.ScrollFrame.ScrollContent.ProfileSection")
	if not profile then return end

	local container = profile:FindFirstChild("TextContainer") or profile

	local display = target.DisplayName
	if not display or display == "" then display = target.Name end

	setText(container:FindFirstChild("PlayerName"), display)
	setText(container:FindFirstChild("PlayerUsername"), "@" .. target.Name)

	local stats = container:FindFirstChild("StatsLabel")
	if stats and stats:IsA("GuiObject") then stats.Visible = false end

	local hideRow = find(gui, "MenuFrame.ScrollFrame.ScrollContent.ButtonsSection.ButtonsFrame.Choose_HideAvatar.Container.TextLabel")
	if HideAvatarManager and HideAvatarManager.IsAvatarHidden then
		setText(hideRow, HideAvatarManager:IsAvatarHidden(target) and "Show avatar" or "Hide avatar")
	end

	local avatar = profile:FindFirstChild("CharacterViewport")
	if avatar and avatar:IsA("ImageLabel") and ShowAvatarModule then
		ShowAvatarModule:ShowCharacter(target, avatar)
	end
end

-- ── Wire Player Menu ────────────────────────────────────────
-- Hover TIDAK di-wire di sini. MenuSystemInit sudah punya hover sendiri
-- (CARD_HOVER + bar accent + stroke transparency); kalau ditimpa lagi dari
-- sini, dua tween saling adu dan stroke baris ikut hilang permanen.

local function wirePlayerMenu()
	local gui = UIManager.Get("PlayerMenu")
	if not gui then
		warn("[MenuBinder] PlayerMenuGui tidak ditemukan")
		return false
	end

	local path = "MenuFrame.ScrollFrame.ScrollContent.ButtonsSection.ButtonsFrame"
	local btns = find(gui, path)

	-- MenuSystemInit bisa belum selesai build saat BindAll dipanggil.
	local deadline = os.clock() + 5
	while not btns and os.clock() < deadline do
		task.wait(0.1)
		btns = find(gui, path)
	end

	if not btns then
		warn("[MenuBinder] ButtonsFrame tidak ditemukan di PlayerMenuGui")
		return false
	end

	local actions = {
		Choose_Carry = function()
			if not isValid(currentPlayer) then return end
			local target = currentPlayer
			UIManager.Hide("PlayerMenu")
			CarryUI.ShowSelect(CarryManager:GetCarryTypes(), function(carryTitle)
				if isValid(target) then
					CarryManager:SendCarryRequest(target, carryTitle)
				end
			end)
		end,
		Choose_StopCarry = function()
			CarryManager:StopCarry()
			UIManager.Hide("PlayerMenu")
		end,
		Choose_AddFriend = function()
			if not isValid(currentPlayer) then return end
			local s = AddFriendManager:GetFriendshipStatus(currentPlayer)
			if s and s.isFriend then
				AddFriendManager:SendNotification("Already Friends!", s.message, 4)
			else
				AddFriendManager:SendFriendRequest(currentPlayer)
			end
			UIManager.Hide("PlayerMenu")
		end,
		Choose_PrivateChat = function()
			if not isValid(currentPlayer) then return end
			PrivateChatManager:OpenPrivateChat(currentPlayer)
			UIManager.Hide("PlayerMenu")
		end,
		Choose_ViewProfile = function()
			if not isValid(currentPlayer) then return end
			ViewProfileManager:ViewProfile(currentPlayer)
			UIManager.Hide("PlayerMenu")
		end,
		Choose_Sync = function()
			if not isValid(currentPlayer) then return end
			SyncManager:StartSync(currentPlayer)
			UIManager.Hide("PlayerMenu")
		end,
		Choose_HideAvatar = function()
			if hideDebounce or not isValid(currentPlayer) or not HideAvatarManager then return end
			hideDebounce = true
			pcall(HideAvatarManager.HideAvatar, HideAvatarManager, currentPlayer)
			task.delay(0.5, function() hideDebounce = false end)
			UIManager.Hide("PlayerMenu")
		end,
	}

	local count = 0
	for name, action in pairs(actions) do
		local btn = btns:FindFirstChild(name)
		if btn and btn:IsA("GuiButton") then
			track(btn.Activated:Connect(action))
			count += 1
		else
			warn("[MenuBinder] Tombol tidak ditemukan:", name)
		end
	end

	local close = find(gui, "MenuFrame.CloseButton")
	if close and close:IsA("GuiButton") then
		track(close.Activated:Connect(function() UIManager.Hide("PlayerMenu") end))
	end

	return count >= 1
end

-- ── Public API ──────────────────────────────────────────────

function MenuBinder.BindAll()
	if bound then return true end

	for _, mgr in ipairs({ AddFriendManager, ViewProfileManager, PrivateChatManager }) do
		if mgr.Init then pcall(mgr.Init, mgr) end
	end

	if not UIManager.IsReady() then
		local ready = false
		UIManager.OnReady(function() ready = true end)
		local deadline = os.clock() + 30
		while not ready and os.clock() < deadline do task.wait(0.1) end
		if not ready then
			warn("[MenuBinder] UIManager timeout")
			return false
		end
	end

	if bound then return true end

	bound = wirePlayerMenu()
	if not bound then warn("[MenuBinder] BindAll gagal — tombol kartu pemain tidak tersambung") end
	return bound
end

function MenuBinder.SetMenuPlayer(target)
	if not isValid(target) then
		currentPlayer = nil
		UIManager.Hide("PlayerMenu")
		return false
	end

	CarryUI.HideSelect()

	currentPlayer = target
	UIManager.SetTargetPlayer(target)
	updatePlayerInfo(target)
	UIManager.Show("PlayerMenu")
	return true
end

function MenuBinder.GetMenuPlayer()
	return currentPlayer
end

function MenuBinder.Unbind()
	for _, conn in ipairs(connections) do conn:Disconnect() end
	table.clear(connections)
	currentPlayer = nil
	bound = false
end

return MenuBinder