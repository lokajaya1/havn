--!strict
-- ServerScriptService/ThemeMap/Service (ModuleScript) — orkestrasi tema map (themeMap, claude/Rencana_Tema.md).
-- Semua API Roblox berisiko masuk lewat `deps` (dipasang init.server.luau; tes Lune memasang tiruan):
--   deps = { cfg, rules, store (GetAsync/UpdateAsync), messaging (PublishAsync/SubscribeAsync), topic, jobId,
--            assets() → ServerStorage.ThemeMap?, workspace, players() → { Player }, rankOf(player) → number?,
--            adminRank, pivot(character, Vector3), setAttr(name, value), json(value) → string,
--            now() (detik UTC), clock() (os.clock), wait(dtk?), log(text), warn(text) }
-- Alur: start() = validasi aset → bersihkan sisa Workspace.ThemeMap → baca DataStore (3×) → pasang → langganan pesan.
-- set() = permintaan admin: jeda → rank → siap → validasi → aset → UpdateAsync → pasang → kabari server lain.

local Service = {}
Service.__index = Service

function Service.new(deps: any)
	local self = setmetatable({}, Service)
	self.deps = deps
	self.cfg = deps.cfg
	self.rules = deps.rules
	self.rec = nil -- rekaman DataStore terakhir yang diketahui (Rules.Record)
	self.ready = false -- DataStore sudah terbaca; sebelum itu edit ditolak (tidak menimpa rekaman yang tak terbaca)
	self.mounted = nil :: string? -- id tema yang terpasang (nil = Default / belum)
	self.mountRoot = nil :: Instance? -- klon yang terpasang di Workspace.ThemeMap
	self.gen = 0 -- naik tiap pasang/lepas; pasang bertahap berhenti kalau ada pergantian baru
	self.missing = {} :: { [string]: string } -- id → alasan aset tidak bisa dipasang
	self.lastAdmin = {} :: { [number]: number } -- userId → clock
	self.lastServer = nil :: number?
	self.saving = false
	self.subscribed = false
	self.lastLoadAt = nil :: number?
	self.lastPollAt = nil :: number?
	return self
end

-- ── aset ───────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Templat sah: ada, berisi part, TANPA skrip (Script di Workspace akan jalan). → templat | nil, alasan
function Service:template(id: string): (Instance?, string?)
	local t = self.cfg.find(id)
	if not t or not t.folder then
		return nil, nil -- Default: tidak ada templat (sah)
	end
	local dir = self.deps.assets()
	local inst = dir and dir:FindFirstChild(t.folder)
	if not inst then
		return nil, "aset tidak ada"
	end
	local parts = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			return nil, "aset berisi skrip"
		end
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	if parts == 0 then
		return nil, "aset kosong"
	end
	return inst, nil
end

function Service:checkAssets()
	self.missing = {}
	for _, t in self.cfg.list do
		if t.folder then
			local inst, why = self:template(t.id)
			if not inst then
				self.missing[t.id] = why or "aset tidak ada"
				self.deps.warn(("[ThemeMap] tema %s tidak bisa dipasang: %s (ServerStorage.%s.%s)"):format(t.id, self.missing[t.id], self.cfg.assetFolder, t.folder))
			end
		end
	end
end

-- ── state ke client (atribut folder remote) ────────────────────────────────────────────────────────────────────────

function Service:publishState()
	local d, rec = self.deps, self.rec
	local missing = {}
	for id, why in self.missing do
		table.insert(missing, { id = id, why = why })
	end
	table.sort(missing, function(a, b)
		return a.id < b.id
	end)
	d.setAttr("Ready", self.ready)
	d.setAttr("Active", self.mounted or self.cfg.default)
	d.setAttr("Missing", d.json(missing))
	d.setAttr("State", d.json({
		id = if rec then rec.id else self.cfg.default,
		active = self.mounted or self.cfg.default,
		fromT = rec and rec.fromT,
		untilT = rec and rec.untilT,
		byName = rec and rec.byName,
		at = rec and rec.at,
		rev = if rec then rec.rev else 0,
		log = if rec then rec.log else {},
		now = d.now(),
	}))
end

-- ── pasang / lepas ─────────────────────────────────────────────────────────────────────────────────────────────────

function Service:mountFolder(): Instance
	local ws = self.deps.workspace
	local f = ws:FindFirstChild(self.cfg.mountFolder)
	if not f then
		f = Instance.new("Folder")
		f.Name = self.cfg.mountFolder
		f.Parent = ws
	end
	return f
end

