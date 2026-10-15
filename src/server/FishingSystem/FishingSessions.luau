--[[
	Server-authoritative Phase 3 fishing sessions. Public: Start, StartCast, EndSession,
	GetSession, ForcePress, SetDevLatency. One shared heartbeat services every session.
]]
local Players = game:GetService("Players")
-- DEV_ONLY_BEGIN StudioGuardDependency
local RunService = game:GetService("RunService")
-- DEV_ONLY_END StudioGuardDependency
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local LeaderboardService = require(script.Parent.LeaderboardService)
local Rolls = require(script.Parent.Rolls)
local Modifiers = require(script.Parent.Modifiers)
local FishingZones = require(script.Parent.FishingZones)
local FishingVisuals = require(script.Parent.FishingVisuals)
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local Rarities = require(ReplicatedStorage.FishingSystemV2.Rarities)
local Remotes = ReplicatedStorage.FishingSystemV2.Remotes

local FishingSessions = {}
-- DEV_ONLY_BEGIN DevLatencyState
local sessions, cooldowns, rateWindows, devLatency, nextAuto = {}, {}, {}, {}, {}
-- DEV_ONLY_END DevLatencyState
local started = false
local function now() return Workspace:GetServerTimeNow() end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function angleAt(session, time) return (session.startAngle + session.speed * (time - session.startTime)) % 360 end
local function angularDistance(a,b) return math.abs(((a-b+540)%360)-180) end
local function rateAllowed(player, key, maxPerSecond)
	local stamp = os.clock(); local bucket = rateWindows[player] or {}; rateWindows[player]=bucket
	local list=bucket[key] or {}; bucket[key]=list
	for i=#list,1,-1 do if stamp-list[i] > 1 then table.remove(list,i) end end
	if #list >= maxPerSecond then return false end
	table.insert(list,stamp); return true
end
local function sendMessage(player, message) Remotes.FishingMessage:FireClient(player, message) end
local function getAutoData(player)
	local data=Data.Get(player); return data and data.Settings and data.Settings.AutoFish
end
local function isHeld(session) return sessions[session.player] == session end

local warnedZoneFit = false
local function generateZones(session, activeFrom)
	local rarity = session.rarity
	local count, width = Config.ZoneCount[rarity], Config.ZoneWidthDegrees[rarity]
	local tolerance = Config.HitToleranceDegrees
	local speed = session.speed
	local lead, gap = Config.MinLeadSeconds, Config.MinZoneGapDegrees
	local totalWidth = count * width
	local function availableFor(value) return 360 - (speed * value + tolerance * 2) end
	local available = availableFor(lead)
	if totalWidth + math.max(0,count-1)*gap > available then
		lead = math.max(0,(360-tolerance*2-totalWidth)/speed)
		available = availableFor(lead)
		gap = count > 1 and math.max(0,(available-totalWidth)/(count-1)) or 0
		if not warnedZoneFit then warnedZoneFit=true; warn("[FishingSystem.FishingSessions] Zone fit reduced lead/gap for tuning safety.") end
	end
	local tick = angleAt(session, activeFrom)
	local excludedEnd = tick + tolerance + speed * lead + tolerance
	local leftover = math.max(0, available - totalWidth - gap * math.max(0,count-1))
	local weights,total = {},0
	for i=1,count+1 do weights[i]=session.random:NextNumber(); total+=weights[i] end
	local cursor = excludedEnd + leftover * weights[1]/total
	local zones={}
	for i=1,count do
		local center=(cursor+width*.5)%360
		table.insert(zones,{center=center,halfWidth=width*.5})
		cursor += width + gap + leftover*weights[i+1]/total
	end
	session.zones,session.zonesRevision,session.zonesActiveFrom=zones,(session.zonesRevision or 0)+1,activeFrom
end

local function stopVisual(session, pull)
	if not session.visual then return end
	local visual=session.visual; session.visual=nil
	if pull then
		task.spawn(function()
			local root=session.player.Character and session.player.Character:FindFirstChild("HumanoidRootPart")
			FishingVisuals.PullBack(visual, root and root.Position or visual.bobber.Position)
			FishingVisuals.Destroy(visual)
		end)
	else FishingVisuals.Destroy(visual) end
end

