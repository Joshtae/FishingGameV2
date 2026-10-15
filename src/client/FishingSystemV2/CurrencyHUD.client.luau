-- Client display only: reads server-written Player attributes and never changes currency.
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local NumberFormat=require(ReplicatedStorage.FishingSystemV2.NumberFormat)
local player=Players.LocalPlayer
local hud=player:WaitForChild("PlayerGui"):WaitForChild("FishingSystemV2"):WaitForChild("CurrencyHUD")
local labels={Cash=hud.CashPill.Amount,Gems=hud.GemsPill.Amount}
local gains={Cash=hud.CashPill.Gain,Gems=hud.GemsPill.Gain}
local displayed={Cash=0,Gems=0}
local actual={Cash=0,Gems=0}
local textCache={}
local revision={Cash=0,Gems=0}
local pendingGain={Cash=0,Gems=0}
local gainQueued={Cash=false,Gems=false}
local function setText(kind,value)
	local text=NumberFormat.Format(value)
	if textCache[kind]~=text then labels[kind].Text=text;textCache[kind]=text end
end
local function showGain(kind,amount)
	if amount<=0 then return end
	pendingGain[kind]+=amount
	if gainQueued[kind] then return end
	gainQueued[kind]=true
	task.delay(.2,function()
		local label=gains[kind];local value=pendingGain[kind];pendingGain[kind]=0;gainQueued[kind]=false
		label.Text="+"..NumberFormat.Format(value)
		label.TextTransparency=0;label.TextStrokeTransparency=0;label.Position=UDim2.fromScale(.5,0);label.Visible=true
		TweenService:Create(label,TweenInfo.new(.55),{Position=UDim2.fromScale(.5,-.35),TextTransparency=1,TextStrokeTransparency=1}):Play()
		task.delay(.58,function() label.Visible=false end)
	end)
end
local function update(kind)
	local value=player:GetAttribute(kind)
	if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then value=0 end
	local prior=actual[kind];actual[kind]=value
	if value>prior then showGain(kind,value-prior) end
	revision[kind]+=1
	local this=revision[kind]
	if value<=displayed[kind] or value-displayed[kind]>math.max(10000,value*.1) then displayed[kind]=value;setText(kind,value);return end
	local start=displayed[kind];local started=os.clock()
	task.spawn(function()
		while revision[kind]==this do
			local alpha=math.min(1,(os.clock()-started)/.25)
			displayed[kind]=math.min(value,start+(value-start)*alpha)
			setText(kind,displayed[kind])
			if alpha>=1 then displayed[kind]=value;setText(kind,value);break end
			task.wait()
		end
	end)
end
for kind in pairs(labels) do player:GetAttributeChangedSignal(kind):Connect(function() update(kind) end);update(kind) end
