local P=game:GetService("Players").LocalPlayer;local RS=game:GetService("ReplicatedStorage");local UIS=game:GetService("UserInputService");local Tween=game:GetService("TweenService")
local R=RS.FishRngWorldAction;local Fish=RS:WaitForChild("FishRngAction");local last=os.clock();local auto=false;local quick=false
local function find(gui,path) local x=gui;for part in string.gmatch(path,"[^.]+")do x=x:WaitForChild(part)end;return x end
local pg=P:WaitForChild("PlayerGui");local plot=find(pg,"PlotGui.Plots.PlotUIButton");local fishing=find(pg,"FishingGui.Shops.FishingUIButton");local shop=find(pg,"ShopGui.Shops.ShopUIButton")
plot.MouseButton1Click:Connect(function()R:FireServer("Plot")end);fishing.MouseButton1Click:Connect(function()R:FireServer("Fishing")end);shop.MouseButton1Click:Connect(function()R:FireServer("Shop")end)
local q=find(pg,"FishingSystem.QuickFishing");local a=find(pg,"FishingSystem.AutoFish");local qb=q:WaitForChild("QuickFishButton");local ab=a:WaitForChild("AutoFishButton");local gem=q.GemOption:FindFirstChild("GemBuyOption") or q.GemOption:FindFirstChildWhichIsA("TextButton");local robux=q.RobuxOption:FindFirstChild("RobuxBuyOption") or q.RobuxOption:FindFirstChildWhichIsA("TextButton")
local off=Color3.fromRGB(204,213,200);local on=Color3.fromRGB(56,213,21);local offS=Color3.fromRGB(124,130,122);local onS=Color3.fromRGB(35,131,13)
local function paint(frame,value)frame.BackgroundColor3=value and on or off;local st=frame:FindFirstChildOfClass("UIStroke");if st then st.Color=value and onS or offS end end
local function wiggle(frame)local base=frame.Rotation;frame.MouseEnter:Connect(function()Tween:Create(frame,TweenInfo.new(.1),{Rotation=base+2}):Play()end);frame.MouseLeave:Connect(function()Tween:Create(frame,TweenInfo.new(.1),{Rotation=base}):Play()end)end
paint(q,false);paint(a,false);wiggle(q);wiggle(a)
gem.MouseButton1Click:Connect(function()R:FireServer("BuyQuickGems")end)
robux.MouseButton1Click:Connect(function()warn("Quick Fish needs your 49 Robux developer-product ID before it can open Roblox purchase.")end)
qb.MouseButton1Click:Connect(function()R:FireServer("ToggleQuick")end);ab.MouseButton1Click:Connect(function()R:FireServer("ToggleAuto")end)
R.OnClientEvent:Connect(function(k,v)if k=="QuickUnlocked" then qb.Text="QUICK FISH" elseif k=="Quick" then quick=v;paint(q,v) elseif k=="Auto" then auto=v;paint(a,v) end end)
UIS.InputBegan:Connect(function(_,gp)if not gp then last=os.clock()end end)
task.spawn(function()while true do task.wait(.5);if auto or os.clock()-last>=20 then Fish:FireServer("StartFishing");task.wait(quick and 1.5 or 3);Fish:FireServer("Catch",999);if not auto then last=os.clock()end end end end)
