-- Server-only currency authority.
-- GetCash(player), GetGems(player), AddCash(player, amount), AddGems(player, amount),
-- TrySpendCash(player, amount), TrySpendGems(player, amount), SetCash(player, amount),
-- SetGems(player, amount), and Refresh(player) never yield. Changed(player, kind, newValue)
-- fires after a successful server-side mutation or refresh.
local Players=game:GetService("Players")
local root=script.Parent
local Data=require(root.Data)
local Signal=require(root.Signal)
local Currency={MaxCurrency=1e300,Changed=Signal.new()}
local lastReplication,pending={},{}
local function valid(value,positive)
	return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge and (positive and value>0 or value>=0)
end
local function syncLeaderstats(player,rebirths)
	local folder=player:FindFirstChild("leaderstats")
	if not folder then folder=Instance.new("Folder");folder.Name="leaderstats";folder.Parent=player end
	local stat=folder:FindFirstChild("Rebirths")
	if not stat then stat=Instance.new("IntValue");stat.Name="Rebirths";stat.Parent=folder end
	stat.Value=math.clamp(math.floor(rebirths),0,250)
end
local function replicateNow(player)
	local data=Data.Get(player)
	if not data or player.Parent~=Players then return end
	player:SetAttribute("Cash",data.Cash)
	player:SetAttribute("Gems",data.Gems)
	syncLeaderstats(player,data.Rebirths)
	lastReplication[player]=os.clock()
	pending[player]=nil
end
local function queueReplication(player)
	local now=os.clock()
	if now-(lastReplication[player] or -math.huge)>=0.1 then replicateNow(player);return end
	if pending[player] then return end
	pending[player]=true
	task.delay(0.1-(now-lastReplication[player]),function() replicateNow(player) end)
end
local function mutate(player,kind,amount,spend)
	local data=Data.Get(player)
	if not data then return false end
	if not valid(amount,true) then warn("[FishingSystem.Currency] Rejected invalid "..kind.." amount for UserId "..player.UserId);return false end
	local balance=data[kind]
	if not valid(balance,false) then warn("[FishingSystem.Currency] Rejected invalid stored "..kind.." for UserId "..player.UserId);return false end
	if spend and not (balance >= amount) then return false end
	local nextValue=spend and balance-amount or math.min(Currency.MaxCurrency,balance+amount)
	data[kind]=math.max(0,math.min(Currency.MaxCurrency,nextValue))
	Currency.Changed:Fire(player,kind,data[kind])
	queueReplication(player)
	return true
end
function Currency.GetCash(player) local data=Data.Get(player);return data and data.Cash or false end
function Currency.GetGems(player) local data=Data.Get(player);return data and data.Gems or false end
function Currency.AddCash(player,amount) return mutate(player,"Cash",amount,false) end
function Currency.AddGems(player,amount) return mutate(player,"Gems",amount,false) end
function Currency.TrySpendCash(player,amount) return mutate(player,"Cash",amount,true) end
function Currency.TrySpendGems(player,amount) return mutate(player,"Gems",amount,true) end
local function set(player,kind,amount)
	local data=Data.Get(player)
	if not data then return false end
	if not valid(amount,false) then warn("[FishingSystem.Currency] Rejected invalid "..kind.." set value for UserId "..player.UserId);return false end
	data[kind]=math.min(Currency.MaxCurrency,amount)
	Currency.Changed:Fire(player,kind,data[kind])
	queueReplication(player)
	return true
end
function Currency.SetCash(player,amount) return set(player,"Cash",amount) end
function Currency.SetGems(player,amount) return set(player,"Gems",amount) end
function Currency.Refresh(player)
	local data=Data.Get(player)
	if not data then return false end
	replicateNow(player)
	Currency.Changed:Fire(player,"Cash",data.Cash)
	Currency.Changed:Fire(player,"Gems",data.Gems)
	Currency.Changed:Fire(player,"Rebirths",data.Rebirths)
	return true
end
Data.Loaded:Connect(Currency.Refresh)
Players.PlayerRemoving:Connect(function(player) lastReplication[player]=nil;pending[player]=nil end)
return Currency
