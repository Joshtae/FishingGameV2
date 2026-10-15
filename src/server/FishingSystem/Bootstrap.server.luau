--[[
	Phase 1 server bootstrap.
	Loads a session-locked profile before assigning a plot, and releases it before
	the plot is cleared. No remotes or client data access are created here.
]]
local Players = game:GetService("Players")

local root = script.Parent
local Data = require(root.Data)
local Plots = require(root.Plots)

local releasing = {}

local function releasePlayer(player)
	if releasing[player] then
		return
	end
	releasing[player] = true

	local preparedPlot
	Data.Release(
		player,
		function()
			preparedPlot = Plots.PrepareRelease(player)
		end,
		function()
			Plots.FinishRelease(player, preparedPlot)
		end
	)

	releasing[player] = nil
end

local function loadAndAssign(player)
	local data = Data.LoadPlayer(player)
	if not data or player.Parent ~= Players then
		return
	end

	-- Data.Loaded is fired by LoadPlayer before this synchronous claim occurs.
	local plot = Plots.Assign(player)
	if not plot then
		-- There is no UI or remote in Phase 1; the kick message is the player-facing notice.
		player:Kick("No free plot available")
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadAndAssign, player)
end)

Players.PlayerRemoving:Connect(releasePlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadAndAssign, player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		releasePlayer(player)
	end
end)

-- FishingSystemV2 server services are initialized here after the Phase 1 bootstrap is present.
require(root.Phase2Bootstrap)
