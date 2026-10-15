--[[ Local Phase 3 presentation and input controller. The server decides every cast, hit, roll, and award. ]]
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local UserInputService=game:GetService("UserInputService")
local ContextActionService=game:GetService("ContextActionService")
local ContentProvider=game:GetService("ContentProvider")
local TweenService=game:GetService("TweenService")
local StarterGui=game:GetService("StarterGui")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local shared=ReplicatedStorage:WaitForChild("FishingSystemV2")
local Config=require(shared.FishingConfig)
local Rarities=require(shared.Rarities)
local Colors=require(shared.RarityColors)
local Remotes=shared:WaitForChild("Remotes")
local gui=player:WaitForChild("PlayerGui"):WaitForChild("FishingSystemV2")
local root=gui:WaitForChild("FishingTimingGui")
local track=root.Track
local center=track.Center
local zonesLayer=track.ZonesLayer
local tickPivot=track.TickPivot
local tickMark=tickPivot.TickMark
local meter=root.ReelMeter
local reel=root.ReelButton
local fishIcon=center.FishIcon
local streakPips=center.StreakPips
local tickSparkle=tickMark.HitSparkle
local reelPressScale=reel.PressScale
local streakPulseScale=center.Streak.PulseScale
local cancel=root.CancelButton
local auto=root.AutoFishButton
local waitingLabel=gui:WaitForChild("WaitingLabel")
local biteCue=gui:WaitForChild("BiteCue")
local mobileCast=gui.MobileCastButton
local hotbar=gui:WaitForChild("Phase4Hotbar")
local touchControls=player:WaitForChild("PlayerGui"):WaitForChild("FishingTouchControlsGui"):WaitForChild("FishingTouchControls")
local circleCapScale=root:WaitForChild("CircleCapScale")
local popup=gui.CatchPopup
local indicator=shared.FishingIndicatorTemplate:Clone()
indicator.Name="FishingAimIndicator";indicator.Parent=Workspace;indicator.Transparency=1
-- DEV_ONLY_BEGIN DevZoneState
local state={session=nil,pending=false,target=nil,fishable=false,mobile=false,segments={},devZones=false,devCopies={},autoEnabled=false,manualSession=false,castToken=0}
-- DEV_ONLY_END DevZoneState
local lastTouchCastScanAt=0
local function captureLayout(button)
	local aspect=button:FindFirstChildWhichIsA("UIAspectRatioConstraint")
	return {parent=button.Parent,position=button.Position,size=button.Size,anchor=button.AnchorPoint,zIndex=button.ZIndex,aspect=aspect,aspectRatio=aspect and aspect.AspectRatio}
end
local desktopLayouts={ [reel]=captureLayout(reel),[cancel]=captureLayout(cancel),[auto]=captureLayout(auto) }
local desktopCirclePosition=root.Position
local autoVisibleBeforeWaiting=nil
local desktopCastLayout=captureLayout(mobileCast)
local applyMobileCastLayout
local tracks={};local holdTrack=nil;local fishBobTween=nil;local startFishBob;local stopFishBob
local function notify(message) pcall(function() StarterGui:SetCore("SendNotification",{Title="Fishing",Text=message,Duration=2}) end) end
local function finiteVector(v) return typeof(v)=="Vector3" and v.X==v.X and v.Y==v.Y and v.Z==v.Z and math.abs(v.X)<math.huge and math.abs(v.Y)<math.huge and math.abs(v.Z)<math.huge end
local function zones()
	local out={};for _,obj in ipairs(Workspace:GetDescendants()) do if obj:IsA("BasePart") and string.match(obj.Name,"^FishingPart%d+$") then table.insert(out,obj) end end;return out
end
local function inside(zone,point)
	local p=zone.CFrame:PointToObjectSpace(point);local h=zone.Size*.5
	return math.abs(p.X)<=h.X and math.abs(p.Z)<=h.Z and math.abs(p.Y)<=h.Y+Config.ZoneVerticalPadding
end
local function buildAimRaycastParams(character, fishingZones)
	local filter=table.clone(fishingZones);if character then table.insert(filter,character) end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=filter;params.IgnoreWater=false
	return params
