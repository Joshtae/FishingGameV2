local P=game:GetService("Players").LocalPlayer
local RS=game:GetService("ReplicatedStorage")
local A=RS:WaitForChild("FishRngAction")
local E=RS:WaitForChild("FishRngState")
local G=P.PlayerGui:WaitForChild("FishRng")
local inv=G.InventoryPanel
local shop=G.ShopPanel
local reb=G.RebirthPanel
local result=G.Result
G.Fishing.Visible=false
G.WaterPrompt.Visible=false
local function hide() inv.Visible=false;shop.Visible=false;reb.Visible=false end
for _,n in ipairs({"Inventory","Shop","Rebirth"}) do G.Nav[n].MouseButton1Click:Connect(function() local x=G[n.."Panel"];hide();x.Visible=not x.Visible end) end
G.Nav.Fish.MouseButton1Click:Connect(function() result.Text="Move to water and click the green fishing circle.";result.Visible=true;task.wait(1.5);result.Visible=false end)
G.ShopPanel.BuyRod.MouseButton1Click:Connect(function() A:FireServer("BuyRod") end)
G.RebirthPanel.Confirm.MouseButton1Click:Connect(function() A:FireServer("Rebirth") end)
E.OnClientEvent:Connect(function(kind,data)
 if kind=="Catch" then
  result.Text="You just fished a "..data.rarity.." "..data.name.."!"
  result.TextColor3=data.color
  result.Visible=true
  task.delay(2.5,function() result.Visible=false end)
 elseif kind=="State" then
  G.TopBar.Cash.Text="$ "..math.floor(data.cash)
  G.TopBar.Income.Text="$ "..math.floor(data.income).." / sec"
  G.TopBar.Rebirths.Text="Rebirths: "..data.rebirths
  for _,c in ipairs(inv.List:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
  for _,item in ipairs(data.inventory) do
   local b=Instance.new("TextButton");b.Size=UDim2.new(1,-8,0,46)
   b.Text=item.rarity.."  "..item.name.."  •  $"..item.income.."/sec   [EQUIP]"
   b.TextColor3=Color3.new(1,1,1);b.TextStrokeTransparency=.4;b.BackgroundColor3=item.color;b.Font=Enum.Font.GothamBlack;b.TextSize=16;b.Parent=inv.List
   b.MouseButton1Click:Connect(function() A:FireServer("Equip",item.id) end)
  end
  inv.List.CanvasSize=UDim2.fromOffset(0,#data.inventory*53)
 end
end)
