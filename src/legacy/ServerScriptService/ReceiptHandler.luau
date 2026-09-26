-- ServerScriptService.ReceiptHandler
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PurchaseHistoryDS = DataStoreService:GetDataStore("PurchaseHistory")

local Handler = {}
Handler.ProductHandlers = {}

-- KONFIGURASI PENTING UNTUK KREATOR ASSET
-- Ubah AUTO_HOOK_PROCESS_RECEIPT menjadi false JIKA game Anda sudah menggunakan 
-- sistem donasi/pembelian lain (seperti Donation Board dari Toolbox) yang menggunakan ProcessReceipt.
-- Roblox hanya mengizinkan 1 ProcessReceipt per game!
Handler.AUTO_HOOK_PROCESS_RECEIPT = true

function Handler.RegisterProduct(productId, func)
	Handler.ProductHandlers[productId] = func
end

local function processReceipt(receiptInfo)
	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local purchaseId = receiptInfo.PurchaseId
	
	-- [ANTI-FAKE / ANTI-DUPLICATE DONATION]
	-- Cek apakah transaksi ini sudah pernah sukses diproses sebelumnya
	local successCheck, isProcessed = pcall(function()
		return PurchaseHistoryDS:GetAsync(purchaseId)
	end)
	
	if successCheck and isProcessed then
		-- Roblox mengirim ulang struk lama karena lag jaringan, konfirmasi agar Roblox berhenti mengirimnya
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local func = Handler.ProductHandlers[productId]
	if func then
		local pSuccess, result = pcall(func, receiptInfo, player)
		if pSuccess and result == true then
			-- Pembelian sukses! Simpan ID struk ke DataStore agar tidak bisa diklaim ulang
			pcall(function()
				PurchaseHistoryDS:SetAsync(purchaseId, true)
			end)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			warn("ReceiptHandler: Pembelian gagal diproses atau dikembalikan false untuk productId: " .. tostring(productId))
		end
	else
		-- Jika bukan produk dari shop ini (misal Donasi Board), lewati tanpa error agar bisa di-handle sistem lain
		if not Handler.AUTO_HOOK_PROCESS_RECEIPT then
			warn("ReceiptHandler: Produk " .. tostring(productId) .. " bukan milik Shop, meneruskan ke handler eksternal...")
		end
	end
	
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Mengekspos fungsi manual jika kreator ingin memanggilnya dari script Donasi eksternal
function Handler.ProcessExternalReceipt(receiptInfo)
	return processReceipt(receiptInfo)
end

if Handler.AUTO_HOOK_PROCESS_RECEIPT then
	MarketplaceService.ProcessReceipt = processReceipt
end

return Handler
