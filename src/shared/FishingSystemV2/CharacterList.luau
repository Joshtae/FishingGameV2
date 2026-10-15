-- Canonical Phase 2 character definitions. One entry is returned for every shipped character and placeholder.
local Rarities = require(script.Parent.Rarities)
local real = {
	{"common_01","AnyaForger","AnyaForger",1},
	{"uncommon_01","Teto","Teto",2},
	{"rare_01","LaraCraft","LaraCraft",3},
	{"epic_01","Rukia","Rukia",4},
	{"legendary_01","ChinLi","ChinLi",5},
	{"mythical_01","FlashFelineRig","FlashFelineRig",6},
	{"heavenly_01","Mikusu","Mikusu",7},
	{"divine_01","SailorEarth","SailorEarth",8},
	{"cosmic_01","Asuka","Asuka",9},
	{"transcendent_01","NicoRobin","NicoRobin",10},
	{"secret_01","Hinata","Hinata",11},
}
local list = {}
for _, entry in ipairs(real) do
	table.insert(list, {id=entry[1], displayName=entry[2], modelName=entry[3], rarity=entry[4], weight=entry[4], placeholder=false})
end
for rarityIndex, rarityName in ipairs(Rarities.List) do
	for slot=2,10 do
		local id = string.lower(rarityName) .. "_" .. string.format("%02d",slot)
		table.insert(list, {id=id, displayName=rarityName.." Placeholder "..slot, modelName=string.format("Placeholder_%s_%02d",rarityName,slot), rarity=rarityIndex, weight=rarityIndex, placeholder=true})
	end
end
return list
