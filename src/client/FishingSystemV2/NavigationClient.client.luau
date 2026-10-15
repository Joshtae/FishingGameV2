-- Client-side R3 top-navigation hooks. The server selects and validates every destination.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local WorldConfig = require(ReplicatedStorage.FishingSystemV2.WorldConfig)
local Navigate = ReplicatedStorage.FishingSystemV2.Remotes.Navigate
local lastSent = -math.huge
local boundTopFrames = nil
local boundOverall = nil
local connections = {}

local function disconnectButtons()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function firstGuiButton(frame)
	return frame and frame:FindFirstChildWhichIsA("GuiButton", true)
end

local function bindTopFrames()
	local topFrames = playerGui:FindFirstChild("TopFrames")
	local overall = topFrames and topFrames:FindFirstChild("OverallTopFrame")
	if topFrames == boundTopFrames and overall == boundOverall then return end

	disconnectButtons()
	boundTopFrames, boundOverall = topFrames, overall
	if not overall then return end

	for frameName, destination in pairs({
		FishingFrame = "Fishing",
		PlotFrame = "Plot",
		ShopFrame = "Shop",
	}) do
		local button = firstGuiButton(overall:FindFirstChild(frameName))
		if button then
			table.insert(connections, button.Activated:Connect(function()
				local stamp = os.clock()
				if stamp - lastSent < WorldConfig.NavigateCooldownSeconds then return end
				lastSent = stamp
				Navigate:FireServer(destination)
			end))
		end
	end
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TopFrames" then task.defer(bindTopFrames) end
end)

bindTopFrames()