end
local function isFishableWaterPoint(point, character, rootPart, fishingZones)
	local valid=false;for _,zone in ipairs(fishingZones) do if inside(zone,point) then valid=true;break end end
	return valid and rootPart and (rootPart.Position-point).Magnitude<=Config.MaxCastDistance
end
local function aimResult(screenPosition)
	local camera=Workspace.CurrentCamera;if not camera then return nil,false end
	local ray=camera:ViewportPointToRay(screenPosition.X,screenPosition.Y)
	local character=player.Character;local fishingZones=zones();local params=buildAimRaycastParams(character,fishingZones)
	local hit=Workspace:Raycast(ray.Origin,ray.Direction*500,params)
	if not hit or hit.Material~=Enum.Material.Water then return hit and hit.Position or nil,false end
	local rootPart=character and character:FindFirstChild("HumanoidRootPart")
	return hit.Position,isFishableWaterPoint(hit.Position,character,rootPart,fishingZones)==true
end
local setAim
local function scanTouchTarget()
	local character=player.Character;local rootPart=character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then setAim(nil,false);return end
	local flatLook=Vector3.new(rootPart.CFrame.LookVector.X,0,rootPart.CFrame.LookVector.Z)
	if flatLook.Magnitude==0 then setAim(nil,false);return end
	flatLook=flatLook.Unit
	local fishingZones=zones();local params=buildAimRaycastParams(character,fishingZones)
	for _,angle in ipairs(Config.TouchCastAnglesDeg) do
		local direction=CFrame.Angles(0,math.rad(angle),0):VectorToWorldSpace(flatLook)
		for _,distance in ipairs(Config.TouchCastDistances) do
			local point=rootPart.Position+direction*distance
			local hit=Workspace:Raycast(point+Vector3.new(0,12,0),Vector3.new(0,-30,0),params)
			if hit and hit.Material==Enum.Material.Water and isFishableWaterPoint(hit.Position,character,rootPart,fishingZones) then setAim(hit.Position,true);return end
		end
	end
	setAim(nil,false)
end
setAim=function(position,valid)
	state.target,state.fishable=position,valid==true
	if state.mobile then
		indicator.Transparency=1
	elseif position and not state.session then
		indicator.Transparency=.25;indicator.Color=valid and Color3.fromRGB(70,255,120) or Color3.fromRGB(255,77,77)
		indicator.CFrame=CFrame.new(position)*CFrame.Angles(0,0,math.rad(90))
	else indicator.Transparency=1 end
	if applyMobileCastLayout then applyMobileCastLayout() end
	mobileCast.Visible=state.mobile and valid and not state.session and not state.pending
end
local function setJumpEnabled(enabled,character)
	local targetCharacter=character or player.Character
	local humanoid=targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,enabled) end) end
end
local function applyTimingCircleCap()
	circleCapScale.Scale=1
	task.defer(function()
		local camera=Workspace.CurrentCamera
		if not camera then return end
		local unscaledDiameter=root.AbsoluteSize.X
		local cap=camera.ViewportSize.Y*.38
		circleCapScale.Scale=math.min(1,cap/math.max(1,unscaledDiameter))
	end)
end
local function restoreDesktopFishingLayout()
	root.Position=desktopCirclePosition
	touchControls.Visible=false
	for button,layout in pairs(desktopLayouts) do
		if button.Parent~=layout.parent then button.Parent=layout.parent end
		button.Position=layout.position
		button.Size=layout.size
		button.AnchorPoint=layout.anchor
		button.ZIndex=layout.zIndex
		if layout.aspect and layout.aspectRatio then layout.aspect.AspectRatio=layout.aspectRatio end
	end
