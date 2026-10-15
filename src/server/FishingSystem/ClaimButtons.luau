-- Server-only ClaimPart collection. CLAIM_BUTTON_TO_PODIUM is the single source of button mapping.
-- Init(), ToggleDevButtonMap(), and CleanupDevButtonMap() are supported.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Plots=require(script.Parent.Plots)
local Income=require(script.Parent.Income)
local CashCollected=ReplicatedStorage.FishingSystemV2.Remotes:WaitForChild("CashCollected")
local ClaimButtons={CollectMaxDistance=20,PlayerDebounce=0.3,ButtonDebounce=0.5}
ClaimButtons.CLAIM_BUTTON_TO_PODIUM={
	BuyButton1="Podium1",BuyButton2="Podium2",BuyButton3="Podium3",BuyButton4="Podium4",
	BuyButton5="AdditionalPodium1",BuyButton6="AdditionalPodium2",BuyButton7="Podium5",
	BuyButton8="Podium6",BuyButton9="Podium7",BuyButton10="Podium8",
}
local initialized,lastPlayer,lastButton,token=false, {}, {}, 0
local function getPlayerFromHit(hit)
	local current=hit
	while current and current~=workspace do
		if current:IsA("Model") then
			local player=Players:GetPlayerFromCharacter(current)
			if player then return player,current end
		end
		current=current.Parent
	end
end
local function tryCollect(plot,claimPart,podiumId,hit)
	local player,character=getPlayerFromHit(hit)
	if not player or Plots.Get(player)~=plot or Plots.GetOwnerUserId(plot)~=player.UserId then return end
	local humanoid=character:FindFirstChildOfClass("Humanoid")
	local root=character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health<=0 or not root or not root:IsA("BasePart") then return end
	if (root.Position-claimPart.Position).Magnitude>ClaimButtons.CollectMaxDistance then return end
	local now=os.clock()
	if now-(lastPlayer[player] or -math.huge)<ClaimButtons.PlayerDebounce then return end
	if now-(lastButton[claimPart] or -math.huge)<ClaimButtons.ButtonDebounce then return end
	local amount=Income.CollectPodium(player,podiumId)
	if amount>0 then
		CashCollected:FireClient(player,amount,claimPart.CFrame:PointToWorldSpace(Vector3.new(0,claimPart.Size.Y/2,0)))
		lastPlayer[player]=now
		lastButton[claimPart]=now
		token+=1
		claimPart:SetAttribute("FishingSystemV2ClaimAmount",amount)
		claimPart:SetAttribute("FishingSystemV2ClaimToken",token)
	end
end
function ClaimButtons.Init()
	if initialized then return end
	initialized=true
	for plotIndex=1,8 do
		local plot=workspace:FindFirstChild("Plot"..plotIndex)
		if plot then
			for buttonName,podiumId in pairs(ClaimButtons.CLAIM_BUTTON_TO_PODIUM) do
				local button=plot:FindFirstChild(buttonName,true)
				local claimPart=button and button:FindFirstChild("ClaimPart",true)
				if claimPart and claimPart:IsA("BasePart") then
					claimPart.Touched:Connect(function(hit) tryCollect(plot,claimPart,podiumId,hit) end)
				else
					warn("[FishingSystemV2] Missing ClaimPart for "..plot.Name.."."..buttonName)
				end
			end
		end
	end
end
-- DEV_ONLY_BEGIN CleanupDevButtonMap
function ClaimButtons.CleanupDevButtonMap()
	for _,plot in ipairs(workspace:GetChildren()) do
		if plot.Name:match("^Plot%d+$") then
			for _,item in ipairs(plot:GetDescendants()) do
				if item:IsA("BillboardGui") and item.Name=="DEV_ButtonMapLabel" and item:GetAttribute("FishingSystemV2DevButtonMap") then item:Destroy() end
			end
		end
	end
end
-- DEV_ONLY_END CleanupDevButtonMap
-- DEV_ONLY_BEGIN ToggleDevButtonMap
function ClaimButtons.ToggleDevButtonMap()
	if not RunService:IsStudio() then return false,"Studio only" end
	local found=false
	for _,plot in ipairs(workspace:GetChildren()) do
		for _,item in ipairs(plot:GetDescendants()) do
			if item:IsA("BillboardGui") and item.Name=="DEV_ButtonMapLabel" and item:GetAttribute("FishingSystemV2DevButtonMap") then found=true;break end
		end
	end
	if found then ClaimButtons.CleanupDevButtonMap();return false end
	for plotIndex=1,8 do
		local plot=workspace:FindFirstChild("Plot"..plotIndex)
		if plot then for buttonName,podiumId in pairs(ClaimButtons.CLAIM_BUTTON_TO_PODIUM) do
			local button=plot:FindFirstChild(buttonName,true)
			local claimPart=button and button:FindFirstChild("ClaimPart",true)
			if claimPart then
				local gui=Instance.new("BillboardGui")
				gui.Name="DEV_ButtonMapLabel";gui:SetAttribute("FishingSystemV2DevButtonMap",true)
				gui.Adornee=claimPart;gui.Size=UDim2.fromOffset(170,34);gui.StudsOffset=Vector3.new(0,3,0);gui.AlwaysOnTop=true
				local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundColor3=Color3.fromRGB(25,50,95);label.BackgroundTransparency=.2;label.TextColor3=Color3.new(1,1,1);label.TextScaled=true;label.Text=buttonName.." → "..podiumId;label.Parent=gui
				gui.Parent=claimPart
			end
		end end
	end
	return true
end
-- DEV_ONLY_END ToggleDevButtonMap
return ClaimButtons
