-- Studio-only chat bridge for Phase 3 diagnostics; delete DEV_TEST_ONLY before release.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then return end
local Commands=require(script.Parent.Phase3Commands)
local function connect(player) player.Chatted:Connect(function(message) Commands.HandleChat(player,message) end) end
Players.PlayerAdded:Connect(connect)
for _,player in ipairs(Players:GetPlayers()) do connect(player) end