end
local function applyTouchFishingLayout()
	root.Position=desktopCirclePosition
	touchControls.Visible=true
	local layouts={
		{button=reel,left=.3944,width=.224,anchor=Vector2.new(.5,1),aspect=2.5},
		{button=cancel,left=.2664,width=.1152,anchor=Vector2.new(1,1),aspect=72/44},
		{button=auto,left=.6312,width=.1152,anchor=Vector2.new(0,1),aspect=72/44},
	}
	for _,layout in ipairs(layouts) do
		local button=layout.button
		button.Parent=touchControls
		button.AnchorPoint=layout.anchor
		button.ZIndex=desktopLayouts[button].zIndex+10
		local aspect=desktopLayouts[button].aspect
		if aspect then aspect.AspectRatio=layout.aspect end
	end
	task.defer(function()
		if not state.mobile or not state.session then return end
		local camera=Workspace.CurrentCamera
		if not camera then return end
		local safeOrigin=touchControls.AbsolutePosition
		local safeSize=touchControls.AbsoluteSize
		local bottom=safeOrigin.Y+safeSize.Y-8
		for _,layout in ipairs(layouts) do
			local width=safeSize.X*layout.width
			local height=width/layout.aspect
			local button=layout.button
			button.Size=UDim2.fromOffset(width,height)
			button.Position=UDim2.fromOffset(
				safeSize.X*layout.left+layout.anchor.X*width,
				bottom-safeOrigin.Y
			)
		end
		task.defer(function()
			if not state.mobile or not state.session then return end
			local controlTop=math.min(reel.AbsolutePosition.Y,cancel.AbsolutePosition.Y,auto.AbsolutePosition.Y)
			local requiredBottom=controlTop-8
			local circleBottom=root.AbsolutePosition.Y+root.AbsoluteSize.Y
			if circleBottom>requiredBottom then
				root.Position=UDim2.new(desktopCirclePosition.X.Scale,desktopCirclePosition.X.Offset,desktopCirclePosition.Y.Scale,desktopCirclePosition.Y.Offset-(circleBottom-requiredBottom))
			end
		end)
	end)
end
applyMobileCastLayout=function()
	local layout=desktopCastLayout
	local aspect=layout.aspect
	if state.mobile then
		mobileCast.AnchorPoint=Vector2.new(1,1)
		mobileCast.Position=UDim2.fromScale(.7712,.655556)
		mobileCast.Size=UDim2.fromScale(.1536,.133333)
		if aspect then aspect.AspectRatio=2 end
		task.defer(function()
			if not state.mobile or state.session then return end
			local firstSlot=hotbar:FindFirstChild("Slot1")
			if firstSlot then
				mobileCast.Position=UDim2.new(.7712,0,0,firstSlot.AbsolutePosition.Y-8)
			end
		end)
	else
		mobileCast.Position=layout.position
		mobileCast.Size=layout.size
		mobileCast.AnchorPoint=layout.anchor
		mobileCast.ZIndex=layout.zIndex
		if aspect and layout.aspectRatio then aspect.AspectRatio=layout.aspectRatio end
	end
end
local function applyDesktopReelCancelGap()
	task.defer(function()
		if state.mobile or not state.session then return end
		for _,button in ipairs({reel,cancel}) do
			local position=button.Position
			button.Position=UDim2.new(position.X.Scale,position.X.Offset,0,root.AbsoluteSize.Y+8+button.AnchorPoint.Y*button.AbsoluteSize.Y)
		end
	end)
end
local function applyFishingControlLayout()
	applyTimingCircleCap()
	if state.mobile and state.session then
		applyTouchFishingLayout()
	else
		restoreDesktopFishingLayout()
		if state.session then applyDesktopReelCancelGap() end
	end
	applyMobileCastLayout()
end
local function releaseManualReelLock()
	ContextActionService:UnbindAction("FishingReel")
	state.manualSession=false
	setJumpEnabled(true)
end

local function setWaitingControls(waiting)
	if waiting then
		autoVisibleBeforeWaiting=auto.Visible
		reel.Visible=false
		auto.Visible=false
		cancel.Visible=true
	else
		reel.Visible=true
		if autoVisibleBeforeWaiting~=nil then auto.Visible=autoVisibleBeforeWaiting;autoVisibleBeforeWaiting=nil end
	end
end
local function stopTrack(track,fade) if track and track.IsPlaying then track:Stop(fade or .08) end end
local function stopAllAnimations()
	for _,track in pairs(tracks) do stopTrack(track,.08) end
	holdTrack=nil
end
local function playOnly(name)
	for key,track in pairs(tracks) do if key~=name then stopTrack(track,.08) end end
	local track=tracks[name];if track then track:AdjustSpeed(1);track:Play(.06);return track end
