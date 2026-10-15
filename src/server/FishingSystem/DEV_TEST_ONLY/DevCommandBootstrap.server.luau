--[[
	Studio-only chat command bridge for DEV_TEST_ONLY.Commands.
	Delete the DEV_TEST_ONLY folder before release to remove every diagnostic command.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Commands = require(script.Parent.Commands)

local function connectPlayer(player)
	player.Chatted:Connect(function(message)
		Commands.HandleChat(player, message)
	end)
end

Players.PlayerAdded:Connect(connectPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end