function FishingSessions.EndSession(player, outcome)
	local session=sessions[player]
	if not session then return false end
	sessions[player]=nil
	local cooldown = outcome=="Success" and Config.SuccessCooldown or outcome=="Failed" and Config.FailCooldown or Config.CancelCooldown
	cooldowns[player]=now()+cooldown
	local catch
	if outcome=="Success" then
		local uid,reason=Inventory.AddCharacter(player,session.character.id)
		if uid then LeaderboardService.RecordCatch(player); catch={id=session.character.id, rarity=session.rarity, name=session.character.displayName, uid=uid}
		else outcome="Failed"; warn("[FishingSystem.FishingSessions] Success award failed for "..player.UserId..": "..tostring(reason)) end
	end
	stopVisual(session,outcome=="Cancelled" or outcome=="Failed")
	Remotes.SessionEnd:FireClient(player,session.id,outcome,catch)
	if outcome=="Failed" then sendMessage(player,"The line snapped! The fish got away.") end
	if session.auto and outcome~="Cancelled" then nextAuto[player]=now()+Config.AutoFishRecastDelay end
	return true
end

local function sendCastAccepted(session)
	Remotes.CastAccepted:FireClient(session.player, session.id, session.target, session.auto)
end

local function sendCastResult(session)
	Remotes.CastResult:FireClient(session.player,{
		sessionId=session.id,startTime=session.startTime,startAngle=session.startAngle,speed=session.speed,
		zones=session.zones,zonesRevision=session.zonesRevision,zonesActiveFrom=session.zonesActiveFrom,
		requiredHits=session.requiredHits,tolerance=Config.HitToleranceDegrees,auto=session.auto,
	})
end

function FishingSessions.StartCast(player,target,isAuto)
	if sessions[player] then return nil,"Already fishing." end
	if cooldowns[player] and now()<cooldowns[player] then return nil,"Please wait a moment." end
	if not Rolls.GetEquippedRod(player) then return nil,"You need an equipped rod." end
	if not Inventory.HasRoom(player,1) then return nil,"Backpack full" end
	local valid,reason=FishingZones.ValidateTarget(player,target)
	if not valid then return nil,reason end
	local sessionRandom=Random.new()
	local character,rarity=Rolls.Roll(player,sessionRandom)
	if not character then return nil,"No fish can be caught with this rod." end
	Inventory.PutAway(player)
	local createdAt=now()
	local biteWait=math.max(
		Config.BiteWaitFloorSeconds,
		sessionRandom:NextNumber(Config.BiteWaitMinSeconds,Config.BiteWaitMaxSeconds)/Rolls.GetReelSpeed(player)
	)
	local landingDelay=Config.MaxWindupWaitSeconds+Config.CastThrowSeconds*Config.ThrowReleaseFraction
	local session={
		player=player,id=Data.NewUid(),random=sessionRandom,phase="Waiting",rarity=rarity,character=character,
		requiredHits=Rolls.GetRequiredHits(player,rarity),hits=0,misses=0,streak=0,createdAt=createdAt,biteAt=createdAt+landingDelay+biteWait,
		startTime=nil,startAngle=sessionRandom:NextNumber(0,360),speed=Config.TickSpeedDegrees[rarity],castOrigin=valid.origin,
		target=valid.target,spot=valid.spot,auto=isAuto==true,lastPressEffectiveTime=-math.huge,lastAcceptedPress=nil,
		perfectHits={},visual=nil,
	}
	sessions[player]=session
	session.visual=FishingVisuals.Create(player,session.target,function() return isHeld(session) end)
	local autoData=getAutoData(player)
	if autoData and autoData.enabled then
		if autoData.spot~=session.spot or not autoData.target or (Vector3.new(autoData.target.x,autoData.target.y,autoData.target.z)-session.target).Magnitude>1 then
			autoData.spot=session.spot; autoData.target={x=session.target.X,y=session.target.Y,z=session.target.Z}
		end
	end
	sendCastAccepted(session)
	return session
end

local function oneWayLatency(player)
	-- DEV_ONLY_BEGIN DevLatencyOverride
	if devLatency[player] then return devLatency[player] end
	-- DEV_ONLY_END DevLatencyOverride
	local ok,ping=pcall(function() return player:GetNetworkPing() end)
	return ok and type(ping)=="number" and ping*.5 or 0