end
local function setupTracks(character)
	restoreDesktopFishingLayout();releaseManualReelLock();stopFishBob();stopAllAnimations();tracks={}
	local humanoid=character:WaitForChild("Humanoid",10);setJumpEnabled(true,character);local animator=humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator",5));if not animator then return end
	local definitions={Windup=Config.CastWindupAnimationId,Throw=Config.CastThrowAnimationId,Catch=Config.CatchAnimationId,Cancel=Config.CancelAnimationId}
	local assets={}
	for name,id in pairs(definitions) do local animation=Instance.new("Animation");animation.AnimationId=id;assets[#assets+1]=animation;local ok,track=pcall(function()return animator:LoadAnimation(animation)end);if ok then track.Priority=Enum.AnimationPriority.Action;track.Looped=false;tracks[name]=track end end
	pcall(function()ContentProvider:PreloadAsync(assets)end)
	humanoid.Died:Connect(function() state.session=nil;state.pending=false;restoreDesktopFishingLayout();waitingLabel.Visible=false;biteCue.Visible=false;setWaitingControls(false);releaseManualReelLock();stopFishBob();root.Visible=false;setAim(nil,false);stopAllAnimations() end)
end
local function runCosmetic(callback)
	local ok,err=pcall(callback)
	if not ok then warn("[FishingSystem.Phase3FishingClient] Cosmetic failed: "..tostring(err)) end
end
local function clearSegments()
	for _,segment in ipairs(state.segments) do segment.Visible=false end
end
local function segment(index)
	local item=state.segments[index]
	if item then return item end
	item=Instance.new("Frame");item.Name="ZoneSegment";item.AnchorPoint=Vector2.new(.5,.5);item.Size=UDim2.fromScale(.023,.1);item.BackgroundColor3=Color3.new(1,1,1);item.ZIndex=2;item.Parent=zonesLayer
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(1,0);c.Parent=item
	local s=Instance.new("UIStroke");s.Thickness=1;s.Transparency=1;s.Parent=item
	local g=Instance.new("UIGradient");g.Rotation=90;g.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(32,141,85)),ColorSequenceKeypoint.new(1,Color3.fromRGB(112,255,148))});g.Parent=item
	state.segments[index]=item;return item
end
local function showZones(list)
	clearSegments();local index=0
	for _,zone in ipairs(list or {}) do
		for angle=zone.center-zone.halfWidth,zone.center+zone.halfWidth,Config.ZoneSegmentDegrees do
			index+=1;local part=segment(index);local r=math.rad(angle);part.Position=UDim2.fromScale(.5+.43*math.sin(r),.5-.43*math.cos(r));part.Rotation=angle;part.Visible=true;part.BackgroundTransparency=1
			runCosmetic(function() TweenService:Create(part,TweenInfo.new(Config.ZoneArmSeconds),{BackgroundTransparency=0}):Play() end)
		end
	end
end
local function configureMeter(requiredHits)
	for index=1,12 do
		local divider=meter:FindFirstChild("Divider"..index)
		if divider then
			divider.Visible=index<requiredHits
			if divider.Visible then divider.Position=UDim2.fromScale(index/requiredHits,.5) end
		end
	end
end
local function updateProgress(data)
	local requiredHits=math.max(1,tonumber(data.requiredHits) or 1)
	center.Misses.Text="Misses "..data.misses.."/"..Config.MaxMisses
	center.Streak.Text="Streak "..data.streak.."/"..Config.MaxConsecutiveMisses
	center.Streak.TextColor3=data.streak>=3 and Color3.fromRGB(112,255,148) or Color3.fromRGB(255,253,240)
	for index=1,5 do
		local pip=streakPips:FindFirstChild("Pip"..index)
		if pip then pip.BackgroundColor3=index<=data.streak and Color3.fromRGB(112,255,148) or Color3.fromRGB(126,140,151) end
	end
	configureMeter(requiredHits)
	local fillTarget=UDim2.fromScale(math.clamp(data.hits/requiredHits,0,1),1)
	runCosmetic(function() TweenService:Create(meter.Fill,TweenInfo.new(.12),{Size=fillTarget}):Play() end)
