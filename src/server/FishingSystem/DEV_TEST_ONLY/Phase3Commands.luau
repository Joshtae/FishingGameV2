--[[ Studio-only Phase 3 diagnostics (/devresumetest and /devautofishsave included). Delete DEV_TEST_ONLY before release. ]]
local HttpService=game:GetService("HttpService")
local KeyframeSequenceProvider=game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then return {} end
local root=script.Parent.Parent
local Config=require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local Characters=require(ReplicatedStorage.FishingSystemV2.Characters)
local Inventory=require(root.Inventory)
local Rolls=require(root.Rolls)
local Modifiers=require(root.Modifiers)
local Sessions=require(root.FishingSessions)
local Data=require(root.Data)
local Remotes=ReplicatedStorage.FishingSystemV2.Remotes
local Commands={}
local DEV_USER_IDS={[50571834]=true}
local function authorized(p) return DEV_USER_IDS[p.UserId]==true end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
function Commands.HandleChat(player,message)
	if not authorized(player) then return end
	local cmd,arg=string.match(message,"^(%S+)%s*(.*)$")
	if cmd=="/devrod" then
		if Rolls.SetDevRod(player,string.lower(arg)) then print("[DEV_TEST_ONLY] Equipped DEV rod "..arg) else warn("[DEV_TEST_ONLY] Use /devrod max or /devrod steel") end
	elseif cmd=="/devfishtoggle" then
		local key=string.lower(arg);local current=key=="fasterreel" and Modifiers.HasFasterReel(player) or key=="autofish" and Modifiers.HasAutoFish(player)
		if Modifiers.SetDevToggle(player,key,not current) then
			if key=="autofish" then Remotes.FishingMessage:FireClient(player,"__AUTO_AVAILABLE__"..tostring(not current)) end
			print("[DEV_TEST_ONLY] "..key.."="..tostring(not current))
		end
	elseif cmd=="/devlatency" then
		local value=tonumber(arg);if finite(value) and value>=0 then Sessions.SetDevLatency(player,value);print("[DEV_TEST_ONLY] fake one-way latency="..value) end
	elseif cmd=="/devforcepress" then Sessions.ForcePress(player,string.lower(arg))
	elseif cmd=="/devodds" then
		local chances=Rolls.GetChances(player,tonumber(arg));print("[DEV_TEST_ONLY] odds="..HttpService:JSONEncode(chances))
	elseif cmd=="/devrolls" then
		local luck,n=string.match(arg,"^(%S+)%s+(%S+)$");luck,n=tonumber(luck),tonumber(n);if finite(luck) and n and n%1==0 and n>0 and n<=100000 then local out={};for _=1,n do local _,r=Rolls.Roll(player,Random.new(),luck);out[r]=(out[r]or 0)+1 end;print("[DEV_TEST_ONLY] rolls="..HttpService:JSONEncode(out)) end
	elseif cmd=="/devfillbag" then
		local n=tonumber(arg) or 0;local id=Characters.GetActive()[1] and Characters.GetActive()[1].id;for _=1,n do Inventory.AddCharacter(player,id,nil,{bypassCapacity=true}) end;print("[DEV_TEST_ONLY] filled "..n.." entries")
	elseif cmd=="/devconfig" then
		local key,value=string.match(arg,"^(%S+)%s+(%S+)$");if key and Config[key]~=nil then local number=tonumber(value);Config[key]=number~=nil and number or value=="true" and true or value=="false" and false or Config[key];print("[DEV_TEST_ONLY] config "..key.."="..tostring(Config[key])) end
	elseif cmd=="/devshowzones" then Remotes.FishingMessage:FireClient(player,"__DEV_SHOW_ZONES__")
	elseif cmd=="/devautofishsave" then
		local data=Data.Get(player)
		print("[DEV_TEST_ONLY] Settings.AutoFish="..HttpService:JSONEncode(data and data.Settings and data.Settings.AutoFish or {}))
	elseif cmd=="/devresumetest" then
		-- Stop the live Auto Fish scheduler while preserving saved state, just as a fresh join would.
		Sessions.StopForResumeTest(player)
		local data=Data.Get(player)
		if not data or not data.Settings or not data.Settings.AutoFish then warn("[DEV_TEST_ONLY] No loaded AutoFish settings.");return end
		print("[DEV_TEST_ONLY] Fresh-join resume simulation: "..HttpService:JSONEncode(data.Settings.AutoFish))
		Sessions.QueueResume(player)
	elseif cmd=="/devanimlen" then
		for _,pair in ipairs({{"CastWindup",Config.CastWindupAnimationId},{"CastThrow",Config.CastThrowAnimationId},{"Catch",Config.CatchAnimationId}}) do
			local ok,seq=pcall(function() return KeyframeSequenceProvider:GetKeyframeSequenceAsync(pair[2]) end)
			local length,markers,looped=0,{},false
			if ok then looped=seq.Loop;for _,frame in ipairs(seq:GetKeyframes()) do length=math.max(length,frame.Time);for _,marker in ipairs(frame:GetMarkers()) do table.insert(markers,marker.Value) end end;seq:Destroy() end
			print(("[DEV_TEST_ONLY] %s loaded=%s Length=%.2f looped=%s markers=%s"):format(pair[1],tostring(ok),length,tostring(looped),table.concat(markers,",")))
		end
		print("[DEV_TEST_ONLY] suggested StartArmSeconds="..Config.StartArmSeconds)
	end
end
return Commands
