--!strict
-- ReplicatedStorage/Modules/Inventory (ModuleScript) — aturan MURNI tas / inventory (tanpa GetService/Instance/yield).
-- Dipakai StarterPlayerScripts.CustomBackpackUI; diuji Lune (tc_test.luau). Waktu selalu disuntik (now).
--
-- Model (seperti backpack Roblox): hotbar = slot bernomor 1…cap berisi NAMA tool. Tool baru → slot kosong terendah;
-- hotbar penuh → hanya di jendela inventory. Tool yang hilang sementara (mati / respawn) tetap memesan slotnya selama
-- `hold` dtk, jadi urutan hotbar tidak teracak setiap respawn. Tool yang dikeluarkan pemain dari hotbar (unassign) tidak
-- diisi otomatis lagi sampai pemain menaruhnya kembali.

local Inventory = {}

export type State = {
	cap: number,
	slots: { [number]: string }, -- slot → nama tool
	gone: { [string]: number }, -- nama tool ber-slot yang sedang tidak ada → waktu PERTAMA terlihat hilang
	out: { [string]: boolean }, -- nama yang sengaja dikeluarkan dari hotbar
}

export type Item = { name: string, tip: string? }

function Inventory.new(cap: number): State
	return { cap = cap, slots = {}, gone = {}, out = {} }
end

function Inventory.slotOf(state: State, name: string): number?
	for i = 1, state.cap do
		if state.slots[i] == name then
			return i
		end
	end
	return nil
end

-- names = tool yang ADA sekarang, urutan datang (Backpack lalu karakter). Dipanggil setiap tool datang / pergi.
-- `hold` dihitung dari saat tool PERTAMA terlihat hilang (bukan dari sync terakhir) → respawn setelah lama diam
-- tetap tidak mengacak hotbar.
function Inventory.sync(state: State, names: { string }, now: number, hold: number)
	local present: { [string]: boolean } = {}
	for _, n in names do
		present[n] = true
	end
	for i = 1, state.cap do
		local n = state.slots[i]
		if n then
			if present[n] then
				state.gone[n] = nil
			else
				local since = state.gone[n]
				if since == nil then
					state.gone[n] = now
				elseif now - since > hold then
					state.slots[i] = nil -- hilang lebih lama dari hold → slot dilepas
					state.gone[n] = nil
				end
			end
		end
	end
	for _, n in names do
		if not state.out[n] and not Inventory.slotOf(state, n) then
			for i = 1, state.cap do
				if state.slots[i] == nil then
					state.slots[i] = n
					break
				end
			end
		end
	end
end

-- Taruh tool di slot `to` (seret ke hotbar). Asalnya slot lain → TUKAR; penghuni lama tanpa tempat → ke inventory.
function Inventory.move(state: State, name: string, to: number)
	if to < 1 or to > state.cap then
		return
	end
	local from = Inventory.slotOf(state, name)
	local other = state.slots[to]
	if from == to then
		return
	end
	state.slots[to] = name
	state.out[name] = nil
	if from then
		state.slots[from] = other -- tukar (other nil → slot asal kosong)
	elseif other then
		state.out[other] = true -- tergeser keluar hotbar, tetap ada di inventory
	end
end

-- Keluarkan dari hotbar (seret slot keluar): hanya ada di inventory sampai ditaruh lagi.
function Inventory.unassign(state: State, name: string)
	local i = Inventory.slotOf(state, name)
	if i then
		state.slots[i] = nil
	end
	state.gone[name] = nil
	state.out[name] = true
end

local KEYS: { [string]: number } = {
	One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8, Nine = 9, Zero = 10,
}

-- Nama Enum.KeyCode → nomor slot (1–9, 0 = slot 10), atau nil.
function Inventory.keyToSlot(keyName: string): number?
	return KEYS[keyName]
end

function Inventory.keyLabel(i: number): string
	return if i == 10 then "0" else tostring(i)
end

-- Urutan kartu di jendela inventory: yang di hotbar (urut slot) dulu, sisanya A–Z.
function Inventory.order(state: State, names: { string }): { string }
	local has: { [string]: boolean } = {}
	for _, n in names do
		has[n] = true
	end
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for i = 1, state.cap do
		local n = state.slots[i]
		if n and has[n] and not seen[n] then
			table.insert(out, n)
			seen[n] = true
		end
	end
	local rest: { string } = {}
	for _, n in names do
		if not seen[n] then
			table.insert(rest, n)
			seen[n] = true
		end
	end
	table.sort(rest, function(a: string, b: string)
		return string.lower(a) < string.lower(b)
	end)
	for _, n in rest do
		table.insert(out, n)
	end
	return out
