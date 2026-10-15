local RunService=game:GetService("RunService")
local rig=script.Parent
local basePivot=rig:GetPivot()
local started=os.clock()
local connection
connection=RunService.Heartbeat:Connect(function()
 if not rig.Parent then connection:Disconnect();return end
 local t=os.clock()-started
 local breath=math.sin(t*math.pi*1.05)
 local sway=math.sin(t*math.pi*.525)
 rig:PivotTo(basePivot*CFrame.new(0,breath*.10,0)*CFrame.Angles(0,0,math.rad(sway*.65)))
end)
