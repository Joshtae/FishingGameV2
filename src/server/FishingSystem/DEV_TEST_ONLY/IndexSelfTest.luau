-- Studio-only pure/self-contained Phase 6 Index checks. Delete with DEV_TEST_ONLY at launch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = script.Parent.Parent
local Data = require(root.Data)
local Config = require(ReplicatedStorage.FishingSystemV2.IndexConfig)

local IndexSelfTest = {}

local function pass(label, condition, detail)
	print(("[IndexSelfTest] %s %s%s"):format(condition and "PASS" or "FAIL", label, detail and (" | " .. detail) or ""))
	return condition
end

local function close(a, b, tolerance)
	return math.abs(a - b) <= tolerance
end

local function chances(luck)
	local raw, total = {}, 0
	for rarity = 1, 4 do
		local weight = 100 * (.4 ^ (rarity - 1)) * (luck ^ ((rarity - 1) / 10))
		raw[rarity] = weight
		total += weight
	end
	for rarity = 1, 4 do raw[rarity] = raw[rarity] / total * 100 end
	return raw
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = copy(child) end
	return result
end

function IndexSelfTest.Run()
	local all = true
	local expectedLuck = {[0] = 1, [1] = 1.25, [2] = 1.5, [4] = 2, [11] = 3.75}
	for claimed, expected in pairs(expectedLuck) do
		all = pass("IndexLuck " .. claimed, close(1 + Config.LuckPerClaim * claimed, expected, 1e-9)) and all
	end

	local expectedOdds = {
		[1] = {61.58, 24.63, 9.85, 3.94},
		[1.25] = {60.80, 24.87, 10.17, 4.16},
		[2] = {59.13, 25.35, 10.87, 4.66},
		[3.75] = {56.82, 25.94, 11.84, 5.41},
	}
	for luck, expected in pairs(expectedOdds) do
		local actual = chances(luck)
		local ok = true
		for rarity = 1, 4 do ok = ok and close(actual[rarity], expected[rarity], .05) end
		all = pass("Steel odds luck=" .. luck, ok) and all
	end

	local originalCharacters = {
		{uid = "a", id = "common_01"}, {uid = "b", id = "common_01"},
		{uid = "c", id = "rare_01"}, {uid = "d", id = "common_02"},
	}
	local migrationData = {DataVersion = 3, Cash = 99, Characters = copy(originalCharacters), Hotbar = { ["1"] = "a" }}
	Data.Migrations[3](migrationData)
	local migrationOk = migrationData.DataVersion == 4
		and migrationData.Index.Discovered.common_01 == true
		and migrationData.Index.Discovered.rare_01 == true
		and migrationData.Index.Discovered.common_02 == nil
		and next(migrationData.Index.Claimed) == nil
		and migrationData.Cash == 99
		and migrationData.Hotbar["1"] == "a"
		and #migrationData.Characters == #originalCharacters
	all = pass("Migration v3 backfill", migrationOk) and all
	local emptyData = {DataVersion = 3}
	Data.Migrations[3](emptyData)
	all = pass("Migration v3 empty Characters", emptyData.DataVersion == 4 and type(emptyData.Index.Discovered) == "table" and next(emptyData.Index.Discovered) == nil) and all

	local sanitized = copy(Data.Template)
	sanitized.Index = {Discovered = {common_01 = true, [5] = true, rare_01 = "yes"}, Claimed = {epic_01 = true}}
	Data.Sanitize({UserId = 0}, sanitized)
	all = pass("Index sanitizer invalid dictionaries", sanitized.Index.Discovered.common_01 == true and sanitized.Index.Discovered.rare_01 == nil and next(sanitized.Index.Claimed) == nil) and all
	local resetIndex = copy(Data.Template)
	resetIndex.Index = 7
	Data.Sanitize({UserId = 0}, resetIndex)
	all = pass("Index sanitizer non-table", type(resetIndex.Index) == "table" and next(resetIndex.Index.Discovered) == nil and next(resetIndex.Index.Claimed) == nil) and all

	local configOk = Config.LuckPerClaim == .25 and Config.ClaimRateLimitPerSecond == 5 and Config.SnapshotMaxPerSecond == 10 and Config.MaxIdLength == 64 and Config.EntryBuildBatch == 20 and Config.DiscoveryToastSeconds == 2
	for rarity = 1, 11 do configOk = configOk and Config.IndexDiscoveryGems[rarity] == 0 end
	all = pass("IndexConfig values", configOk) and all
	return all
end

return IndexSelfTest
