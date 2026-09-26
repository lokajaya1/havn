-- ═══════════════════════════════════════════════════════════
-- TitleStyle — ReplicatedStorage > CustomUIModules
--
-- Satu sumber tampilan plate title: dipakai bareng overhead tag (di
-- dunia) dan preview di panel role (di layar).
--
-- DUA MODE:
--   Build(parent, textSize)              → mode piksel, untuk ScreenGui
--   Build(parent, textSize, designWidth) → mode scale, untuk BillboardGui
--
-- Mode scale dipakai overhead tag supaya tag ikut mengecil saat kamera
-- menjauh. Semua ukuran dinyatakan sebagai pecahan dari kotak induk,
-- bukan piksel mati — jadi tidak ada satu pun angka yang perlu dihitung
-- ulang tiap frame.
--
-- "design px" = satuan rancangan. Angkanya dibagi TAG_PPS untuk jadi
-- stud, jadi layout tetap enak dibaca dalam piksel.
-- ═══════════════════════════════════════════════════════════

local TextService = game:GetService("TextService")

local TitleStyle = {}

TitleStyle.WHITE = Color3.fromRGB(255, 255, 255)
TitleStyle.INK   = Color3.fromRGB(18, 18, 21)

-- ── geometri bersama (design px) ───────────────────────────
TitleStyle.TEXT_SIZE = 14
TitleStyle.PLATE_H   = TitleStyle.TEXT_SIZE + 6   -- 20
TitleStyle.NAME_GAP  = 2                          -- jarak plate → nama
TitleStyle.TAG_W     = 300                        -- lebar acuan overhead tag
TitleStyle.TAG_PPS   = 36                         -- design px per stud

-- Palet dipakai untuk warna teks DAN warna plate.
TitleStyle.COLORS = {
	{ name = "Ink",    color = Color3.fromRGB( 18,  18,  21) },
	{ name = "Snow",   color = Color3.fromRGB(255, 255, 255) },
	{ name = "Ash",    color = Color3.fromRGB(148, 163, 184) },
	{ name = "Gold",   color = Color3.fromRGB(212, 175,  55) },
	{ name = "Blood",  color = Color3.fromRGB(226,  29,  52) },
	{ name = "Ember",  color = Color3.fromRGB(255,  94,  58) },
	{ name = "Amber",  color = Color3.fromRGB(255, 176,  32) },
	{ name = "Lime",   color = Color3.fromRGB(163, 230,  53) },
	{ name = "Mint",   color = Color3.fromRGB( 45, 212, 191) },
	{ name = "Ice",    color = Color3.fromRGB( 56, 189, 248) },
	{ name = "Violet", color = Color3.fromRGB(192, 132, 252) },
	{ name = "Pink",   color = Color3.fromRGB(244, 114, 182) },
}

TitleStyle.PLATES = {
	{ name = "Fade",  key = "Fade"  },  -- bar gelap, pinggir luntur
	{ name = "Solid", key = "Solid" },  -- bar penuh, sudut membulat
	{ name = "Polos", key = "None"  },  -- teks doang
}

TitleStyle.EFFECTS = {
	{ name = "Normal",  key = "None"  },
	{ name = "Rainbow", key = "RGB"   },
	{ name = "Pulse",   key = "Pulse" },
	{ name = "Fire",    key = "Fire"  },
}

TitleStyle.FONTS = {
	{ name = "Builder", font = Enum.Font.BuilderSansBold },
	{ name = "Gotham",  font = Enum.Font.GothamBlack     },
	{ name = "Bold",    font = Enum.Font.GothamBold      },
	{ name = "Source",  font = Enum.Font.SourceSansBold  },
	{ name = "Arcade",  font = Enum.Font.Arcade          },
	{ name = "Cartoon", font = Enum.Font.Cartoon         },
	{ name = "Creepy",  font = Enum.Font.Creepster       },
}

TitleStyle.FONT_ENUM  = {}
TitleStyle.VALID_FONT = {}
for _, f in ipairs(TitleStyle.FONTS) do
	TitleStyle.FONT_ENUM[f.name]  = f.font
	TitleStyle.VALID_FONT[f.name] = true
end