end
startFishBob=function()
	runCosmetic(function()
		if fishBobTween then fishBobTween:Cancel() end
		local basePosition=UDim2.fromScale(.3,0)
		fishIcon.Position=basePosition
		fishBobTween=TweenService:Create(fishIcon,TweenInfo.new(.45,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Position=basePosition+UDim2.fromScale(0,.035)})
		fishBobTween:Play()
	end)
end
stopFishBob=function()
	runCosmetic(function()
		if fishBobTween then fishBobTween:Cancel();fishBobTween=nil end
		fishIcon.Position=UDim2.fromScale(.3,0)
		tickSparkle.Visible=false
	end)
end
local function playReelSquish()
	runCosmetic(function()
		reelPressScale.Scale=1
		local inTween=TweenService:Create(reelPressScale,TweenInfo.new(.06),{Scale=.9})
		local outTween=TweenService:Create(reelPressScale,TweenInfo.new(.10),{Scale=1})
		inTween.Completed:Connect(function() pcall(function() outTween:Play() end) end);inTween:Play()
	end)
end
local function playHitFeedback()
	runCosmetic(function()
		for _,segment in ipairs(state.segments) do
			if segment.Visible then
				local zoneFlash=TweenService:Create(segment,TweenInfo.new(.07),{BackgroundColor3=Color3.fromRGB(255,253,240)})
				local zoneReset=TweenService:Create(segment,TweenInfo.new(.12),{BackgroundColor3=Color3.new(1,1,1)})
				zoneFlash.Completed:Connect(function() pcall(function() zoneReset:Play() end) end)
				zoneFlash:Play()
			end
		end
		tickSparkle.Visible=true
		tickSparkle.Size=UDim2.fromScale(.55,.55)
		tickSparkle.BackgroundTransparency=.05
		local sparkleTween=TweenService:Create(tickSparkle,TweenInfo.new(.16),{Size=UDim2.fromScale(1.8,1.8),BackgroundTransparency=1})
		sparkleTween:Play()
		if streakPulseScale then
			local pulseIn=TweenService:Create(streakPulseScale,TweenInfo.new(.08),{Scale=1.16})
			local pulseOut=TweenService:Create(streakPulseScale,TweenInfo.new(.12),{Scale=1})
			pulseIn.Completed:Connect(function() pcall(function() pulseOut:Play() end) end);pulseIn:Play()
		end
		task.delay(.18,function() pcall(function() tickSparkle.Visible=false end) end)
	end)
end
local function playMissFeedback()
	runCosmetic(function()
		local flash=TweenService:Create(track,TweenInfo.new(.06),{BackgroundColor3=Color3.fromRGB(89,42,54)})
		local shakeOut=TweenService:Create(track,TweenInfo.new(.04),{Position=UDim2.new(.5,4,.43,0)})
		local shakeBack=TweenService:Create(track,TweenInfo.new(.07),{Position=UDim2.new(.5,0,.43,0)})
		flash:Play()
		shakeOut.Completed:Connect(function() pcall(function() shakeBack:Play() end) end)
		shakeOut:Play()
		task.delay(.12,function() pcall(function() track.BackgroundColor3=Color3.fromRGB(12,21,32) end) end)
	end)
end
local function bindReel()
	ContextActionService:UnbindAction("FishingReel")
	ContextActionService:BindActionAtPriority("FishingReel",function(_,inputState)
		if inputState==Enum.UserInputState.Begin and state.session and state.session.phase=="Reeling" and state.manualSession and not state.mobile then Remotes.Press:FireServer(state.session.sessionId,Workspace:GetServerTimeNow()) end
		return Enum.ContextActionResult.Sink
	end,false,Enum.ContextActionPriority.High.Value,Enum.KeyCode.Space)
