-- ReplicatedStorage.TopbarCover — tombol topbar disembunyikan sementara selama tertutup panel yang terbuka
-- (mis. 🌐 & "/" di baris kedua portrait saat panel Menu terbuka), lalu muncul lagi setelah panel ditutup.
-- Deteksi = overlap nyata (GetGuiObjectsAtPosition di tengah tombol, pola sprintSystem), dipicu _G.PanelCoordinator
-- dan dicek ringan tiap `EVERY` detik selama ada panel aktif. Hanya properti Visible yang diubah, dan hanya
-- kalau modul ini sendiri yang menyembunyikannya (tombol yang disembunyikan skrip lain tidak dimunculkan).
local Players = game:GetService("Players")

local TopbarCover = {}

local COVER_MIN = 120 -- sisi terkecil objek penutup (panel), tombol topbar 42 px tidak dihitung
local EVERY = 0.25

local function solid(obj)
	if obj:IsA("GuiButton") then
		return true
	elseif obj.BackgroundTransparency < 0.95 then
		return true
	elseif obj:IsA("ImageLabel") and obj.Image ~= "" and obj.ImageTransparency < 0.95 then
		return true
	end
	return false
end

-- true kalau titik tengah tombol tertutup objek besar yang tampak (bukan tombol itu / isinya).
function TopbarCover.covered(btn, playerGui)
	local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return false
	end
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
	end)
	if not ok or type(objects) ~= "table" then
		return false
	end
	for _, obj in objects do
		if obj ~= btn and not obj:IsDescendantOf(btn) and obj.Visible then
			local sz = obj.AbsoluteSize
			if sz.X >= COVER_MIN and sz.Y >= COVER_MIN and solid(obj) then
				return true
			end
		end
	end
	return false
end

-- Pantau satu tombol. ownPanel = nama panel milik tombol itu sendiri di PanelCoordinator (tidak disembunyikan
-- oleh panelnya sendiri), boleh nil.
function TopbarCover.watch(btn, ownPanel)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hiddenByUs = false
	local active = nil
	local function refresh()
		if not btn.Parent then
			return
		end
		local panelOpen = active ~= nil and active ~= ownPanel
		-- sudah disembunyikan → tetap sampai panel ditutup (tombol tersembunyi tidak diukur ulang, tanpa kedip)
		local cover = panelOpen and (hiddenByUs or TopbarCover.covered(btn, playerGui))
		if cover and btn.Visible then
			hiddenByUs = true
			btn.Visible = false
		elseif not cover and hiddenByUs then
			hiddenByUs = false
			btn.Visible = true
		end
	end
	task.spawn(function()
		local deadline = os.clock() + 10
		while not (_G.PanelCoordinator and _G.PanelCoordinator.OnChange) and os.clock() < deadline do
			task.wait(0.1)
		end
		local coord = _G.PanelCoordinator
		if coord and coord.OnChange then
			coord.OnChange(function(name)
				active = name
				refresh()
				task.delay(0.05, refresh) -- setelah panel selesai layout / animasi
				task.delay(0.3, refresh)
			end)
		end
		while btn.Parent do
			task.wait(EVERY)
			if active ~= nil or hiddenByUs then
				refresh()
			end
		end
	end)
end

return TopbarCover
