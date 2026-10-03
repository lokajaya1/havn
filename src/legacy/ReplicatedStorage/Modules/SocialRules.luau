--!strict
-- ReplicatedStorage/Modules/SocialRules (ModuleScript) — aturan MURNI ruangan SOCIAL (claude/Rencana_Social.md).
-- Tanpa GetService / Instance / yield: jam dioper oleh pemanggil (os.clock) → bisa dites dengan jam palsu.
-- Angka di ReplicatedStorage.Config.Social. Batas terima remote memakai ToolRules.bucket/take.

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

return SocialRules
