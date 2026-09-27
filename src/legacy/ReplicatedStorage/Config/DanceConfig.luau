-- DanceConfig — ReplicatedStorage > Config (ModuleScript)
-- Daftar nama dance untuk UI (DanceClient). Sumber tunggal: DanceAssets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DanceAssets = require(ReplicatedStorage.Assets.Animations.Dances.DanceAssets)

if not (DanceAssets and DanceAssets.dances) then
	error("❌ DanceConfig: DanceAssets ModuleScript is required! Cannot find ReplicatedStorage.Assets.Animations.Dances.DanceAssets")
end

local dances, danceNames = {}, {}
for danceName, animationId in pairs(DanceAssets.dances) do
	dances[danceName] = animationId
	table.insert(danceNames, danceName)
end
table.sort(danceNames)

local DanceConfig = {}

-- Nama dance, urut abjad.
function DanceConfig:getDanceNames()
	return danceNames
end

-- nama → id animasi
function DanceConfig:getDances()
	return dances
end

-- Properti lama (DanceClient masih punya jalur cadangan untuk ini).
DanceConfig.danceName = danceNames
DanceConfig.dances    = dances

return DanceConfig
