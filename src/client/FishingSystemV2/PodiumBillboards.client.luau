local CollectionService=game:GetService("CollectionService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local template=ReplicatedStorage.FishingSystemV2.PodiumBillboardTemplate
local NumberFormat=require(ReplicatedStorage.FishingSystemV2.NumberFormat)
local function update(gui,model)
	gui.Label.Text=(model:GetAttribute("DisplayName") or model:GetAttribute("CharacterId") or "Character").."\n$"..NumberFormat.FormatRate(model:GetAttribute("CPS") or 0)
end
local function attach(model)
	if not model:IsA("Model") then return end
	local gui=model:FindFirstChild("FishingSystemV2Billboard")
	if not gui then
		local root=model.PrimaryPart or model:FindFirstChild("HumanoidRootPart",true)
		if not root then return end
		gui=template:Clone();gui.Name="FishingSystemV2Billboard";gui.Adornee=root;gui.Parent=model
		model:GetAttributeChangedSignal("CPS"):Connect(function() if gui.Parent then update(gui,model) end end)
		model:GetAttributeChangedSignal("DisplayName"):Connect(function() if gui.Parent then update(gui,model) end end)
	end
	update(gui,model)
end
for _,item in ipairs(CollectionService:GetTagged("PlacedCharacter")) do attach(item) end
CollectionService:GetInstanceAddedSignal("PlacedCharacter"):Connect(attach)
