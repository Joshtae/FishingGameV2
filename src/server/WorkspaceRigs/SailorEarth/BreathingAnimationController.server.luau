-- Original breathing idle for Block Avatar rigs that use AnimationConstraints.
local RunService=game:GetService("RunService")
local rig=script.Parent
local basePivot=rig:GetPivot()
local started=os.clock()
local connection
connection=RunService.Heartbeat:Connect(function()
 if not rig.Parent then
  if connection then connection:Disconnect() end
  return
 end
 local t=os.clock()-started
 local breath=math.sin(t*math.pi*1.05)
 local sway=math.sin(t*math.pi*0.525)
 local offset=CFrame.new(0,breath*0.10,0)*CFrame.Angles(0,0,math.rad(sway*0.65))
 rig:PivotTo(basePivot*offset)
end)