end
function FishingSessions.Press(player,sessionId,clientServerTime)
	local session=sessions[player]
	if not session or session.id~=sessionId or not finite(clientServerTime) or not rateAllowed(player,"press",Config.InputRatePerSecond) then return end
	if session.phase~="Reeling" then return end
	local current=now(); local estimate=current-math.clamp(oneWayLatency(player),0,Config.MaxLatencyCompensation)
	local effective=math.abs(clientServerTime-estimate)<=Config.TimestampTrustWindow and clientServerTime or estimate
	effective=math.min(effective,current)
	if effective<=session.lastPressEffectiveTime or effective-session.lastPressEffectiveTime<Config.PressCooldownSeconds or effective<session.zonesActiveFrom then
		Remotes.PressResult:FireClient(player,{sessionId=session.id,result="Ignored",hits=session.hits,requiredHits=session.requiredHits,misses=session.misses,streak=session.streak}); return
	end
	session.lastPressEffectiveTime=effective; session.lastAcceptedPress=effective
	local angle=angleAt(session,effective); local hit,nearCenter=false,false
	for _,zone in ipairs(session.zones) do
		local d=angularDistance(angle,zone.center)
		if d<=zone.halfWidth+Config.HitToleranceDegrees then hit=true; nearCenter=d<=1; break end
	end
	if hit then
		session.hits+=1; session.streak=0; table.insert(session.perfectHits,nearCenter)
		if #session.perfectHits>20 then table.remove(session.perfectHits,1) end
		if #session.perfectHits==20 then local all=true;for _,v in ipairs(session.perfectHits) do all=all and v end;if all and not session.warnedPerfect then session.warnedPerfect=true;warn("[FishingSystem.FishingSessions] Suspicious perfect timing for UserId "..player.UserId) end end
		if session.hits>=session.requiredHits then
			Remotes.PressResult:FireClient(player,{sessionId=session.id,result="Hit",hits=session.hits,requiredHits=session.requiredHits,misses=session.misses,streak=session.streak})
			FishingSessions.EndSession(player,"Success"); return
		end
		generateZones(session,current+Config.ZoneArmSeconds)
		Remotes.PressResult:FireClient(player,{sessionId=session.id,result="Hit",hits=session.hits,requiredHits=session.requiredHits,misses=session.misses,streak=session.streak,zones=session.zones,revision=session.zonesRevision,activeFrom=session.zonesActiveFrom})
	else
		session.misses+=1;session.streak+=1
		Remotes.PressResult:FireClient(player,{sessionId=session.id,result="Miss",hits=session.hits,requiredHits=session.requiredHits,misses=session.misses,streak=session.streak})
		if session.misses>=Config.MaxMisses or session.streak>=Config.MaxConsecutiveMisses then FishingSessions.EndSession(player,"Failed") end
	end
end
function FishingSessions.GetSession(player) return sessions[player] end
-- DEV_ONLY_BEGIN StopForResumeTest
-- Studio-only diagnostic helper: clears live automation while preserving the saved AutoFish preference.
function FishingSessions.StopForResumeTest(player)
	if not RunService:IsStudio() then return false end
	FishingSessions.EndSession(player, "Cancelled")
	nextAuto[player] = nil
	return true
end
-- DEV_ONLY_END StopForResumeTest
function FishingSessions.QueueResume(player)
	task.spawn(function()
		task.wait(Config.ResumeDelaySeconds)
		local autoData=getAutoData(player)
		if not autoData or not autoData.enabled then return end
		if not Modifiers.HasAutoFish(player) then autoData.enabled=false; return end
		if not autoData.target then autoData.enabled=false; sendMessage(player,"Auto Fish couldn't resume: no saved target."); return end
		local target=Vector3.new(autoData.target.x,autoData.target.y,autoData.target.z)
		local standPoint,reason=FishingZones.GetStandPoint(target)
		local character=player.Character
		local humanoid=character and character:FindFirstChildOfClass("Humanoid")
		if not standPoint or not humanoid or humanoid.Health<=0 then autoData.enabled=false;sendMessage(player,"Auto Fish couldn't resume: "..tostring(reason or "no safe standing point."));return end
		character:PivotTo(CFrame.new(standPoint))
		nextAuto[player]=now()+.1
	end)
