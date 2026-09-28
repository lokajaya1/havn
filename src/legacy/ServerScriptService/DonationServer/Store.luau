-- DonationServer.Store — simpan total donasi per pemain, tepat sekali per PurchaseId.
-- DonationData_v1 <uid> = { total = N, r = { purchaseId terakhir } } → sumber kebenaran.
--   Struk yang sama bisa datang lagi / ke server lain: purchaseId dicatat di record YANG SAMA
--   dengan total dalam satu UpdateAsync, jadi total tidak pernah bertambah dua kali.
--   Field lain yang sudah ada di record dipertahankan (format lama { total } tetap terbaca).
-- PlayerDonations_v1 <uid> = total → cermin untuk papan; hanya naik (UpdateAsync max).
local Store = {}
Store.__index = Store

-- Logika murni (tanpa API Roblox): nilai lama → record baru, atau nil kalau struk sudah tercatat.
function Store.apply(old, purchaseId, robux, recent)
	local rec = {}
	if type(old) == "table" then
		for k, v in old do
			rec[k] = v
		end
	elseif type(old) == "number" then
		rec.total = old
	end
	rec.total = tonumber(rec.total) or 0
	local list = {}
	if type(rec.r) == "table" then
		for _, id in rec.r do
			if id == purchaseId then
				return nil, rec.total
			end
			table.insert(list, id)
		end
	end
	table.insert(list, purchaseId)
	while #list > recent do
		table.remove(list, 1)
	end
	rec.r = list
	rec.total += robux
	return rec, rec.total
end

function Store.new(dataStore, orderedStore, cfg, delayFn)
	return setmetatable({ data = dataStore, ordered = orderedStore, cfg = cfg, delay = delayFn }, Store)
end

-- Cermin ordered: tidak pernah turun (tulisan dari server lain bisa datang terlambat).
function Store:mirror(key, total, attempt)
	local ok, err = pcall(function()
		self.ordered:UpdateAsync(key, function(old)
			local cur = tonumber(old) or 0
			if cur >= total then
				return nil
			end
			return total
		end)
	end)
	if ok then
		return true
	end
	attempt = attempt or 1
	local wait = self.cfg.retry[attempt]
	if wait then
		self.delay(wait, function()
			self:mirror(key, total, attempt + 1)
		end)
	else
		warn("[Donation] papan " .. key .. " gagal diperbarui (" .. tostring(err) .. "), diperbaiki donasi berikutnya")
	end
	return false
end

-- → ok, total, isNew. ok=false = belum tersimpan (struk harus diulang Roblox).
function Store:record(userId, purchaseId, robux)
	local key = tostring(userId)
	local isNew, total = false, 0
	local ok, err = pcall(function()
		self.data:UpdateAsync(key, function(old)
			local rec, t = Store.apply(old, purchaseId, robux, self.cfg.recent)
			isNew, total = rec ~= nil, t
			return rec
		end)
	end)
	if not ok then
		warn("[Donation] simpan donasi uid " .. key .. " gagal (" .. tostring(err) .. "), struk diulang nanti")
		return false, 0, false
	end
	self:mirror(key, total)
	return true, total, isNew
end

return Store