TitleStyle.VALID_PLATE, TitleStyle.VALID_EFFECT = {}, {}
for _, p in ipairs(TitleStyle.PLATES)  do TitleStyle.VALID_PLATE[p.key]  = true end
for _, e in ipairs(TitleStyle.EFFECTS) do TitleStyle.VALID_EFFECT[e.key] = true end

-- ── hex ────────────────────────────────────────────────────

function TitleStyle.ToHex(c)
	return string.format("%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5))
end

function TitleStyle.FromHex(hex, fallback)
	if type(hex) ~= "string" then return fallback end
	hex = hex:gsub("#", "")
	if #hex ~= 6 then return fallback end
	local r, g, b = tonumber(hex:sub(1,2),16), tonumber(hex:sub(3,4),16), tonumber(hex:sub(5,6),16)
	if not (r and g and b) then return fallback end
	return Color3.fromRGB(r, g, b)
end

-- ── build ──────────────────────────────────────────────────
-- designWidth diisi = lebar kotak induk dalam design px → mode scale.
-- Dikosongkan → mode piksel (preview panel).

function TitleStyle.Build(parent, textSize, designWidth)
	textSize = textSize or TitleStyle.TEXT_SIZE
	local plateH = textSize + 6
	local scaled = type(designWidth) == "number" and designWidth > 0

	local plate = Instance.new("Frame")
	plate.Name             = "Plate"
	plate.AnchorPoint      = Vector2.new(0.5, 0.5)
	plate.Position         = UDim2.new(0.5, 0, 0.5, 0)
	plate.BackgroundColor3 = TitleStyle.INK
	plate.BorderSizePixel  = 0
	plate.Size = scaled and UDim2.fromScale(0.3, 1) or UDim2.new(0, 80, 0, plateH)
	plate.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = scaled and UDim.new(0.15, 0) or UDim.new(0, 3)
	corner.Parent = plate

	local plateGradient = Instance.new("UIGradient")
	plateGradient.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name                   = "Label"
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.BuilderSansBold
	label.TextColor3             = TitleStyle.WHITE
	label.Text                   = ""
	label.Parent                 = plate

	if scaled then
		-- Tinggi teks ikut tinggi plate, tinggi plate ikut ukuran billboard
		-- dalam stud. Itu yang bikin ukurannya konsisten di semua jarak.
		label.TextScaled = true
		local pad = Instance.new("UIPadding")
		pad.PaddingTop    = UDim.new(3 / plateH, 0)
		pad.PaddingBottom = UDim.new(3 / plateH, 0)
		pad.Parent = label
	else
		label.TextSize = textSize
	end

	local textGradient = Instance.new("UIGradient")
	textGradient.Parent = label

	local textStroke = Instance.new("UIStroke")
	textStroke.Color        = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness    = 1
	textStroke.Transparency = 0.5
	textStroke.Parent       = label

	return {
		plate = plate, plateGradient = plateGradient, corner = corner,
		label = label, textGradient = textGradient, textStroke = textStroke,
		textSize = textSize, plateH = plateH,
		designWidth = scaled and designWidth or nil,
	}
end

-- ── paint (statis, dipanggil hanya saat ada perubahan) ─────

local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0,    1),
	NumberSequenceKeypoint.new(0.24, 0.06),
	NumberSequenceKeypoint.new(0.76, 0.06),
	NumberSequenceKeypoint.new(1,    1),
})
local SOLID = NumberSequence.new(0.06)
local CLEAR = NumberSequence.new(1)

-- Ruang tambahan di kiri-kanan teks. Fade butuh ekor untuk luntur,
-- Solid cuma butuh padding biasa.
local PAD_X = { Fade = 42, Solid = 16, None = 0 }

