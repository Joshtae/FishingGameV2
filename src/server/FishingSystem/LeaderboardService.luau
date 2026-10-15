--[[
Server-only leaderboard data authority.
Start() mirrors loaded TotalCatches into the replicated Catches attribute.
RecordCatch(player) increments TotalCatches exactly once after FishingSessions awards a successful catch.
]]
local Players = game:GetService("Players")
local Data = require(script.Parent.Data)

local LeaderboardService = {}
local started = false

local function syncPlayer(player, data)
	if player.Parent ~= Players or not Data.IsLoaded(player) or type(data) ~= "table" then return false end
	local catches = data.TotalCatches
	if type(catches) ~= "number" or catches ~= catches or catches == math.huge or catches == -math.huge or catches < 0 or catches % 1 ~= 0 then
		catches = 0
		data.TotalCatches = catches
	end
	player:SetAttribute("Catches", catches)
	return true
end

-- Increments an already-loaded player's saved catch total and replicated Catches attribute.
function LeaderboardService.RecordCatch(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not Data.IsLoaded(player) then return false end
	local data = Data.Get(player)
	if not data then return false end
	local catches = data.TotalCatches
	if type(catches) ~= "number" or catches ~= catches or catches == math.huge or catches == -math.huge or catches < 0 or catches % 1 ~= 0 then
		catches = 0
	end
	data.TotalCatches = catches + 1
	player:SetAttribute("Catches", data.TotalCatches)
	return true
end

-- Connects profile-load synchronization and initializes players that loaded before this service started.
function LeaderboardService.Start()
	if started then return end
	started = true
	Data.Loaded:Connect(syncPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		local data = Data.Get(player)
		if data then syncPlayer(player, data) end
	end
end

return LeaderboardService
