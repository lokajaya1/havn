--!strict
-- ReplicatedStorage/Modules/SocialRules (ModuleScript) — aturan MURNI ruangan SOCIAL (claude/Rencana_Social.md).
-- Tanpa GetService / Instance / yield: jam dioper oleh pemanggil (os.clock) → bisa dites dengan jam palsu.
-- Angka di ReplicatedStorage.Config.Social. Batas terima remote memakai ToolRules.bucket/take.
-- Isi: carry (jeda pasangan/target), teks publik 1× per menit, private chat (nama channel whisper), hide avatar.

local SocialRules = {}

-- ── validasi ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- userId sah: angka bulat ≥ 1 (NaN, inf, pecahan, string ditolak).
function SocialRules.validUserId(v: any): boolean
	return type(v) == "number" and v == v and v >= 1 and v < math.huge and v % 1 == 0
end

-- ── carry: jeda pasangan & jeda target ───────────────────────────────────────────────────────────────────────────
-- Satu catatan per pasangan peminta → target: sampai kapan diblok + waktu penolakan terakhir (strike).
-- incoming[target] = waktu permintaan terakhir yang benar-benar dikirim ke target (dari siapa pun).
export type CarryConfig = {
	PAIR_COOLDOWN: number,
	STRIKES: number,
	STRIKE_WINDOW: number,
	PAIR_BLOCK: number,
	TARGET_GAP: number,
}
type Pair = { blockedUntil: number, strikes: { number } }
export type CarryState = {
	pairs: { [number]: { [number]: Pair } },
	incoming: { [number]: number },
}

function SocialRules.carryState(): CarryState
	return { pairs = {}, incoming = {} }
end

-- Boleh peminta meminta target sekarang?
-- → true, nil, 0 | false, "pair", sisa dtk (jeda pasangan) | false, "target", sisa dtk (target baru saja dimintai).
function SocialRules.carryCheck(
	state: CarryState,
	requesterId: number,
	targetId: number,
	now: number,
	cfg: CarryConfig
): (boolean, string?, number)
	local mine = state.pairs[requesterId]
	local p = mine and mine[targetId]
	if p and now < p.blockedUntil then
		return false, "pair", p.blockedUntil - now
	end
	local last = state.incoming[targetId]
	if last and now - last < cfg.TARGET_GAP then
		return false, "target", cfg.TARGET_GAP - (now - last)
	end
	return true, nil, 0
end

-- Permintaan benar-benar dikirim ke target.
function SocialRules.carrySent(state: CarryState, targetId: number, now: number)
	state.incoming[targetId] = now
end

-- Permintaan selesai. accepted → catatan pasangan dihapus. Selain itu (ditolak / kedaluwarsa / dibatalkan) →
-- strike dicatat; jeda = PAIR_COOLDOWN, atau PAIR_BLOCK kalau strike dalam STRIKE_WINDOW sudah ≥ STRIKES.
function SocialRules.carryEnded(
	state: CarryState,
	requesterId: number,
	targetId: number,
	now: number,
	accepted: boolean,
	cfg: CarryConfig
)
	local mine = state.pairs[requesterId]
	if accepted then
		if mine then
			mine[targetId] = nil
			if next(mine) == nil then
				state.pairs[requesterId] = nil
			end
		end
		return
	end
	if not mine then
		mine = {}
		state.pairs[requesterId] = mine
	end
	local p = mine[targetId]
	if not p then
		p = { blockedUntil = 0, strikes = {} }
		mine[targetId] = p
	end
	local kept = {}
	for _, t in p.strikes do
		if now - t < cfg.STRIKE_WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	p.strikes = kept
	local gap = if #kept >= cfg.STRIKES then cfg.PAIR_BLOCK else cfg.PAIR_COOLDOWN
	p.blockedUntil = math.max(p.blockedUntil, now + gap)
end

