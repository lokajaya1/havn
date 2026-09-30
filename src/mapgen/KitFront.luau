--!strict
-- MapGen/KitFront — arah DEPAN tiap kit ServerStorage.MapKit dalam orientasi simpannya (data murni).
-- Diukur 30 Sep 2026 (claude/Rencana_Workspace_R15.md §10–§12): bukti data (Seat, decal, posisi part) + raycast 15 sinar per
-- sisi (sisi terbuka = sinar masuk lebih dalam) + uji duduk di Play (badan menghadap Seat, dot 1.00).
-- front: "+X" | "-X" | "+Z" | "-Z" = sisi depan; "any" = simetris / arah tidak penting (boleh diputar bebas).
-- Kit berarah WAJIB dipasang lewat Prefabs.facing / Prefabs.seatFacing (arah tujuan), bukan yaw tebakan.

export type Front = { front: string, source: string }

local kits: { [string]: Front } = {
	-- berarah (terbukti)
	Bus_Stop_01_A = { front = "+Z", source = "screenshot 15:40 + raycast 4.3/0.4" },
	MetalBench_01_A = { front = "+Z", source = "raycast 2.5/1.2 (sandaran di -Z)" },
	Kit_PhoneBooth = { front = "-Z", source = "telepon & poster di sisi +Z" },
	Kit_EggChair = { front = "-X", source = "Seat -X + raycast 5.4/2.3 + uji duduk" },
	Kit_VendingMachine = { front = "+Z", source = "12 decal menghadap +Z" },
	Kit_ArcadeMachines = { front = "+X", source = "panel belakang di -X + raycast 2.0/0.6" },
	Kit_NeonSofa = { front = "-Z", source = "Seat -Z + sandaran +Z + uji duduk" },
	Kit_BeanBag = { front = "+X", source = "Seat +X + raycast 2.1/0.7 + uji duduk" },
	Kit_BarStool = { front = "-Z", source = "Seat -Z (bundar)" },
	Kit_NeonBarShelf = { front = "+X", source = "raycast 1.7/0.0 (rak terbuka)" },
	Kit_SpeakerTripod = { front = "+X", source = "raycast 1.5/1.0 (lemah, cek visual R5)" },
	Kit_LifeguardTower = { front = "-X", source = "raycast 28.0/21.7" },
	StreetLightPole_01_A = { front = "+Z", source = "lengan lampu di +Z + raycast 9.3/4.4" },
	-- simetris / bebas
	Kit_HighTable = { front = "any", source = "2 Seat berhadapan (+X & -X)" },
	Kit_BarCounter = { front = "any", source = "raycast simetris" },
	Kit_Surfboards = { front = "any", source = "raycast simetris" },
	ContainerRed = { front = "any", source = "kotak mesh 30x10x10" },
	ContainerBlue = { front = "any", source = "kotak mesh 30x10x10" },
	ContainerYellow = { front = "any", source = "kotak mesh 30x10x10" },
	ContainerGreen = { front = "any", source = "kotak mesh 30x10x10" },
	FireHydrant_01_A = { front = "any", source = "silinder" },
	Planter_Rectangle_01_A = { front = "any", source = "kotak" },
	Kit_Boat = { front = "any", source = "dekorasi laut" },
	Kit_Buoy = { front = "any", source = "silinder" },
	Kit_CargoShip = { front = "any", source = "latar laut" },
	Kit_ChainFence = { front = "any", source = "panel pagar" },
	Kit_Crate = { front = "any", source = "kubus" },
	Kit_FairyLights = { front = "any", source = "untaian lampu" },
	Kit_Forklift = { front = "any", source = "dekorasi pelabuhan" },
	Kit_JerseyBarrier = { front = "any", source = "simetris" },
	Kit_LifeBuoy = { front = "any", source = "cincin" },
	Kit_Lighthouse = { front = "any", source = "menara bundar" },
	Kit_OilBarrel = { front = "any", source = "silinder" },
	Kit_Pallet = { front = "any", source = "simetris" },
	Kit_PalmTree = { front = "any", source = "pohon" },
	Kit_Tetrapod = { front = "any", source = "simetris" },
	Kit_TireStack = { front = "any", source = "silinder" },
	Kit_VipRope = { front = "any", source = "simetris" },
}

local KitFront = { kits = kits }

local HEADING: { [string]: number } = { ["-Z"] = 0, ["-X"] = 90, ["+Z"] = 180, ["+X"] = -90 }

-- Arah hadap (derajat; 0 = utara/−Z, 90 = barat/−X, −90 = timur/+X, 180 = selatan/+Z) sisi depan kit di orientasi simpan.
-- nil kalau kit tidak terdaftar atau "any".
function KitFront.headingOf(kitName: string): number?
	local e = kits[kitName]
	return if e then HEADING[e.front] else nil
end

return KitFront
