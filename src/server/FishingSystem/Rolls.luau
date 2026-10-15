--[[ Server-authoritative fishing rolls and reel calculations. Public: GetChances, Roll, GetReelSpeed, GetRequiredHits. ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(script.Parent.Data)
local Modifiers = require(script.Parent.Modifiers)
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local Rods = require(ReplicatedStorage.FishingSystemV2.Rods)
local Characters = require(ReplicatedStorage.FishingSystemV2.Characters)

local Rolls = {}
-- DEV_ONLY_BEGIN DevRodState
local devRods = {}
local testRod = {Luck = 1024, Reel = 10, Strength = 99}
-- DEV_ONLY_END DevRodState

local function getRod(player)
	-- DEV_ONLY_BEGIN DevRodOverride
	if devRods[player] then return devRods[player] end
	-- DEV_ONLY_END DevRodOverride
	local data = Data.Get(player)
	local equipped = data and data.Rods and data.Rods.Equipped
	local owned = data and data.Rods and data.Rods.Owned or {}
	if type(equipped) ~= "string" or table.find(owned, equipped) == nil then return nil end
	return Rods[equipped]
end

function Rolls.GetEquippedRod(player) return getRod(player) end

local function eligible(rarity, strength)
	local choices = {}
	for _, definition in ipairs(Characters.GetActiveByRarity(rarity)) do
		if definition.weight <= strength then table.insert(choices, definition) end
	end
	return choices
end

function Rolls.GetChances(player, luckOverride)
	local rod = getRod(player)
	if not rod then return {} end
	local luck = luckOverride or (rod.Luck * Modifiers.GetCastLuck(player))
	if type(luck) ~= "number" or luck <= 0 then luck = 1 end
	local raw, total = {}, 0
	for rarity = 1, #Config.BaseHits do
		if #eligible(rarity, rod.Strength) > 0 then
			local weight = 100 * (0.4 ^ (rarity - 1)) * (luck ^ ((rarity - 1) / 10))
			raw[rarity] = weight
			total += weight
		else raw[rarity] = 0 end
	end
	local chances = {}
	for rarity = 1, #Config.BaseHits do chances[rarity] = total > 0 and raw[rarity] / total * 100 or 0 end
	return chances
end

function Rolls.Roll(player, random, luckOverride)
	local rod = getRod(player)
	if not rod then return nil, "no equipped rod" end
	random = random or Random.new()
	local chances = Rolls.GetChances(player, luckOverride)
	local roll, running = random:NextNumber(0, 100), 0
	local rarity = 1
	for i, chance in ipairs(chances) do
		running += chance
		if roll <= running then rarity = i; break end
	end
	local choices = eligible(rarity, rod.Strength)
	if #choices == 0 then return nil, "no eligible character" end
	return choices[random:NextInteger(1, #choices)], rarity
end

function Rolls.GetReelSpeed(player)
	local rod = getRod(player)
	if not rod then return 0 end
	return rod.Reel * (Modifiers.HasFasterReel(player) and Config.FasterReelMultiplier or 1) * Modifiers.ReelPotionMult(player) * Modifiers.EventReelMult()
end

function Rolls.GetRequiredHits(player, rarity)
	local speed = Rolls.GetReelSpeed(player)
	if speed <= 0 then return math.huge end
	return math.max(1, math.ceil(Config.BaseHits[rarity] / speed - 1e-9))
end

-- DEV_ONLY_BEGIN SetDevRodAndClear
function Rolls.SetDevRod(player, name)
	if name == "max" then devRods[player] = testRod elseif name == "steel" then devRods[player] = nil else return false end
	return true
end
function Rolls.Clear(player) devRods[player] = nil end
-- DEV_ONLY_END SetDevRodAndClear
return Rolls
