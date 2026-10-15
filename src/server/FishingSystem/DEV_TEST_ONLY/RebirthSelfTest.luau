-- Studio-only Phase 5 static rebirth checks. Delete with DEV_TEST_ONLY before launch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = script.Parent.Parent
local Data = require(root.Data)
local Rebirths = require(ReplicatedStorage.FishingSystemV2.Rebirths)
local NumberFormat = require(ReplicatedStorage.FishingSystemV2.NumberFormat)

local RebirthSelfTest = {}

local PodiumCount = 10
local MutationFactor = 10
local BonusFactor = 3
local MaxRarityBaseCPS = 8 ^ 10 -- Mirrors Income's BaseCPSGrowth = 8 at rarity index 11.

local function clone(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do copy[key] = clone(child) end
	return copy
end

local function finite(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function check(results, name, condition, detail)
	table.insert(results, {name = name, passed = condition, detail = detail or ""})
end

function RebirthSelfTest.Run()
	local results = {}

	check(results, "bounds", Rebirths.GetCost(-1) == nil and Rebirths.GetCost(250) == nil
		and Rebirths.GetMult(-1) == nil and Rebirths.GetMult(251) == nil, "invalid levels return nil")

	local exact = Rebirths.GetCost(0) == 10 and Rebirths.GetCost(1) == 40
		and Rebirths.GetCost(10) == 1e7 and Rebirths.GetCost(20) == 7.94e8
		and Rebirths.GetCost(25) == 1e10 and Rebirths.GetCost(50) == 5e12
		and Rebirths.GetCost(65) == 2.77e13 and Rebirths.GetCost(100) == 3e15
		and Rebirths.GetCost(120) == 8.86e15 and Rebirths.GetCost(129) == 2.26e16
		and Rebirths.GetCost(130) == 5.01e16 and Rebirths.GetCost(150) == 5e17
		and Rebirths.GetCost(175) == 5e18 and Rebirths.GetCost(200) == 2e19
		and Rebirths.GetCost(225) == 5e19 and Rebirths.GetCost(249) == 1e20
		and Rebirths.GetMult(0) == 1 and Rebirths.GetMult(1) == 1.06
		and Rebirths.GetMult(10) == 1.82 and Rebirths.GetMult(20) == 3.31
		and Rebirths.GetMult(25) == 4.47 and Rebirths.GetMult(50) == 20
		and Rebirths.GetMult(65) == 26.3 and Rebirths.GetMult(100) == 50
		and Rebirths.GetMult(120) == 60 and Rebirths.GetMult(129) == 66
		and Rebirths.GetMult(130) == 66 and Rebirths.GetMult(150) == 80
		and Rebirths.GetMult(175) == 100 and Rebirths.GetMult(200) == 125
		and Rebirths.GetMult(225) == 137 and Rebirths.GetMult(249) == 149
		and Rebirths.GetMult(250) == 150
	check(results, "anchors", exact, "all documented anchors")

	check(results, "interpolation", Rebirths.GetCost(2) == 159
		and Rebirths.GetCost(5) >= 9900 and Rebirths.GetCost(5) <= 10100
		and Rebirths.GetCost(15) >= 8.90e7 and Rebirths.GetCost(15) <= 8.92e7
		and Rebirths.GetCost(75) >= 1.05e14 and Rebirths.GetCost(75) <= 1.07e14
		and Rebirths.GetMult(2) == 1.13
		and Rebirths.GetMult(15) >= 2.45 and Rebirths.GetMult(15) <= 2.46
		and Rebirths.GetMult(75) >= 31.5 and Rebirths.GetMult(75) <= 31.7
		and Rebirths.GetMult(110) >= 54.7 and Rebirths.GetMult(110) <= 54.9, "interpolated lookup values")

	local monotonic = true
	for n = 1, Rebirths.MaxRebirths - 1 do
		if Rebirths.GetCost(n) < Rebirths.GetCost(n - 1) then monotonic = false end
	end
	for n = 1, Rebirths.MaxRebirths do
		if Rebirths.GetMult(n) < Rebirths.GetMult(n - 1) then monotonic = false end
	end
	check(results, "monotonic", monotonic, "costs and multipliers never decrease")

	local podiumId = next(Data.Template.Plot.Podiums)
	local invalidRebirths = {-5, 3.5, 9999, 251}
	local invalidRebirthsPass = true
	for _, value in ipairs(invalidRebirths) do
		local corrupt = clone(Data.Template)
		corrupt.Rebirths = value
		Data.Sanitize({UserId = 0}, corrupt)
		invalidRebirthsPass = invalidRebirthsPass and corrupt.Rebirths == 0
	end
	check(results, "sanitize_rebirths", invalidRebirthsPass, "Rebirths -5, 3.5, 9999, and 251 reset to 0")

	local invalidNumbers = clone(Data.Template)
	invalidNumbers.Cash = 0 / 0
	invalidNumbers.Food = -1
	Data.Sanitize({UserId = 0}, invalidNumbers)
	check(results, "sanitize_cash_food", invalidNumbers.Cash == 0 and invalidNumbers.Food == 0,
		"Cash NaN and Food -1 reset to 0")

	local function testStoredCash(value)
		local corrupt = clone(Data.Template)
		corrupt.Plot.Podiums[podiumId] = {unlocked = true, characterUid = "x", storedCash = value}
		Data.Sanitize({UserId = 0}, corrupt)
		local podium = corrupt.Plot.Podiums[podiumId]
		return podium.unlocked == true and podium.characterUid == "x" and podium.storedCash == 0
	end
	check(results, "sanitize_stored_cash", testStoredCash(math.huge) and testStoredCash(0 / 0),
		"Infinity and NaN storedCash reset alone while unlocked and characterUid remain")

	local valid = clone(Data.Template)
	valid.Rebirths = 2
	valid.Cash = 1.25
	valid.Food = 2.5
	valid.Plot.Podiums[podiumId] = {unlocked = true, characterUid = "x", storedCash = 3.75}
	Data.Sanitize({UserId = 0}, valid)
	check(results, "sanitize_valid_values", valid.Rebirths == 2 and valid.Cash == 1.25 and valid.Food == 2.5
		and valid.Plot.Podiums[podiumId].unlocked == true
		and valid.Plot.Podiums[podiumId].characterUid == "x"
		and valid.Plot.Podiums[podiumId].storedCash == 3.75, "valid values remain unchanged")

	check(results, "number_format", NumberFormat.Format(10) == "10"
		and NumberFormat.Format(1e7) == "10M"
		and NumberFormat.Format(7.94e8) == "794M"
		and NumberFormat.Format(1e20) == "100Qi"
		and NumberFormat.FormatRate(1.06) == "1.06/s", "shared formatter strings")

	local pacingExpectedSeconds = {
		[50] = 0.78,
		[100] = 186,
		[150] = 5.4 * 60 * 60,
		[200] = 5.8 * 24 * 60 * 60,
		[249] = 24 * 24 * 60 * 60,
	}
	for _, level in ipairs({50, 100, 150, 200, 249}) do
		local cps = PodiumCount * MaxRarityBaseCPS * MutationFactor * BonusFactor * (Rebirths.GetMult(level) or 1)
		local seconds = Rebirths.GetCost(level) / cps
		local expected = pacingExpectedSeconds[level]
		local withinTolerance = finite(cps) and finite(seconds) and cps > 0 and seconds > 0
			and math.abs(seconds - expected) / expected <= 0.05
		check(results, "pacing_" .. level, withinTolerance,
			string.format("n=%d expected=%.2fs actual=%.2fs cps=%.0f", level, expected, seconds, cps))
	end

	for _, result in ipairs(results) do
		local prefix = result.passed and "PASS" or "FAIL"
		print(("[DEV_TEST_ONLY][RebirthSelfTest] %s %s %s"):format(prefix, result.name, result.detail))
	end
	print("[DEV_TEST_ONLY][RebirthSelfTest] NOT RUN mutation CPS checks: mutations are not implemented in Income.")
	return results
end

return RebirthSelfTest
