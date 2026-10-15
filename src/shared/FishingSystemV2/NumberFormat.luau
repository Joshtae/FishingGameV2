-- Shared number presentation API. Format(n) formats balances/costs; FormatRate(n) formats rates with "/s".
local NumberFormat={}
local suffixes={{1,""},{1e3,"K"},{1e6,"M"},{1e9,"B"},{1e12,"T"},{1e15,"Qa"},{1e18,"Qi"},{1e21,"Sx"},{1e24,"Sp"},{1e27,"Oc"},{1e30,"No"},{1e33,"Dc"}}
local function trim(text)
	text=text:gsub("(%..-)0+$","%1"):gsub("%.$","")
	return text
end
local function truncate(value,decimals)
	local factor=10^decimals
	local epsilon=math.abs(value)*1e-9
	return math.floor((value+epsilon)*factor)/factor
end
local function significant(value)
	if value>=100 then return truncate(value,0),0 end
	if value>=10 then return truncate(value,1),1 end
	return truncate(value,2),2
end
local function scientific(value)
	local exponent=0
	while value>=10 do value/=10;exponent+=1 end
	local shown,decimals=significant(value)
	return trim(string.format("%."..decimals.."f",shown)).."e"..exponent
end
local function formatPositive(value,rate)
	if value>=1e36 then return scientific(value) end
	if value<1000 then
		if rate then
			local shown,decimals=significant(value)
			return trim(string.format("%."..decimals.."f",shown))
		end
		return tostring(math.floor(value+value*1e-9))
	end
	local chosen=suffixes[1]
	for _,candidate in ipairs(suffixes) do
		if value>=candidate[1] then chosen=candidate else break end
	end
	local scaled=value/chosen[1]
	local shown,decimals=significant(scaled)
	return trim(string.format("%."..decimals.."f",shown))..chosen[2]
end
local function format(value,rate)
	if type(value)~="number" or value~=value then return "0" end
	if value==math.huge then return "∞" end
	if value==-math.huge then return "-∞" end
	if value<0 then return "-"..formatPositive(-value,rate) end
	return formatPositive(value,rate)
end
function NumberFormat.Format(value) return format(value,false) end
function NumberFormat.FormatRate(value) return format(value,true).."/s" end
return NumberFormat