local function worldBox(p: BasePart): any
	local cf, h = p.CFrame, p.Size / 2
	local ax, ay, az = cf.RightVector * h.X, cf.UpVector * h.Y, cf.LookVector * h.Z
	local ex = math.abs(ax.X) + math.abs(ay.X) + math.abs(az.X)
	local ey = math.abs(ax.Y) + math.abs(ay.Y) + math.abs(az.Y)
	local ez = math.abs(ax.Z) + math.abs(ay.Z) + math.abs(az.Z)
	local c = cf.Position
	return { minX = c.X - ex, maxX = c.X + ex, minY = c.Y - ey, maxY = c.Y + ey, minZ = c.Z - ez, maxZ = c.Z + ez }
end

-- Pemain yang akan tertimpa part padat tema dipindah ke tepi SEBELUM dekor muncul (T0b: tanpa ini terjebak di kue).
function Service:pushPlayers(clone: Instance): number
	local boxes = {}
	for _, p in clone:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide then
			table.insert(boxes, worldBox(p))
		end
	end
	if #boxes == 0 then
		return 0
	end
	local moved = 0
	for _, plr in self.deps.players() do
		local char = (plr :: any).Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local q = hrp.CFrame.Position
			local nx, nz = self.rules.pushOut(boxes, q.X, q.Y, q.Z, self.cfg.push)
			if nx and nz then
				self.deps.pivot(char, Vector3.new(nx, q.Y, nz))
				moved += 1
			end
		end
	end
	return moved
end

function Service:unmount()
	self.gen += 1
	if self.mountRoot then
		self.mountRoot:Destroy()
		self.mountRoot = nil
	end
	self.mounted = nil
end

-- Pasang tema `id` (Default = lepas). Sama dengan yang terpasang → tidak apa-apa. Bertahap: satu anak folder per frame
-- (T0c: 631 instance sekaligus = 1 hentakan ±100 ms di client desktop).
function Service:apply(id: string): boolean
	if id == (self.mounted or self.cfg.default) then
		return false
	end
	self:unmount()
	if id == self.cfg.default then
		self:publishState()
		return true
	end
	local tpl, why = self:template(id)
	if not tpl then
		self.missing[id] = why or "aset tidak ada"
		self.deps.warn(("[ThemeMap] %s tidak dipasang: %s — tetap Default"):format(id, self.missing[id]))
		self:publishState()
		return false
	end
	local gen = self.gen
	local clone = (tpl :: Instance):Clone()
	local moved = self:pushPlayers(clone)
	local pieces = clone:GetChildren()
	for _, c in pieces do
		c.Parent = nil
	end
	clone.Parent = self:mountFolder()
	self.mountRoot = clone
	self.mounted = id
	self:publishState()
	for _, c in pieces do
		if self.gen ~= gen then
			c:Destroy()
		else
			c.Parent = clone
			self.deps.wait()
		end
	end
	if moved > 0 then
		self.deps.log(("[ThemeMap] %d pemain dipindah keluar dari part padat %s"):format(moved, id))
	end
	return true
end

function Service:applyEffective(): boolean
	return self:apply(self.rules.effective(self.cfg, self.rec, self.deps.now()))
end

-- ── DataStore & pesan ──────────────────────────────────────────────────────────────────────────────────────────────

-- Rekaman lebih baru dari server lain → adopsi + pasang.
function Service:adopt(raw: any): boolean
	local rec = self.rules.sanitize(self.cfg, raw)
	if rec and (not self.rec or rec.rev > self.rec.rev) then
		self.rec = rec
		self:applyEffective()
		self:publishState()
		return true
	end
	return false
end

function Service:read(): (boolean, any)
	local d = self.deps
	return pcall(function()
		return d.store:GetAsync(d.cfg.store.key)
	end)
end

function Service:load(attempts: number): boolean
	local d = self.deps
	for i = 1, attempts do
		local ok, raw = self:read()
		if ok then
			self.ready = true
			self.rec = self.rules.sanitize(self.cfg, raw)
			self:applyEffective()
			self:publishState()
			return true
		end
		d.warn(("[ThemeMap] DataStore gagal dibaca (%d/%d): %s"):format(i, attempts, tostring(raw)))
		if i < attempts then
			d.wait(self.cfg.load.delay)
		end
	end
	self:publishState()
	return false
end

function Service:poll(): boolean
	if not self.ready or self.saving then
		return false
	end
	local ok, raw = self:read()
	return ok and self:adopt(raw)
end

function Service:onMessage(data: any)
	if type(data) ~= "table" or data.job == self.deps.jobId or type(data.rev) ~= "number" then
		return
	end
	if not self.ready or self.saving or (self.rec and data.rev <= self.rec.rev) then
		return
	end
	self:poll()
end

function Service:subscribe(): boolean
	local d = self.deps
	local ok, err = pcall(function()
		d.messaging:SubscribeAsync(d.topic, function(msg: any)
			self:onMessage(msg and msg.Data)
		end)
	end)
	self.subscribed = ok
	if not ok then
		d.warn("[ThemeMap] langganan MessagingService gagal, dicoba lagi: " .. tostring(err))
	end
	return ok