end
local function beginCast()
	if not state.fishable or not state.target or state.session or state.pending then return end
	if state.mobile then
		local rootPart=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local flatDelta=rootPart and Vector3.new(state.target.X-rootPart.Position.X,0,state.target.Z-rootPart.Position.Z)
		if flatDelta and flatDelta.Magnitude>0 then rootPart.CFrame=CFrame.lookAt(rootPart.Position,rootPart.Position+flatDelta) end
	end
	state.castToken+=1
	local castToken=state.castToken
	state.manualSession=true;setJumpEnabled(false);bindReel()
	state.pending=true;mobileCast.Visible=false;playOnly("Windup");Remotes.Cast:FireServer(state.target)
	task.delay(Config.CastResultTimeoutSeconds,function()
		if state.pending and state.castToken==castToken then
			state.pending=false
			stopTrack(tracks.Windup,.08)
			releaseManualReelLock()
		end
	end)
end
local function beginThrow(session)
	task.spawn(function()
		local windup=tracks.Windup;local deadline=os.clock()+Config.MaxWindupWaitSeconds
		while state.session==session and windup and windup.IsPlaying and windup.TimePosition<math.max(0,windup.Length-.02) and os.clock()<deadline do task.wait() end
		if state.session~=session then return end
		stopTrack(windup,.04)
		local throw=playOnly("Throw")
		if throw and Config.HoldFinalPose then
			while state.session==session and throw.IsPlaying and throw.TimePosition<math.max(0,throw.Length-.03) do task.wait() end
			if state.session==session and throw.IsPlaying then throw:AdjustSpeed(0);holdTrack=throw end
		end
	end)
end
local function finish(outcome,catch)
	state.pending=false;state.session=nil;restoreDesktopFishingLayout();root.Visible=false;waitingLabel.Visible=false;biteCue.Visible=false;setWaitingControls(false);mobileCast.Visible=false;indicator.Transparency=1;releaseManualReelLock();stopFishBob()
	if outcome=="Success" then stopTrack(holdTrack,.06);playOnly("Catch")
	elseif outcome=="Cancelled" then stopTrack(holdTrack,.06);playOnly("Cancel")
	else stopAllAnimations() end
	if catch then popup.CharacterName.Text=catch.name.." • "..(Rarities.List[catch.rarity] or "");popup.CharacterName.TextColor3=Colors[catch.rarity] or Color3.new(1,1,1);popup.Visible=true;task.delay(2,function()popup.Visible=false end) end
end
Remotes.CastAccepted.OnClientEvent:Connect(function(sessionId,target,auto)
	if not state.pending or state.session or type(sessionId)~="string" or typeof(target)~="Vector3" then return end
	state.pending=false
	local session={sessionId=sessionId,target=target,auto=auto==true,phase="Waiting"}
	state.session=session
	if state.manualSession then setJumpEnabled(false);bindReel() end
	root.Visible=false
	waitingLabel.Text=state.mobile and "Waiting for a bite..." or "Waiting for a bite... (X to cancel)"
	waitingLabel.Visible=true
	biteCue.Visible=false
	setAim(nil,false)
	applyFishingControlLayout()
	setWaitingControls(true)
	beginThrow(session)
end)

