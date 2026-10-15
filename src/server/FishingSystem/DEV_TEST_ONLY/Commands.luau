--[[
	Studio-only diagnostics. Delete the entire DEV_TEST_ONLY folder before release.
	/devdata /devplotmap /devcash /devsave /devoldversion /devfailload /devplotclaim /devclearplot
	/devgive <id or rarity> [count] [mutation] /devclearchars /devextraslots <n> /devhotbar /devstored <podiumId> <amount> /devcps
	/devcharcheck /devbuttonmap /devgems <n> /devaddcash <n> /devspend <n> /devformat <n> /devplaytime <seconds>
	/devindex /devdiscover <id|all> /devclaimall /devindexreset <claimed|all> /devindexbackfill /devindexgems <rarity> <n> /devindexshowall <on|off> /devleaderboardpreview <on|off> /devcatches <n>
]]
local CollectionService=game:GetService("CollectionService")
local HttpService=game:GetService("HttpService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local root=script.Parent.Parent
local Data=require(root.Data)
local Plots=require(root.Plots)
local Podiums=require(root.Podiums)
local Income=require(root.Income)
local Currency=require(root.Currency)
local Inventory=require(root.Inventory)
local CurrencyCommands=require(script.Parent.CurrencyCommands)
local ClaimButtons=require(root.ClaimButtons)
local PlaytimeService=require(root.PlaytimeService)
local shared=ReplicatedStorage:WaitForChild("FishingSystemV2")
local Rarities=require(shared.Rarities)
local Characters=require(shared.Characters)
local IndexConfig=require(shared.IndexConfig)
local IndexService=require(root.IndexService)
local Rolls=require(root.Rolls)
local Modifiers=require(root.Modifiers)
local Commands={}
local DEV_USER_IDS={[50571834]=true}
local function finite(value) return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge and value>=0 end
local function authorized(player) return RunService:IsStudio() and DEV_USER_IDS[player.UserId]==true end

function Commands.PrintData(player)
	local data=Data.Get(player)
	if not data then warn("[DEV_TEST_ONLY] No loaded data for "..player.Name);return end
	print("[DEV_TEST_ONLY] Data for "..player.Name..": "..HttpService:JSONEncode(data))
end
function Commands.PrintPlotMap()
	local rows={}
	for i=1,8 do local plot=Workspace:FindFirstChild("Plot"..i);table.insert(rows,{plot="Plot"..i,ownerUserId=plot and Plots.GetOwnerUserId(plot) or nil}) end
	print("[DEV_TEST_ONLY] Plot map: "..HttpService:JSONEncode(rows))
end
function Commands.SetCash(player,amount)
	local ok=Currency.SetCash(player,amount)
	if ok then print("[DEV_TEST_ONLY] Cash set to "..amount) end
end
function Commands.ForceSave(player) print("[DEV_TEST_ONLY] Force save: "..tostring(Data.ForceSave(player))) end
function Commands.SimulateOldVersion(player)
	local data=Data.Get(player);if not data then return end
	data.DataVersion=0;Data.RunMigrationsForTest(player,data)
	print("[DEV_TEST_ONLY] Old-version migration result: DataVersion="..tostring(data.DataVersion))
end
function Commands.SimulateFailedLoad(player) player:Kick("Could not load your data. Please rejoin.") end
function Commands.SimulateSameTickClaims()
	for i=1,8 do local plot=Workspace:FindFirstChild("Plot"..i);if plot and Plots.GetOwnerUserId(plot) then warn("[DEV_TEST_ONLY] All plots must be free before /devplotclaim.");return end end
	local claims,unique={},{}
	for i=1,8 do local fake={UserId=-i};local plot=Plots.Assign(fake);claims[i]={player=fake,plot=plot};if plot then unique[plot]=true end end
	local ninth=Plots.Assign({UserId=-9});local count=0;for _ in pairs(unique) do count+=1 end
	print(("[DEV_TEST_ONLY] Claims=%d, distinct=%d, ninth=%s"):format(#claims,count,tostring(ninth)))
	for _,claim in ipairs(claims) do local plot=Plots.PrepareRelease(claim.player);Plots.FinishRelease(claim.player,plot) end
end
function Commands.TestClearPlot(player)
	local plot=Plots.Get(player);if not plot then warn("[DEV_TEST_ONLY] Player has no assigned plot.");return end
	local tagged=Instance.new("Part");tagged.Name="DEV_TaggedPlacedCharacter";tagged.Anchored=true;tagged.Parent=plot;CollectionService:AddTag(tagged,Plots.PlacedCharacterTag)
	local untagged=Instance.new("Part");untagged.Name="DEV_UntaggedControl";untagged.Anchored=true;untagged.Parent=plot
	Plots.ClearPlot(plot);local passed=tagged.Parent==nil and untagged.Parent==plot;untagged:Destroy()
	print("[DEV_TEST_ONLY] ClearPlot tagged-only test passed: "..tostring(passed))
end
function Commands.GiveCharacters(player,selector,countText,mutation)
	local data=Data.Get(player);if not data then warn("[DEV_TEST_ONLY] No loaded data.");return end
	local definition=Characters.GetById(string.lower(selector or ""))
	if not definition then local r=Rarities.GetByName(selector);local choices=r and Characters.GetActiveByRarity(r.index) or {};definition=choices[1] end
	if not definition then warn("[DEV_TEST_ONLY] Unknown active character id or rarity: "..tostring(selector));return end
	local count=(countText==nil or countText=="") and 1 or tonumber(countText)
	if type(count)~="number" or count%1~=0 or count<1 or count>100 then warn("[DEV_TEST_ONLY] Count must be 1-100.");return end
	for _=1,count do
		local uid, reason = Inventory.AddCharacter(player, definition.id, (mutation~="" and mutation or nil), {bypassCapacity=true})
		if not uid then warn("[DEV_TEST_ONLY] Could not grant character: "..tostring(reason)); return end
	end
	print(("[DEV_TEST_ONLY] Added %d %s character(s) through Inventory.AddCharacter"):format(count,definition.id))
end
function Commands.ClearCharacters(player)
	local data,plot=Data.Get(player),Plots.Get(player);if not data then return end
	warn("[DEV_TEST_ONLY] /devclearchars changes real saved Studio data: Characters, Hotbar, ExtraSlots, and podium placements.")
	Inventory.PutAway(player)
	data.Characters={}
	data.Hotbar={}
	data.ExtraSlots=0
	if plot then
		Plots.ClearPlot(plot)
		for id in pairs(Plots.GetPodiums(plot)) do
			local state=data.Plot.Podiums[id]
			state.characterUid=nil
		end
		Podiums.Rebuild(player,plot)
	end
	Inventory.NotifyChanged(player)
	print("[DEV_TEST_ONLY] Cleared Characters, Hotbar, ExtraSlots, and podium character UIDs; currencies, rods, settings, and stored cash were kept.")
end
function Commands.AddExtraSlots(player,amountText)
	local amount=tonumber(amountText)
	local ok=Inventory.AddExtraSlots(player,amount)
	print("[DEV_TEST_ONLY] /devextraslots ok="..tostring(ok).." amount="..tostring(amount))
end
function Commands.PrintHotbar(player)
	local hotbar=Inventory.GetHotbar(player) or {}
	print("[DEV_TEST_ONLY] Hotbar="..HttpService:JSONEncode(hotbar).." heldUid="..tostring(Inventory.GetHeldUid(player)).." activeSlot="..tostring(Inventory.GetActiveSlot(player)).." used="..Inventory.GetUsedSlots(player).." capacity="..Inventory.GetCapacity(player))
end
function Commands.SetStoredCash(player,podiumId,amountText)
	local amount=tonumber(amountText);if not finite(amount) then warn("[DEV_TEST_ONLY] Stored cash must be finite and non-negative.");return end
	local data,plot=Data.Get(player),Plots.Get(player);local state=data and data.Plot.Podiums[podiumId];local podium=plot and Plots.GetPodiums(plot)[podiumId]
	if not state or not podium or not state.unlocked then warn("[DEV_TEST_ONLY] Podium must exist and be unlocked.");return end
	state.storedCash=amount;Podiums.RefreshPodium(player,podiumId);print("[DEV_TEST_ONLY] Stored cash on "..podiumId.." set to "..amount)
end
function Commands.PrintCPS(player)
	local plot=Plots.Get(player);if not plot then warn("[DEV_TEST_ONLY] No assigned plot.");return end
	local rows={};for id in pairs(Plots.GetPodiums(plot)) do table.insert(rows,id.."="..Income.GetPodiumCPS(player,id)) end;table.sort(rows)
	print(("[DEV_TEST_ONLY] CPS: %s | total=%s"):format(table.concat(rows,", "),Income.GetTotalCPS(player)))
end
function Commands.CharacterCheck()
	local report=Characters.Validate()
	print(("[DEV_TEST_ONLY] Character check: total=%d real=%d placeholders=%d errors=%d perRarity=%s"):format(report.total,report.real,report.placeholders,#report.errors,HttpService:JSONEncode(report.perRarity)))
	for _,err in ipairs(report.errors) do warn("[DEV_TEST_ONLY] Character check: "..err) end
end
function Commands.ButtonMap()
	print("[DEV_TEST_ONLY] Button mapping: "..HttpService:JSONEncode(ClaimButtons.CLAIM_BUTTON_TO_PODIUM))
	local shown=ClaimButtons.ToggleDevButtonMap()
	print("[DEV_TEST_ONLY] /devbuttonmap labels "..(shown and "shown" or "removed"))
end
function Commands.SetPlaytime(player, amountText)
	local amount = tonumber(amountText)
	if not finite(amount) then
		warn("[DEV_TEST_ONLY] PlaytimeSeconds must be finite and non-negative.")
		return
	end
	local data = Data.Get(player)
	if not data then
		warn("[DEV_TEST_ONLY] No loaded data.")
		return
	end
	data.PlaytimeSeconds = amount
	PlaytimeService.RefreshPlayer(player)
	print("[DEV_TEST_ONLY] PlaytimeSeconds set to " .. amount)
end
local function activeDefinition(id)
	if type(id) ~= "string" then return nil end
	for _, definition in ipairs(Characters.GetActive()) do
		if definition.id == id then return definition end
	end
	return nil
end

function Commands.PrintIndex(player)
	local snapshot = IndexService.GetSnapshot(player)
	if not snapshot then warn("[DEV_TEST_ONLY] No loaded Index data."); return end
	local rod = Rolls.GetEquippedRod(player)
	local castLuck = rod and rod.Luck * Modifiers.GetCastLuck(player) or 0
	print("[DEV_TEST_ONLY] Index=" .. HttpService:JSONEncode(snapshot)
		.. " | GetLuckMultiplier=" .. tostring(Modifiers.GetLuckMultiplier(player))
		.. " | CastLuck=" .. tostring(castLuck)
		.. " | Chances=" .. HttpService:JSONEncode(Rolls.GetChances(player)))
end

function Commands.DiscoverIndex(player, selector)
	if string.lower(tostring(selector)) == "all" then
		local count = 0
		for _, definition in ipairs(Characters.GetActive()) do if IndexService.Discover(player, definition.id) then count += 1 end end
		print("[DEV_TEST_ONLY] Index discovered " .. count .. " active id(s).")
		return
	end
	local definition = activeDefinition(string.lower(tostring(selector or "")))
	if not definition then warn("[DEV_TEST_ONLY] Unknown or inactive Index id."); return end
	print("[DEV_TEST_ONLY] Index discover " .. definition.id .. " new=" .. tostring(IndexService.Discover(player, definition.id)))
end

function Commands.ClaimAllIndex(player)
	print("[DEV_TEST_ONLY] Index claimed " .. tostring(IndexService.ClaimAll(player)) .. " id(s).")
end

function Commands.ResetIndex(player, mode)
	local data = Data.Get(player)
	if not data or type(data.Index) ~= "table" then warn("[DEV_TEST_ONLY] No loaded Index data."); return end
	mode = string.lower(tostring(mode))
	if mode == "claimed" then
		data.Index.Claimed = {}
	elseif mode == "all" then
		data.Index.Discovered, data.Index.Claimed = {}, {}
	else
		warn("[DEV_TEST_ONLY] Usage: /devindexreset claimed|all")
		return
	end
	IndexService.RefreshPlayer(player)
	print("[DEV_TEST_ONLY] Index reset " .. mode)
end

function Commands.BackfillIndex(player)
	local data = Data.Get(player)
	if not data then warn("[DEV_TEST_ONLY] No loaded data."); return end
	Data.Migrations[3](data)
	Data.Sanitize(player, data)
	IndexService.RefreshPlayer(player)
	print("[DEV_TEST_ONLY] Re-ran Index migration backfill.")
end

function Commands.SetIndexGems(rarityText, amountText)
	local rarity, amount = tonumber(rarityText), tonumber(amountText)
	if type(rarity) ~= "number" or rarity % 1 ~= 0 or rarity < 1 or rarity > 11 or not finite(amount) then
		warn("[DEV_TEST_ONLY] Usage: /devindexgems <rarity 1-11> <finite non-negative amount>")
		return
	end
	IndexConfig.IndexDiscoveryGems[rarity] = amount
	print("[DEV_TEST_ONLY] Runtime IndexDiscoveryGems[" .. rarity .. "]=" .. amount)
end

function Commands.SetIndexShowAll(value)
	local lower = string.lower(tostring(value))
	if lower ~= "on" and lower ~= "off" then warn("[DEV_TEST_ONLY] Usage: /devindexshowall on|off"); return end
	Workspace:SetAttribute("FishingSystemV2_IndexShowAll", lower == "on")
	print("[DEV_TEST_ONLY] FishingSystemV2_IndexShowAll=" .. lower)
end

-- Toggles the local-only Studio leaderboard sample rows. This never reads or writes profile data.
function Commands.SetLeaderboardPreview(argument)
	if not RunService:IsStudio() then return end
	local value=string.lower(tostring(argument or ""))
	if value=="on" then
		Workspace:SetAttribute("R6LeaderboardPreview",true)
		print("[DEV_TEST_ONLY] Leaderboard preview enabled.")
	elseif value=="off" then
		Workspace:SetAttribute("R6LeaderboardPreview",false)
		print("[DEV_TEST_ONLY] Leaderboard preview disabled.")
	else
		warn("[DEV_TEST_ONLY] Usage: /devleaderboardpreview <on|off>")
	end
end

function Commands.SetCatches(player, amountText)
	local amount = tonumber(amountText)
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge or amount < 0 or amount % 1 ~= 0 then
		warn("[DEV_TEST_ONLY] Usage: /devcatches <non-negative integer>")
		return
	end
	local data = Data.Get(player)
	if not data then warn("[DEV_TEST_ONLY] No loaded data."); return end
	data.TotalCatches = amount
	player:SetAttribute("Catches", amount)
	print("[DEV_TEST_ONLY] TotalCatches set to " .. amount)
end

function Commands.HandleChat(player,message)

	if not authorized(player) then return end
	local command,argument=string.match(message,"^(%S+)%s*(.*)$")
	if command=="/devdata" then Commands.PrintData(player)
	elseif command=="/devplotmap" then Commands.PrintPlotMap()
	elseif command=="/devcash" then Commands.SetCash(player,tonumber(argument))
	elseif command=="/devsave" then Commands.ForceSave(player)
	elseif command=="/devoldversion" then Commands.SimulateOldVersion(player)
	elseif command=="/devfailload" then Commands.SimulateFailedLoad(player)
	elseif command=="/devplotclaim" then Commands.SimulateSameTickClaims()
	elseif command=="/devclearplot" then Commands.TestClearPlot(player)
	elseif command=="/devgive" then local a,b,c=string.match(argument,"^(%S+)%s*(%S*)%s*(%S*)$");Commands.GiveCharacters(player,a,b,c)
	elseif command=="/devclearchars" then Commands.ClearCharacters(player)
	elseif command=="/devextraslots" then Commands.AddExtraSlots(player,argument)
	elseif command=="/devhotbar" then Commands.PrintHotbar(player)
	elseif command=="/devstored" then local a,b=string.match(argument,"^(%S+)%s*(%S*)$");Commands.SetStoredCash(player,a,b)
	elseif command=="/devcps" then Commands.PrintCPS(player)
	elseif command=="/devgems" then CurrencyCommands.SetGems(player,argument)
	elseif command=="/devaddcash" then CurrencyCommands.AddCash(player,argument)
	elseif command=="/devspend" then CurrencyCommands.SpendCash(player,argument)
	elseif command=="/devformat" then CurrencyCommands.Format(player,argument)
	elseif command=="/devcharcheck" then Commands.CharacterCheck()
	elseif command=="/devbuttonmap" then Commands.ButtonMap()
	elseif command=="/devplaytime" then Commands.SetPlaytime(player,argument)
	elseif command=="/devindex" then Commands.PrintIndex(player)
	elseif command=="/devdiscover" then Commands.DiscoverIndex(player,argument)
	elseif command=="/devclaimall" then Commands.ClaimAllIndex(player)
	elseif command=="/devindexreset" then Commands.ResetIndex(player,argument)
	elseif command=="/devindexbackfill" then Commands.BackfillIndex(player)
	elseif command=="/devindexgems" then local a,b=string.match(argument,"^(%S+)%s*(%S*)$"); Commands.SetIndexGems(a,b)
	elseif command=="/devindexshowall" then Commands.SetIndexShowAll(argument)
	elseif command=="/devleaderboardpreview" then Commands.SetLeaderboardPreview(argument)
	elseif command=="/devcatches" then Commands.SetCatches(player,argument)
	end
end
return Commands