end
-- DEV_ONLY_BEGIN SetDevLatency
function FishingSessions.SetDevLatency(player,seconds) devLatency[player]=seconds end
-- DEV_ONLY_END SetDevLatency
-- DEV_ONLY_BEGIN ForcePress
function FishingSessions.ForcePress(player,mode)
	local session=sessions[player]; if not session then return false end
	local time=now(); local zone=session.zones[1]
	if mode=="hit" then session.zonesActiveFrom=time; FishingSessions.Press(player,session.id,time)
	elseif mode=="miss" then session.zones={{center=(angleAt(session,time)+180)%360,halfWidth=0}};session.zonesActiveFrom=time;FishingSessions.Press(player,session.id,time) else return false end
	return true
end
-- DEV_ONLY_END ForcePress

local function handleAuto(player)
	local autoData=getAutoData(player)
	if not autoData or not autoData.enabled or not Modifiers.HasAutoFish(player) then return end
	local session=sessions[player]
	if session then
		if session.auto and session.phase=="Reeling" and now()>=session.zonesActiveFrom then
			local zone=session.zones[1]
			local desired=(zone.center-session.startAngle)/session.speed+session.startTime
			if desired<now() then desired=now() end
			session.zonesActiveFrom=desired+9999
			task.delay(math.max(0,desired-now()),function()
			if isHeld(session) then session.zonesActiveFrom=desired; FishingSessions.Press(player,session.id,desired) end
			end)
		end
		return
	end
	if nextAuto[player] and now()>=nextAuto[player] then
		nextAuto[player]=nil
		if not autoData.target then autoData.enabled=false;sendMessage(player,"Auto Fish couldn't resume: no saved target.");return end
		local target=Vector3.new(autoData.target.x,autoData.target.y,autoData.target.z)
		local startedCast,reason=FishingSessions.StartCast(player,target,true)
		if not startedCast then autoData.enabled=false;sendMessage(player,"Auto Fish couldn't resume: "..tostring(reason)); end
	end
end
-- DEV_ONLY_BEGIN RunIsolationTest
-- Studio-only isolation harness for ownership, stale-session, and cleanup verification.
function FishingSessions.DEV_RunIsolationTest(player)
	if not RunService:IsStudio() then return nil, "Studio only" end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil, "No character" end
	FishingSessions.EndSession(player, "Cancelled")
	local stamp = now()
	local function makeSession(owner, id, visual)
		return {
			player = owner, id = id, random = Random.new(991), phase = "Reeling", rarity = 1,
			character = {id = "common_01", displayName = "DEV"}, requiredHits = 99,
			hits = 0, misses = 0, streak = 0, createdAt = stamp, startTime = stamp, startAngle = 0,
			speed = Config.TickSpeedDegrees[1], castOrigin = rootPart.Position,
			target = rootPart.Position + rootPart.CFrame.LookVector * 10, spot = "DEV",
			auto = false, lastPressEffectiveTime = -math.huge, lastAcceptedPress = stamp,
			zones = {{center = 0, halfWidth = 180}}, zonesActiveFrom = stamp,
			visual = visual, perfectHits = {},
		}
	end
	local target = rootPart.Position + rootPart.CFrame.LookVector * 10
	local aVisual
	local a = makeSession(player, "DEV_A_ACTIVE", nil)
	sessions[player] = a
	aVisual = FishingVisuals.Create(player, target, function() return sessions[player] == a end)
	a.visual = aVisual
	local fakeB = {Name = "DEV_B", UserId = -9002}
	local before = {aHits = a.hits, aExists = sessions[player] == a}
	local bPressOk = pcall(function() FishingSessions.Press(fakeB, a.id, stamp) end)
	local bCancel = FishingSessions.EndSession(fakeB, "Cancelled")
	local afterBCancel = sessions[player] == a
	local afterB = {aHits = a.hits, aExists = sessions[player] == a}
	local staleOk = pcall(function() FishingSessions.Press(player, "DEV_A_STALE", stamp) end)
	local wrongTypeOk = pcall(function() FishingSessions.Press(player, {}, stamp) end)
	local secondCast, secondCastReason = FishingSessions.StartCast(player, target, false)
	local b = makeSession(fakeB, "DEV_B_ACTIVE", nil)
	sessions[fakeB] = b
	local pressTime = now()
	a.startTime = pressTime
	a.zonesActiveFrom = pressTime - .01
	a.lastPressEffectiveTime = -math.huge
	FishingSessions.Press(player, a.id, pressTime)
	local isolatedProgress = {aHits = a.hits, bHits = b.hits}
	sessions[player] = nil
	local endedPressOk = pcall(function() FishingSessions.Press(player, a.id, stamp + 1) end)
	sessions[player] = a
	FishingSessions.EndSession(player, "Cancelled")
	task.wait(Config.CancelCooldown + .2)
	local cleanup = {
		rod = aVisual == nil or aVisual.rod.Parent == nil,
		bobber = aVisual == nil or aVisual.bobber.Parent == nil,
		line = aVisual == nil or aVisual.beam.Parent == nil,
		model = aVisual == nil or aVisual.model.Parent == nil,
		sessionRemoved = sessions[player] == nil,
	}
	sessions[fakeB] = nil
	return {
		bPressNoEffect = bPressOk and before.aHits == afterB.aHits and before.aExists and afterB.aExists,
		bCancelNoEffect = bCancel == false and afterBCancel,
		staleIgnoredNoError = staleOk and a.hits == isolatedProgress.aHits,
		wrongTypeIgnoredNoError = wrongTypeOk,
		secondCastIgnored = secondCast == nil and secondCastReason == "Already fishing.",
		endedPressIgnoredNoError = endedPressOk,
		twoSessionProgress = isolatedProgress,
		cleanup = cleanup,
		autoFishProtocol = "AutoFishToggle has no sessionId parameter; an A id sent by B is only a non-true enabled value for B and cannot address A.",
	}
