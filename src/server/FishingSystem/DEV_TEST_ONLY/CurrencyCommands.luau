-- Studio-only currency diagnostics. Delete DEV_TEST_ONLY before release.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Currency=require(script.Parent.Parent.Currency)
local NumberFormat=require(ReplicatedStorage.FishingSystemV2.NumberFormat)
if not RunService:IsStudio() then return {} end
local Commands={}
local function number(text) return tonumber(text) end
function Commands.SetGems(player,text)
	if not RunService:IsStudio() then return end
	local value=number(text);local ok=Currency.SetGems(player,value)
	print("[DEV_TEST_ONLY] /devgems ok="..tostring(ok).." value="..tostring(value))
end
function Commands.AddCash(player,text)
	if not RunService:IsStudio() then return end
	local value=number(text);local ok=Currency.AddCash(player,value)
	print("[DEV_TEST_ONLY] /devaddcash ok="..tostring(ok).." value="..tostring(value))
end
function Commands.SpendCash(player,text)
	if not RunService:IsStudio() then return end
	local value=number(text);local ok=Currency.TrySpendCash(player,value)
	print("[DEV_TEST_ONLY] /devspend ok="..tostring(ok).." value="..tostring(value))
end
function Commands.Format(_,text)
	if not RunService:IsStudio() then return end
	local value=number(text)
	print("[DEV_TEST_ONLY] /devformat "..tostring(value).." => "..NumberFormat.Format(value).." | "..NumberFormat.FormatRate(value))
end
return Commands