function TitleStyle.Paint(refs, style)
	local font = TitleStyle.FONT_ENUM[style.font] or Enum.Font.BuilderSansBold
	local text = style.text or ""

	refs.label.Font = font
	refs.label.Text = text

	-- GetTextSize itu bagian termahal di sini, jadi hasilnya disimpan dan
	-- hanya dihitung ulang kalau teks atau fontnya benar-benar ganti.
	local key = text .. "\1" .. tostring(style.font)
	if refs._boundsKey ~= key then
		refs._boundsKey = key
		refs._boundsX = TextService:GetTextSize(
			text, refs.textSize, font, Vector2.new(1000, 100)).X
	end

	local scaled   = refs.designWidth ~= nil
	local plateKey = style.plate or "Fade"
	local widthPx  = math.max(refs._boundsX + (PAD_X[plateKey] or 0), 24)

	if scaled then
		refs.plate.Size = UDim2.fromScale(math.min(widthPx / refs.designWidth, 1), 1)
	else
		refs.plate.Size = UDim2.new(0, widthPx, 0, refs.plateH)
	end

	refs.plate.BackgroundColor3 = style.plateColor or TitleStyle.INK

	if plateKey == "Fade" then
		refs.plateGradient.Transparency = FADE
		refs.corner.CornerRadius = scaled and UDim.new(0.15, 0) or UDim.new(0, 3)
	elseif plateKey == "Solid" then
		refs.plateGradient.Transparency = SOLID
		refs.corner.CornerRadius = scaled and UDim.new(0.3, 0) or UDim.new(0, 6)
	else
		refs.plateGradient.Transparency = CLEAR
	end

	-- Outline dikontrol dari panel. Tebal 0 = benar-benar mati.
	refs.textStroke.Thickness    = style.outline and (scaled and 1 or 1.5) or 0
	refs.textStroke.Transparency = 0.2
end

-- ── animate (hanya kalau efeknya bukan None) ───────────────

local FLAT = ColorSequence.new(Color3.fromRGB(255, 255, 255))

function TitleStyle.Animate(refs, style, clock)
	local effect = style.effect or "None"
	local base   = style.color or TitleStyle.WHITE

	if effect == "RGB" then
		refs._flick = nil
		refs.textGradient.Color = FLAT
		refs.label.TextColor3   = Color3.fromHSV((clock * 0.25) % 1, 0.85, 1)

	elseif effect == "Pulse" then
		refs._flick = nil
		refs.textGradient.Color = FLAT
		local a = (math.sin(clock * 4) + 1) * 0.5
		refs.label.TextColor3 = base:Lerp(TitleStyle.WHITE, a * 0.7)

	elseif effect == "Fire" then
		refs.label.TextColor3      = TitleStyle.WHITE
		refs.textGradient.Rotation = 90

		-- Dibulatkan ke 40 langkah: ColorSequence baru cuma dibuat saat
		-- angkanya benar-benar berubah, bukan tiap frame.
		local flick = math.clamp(
			0.5 + math.sin(clock * 11) * 0.06 + math.sin(clock * 5.3) * 0.04, 0.05, 0.95)
		flick = math.floor(flick * 40 + 0.5) / 40

		if refs._flick ~= flick then
			refs._flick = flick
			refs.textGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,     Color3.fromRGB(255, 226, 120)),
				ColorSequenceKeypoint.new(flick, Color3.fromRGB(255, 132,  26)),
				ColorSequenceKeypoint.new(1,     Color3.fromRGB(196,  26,  12)),
			})
		end

	else
		refs._flick = nil
		refs.textGradient.Color = FLAT
		refs.label.TextColor3   = base
	end
end

-- Baca setelan title dari Attribute player. Nil kalau tidak punya title.
function TitleStyle.Read(plr)
	local text = plr:GetAttribute("TitleText") or ""
	if text == "" then return nil end
	return {
		text       = text,
		color      = TitleStyle.FromHex(plr:GetAttribute("TitleColor"), TitleStyle.WHITE),
		plate      = plr:GetAttribute("TitlePlate") or "Fade",
		plateColor = TitleStyle.FromHex(plr:GetAttribute("TitlePlateColor"), TitleStyle.INK),
		font       = plr:GetAttribute("TitleFont") or "Builder",
		effect     = plr:GetAttribute("TitleEffect") or "None",
		outline    = plr:GetAttribute("TitleOutline") ~= false,
	}
end

TitleStyle.ATTRIBUTES = {
	"TitleText", "TitleColor", "TitlePlate",
	"TitlePlateColor", "TitleFont", "TitleEffect", "TitleOutline",
}

return TitleStyle