end

-- ── permintaan admin (RemoteFunction Set) ──────────────────────────────────────────────────────────────────────────

-- → { ok = true, state } | { ok = false, reason = "invalid"|"cooldown"|"rank"|"notready"|"missing"|"busy"|"save", wait? }
function Service:set(player: any, id: any, startKey: any, endKey: any): any
	local d, R, cfg = self.deps, self.rules, self.cfg
	local uid = player.UserId
	local clock = d.clock()
	local free, _, waitFor = R.cooldown(cfg, self.lastAdmin[uid], nil, clock)
	if not free then
		return { ok = false, reason = "cooldown", wait = waitFor }
	end
	self.lastAdmin[uid] = clock -- dicatat sebelum cek rank: pemain biasa juga dibatasi
	local rank = d.rankOf(player)
	if type(rank) ~= "number" or rank < d.adminRank then
		return { ok = false, reason = "rank" }
	end
	if not self.ready then
		return { ok = false, reason = "notready" }
	end
	local valid = R.validate(cfg, id, startKey, endKey)
	if not valid then
		return { ok = false, reason = "invalid" }
	end
	if id ~= cfg.default then
		local tpl, why = self:template(id)
		if not tpl then
			self.missing[id] = why or "aset tidak ada"
			self:publishState()
			return { ok = false, reason = "missing" }
		end
	end
	local okServer, _, waitServer = R.cooldown(cfg, nil, self.lastServer, clock)
	if not okServer then
		return { ok = false, reason = "cooldown", wait = waitServer }
	end
	if self.saving then
		return { ok = false, reason = "busy" }
	end
	self.saving = true
	local now = d.now()
	local fromT, untilT = R.window(cfg, startKey, endKey, now)
	local previous = self.mounted or cfg.default
	local knownRev = if self.rec then self.rec.rev else 0
	local saved
	local ok, err = pcall(function()
		d.store:UpdateAsync(cfg.store.key, function(old: any)
			saved = R.nextRecord(cfg, R.sanitize(cfg, old), knownRev, id, fromT, untilT, uid, player.Name, now)
			return saved
		end)
	end)
	self.saving = false
	if not ok or not saved then
		d.warn("[ThemeMap] simpan gagal, tidak ada yang berubah: " .. tostring(err))
		return { ok = false, reason = "save" }
	end
	self.lastServer = clock
	self.rec = saved
	self:applyEffective()
	self:publishState()
	pcall(function()
		d.messaging:PublishAsync(d.topic, { job = d.jobId, rev = saved.rev })
	end)
	d.log("[ThemeMap] " .. R.describe(cfg, saved, previous))
	return { ok = true, state = { id = saved.id, active = self.mounted or cfg.default, rev = saved.rev } }
end

function Service:forget(player: any)
	self.lastAdmin[player.UserId] = nil
end

-- ── mulai ──────────────────────────────────────────────────────────────────────────────────────────────────────────

function Service:start()
	local d = self.deps
	-- sisa tema di Workspace (mis. G.themeMap TAMPIL tanpa SIMPAN sebelum Publish) dibuang: server yang menentukan
	local left = d.workspace:FindFirstChild(self.cfg.mountFolder)
	if left then
		if #left:GetChildren() > 0 then
			d.warn(("[ThemeMap] sisa Workspace.%s dibuang (%d objek) — jalankan G.themeMap(\"<tema>\", \"SIMPAN\") sebelum Publish"):format(self.cfg.mountFolder, #left:GetChildren()))
		end
		left:Destroy()
	end
	self:mountFolder()
	self:checkAssets()
	self:publishState()
	self:subscribe()
	self:load(self.cfg.load.attempts)
	self.lastLoadAt = d.clock()
	self.lastPollAt = d.clock()
end

-- Satu putaran perawatan (init memanggil tiap cfg.tick dtk; clock = os.clock): baca lagi kalau belum siap (tiap
-- cfg.load.retry), langganan ulang, baca ulang DataStore tiap cfg.poll (jaring pengaman pesan hilang), lalu jadwal.
-- → "load" | "poll" | "tick"
function Service:step(clock: number): string
	if not self.ready then
		if clock - (self.lastLoadAt or -math.huge) >= self.cfg.load.retry then
			self.lastLoadAt = clock
			self:load(1)
		end
		return "load"
	end
	if not self.subscribed then
		self:subscribe()
	end
	if clock - (self.lastPollAt or -math.huge) >= self.cfg.poll then
		self.lastPollAt = clock
		self:poll()
		return "poll"
	end
	self:applyEffective()
	return "tick"
end

return Service
