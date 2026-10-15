local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Debris=game:GetService("Debris")
local player=Players.LocalPlayer
local fishAction=RS:WaitForChild("FishRngAction")
local fishState=RS:WaitForChild("FishRngState")
local fishingGui=player.PlayerGui:WaitForChild("FishingSystem")
local bar=fishingGui:WaitForChild("FishingBar")
local back=bar:WaitForChild("BarBack")
local fill=back:WaitForChild("Fill")
local status=bar:WaitForChild("FishingStatus")
local phase="Idle"
local canFish=false
local needed=0
local clicks=0
local sequence=0

bar.Visible=false
fill.AnchorPoint=Vector2.new(0,1)
fill.Position=UDim2.fromScale(0,1)
fill.Size=UDim2.fromScale(1,0)

local ring=Instance.new("Part")
ring.Name="LocalFishingCursor"; ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(.12,3,3)
ring.Material=Enum.Material.Neon; ring.Anchored=true; ring.CanCollide=false; ring.CanQuery=false; ring.Orientation=Vector3.new(0,0,90); ring.Parent=workspace
local badge=Instance.new("BillboardGui"); badge.Size=UDim2.fromOffset(170,34); badge.StudsOffset=Vector3.new(0,2,0); badge.AlwaysOnTop=true; badge.Parent=ring
local text=Instance.new("TextLabel"); text.Size=UDim2.fromScale(1,1); text.BackgroundTransparency=1; text.Font=Enum.Font.GothamBlack;text.TextSize=19;text.TextStrokeTransparency=.2;text.Parent=badge

local function terrainWater(point)
 local terrain=workspace.Terrain
 local region=Region3.new(point-Vector3.new(2,2,2),point+Vector3.new(2,2,2)):ExpandToGrid(4)
 local materials=terrain:ReadVoxels(region,4)
 return materials[1][1][1]==Enum.Material.Water
end

local function marker()
 local head=player.Character and player.Character:FindFirstChild("Head")
 if not head then return end
 for _,spec in ipairs({{Vector3.new(.55,1.65,.3),Vector3.new(0,3.2,0),Enum.PartType.Block},{Vector3.new(.55,.55,.55),Vector3.new(0,2.05,0),Enum.PartType.Ball}}) do
  local p=Instance.new("Part");p.Name="CatchExclamation";p.Shape=spec[3];p.Size=spec[1];p.Material=Enum.Material.Neon;p.Color=Color3.fromRGB(255,230,45);p.Anchored=true;p.CanCollide=false;p.CFrame=head.CFrame+spec[2];p.Parent=workspace;Debris:AddItem(p,1.4)
 end
end

local function finish()
 phase="Idle";bar.Visible=false;ring.Transparency=1;fill.Size=UDim2.fromScale(1,0)
end

local function beginWaiting()
 phase="Waiting";bar.Visible=true;fill.Size=UDim2.fromScale(1,0);sequence+=1
 local mySequence=sequence
 task.spawn(function()
  for i=1,5 do
   if phase~="Waiting" or mySequence~=sequence then return end
   status.Text="Waiting for Catch"..string.rep(".",i%4)
   task.wait(.42)
  end
  if phase=="Waiting" and mySequence==sequence then phase="Biting";status.Text="BITE! CLICK FAST!" end
 end)
end

RunService.RenderStepped:Connect(function()
 if phase~="Idle" then ring.Transparency=1;return end
 local camera=workspace.CurrentCamera
 if not camera then return end
 local mouse=UIS:GetMouseLocation();local ray=camera:ViewportPointToRay(mouse.X,mouse.Y);local hit=workspace:Raycast(ray.Origin,ray.Direction*1000)
 ring.Transparency=1;canFish=false
 if hit then
  local instance=hit.Instance
  canFish=(instance==workspace.Terrain and terrainWater(hit.Position)) or (instance:IsA("BasePart") and (instance.Material==Enum.Material.Water or instance:GetAttribute("FishingWater")==true))
  ring.Position=hit.Position+Vector3.new(0,.1,0);ring.Transparency=.15;ring.Color=canFish and Color3.fromRGB(61,255,100) or Color3.fromRGB(255,70,70)
  text.Text=canFish and "Click to Fish!" or "Find Water";text.TextColor3=ring.Color
 end
end)

UIS.InputBegan:Connect(function(input,processed)
 if processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
 if phase=="Idle" and canFish then
  phase="Starting";fishAction:FireServer("StartFishing")
 elseif phase=="Biting" then
  clicks+=1;fill.Size=UDim2.fromScale(1,math.clamp(clicks/needed,0,1))
  if clicks>=needed then phase="Catching";status.Text="Caught!";fishAction:FireServer("Catch",clicks) end
 end
end)

fishState.OnClientEvent:Connect(function(kind,data)
 if kind=="FishingStart" and phase~="Idle" and phase~="Catching" then
  needed=math.max(1,data.clicks or 10);clicks=0;beginWaiting()
 elseif kind=="Catch" then
  marker();finish()
 end
end)