Remotes.CastResult.OnClientEvent:Connect(function(data)
	if type(data)~="table" or type(data.sessionId)~="string" or not state.session or state.session.sessionId~=data.sessionId or state.session.phase~="Waiting" then return end
	data.phase="Reeling"
	state.session=data
	waitingLabel.Visible=false
	setWaitingControls(false)
	biteCue.Visible=true
	task.delay(Config.BobberDipDownSeconds+Config.BobberDipUpSeconds,function()
		if state.session and state.session.sessionId==data.sessionId then biteCue.Visible=false end
	end)
	root.Visible=true
	setAim(nil,false)
	applyFishingControlLayout()
	showZones(data.zones)
	updateProgress({hits=0,requiredHits=data.requiredHits,misses=0,streak=0})
	startFishBob()
end)
Remotes.PressResult.OnClientEvent:Connect(function(data)
	if not state.session or data.sessionId~=state.session.sessionId then return end
	if data.result=="Hit" and data.zones then
		state.session.zones=data.zones
		state.session.zonesRevision=data.revision
		state.session.zonesActiveFrom=data.activeFrom
		showZones(data.zones)
	end
	updateProgress(data)
	if data.result=="Hit" then playHitFeedback() elseif data.result=="Miss" then playMissFeedback() end
end)
Remotes.SessionEnd.OnClientEvent:Connect(function(sessionId,outcome,catch) if state.session and state.session.sessionId==sessionId then finish(outcome,catch) end end)
Remotes.FishingMessage.OnClientEvent:Connect(function(message,messageKind)
	-- DEV_ONLY_BEGIN DevShowZones
	if message=="__DEV_SHOW_ZONES__" then state.devZones=not state.devZones;for _,copy in ipairs(state.devCopies) do copy:Destroy() end;state.devCopies={};if state.devZones then for _,zone in ipairs(zones()) do local copy=zone:Clone();copy.Name="DEV_"..zone.Name;copy.Transparency=.72;copy.Color=Color3.fromRGB(55,190,255);copy.Anchored=true;copy.CanCollide=false;copy.CanQuery=false;copy.CanTouch=false;copy.Parent=Workspace;table.insert(state.devCopies,copy) end end;return end
	-- DEV_ONLY_END DevShowZones
	-- DEV_ONLY_BEGIN DevAutoAvailability
	if string.sub(message,1,23)=="__AUTO_AVAILABLE__" then auto.Visible=string.sub(message,24)=="true";return end
	-- DEV_ONLY_END DevAutoAvailability
	if messageKind=="CastRejected" and state.pending then state.pending=false;stopTrack(tracks.Windup,.08);releaseManualReelLock() end
	notify(message)
end)
reel.Activated:Connect(function() if state.session and state.session.phase=="Reeling" then Remotes.Press:FireServer(state.session.sessionId,Workspace:GetServerTimeNow());playReelSquish() end end)
cancel.Activated:Connect(function() if state.session then Remotes.Cancel:FireServer() end end)
auto.Activated:Connect(function() state.autoEnabled=not state.autoEnabled;auto.Text=state.autoEnabled and "AUTO: ON" or "AUTO FISH";Remotes.AutoFishToggle:FireServer(state.autoEnabled) end)
mobileCast.Activated:Connect(beginCast)
UserInputService.LastInputTypeChanged:Connect(function(input)
	state.mobile=input==Enum.UserInputType.Touch
	lastTouchCastScanAt=0
	setAim(nil,false)
	if state.session and state.session.phase=="Waiting" then waitingLabel.Text=state.mobile and "Waiting for a bite..." or "Waiting for a bite... (X to cancel)" end
	applyFishingControlLayout()
	mobileCast.Visible=state.mobile and state.fishable and not state.session and not state.pending
end)
UserInputService.InputBegan:Connect(function(input,processed)
	if processed then return end
	if input.KeyCode==Enum.KeyCode.X and state.session then Remotes.Cancel:FireServer();return end
	if input.UserInputType==Enum.UserInputType.MouseButton1 and not state.mobile then
		if state.session then
			if state.manualSession and state.session.phase=="Reeling" then Remotes.Press:FireServer(state.session.sessionId,Workspace:GetServerTimeNow()) end
		elseif not state.pending then beginCast() end
	end
end)
RunService.RenderStepped:Connect(function()
	if state.session then
		if state.session.phase=="Reeling" then tickPivot.Rotation=(state.session.startAngle+state.session.speed*(Workspace:GetServerTimeNow()-state.session.startTime))%360 end
		return
	end
	if not state.mobile then
		local mouse=UserInputService:GetMouseLocation();local p,ok=aimResult(mouse);setAim(p,ok)
	elseif not state.pending and os.clock()-lastTouchCastScanAt>=Config.TouchCastScanInterval then
		lastTouchCastScanAt=os.clock();scanTouchTarget()
	end
end)
local circleCameraConnection
local function bindCircleCap()
	if circleCameraConnection then circleCameraConnection:Disconnect();circleCameraConnection=nil end
	local camera=Workspace.CurrentCamera
	if camera then
		circleCameraConnection=camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyTimingCircleCap)
	end
	applyTimingCircleCap()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCircleCap)
player.CharacterAdded:Connect(setupTracks)
Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer==player then restoreDesktopFishingLayout();releaseManualReelLock() end
end)
bindCircleCap()
applyFishingControlLayout()
if player.Character then setupTracks(player.Character) end
