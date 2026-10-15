-- Shared formatting and display configuration for R4 overhead player tags.
local OverheadTagConfig = {}

OverheadTagConfig.PlaytimeTickSeconds = 60
OverheadTagConfig.TagMaxDistance = 60
OverheadTagConfig.TagStudsOffsetY = 2.5
OverheadTagConfig.TagSizePixels = Vector2.new(200, 50)

local function finiteNonNegative(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
end

-- Formats finite, non-negative seconds into the approved floored Minute/Hour/Day label.
function OverheadTagConfig.FormatPlaytime(value)
	local seconds = finiteNonNegative(value) and math.floor(value) or 0
	if seconds < 3600 then
		local minutes = math.floor(seconds / 60)
		return "Playtime: " .. minutes .. (minutes == 1 and " Minute" or " Minutes")
	end
	if seconds < 86400 then
		local hours = math.floor(seconds / 3600)
		return "Playtime: " .. hours .. (hours == 1 and " Hour" or " Hours")
	end
	local days = math.floor(seconds / 86400)
	return "Playtime: " .. days .. (days == 1 and " Day" or " Days")
end

return OverheadTagConfig
