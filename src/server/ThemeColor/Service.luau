--!strict
-- ServerScriptService/ThemeColor/Service (ModuleScript) — tema warna UI per pemain (themeColor, claude/Rencana_ThemeColor.md).
-- Semua API Roblox berisiko masuk lewat `deps` (dipasang init.server.luau; tes Lune memasang tiruan):
--   deps = { cfg, rules, store (GetAsync/UpdateAsync), ownsPass(player) → boolean (boleh menunggu ShopServer),
--            setAttr(player, name, value), now() (dtk UTC), clock() (os.clock), wait(dtk), spawn(fn), log(text), warn(text) }
-- Alur: join() = atribut default → baca DataStore (3×) → atribut → cek pass → atribut.
--       select() = permintaan pemain (daftar putih, jeda, pass) → atribut langsung → simpan menyusul (≥ cfg.saveGap dtk
--       antar tulis per kunci). leave()/closeAll() = simpan yang belum tersimpan. Gagal baca DataStore → default, TIDAK
--       menimpa rekaman lama kecuali pemain memilih tema baru.

local Service = {}
Service.__index = Service

export type PlayerState = {
	userId: number,
	chosen: string?, -- pilihan pemain (tersimpan / baru dipilih); nil = belum pernah memilih
	owns: boolean, -- punya pass (atau admin)
	lastSelect: number?, -- clock pilihan terakhir yang diterima
	lastSave: number?, -- clock tulis DataStore terakhir
	dirty: boolean, -- ada pilihan yang belum tersimpan
	saving: boolean, -- loop simpan sedang berjalan
	gone: boolean, -- pemain sudah keluar
}

function Service.new(deps: any)
	local self = setmetatable({}, Service)
	self.deps = deps
	self.cfg = deps.cfg
	self.rules = deps.rules
	self.state = {} :: { [any]: PlayerState } -- player → state
	self.inflight = 0 -- UpdateAsync yang sedang berjalan
	self.pending = 0 -- loop simpan yang masih hidup
	return self
end

function Service:key(userId: number): string
	return self.cfg.store.keyPrefix .. tostring(userId)
end

-- Tema efektif → atribut pemain (yang dibaca client).
function Service:publish(player: any): string
	local st = self.state[player]
	if not st then
		return self.cfg.default
	end
	local eff = self.rules.effective(self.cfg, st.chosen, st.owns)
	self.deps.setAttr(player, "ThemeColorPass", st.owns)
	self.deps.setAttr(player, "ThemeColor", eff)
	return eff
end

function Service:join(player: any)
	local st: PlayerState = {
		userId = player.UserId,
		chosen = nil,
		owns = false,
		dirty = false,
		saving = false,
		gone = false,
	}
	self.state[player] = st
	self:publish(player)

	local d = self.deps
	local loaded, raw = false, nil
	for i = 1, self.cfg.store.loadTries do
		local ok, v = pcall(function()
			return d.store:GetAsync(self:key(st.userId))
		end)
		if ok then
			loaded, raw = true, v
			break
		end
		d.warn(("[ThemeColor] baca %s gagal (%d/%d): %s"):format(self:key(st.userId), i, self.cfg.store.loadTries, tostring(v)))
		if i < self.cfg.store.loadTries then
			d.wait(i)
		end
	end
	if st.gone then
		return
	end
	if loaded and st.chosen == nil then
		st.chosen = self.rules.readRecord(self.cfg, raw)
	end
	self:publish(player)

	local owns = d.ownsPass(player) == true
	if st.gone then
		return
	end
	if owns ~= st.owns then
		st.owns = owns
		self:publish(player)
	end
end

-- Kabar dari ShopServer (beli / gift / pass terdeteksi saat join).
function Service:ownership(player: any, owns: boolean)
	local st = self.state[player]
	if not st or st.owns == owns then
		return
	end
	st.owns = owns
	self:publish(player)
end

-- Remote dari client. → { ok = boolean, reason = string?, id = string }
function Service:select(player: any, id: any): { [string]: any }
	local st = self.state[player]
	if not st then
		return { ok = false, reason = "tema", id = self.cfg.default }
	end
	local now = self.deps.clock()
	local current = self.rules.effective(self.cfg, st.chosen, st.owns)
	local ok, why = self.rules.checkSelect(self.cfg, id, current, st.owns, now, st.lastSelect)
	if not ok then
		return { ok = false, reason = why, id = current }
	end
	st.lastSelect = now
	st.chosen = id
	local eff = self:publish(player)
	self:queueSave(st)
	return { ok = true, id = eff }
end

-- ── simpan ────────────────────────────────────────────────────────────────────────────────────────────────────────
function Service:write(st: PlayerState): boolean
	local d = self.deps
	local id = st.chosen
	if id == nil then
		return true
	end
	local rec = self.rules.record(id, d.now())
	st.lastSave = d.clock()
	self.inflight += 1
	local ok, err = pcall(function()
		d.store:UpdateAsync(self:key(st.userId), function()
			return rec
		end)
	end)
	self.inflight -= 1
	if not ok then
		d.warn(("[ThemeColor] simpan %s gagal: %s"):format(self:key(st.userId), tostring(err)))
	end
	return ok
end

-- Simpan pilihan terakhir, paling cepat cfg.saveGap dtk sesudah tulis sebelumnya (pilihan beruntun = 1 tulis).
-- Pemain keluar (st.gone) → langsung tulis tanpa menunggu jeda. Gagal → coba lagi (maks 3×).
function Service:queueSave(st: PlayerState)
	st.dirty = true
	if st.saving then
		return
	end
	st.saving = true
	self.pending += 1
	local d = self.deps
	d.spawn(function()
		local fails = 0
		while st.dirty do
			while not st.gone and st.lastSave and d.clock() - st.lastSave < self.cfg.saveGap do
				d.wait(0.25)
			end
			st.dirty = false
			if not self:write(st) then
				fails += 1
				if fails < 3 then
					st.dirty = true
				end
			end
		end
		st.saving = false
		self.pending -= 1
	end)
end

function Service:leave(player: any)
	local st = self.state[player]
	if not st then
		return
	end
	st.gone = true
	self.state[player] = nil
end

-- BindToClose: tandai semua keluar (loop simpan langsung menulis), tunggu sampai selesai (maks `limit` dtk).
function Service:closeAll(limit: number)
	local players = {}
	for player in self.state do
		table.insert(players, player)
	end
	for _, player in players do
		self:leave(player)
	end
	local d = self.deps
	local t0 = d.clock()
	while (self.pending > 0 or self.inflight > 0) and d.clock() - t0 < limit do
		d.wait(0.1)
	end
end

return Service
