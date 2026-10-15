-- Starts the server-authoritative Phase 3 fishing services.
local Players = game:GetService("Players")
local root = script.Parent
local Data = require(root.Data)
local FishingSessions = require(root.FishingSessions)
FishingSessions.Start()
Data.Loaded:Connect(function(player)
	FishingSessions.QueueResume(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	if Data.IsLoaded(player) then FishingSessions.QueueResume(player) end
end
