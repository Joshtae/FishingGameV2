-- Shared rarity metadata for FishingSystemV2.
local Rarities = {}
Rarities.List = {"Common","Uncommon","Rare","Epic","Legendary","Mythical","Heavenly","Divine","Cosmic","Transcendent","Secret"}
function Rarities.GetByName(name)
	for index, value in ipairs(Rarities.List) do
		if string.lower(value) == string.lower(tostring(name)) then return {name=value,index=index} end
	end
	return nil
end
return Rarities
