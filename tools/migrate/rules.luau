--!strict
-- Pemetaan store HAVN lama → [NEW] HAVN. Sumber: claude/Rencana_Langkah5_Migrasi.md (5b).
-- merge: nama strategi di lib/merge.luau. skipEmpty: nilai kosong tidak ditulis (game membuat default sendiri).

export type StandardRule = {
	name: string,
	from: string,
	to: string,
	merge: string,
	scope: string?, -- default "global"
	prefix: string?, -- hanya kunci yang diawali prefix ini
	key: string?, -- hanya satu kunci ini
	skipEmpty: boolean?,
}

export type OrderedRule = {
	name: string,
	from: string,
	to: string,
	merge: string, -- "sumLedger" | "keepTarget"
}

return {
	source = "10393434502", -- HAVN lama (hanya dibaca)
	target = "10767911181", -- [NEW] HAVN (satu-satunya yang boleh ditulis)
	standard = {
		{ name = "shop", from = "ShopData", to = "ShopData", merge = "shop", skipEmpty = true },
		{ name = "dance", from = "DanceFavorites_v2", to = "DanceFavorites", merge = "unionList", skipEmpty = true },
		{ name = "favPrompt", from = "FavoritePrompted_V1", to = "FavoritePrompted", merge = "orBool" },
		{ name = "volume", from = "PlayerMusicVolume_v2", prefix = "Vol_", to = "MusicVolume", merge = "keepTarget" },
		{
			name = "musicFav",
			from = "PlayerMusicVolume_v2",
			prefix = "MyLib_",
			to = "MusicFavorites",
			merge = "unionById",
			skipEmpty = true,
		},
		{ name = "musicLib", from = "SharedMusicLibrary_v2", key = "GlobalLib", to = "MusicLibrary", merge = "unionById" },
		{ name = "likes", from = "AvatarLikes_v1", to = "AvatarLikes", merge = "likes" },
		{ name = "community", from = "CommunityPref", to = "CommunityPref", merge = "keepTarget" },
		{ name = "titles", from = "AdminTitleData_v1", to = "AdminTitles", merge = "keepTarget" },
		{ name = "adonis", from = "Adonis_1", scope = "Adonis", to = "AdonisData", merge = "adonis" },
		{ name = "donationData", from = "DonationData_v1", to = "DonationData_v1", merge = "keepTarget" },
		{ name = "donationBoard", from = "Donation Board v4", to = "Donation Board v4", merge = "keepTarget" },
	} :: { StandardRule },
	ordered = {
		{ name = "timePlayed", from = "TopTimePlayed", to = "TopTimePlayed", merge = "sumLedger" },
		{ name = "donationsOrdered", from = "PlayerDonations_v1", to = "PlayerDonations_v1", merge = "keepTarget" },
	} :: { OrderedRule },
}
