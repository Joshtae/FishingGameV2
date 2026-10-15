-- Starts the V2 podium, income, collection, and validation services.
local root=script.Parent
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Data=require(root.Data)
local Currency=require(root.Currency)
local Plots=require(root.Plots)
local Podiums=require(root.Podiums)
local Income=require(root.Income)
local ClaimButtons=require(root.ClaimButtons)
local Characters=require(ReplicatedStorage.FishingSystemV2.Characters)
Podiums.Init()
ClaimButtons.Init()
Income.Start()
Plots.Assigned:Connect(function(player,plot) Podiums.Rebuild(player,plot) end)
local report=Characters.Validate()
print(("[FishingSystemV2] Character validation: total=%d real=%d placeholders=%d errors=%d"):format(report.total,report.real,report.placeholders,#report.errors))
for _,err in ipairs(report.errors) do warn("[FishingSystemV2] Character validation: "..err) end
return true
