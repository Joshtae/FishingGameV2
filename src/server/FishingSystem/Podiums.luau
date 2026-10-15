-- Server-only podium placement/display API.
-- RefreshUnlockState(player, plot), Rebuild(player, plot), RefreshPodium(player,podiumId),
-- PlaceCharacter(player,podiumId,characterUid), RemoveCharacter(player,podiumId), and Init() are supported.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CollectionService=game:GetService("CollectionService")
local root=script.Parent
local Data=require(root.Data)
local Plots=require(root.Plots)
local Characters=require(ReplicatedStorage.FishingSystemV2.Characters)
local Income=require(root.Income)
local Inventory=require(root.Inventory)
local Remotes=ReplicatedStorage.FishingSystemV2.Remotes
local Podiums={}
local initialized=false
local function standFor(podium)
	return podium:FindFirstChild("PodiumPart",true) or podium:FindFirstChild("RobuxPodium",true)
end
local function characterByUid(data,uid)
	for _, item in ipairs(data.Characters) do if item.uid==uid then return item end end
end
local function clearDisplay(podium)
	for _, item in ipairs(podium:GetDescendants()) do
		if CollectionService:HasTag(item,"PlacedCharacter") then item:Destroy() end
	end
end
function Podiums.RefreshUnlockState(player,plot)
	local data=Data.Get(player)
	if not data or not plot then return end
	for podiumId,podium in pairs(Plots.GetPodiums(plot)) do
		local state=data.Plot.Podiums[podiumId]
		local prompt=podium:FindFirstChild("PlacePrompt",true)
		if prompt and prompt:IsA("ProximityPrompt") then prompt.Enabled=state and state.unlocked==true or false end
	end
end
function Podiums.RefreshPodium(player,podiumId)
	local plot,data=Plots.Get(player),Data.Get(player)
	local podium=plot and Plots.GetPodiums(plot)[podiumId]
	local state=data and data.Plot.Podiums[podiumId]
	if not podium or not state then return end
	clearDisplay(podium)
	if not state.unlocked or not state.characterUid then return end
	local character=characterByUid(data,state.characterUid)
	local definition=character and Characters.GetById(character.id)
	local stand=standFor(podium)
	if definition and stand then
		local display=Characters.CreateDisplay(definition,stand)
		if display then
			display:SetAttribute("CPS",Income.GetPodiumCPS(player,podiumId))
			display.Parent=podium
		end
	end
end
function Podiums.Rebuild(player,plot)
	plot=plot or Plots.Get(player)
	if not plot then return end
	Podiums.RefreshUnlockState(player,plot)
	for podiumId in pairs(Plots.GetPodiums(plot)) do Podiums.RefreshPodium(player,podiumId) end
end
function Podiums.PlaceCharacter(player,podiumId,characterUid)
	local data,plot=Data.Get(player),Plots.Get(player)
	local podium=plot and Plots.GetPodiums(plot)[podiumId]
	local state=data and data.Plot.Podiums[podiumId]
	if not podium or not state or state.unlocked~=true or state.characterUid then return false,"podium unavailable" end
	local character=characterByUid(data,characterUid)
	local definition=character and Characters.GetById(character.id)
	if not definition or definition.placeholder or Inventory.IsPlaced(player,characterUid) then return false,"character unavailable" end
	if Inventory.GetHeldUid(player)~=characterUid then return false,"hold a character first" end
	if not Inventory.ClearHotbarSlot(player,characterUid) then return false,"character unavailable" end
	state.characterUid=characterUid
	Podiums.RefreshPodium(player,podiumId)
	return true
end

function Podiums.RemoveCharacter(player,podiumId)
	local data,plot=Data.Get(player),Plots.Get(player)
	local podium=plot and Plots.GetPodiums(plot)[podiumId]
	local state=data and data.Plot.Podiums[podiumId]
	if not podium or not state or state.unlocked~=true or type(state.characterUid)~="string" then return false,"podium unavailable" end
	if not Inventory.HasRoom(player,1) then return false,"Backpack full" end
	local uid=state.characterUid
	state.characterUid=nil
	Podiums.RefreshPodium(player,podiumId)
	local added=Inventory.SetHotbarSlot(player,uid)
	if not added then Inventory.NotifyChanged(player) end
	return true
end
function Podiums.Init()
	if initialized then return end
	initialized=true
	for index=1,8 do
		local plot=workspace:FindFirstChild("Plot"..index)
		if plot then
			for podiumId,podium in pairs(Plots.GetPodiums(plot)) do
				local prompt=podium:FindFirstChild("PlacePrompt",true)
				if prompt and prompt:IsA("ProximityPrompt") then
					prompt.Triggered:Connect(function(player)
						if Plots.Get(player)~=plot then return end
						local data=Data.Get(player)
						local state=data and data.Plot.Podiums[podiumId]
						if not state or not state.unlocked then return end
						if state.characterUid then
							local ok,reason=Podiums.RemoveCharacter(player,podiumId)
							if not ok and reason=="Backpack full" then Remotes.InventoryMessage:FireClient(player,"Backpack full") end
							return
						end
						local heldUid=Inventory.GetHeldUid(player)
						if not heldUid then return end
						Podiums.PlaceCharacter(player,podiumId,heldUid)
					end)
				end
			end
		end
	end
end
return Podiums