end

-- Cari (seperti Roblox): cocok di nama ATAU ToolTip, tanpa beda huruf besar/kecil, teks biasa (bukan pola).
function Inventory.filter(items: { Item }, query: string): { Item }
	local q = string.lower((string.gsub(string.gsub(query, "^%s+", ""), "%s+$", "")))
	local out: { Item } = {}
	for _, it in items do
		local tip = it.tip
		if
			q == ""
			or string.find(string.lower(it.name), q, 1, true) ~= nil
			or (tip ~= nil and string.find(string.lower(tip), q, 1, true) ~= nil)
		then
			table.insert(out, it)
		end
	end
	return out
end

-- Gamepad LB/RB: slot berikutnya (dir +1 / −1, memutar) yang berisi tool yang ADA, dari `current` (nil = belum pakai).
function Inventory.cycle(state: State, present: { [string]: boolean }, current: number?, dir: number, count: number): number?
	local n = math.min(count, state.cap)
	if n < 1 then
		return nil
	end
	local i = current or (if dir > 0 then 0 else n + 1)
	for _ = 1, n do
		i += dir
		if i > n then
			i = 1
		elseif i < 1 then
			i = n
		end
		local name = state.slots[i]
		if name and present[name] then
			return i
		end
	end
	return nil
end

export type Dock = {
	x: { [number]: number }, -- slot → posisi x (px) di baris slot; slot tanpa x = tidak tampil
	shown: number, -- jumlah slot yang tampil
	rowX: number, -- x baris slot di dalam dock (sesudah kolom tas + jarak)
	rowW: number,
	showRow: boolean,
	width: number, -- lebar dock = PERSIS lebar isi yang tampil (tas + slot)
}

-- Susunan dock [tas][slot…] seperti Roblox: tertutup = slot berisi saja (rapat); inventory terbuka = semua `count` slot;
-- hotbar disembunyikan = tinggal tas. Lebar selalu = isi yang tampil → UI memakai AnchorPoint 0.5 di tengah layar, jadi
-- dock TENGAH PRESISI di semua keadaan (biasa, disembunyikan, inventory terbuka). present = nama → apa saja (tool ada).
function Inventory.dock(
	state: State,
	present: { [string]: any },
	count: number,
	open: boolean,
	hidden: boolean,
	size: number,
	gap: number,
	bagW: number
): Dock
	local xs: { [number]: number } = {}
	local x, shown = 0, 0
	for i = 1, math.min(count, state.cap) do
		local n = state.slots[i]
		if open or (n ~= nil and present[n] ~= nil) then
			xs[i] = x
			x += size + gap
			shown += 1
		end
	end
	local rowW = if shown > 0 then x - gap else 0
	local showRow = shown > 0 and (open or not hidden)
	return {
		x = xs,
		shown = shown,
		rowX = bagW + gap,
		rowW = rowW,
		showRow = showRow,
		width = bagW + (if showRow then gap + rowW else 0),
	}
end

-- HP: jumlah slot yang muat di tengah layar (kiri/kanan dicadangkan cfg.phoneSide untuk kontrol sentuh Roblox).
function Inventory.phoneSlots(vpX: number, size: number, gap: number, bagW: number, cfg: any): number
	local free = vpX * (1 - 2 * cfg.phoneSide) - bagW - gap
	local n = math.floor((free + gap) / (size + gap))
	return math.clamp(n, cfg.slotsPhoneMin, cfg.slotsPhoneMax)
end

-- Kolom & baris terlihat jendela inventory: kolom yang muat di lebar `roomX`, baris maks rowsMax / yang muat di `roomY`.
function Inventory.grid(count: number, roomX: number, roomY: number, cfg: any, phone: boolean): (number, number)
	local maxCols = if phone then cfg.columnsMaxPhone else cfg.columnsMax
	local cols = math.clamp(math.floor((roomX + cfg.cellGap) / (cfg.cell + cfg.cellGap)), 2, maxCols)
	local rowsMax = if phone then cfg.rowsVisiblePhone else cfg.rowsVisible
	local need = math.max(1, math.ceil(count / cols))
	local fit = math.max(1, math.floor((roomY + cfg.cellGap) / (cfg.cellH + cfg.cellGap)))
	return cols, math.max(1, math.min(need, rowsMax, fit))
end

return Inventory
