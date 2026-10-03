-- ServerScriptService.ReceiptHandler
-- Satu-satunya MarketplaceService.ProcessReceipt di game ini (Roblox hanya memakai SATU callback).
-- Sistem lain (Shop, Donasi) mendaftarkan produknya lewat Handler.RegisterProduct(productId, fn):
--   fn(receiptInfo, player) mengembalikan true HANYA setelah hadiah tersimpan permanen;
--   false / error = struk tidak diterima, Roblox mengirimnya lagi nanti.
-- Struk yang sama bisa datang lebih dari sekali (juga ke server lain), jadi fn WAJIB idempoten
-- per PurchaseId. Store PurchaseHistory (kunci PurchaseId) hanya jalan pintas "sudah selesai".
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Studio: PurchaseHistory_studio (Config/StudioData) → struk pembelian uji tidak dicatat di live.
local StudioData = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StudioData"))
local IS_STUDIO = RunService:IsStudio()
local HISTORY_STORE = StudioData.name("PurchaseHistory", IS_STUDIO)
local PurchaseHistoryDS = DataStoreService:GetDataStore(HISTORY_STORE)
if IS_STUDIO then
	print("[DataStudio] ReceiptHandler: " .. HISTORY_STORE)
end

local Handler = {}
Handler.ProductHandlers = {}

-- Roblox hanya mengizinkan 1 ProcessReceipt per game; modul ini yang memasangnya.
Handler.AUTO_HOOK_PROCESS_RECEIPT = true

local warnedUnknown = {}

function Handler.RegisterProduct(productId, func)
	local old = Handler.ProductHandlers[productId]
	if old and old ~= func then
		warn("ReceiptHandler: productId " .. tostring(productId) .. " didaftarkan dua kali, handler lama diganti")
	end
	Handler.ProductHandlers[productId] = func
end

local function processReceipt(receiptInfo)
	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local purchaseId = receiptInfo.PurchaseId

	-- Sudah pernah selesai? Kalau statusnya tidak bisa dibaca, JANGAN proses (bisa dobel):
	-- Roblox mengirim ulang struk ini nanti.
	local successCheck, isProcessed = pcall(function()
		return PurchaseHistoryDS:GetAsync(purchaseId)
	end)
	if not successCheck then
		warn("ReceiptHandler: cek PurchaseHistory gagal (" .. tostring(isProcessed) .. "), struk " .. tostring(purchaseId) .. " diulang nanti")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if isProcessed then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local func = Handler.ProductHandlers[productId]
	if not func then
		if not warnedUnknown[productId] then
			warnedUnknown[productId] = true
			warn("ReceiptHandler: produk " .. tostring(productId) .. " belum terdaftar, struk diulang nanti")
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local pSuccess, result = pcall(func, receiptInfo, player)
	if not pSuccess then
		warn("ReceiptHandler: handler produk " .. tostring(productId) .. " error: " .. tostring(result))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result ~= true then
		warn("ReceiptHandler: Pembelian gagal diproses atau dikembalikan false untuk productId: " .. tostring(productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Hadiah sudah tersimpan (handler idempoten) → gagal mencatat di sini tidak membuat dobel.
	local saved, err = pcall(function()
		PurchaseHistoryDS:SetAsync(purchaseId, true)
	end)
	if not saved then
		warn("ReceiptHandler: gagal mencatat PurchaseHistory " .. tostring(purchaseId) .. " (" .. tostring(err) .. ")")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Untuk skrip lain yang ingin memproses struk secara manual.
function Handler.ProcessExternalReceipt(receiptInfo)
	return processReceipt(receiptInfo)
end

if Handler.AUTO_HOOK_PROCESS_RECEIPT then
	MarketplaceService.ProcessReceipt = processReceipt
end

return Handler
