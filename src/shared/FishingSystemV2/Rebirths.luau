--[[
	Shared rebirth tuning and lookup API.
	GetCost(n) -> finite next-rebirth Cash cost for integer n 0..249, or nil.
	GetMult(n) -> Cash multiplier for integer n 0..250, or nil.
	FormatMult(mult) -> presentation-only multiplier text with trailing zeroes removed.
]]
local Rebirths = {}

Rebirths.MaxRebirths = 250
Rebirths.KeepsFoodOnRebirth = false
Rebirths.RateLimitPerSecond = 2
Rebirths.ConfirmSeconds = 3
Rebirths.RebornCost = 1e21 -- Presentation anchor only; rebirth 250 has no next cost.

local costAnchors = {
	{n = 0, value = 10},
	{n = 1, value = 40},
	{n = 10, value = 1e7},
	{n = 20, value = 7.94e8},
	{n = 25, value = 1e10},
	{n = 50, value = 5e12},
	{n = 65, value = 2.77e13},
	{n = 100, value = 3e15},
	{n = 120, value = 8.86e15},
	{n = 129, value = 2.26e16},
	{n = 130, value = 5.01e16},
	{n = 150, value = 5e17},
	{n = 175, value = 5e18},
	{n = 200, value = 2e19},
	{n = 225, value = 5e19},
	{n = 249, value = 1e20},
}

local multAnchors = {
	{n = 0, value = 1},
	{n = 1, value = 1.06},
	{n = 10, value = 1.82},
	{n = 20, value = 3.31},
	{n = 25, value = 4.47},
	{n = 50, value = 20},
	{n = 65, value = 26.3},
	{n = 100, value = 50},
	{n = 120, value = 60},
	{n = 129, value = 66},
	{n = 130, value = 66},
	{n = 150, value = 80},
	{n = 175, value = 100},
	{n = 200, value = 125},
	{n = 225, value = 137},
	{n = 249, value = 149},
	{n = 250, value = 150},
}

local function roundSignificant(value, significantFigures)
	if value == 0 then return 0 end
	local magnitude = 10 ^ (math.floor(math.log(value) / math.log(10)) - significantFigures + 1)
	return math.floor(value / magnitude + 0.5) * magnitude
end

local function findExact(anchors, n)
	for _, anchor in ipairs(anchors) do
		if anchor.n == n then return anchor.value end
	end
end

local function roundDecimals(value, decimals)
	local factor = 10 ^ decimals
	return math.floor(value * factor + 0.5) / factor
end

local function interpolate(anchors, n)
	local exact = findExact(anchors, n)
	if exact ~= nil then return exact end
	for index = 1, #anchors - 1 do
		local lower, upper = anchors[index], anchors[index + 1]
		if n > lower.n and n < upper.n then
			local alpha = (n - lower.n) / (upper.n - lower.n)
			return lower.value * (upper.value / lower.value) ^ alpha
		end
	end
	return nil
end

local costs, multipliers = {}, {}
for n = 0, Rebirths.MaxRebirths - 1 do
	costs[n] = roundSignificant(interpolate(costAnchors, n), 3)
end
for n = 0, Rebirths.MaxRebirths do
	multipliers[n] = roundDecimals(interpolate(multAnchors, n), 2)
end

local function validLevel(n)
	return type(n) == "number" and n % 1 == 0 and n >= 0 and n <= Rebirths.MaxRebirths
end

local function isMonotonic(values, lastLevel)
	local previous
	for n = 0, lastLevel do
		local value = values[n]
		if type(value) ~= "number" or (previous and value < previous) then return false end
		previous = value
	end
	return true
end

if not isMonotonic(costs, Rebirths.MaxRebirths - 1) or not isMonotonic(multipliers, Rebirths.MaxRebirths) then
	warn("[FishingSystem.Rebirths] Generated lookup tables are not monotonic.")
end

function Rebirths.GetCost(n)
	if not validLevel(n) or n >= Rebirths.MaxRebirths then return nil end
	return costs[n]
end

function Rebirths.GetMult(n)
	if not validLevel(n) then return nil end
	return multipliers[n]
end

function Rebirths.FormatMult(value)
	if type(value) ~= "number" then return "1" end
	return (string.format("%.2f", value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
end

return Rebirths