end
-- DEV_ONLY_END RunIsolationTest

function FishingSessions.Start()
	if started then return end; started=true; FishingZones.Start()
	Remotes.Cast.OnServerEvent:Connect(function(player,target)
		if not rateAllowed(player,"cast",Config.CastRatePerSecond) then return end
		local session,reason=FishingSessions.StartCast(player,target,false)
		if not session and reason then Remotes.FishingMessage:FireClient(player,reason,"CastRejected") end
	end)
	Remotes.Press.OnServerEvent:Connect(FishingSessions.Press)
	Remotes.Cancel.OnServerEvent:Connect(function(player)
		if rateAllowed(player,"cancel",2) then FishingSessions.EndSession(player,"Cancelled") end
	end)
	Remotes.AutoFishToggle.OnServerEvent:Connect(function(player,enabled)
		if not rateAllowed(player,"auto",2) then return end
		if enabled==true and not Modifiers.HasAutoFish(player) then sendMessage(player,"Auto Fish is locked.");return end
		local autoData=getAutoData(player);if not autoData then return end
		autoData.enabled=enabled==true
		if not autoData.enabled then FishingSessions.EndSession(player,"Cancelled") else nextAuto[player]=now()+Config.AutoFishRecastDelay end
	end)
	Data.Releasing:Connect(function(player)
		FishingSessions.EndSession(player,"Cancelled");
		-- DEV_ONLY_BEGIN ModifiersClearCall
		Modifiers.Clear(player);
		-- DEV_ONLY_END ModifiersClearCall
		-- DEV_ONLY_BEGIN RollsClearCall
		Rolls.Clear(player);
		-- DEV_ONLY_END RollsClearCall
		rateWindows[player]=nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid=character:WaitForChild("Humanoid",10)
			if humanoid then humanoid.Died:Connect(function() FishingSessions.EndSession(player,"Died") end) end
		end)
	end)
	task.spawn(function()
		while started do
			local t=now()
			for player,session in pairs(sessions) do
				local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not root then FishingSessions.EndSession(player,"Died")
				elseif (root.Position-session.castOrigin).Magnitude>Config.MaxWalkAwayDistance then FishingSessions.EndSession(player,"TooFar")
				elseif t-session.createdAt>=Config.SessionMaxSeconds then FishingSessions.EndSession(player,"Timeout")
				elseif session.phase=="Waiting" and t>=session.biteAt then
					session.phase="Reeling"
					session.startTime=session.biteAt
					session.lastAcceptedPress=session.biteAt
					generateZones(session,session.startTime+Config.StartArmSeconds)
					FishingVisuals.Bite(session.visual)
					sendCastResult(session)
				elseif session.phase=="Reeling" and not session.auto and t-session.lastAcceptedPress>=Config.IdleCancelSeconds then FishingSessions.EndSession(player,"Idle")
			end
			end
			for _,player in ipairs(Players:GetPlayers()) do handleAuto(player) end
			task.wait(.1)
		end
	end)
end
return FishingSessions