-- Buang catatan yang tidak berpengaruh lagi (jeda lewat & strike di luar jendela; incoming lewat TARGET_GAP).
-- Catatan TIDAK dibuang saat pemain keluar → keluar-masuk server tidak me-reset jeda.
function SocialRules.carryPrune(state: CarryState, now: number, cfg: CarryConfig)
	for requesterId, mine in state.pairs do
		for targetId, p in mine do
			local live = now < p.blockedUntil
			if not live then
				for _, t in p.strikes do
					if now - t < cfg.STRIKE_WINDOW then
						live = true
						break
					end
				end
			end
			if not live then
				mine[targetId] = nil
			end
		end
		if next(mine) == nil then
			state.pairs[requesterId] = nil
		end
	end
	for targetId, t in state.incoming do
		if now - t >= cfg.TARGET_GAP then
			state.incoming[targetId] = nil
		end
	end
end

-- ── teks publik (aturan 1 menit) ─────────────────────────────────────────────────────────────────────────────────
-- Sisa detik sebelum pemain boleh memasang teks publik lagi (0 = boleh). lastAt = atribut Player (nil = belum pernah).
function SocialRules.textWait(lastAt: any, now: number, cooldown: number): number
	if type(lastAt) ~= "number" or lastAt ~= lastAt then
		return 0
	end
	local left = cooldown - (now - lastAt)
	if left <= 0 then
		return 0
	end
	return math.min(left, cooldown) -- jam mundur tidak boleh membuat jeda lebih dari cooldown
end

-- ── private chat ─────────────────────────────────────────────────────────────────────────────────────────────────
-- Channel whisper resmi TextChatService bernama "RBXWhisper:<UserId1>_<UserId2>" (urutan id tidak dijanjikan dok).
function SocialRules.isWhisperChannel(name: string, a: number, b: number): boolean
	local x, y = tostring(a), tostring(b)
	return name == "RBXWhisper:" .. x .. "_" .. y or name == "RBXWhisper:" .. y .. "_" .. x
end

-- ── hide avatar ──────────────────────────────────────────────────────────────────────────────────────────────────
export type HideConfig = { LTM: { string }, ENABLED: { string }, DETACH: { string } }

-- Cara menyembunyikan satu instance: "ltm" | "enabled" | "detach" | nil (tidak disentuh).
-- isA = function(kelas) return instance:IsA(kelas) end (dioper pemanggil → modul tetap murni).
function SocialRules.hideAction(isA: (string) -> boolean, cfg: HideConfig): string?
	for _, c in cfg.LTM do
		if isA(c) then
			return "ltm"
		end
	end
	for _, c in cfg.ENABLED do
		if isA(c) then
			return "enabled"
		end
	end
	for _, c in cfg.DETACH do
		if isA(c) then
			return "detach"
		end
	end
	return nil
end

-- Avatar pemain disembunyikan? (bukan diri sendiri; pilihan kartu "hide"/"show" menang atas sakelar "Sembunyikan Player Lain")
function SocialRules.avatarHidden(isSelf: boolean, override: string?, hideAll: boolean): boolean
	if isSelf then
		return false
	end
	if override == "hide" then
		return true
	end
	if override == "show" then
		return false
	end
	return hideAll
end

export type HideSettings = { all: boolean, effects: boolean, nametags: boolean }

-- Satu instance di karakter pemain harus disembunyikan? kind = hasil hideAction; isNametag = BillboardGui.
-- Avatar tersembunyi → semua; selain itu efek ikut "Sembunyikan Efek Pemain", nametag ikut "Sembunyikan nametag".
function SocialRules.shouldHide(
	kind: string,
	isNametag: boolean,
	isSelf: boolean,
	override: string?,
	s: HideSettings
): boolean
	if SocialRules.avatarHidden(isSelf, override, s.all) then
		return true
	end
	if kind == "detach" then
		return s.effects
	end
	if isNametag then
		return s.nametags
	end
	return false
end

return SocialRules
