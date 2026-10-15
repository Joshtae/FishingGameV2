--[[
	R3 server-authoritative world navigation and plot spawning.
	Start() wires the Navigate RemoteEvent plus join/respawn plot positioning.
	Clients submit only an approved destination string; this module chooses every position.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = script.Parent
local FishingSessions = require(root.FishingSessions)
local Plots = require(root.Plots)
local WorldConfig = require(ReplicatedStorage.FishingSystemV2.WorldConfig)
local Navigate = ReplicatedStorage.FishingSystemV2.Remotes.Navigate

local NavigationService = {}
local started = false
local lastNavigate = {}
local requestTimes = {}

local function targetCFrame(spawn)
	local topSurface = spawn.CFrame:PointToWorldSpace(Vector3.new(0, spawn.Size.Y * 0.5, 0))
	local position = topSurface + spawn.CFrame.UpVector * WorldConfig.SpawnHeightOffset
	return CFrame.lookAt(position, position + spawn.CFrame.LookVector, spawn.CFrame.UpVector), position
end

local function getAliveCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not rootPart then return nil end
	return character, humanoid, rootPart
end

local function pivotToSpawn(player, character, spawn)
	if player.Character ~= character or not spawn or not spawn:IsA("SpawnLocation") or not spawn:IsDescendantOf(Workspace) then return nil end
	local current, humanoid = getAliveCharacter(player)
	if current ~= character then return nil end
	local destination, position = targetCFrame(spawn)
	humanoid.Sit = false
	character:PivotTo(destination)
	return position
end

local function waitForPlot(player, deadline)
	local plot = Plots.Get(player)
	while not plot and os.clock() < deadline and player.Parent == Players do
		task.wait()
		plot = Plots.Get(player)
	end
	return plot
end

local function placeAtOwnPlot(player, character)
	local rootPart = character:WaitForChild("HumanoidRootPart", WorldConfig.PlotSpawnWaitSeconds)
	if not rootPart or player.Character ~= character then return end
	local workspaceDeadline = os.clock() + WorldConfig.PlotSpawnWaitSeconds
	while not character:IsDescendantOf(Workspace) and os.clock() < workspaceDeadline and player.Character == character do
		task.wait()
	end
	if not character:IsDescendantOf(Workspace) or player.Character ~= character then return end
	local plot = waitForPlot(player, os.clock() + WorldConfig.PlotSpawnWaitSeconds)
	if not plot then
		warn("[FishingSystem.Navigation] Plot assignment timed out for UserId " .. player.UserId .. "; leaving player at ShopSpawn.")
		return
	end
	local spawn = plot:FindFirstChild("PlotSpawn")
	if not spawn or not spawn:IsA("SpawnLocation") then
		warn("[FishingSystem.Navigation] Missing PlotSpawn for " .. plot.Name)
		return
	end
	RunService.Heartbeat:Wait()
	local target = pivotToSpawn(player, character, spawn)
	if not target then return end
	task.delay(1, function()
		local _, _, currentRoot = getAliveCharacter(player)
		if player.Character == character and currentRoot and (currentRoot.Position - target).Magnitude > 5 then
			warn("[FishingSystem.Navigation] Re-pivoting UserId " .. player.UserId .. " after spawn drift.")
			pivotToSpawn(player, character, spawn)
		end
	end)
end

local function attachPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(placeAtOwnPlot, player, character)
	end)
	if player.Character then
		task.spawn(placeAtOwnPlot, player, player.Character)
	end
end

local function chooseFishingSpawn(player)
	local candidates = {}
	for index = 1, 4 do
		local sand = Workspace:FindFirstChild("Sand" .. index)
		local spawn = sand and sand:FindFirstChild("FishingSpawn" .. index)
		if spawn and spawn:IsA("SpawnLocation") then table.insert(candidates, spawn) end
	end
	if #candidates == 0 then return nil end
	local fewest = math.huge
	local leastCrowded = {}
	for _, spawn in ipairs(candidates) do
		local _, position = targetCFrame(spawn)
		local count = 0
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local _, _, rootPart = getAliveCharacter(other)
				if rootPart and (rootPart.Position - position).Magnitude <= WorldConfig.SandCrowdRadius then count += 1 end
			end
		end
		if count < fewest then fewest = count; leastCrowded = {spawn}
		elseif count == fewest then table.insert(leastCrowded, spawn) end
	end
	return leastCrowded[Random.new():NextInteger(1, #leastCrowded)]
end

local function requestAllowed(player)
	local stamp = os.clock()
	local times = requestTimes[player] or {}
	requestTimes[player] = times
	for index = #times, 1, -1 do
		if stamp - times[index] >= 1 then table.remove(times, index) end
	end
	if #times >= WorldConfig.NavigateRateLimit then return false end
	if stamp - (lastNavigate[player] or -math.huge) < WorldConfig.NavigateCooldownSeconds then return false end
	table.insert(times, stamp)
	lastNavigate[player] = stamp
	return true
end

local function handleNavigate(player, destination)
	if destination ~= "Plot" and destination ~= "Shop" and destination ~= "Fishing" then return end
	if not requestAllowed(player) then return end
	local character = getAliveCharacter(player)
	if not character then return end
	local spawn
	if destination == "Plot" then
		local plot = Plots.Get(player)
		spawn = plot and plot:FindFirstChild("PlotSpawn")
	elseif destination == "Shop" then
		spawn = Workspace:FindFirstChild("ShopArea") and Workspace.ShopArea:FindFirstChild("ShopSpawn")
	else
		spawn = chooseFishingSpawn(player)
	end
	if not spawn or not spawn:IsA("SpawnLocation") then return end
	FishingSessions.EndSession(player, "Cancelled")
	pivotToSpawn(player, character, spawn)
end

-- Starts the server-owned RemoteEvent validation and join/respawn positioning once.
function NavigationService.Start()
	if started then return end
	started = true
	Navigate.OnServerEvent:Connect(handleNavigate)
	Players.PlayerAdded:Connect(attachPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastNavigate[player] = nil
		requestTimes[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do attachPlayer(player) end
end

return NavigationService
