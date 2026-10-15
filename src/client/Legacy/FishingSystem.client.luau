local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local config = require(ReplicatedStorage:WaitForChild("FishingSystem"))
local remote = ReplicatedStorage:WaitForChild("FishingRemote")
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FishingSystem")
local panel = gui.FishingBar
local prompt = panel.Prompt
local fill = panel.BarBack.Fill
local result = gui.CatchResult

local state = "Idle"
local targetPosition
local indicator
local exclamation
local requiredClicks = 0
local clicks = 0
local sessionStarted = 0

local function makeIndicator()
	if indicator then return end
	indicator = Instance.new("Part")
	indicator.Name = "FishingCursorIndicator"
	indicator.Shape = Enum.PartType.Cylinder
	indicator.Size = Vector3.new(0.12, 3, 3)
	indicator.Color = Color3.fromRGB(72, 255, 100)
	indicator.Material = Enum.Material.Neon
	indicator.Transparency = 0.18
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CanQuery = false
	indicator.Orientation = Vector3.new(0, 0, 90)
	indicator.Parent = workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(180, 42)
	billboard.StudsOffset = Vector3.new(0, 2.1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = indicator
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "Click to Fish!"
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.fromRGB(110, 255, 124)
	text.TextStrokeTransparency = 0.2
	text.TextSize = 22
	text.Parent = billboard
end

local function removeIndicator()
	if indicator then indicator:Destroy(); indicator = nil end
end

local function showExclamation(position)
	if exclamation then exclamation:Destroy() end
	exclamation = Instance.new("Model")
	exclamation.Name = "FishingBite"
	exclamation.Parent = workspace
	local stem = Instance.new("Part")
	stem.Size = Vector3.new(0.45, 1.65, 0.32)
	stem.Color = Color3.fromRGB(255, 230, 52)
	stem.Material = Enum.Material.Neon
	stem.Anchored = true
	stem.CanCollide = false
	stem.CFrame = CFrame.new(position + Vector3.new(0, 2.25, 0))
	stem.Parent = exclamation
	local dot = Instance.new("Part")
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.5, 0.5, 0.5)
	dot.Color = stem.Color
	dot.Material = stem.Material
	dot.Anchored = true
	dot.CanCollide = false
	dot.CFrame = CFrame.new(position + Vector3.new(0, 1.15, 0))
	dot.Parent = exclamation
	local light = Instance.new("PointLight")
	light.Color = stem.Color
	light.Brightness = 2
	light.Range = 8
	light.Parent = stem
end

local function clearFishing()
	state = "Idle"
	panel.Visible = false
	removeIndicator()
	if exclamation then exclamation:Destroy(); exclamation = nil end
end

local function isFishingWater()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000)
	if not hit then return false end
	local instance = hit.Instance
	if instance:IsA("BasePart") then
		if instance.Material == Enum.Material.Water or instance:GetAttribute("FishingWater") == true then
			targetPosition = hit.Position
			return true
		end
	end
	if instance == workspace.Terrain then
		local region = Region3.new(hit.Position - Vector3.new(2,2,2), hit.Position + Vector3.new(2,2,2)):ExpandToGrid(4)
		local materials = workspace.Terrain:ReadVoxels(region, 4)
		if materials[1][1][1] == Enum.Material.Water then
			targetPosition = hit.Position
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function()
	if state == "Idle" then
		if isFishingWater() then
			makeIndicator()
			indicator.Position = targetPosition + Vector3.new(0, 0.12, 0)
		else
			removeIndicator()
		end
	end
end)

task.spawn(function()
	local dots = 0
	while true do
		if state == "Waiting" then
			dots = (dots % 3) + 1
			prompt.Text = "Waiting for Catch" .. string.rep(".", dots)
		else
			dots = 0
		end
		task.wait(0.45)
	end
end)

local function startFishing()
	if state ~= "Idle" or not targetPosition then return end
	local data = remote:InvokeServer("Start")
	if not data then return end
	requiredClicks = data.clicksRequired
	clicks = 0
	state = "Waiting"
	removeIndicator()
	panel.Visible = true
	fill.Size = UDim2.fromScale(0, 1)
	prompt.Text = "Waiting for Catch"
	local castPosition = targetPosition
	task.delay(Random.new():NextNumber(config.MinBiteDelay, config.MaxBiteDelay), function()
		if state ~= "Waiting" then return end
		state = "Biting"
		sessionStarted = os.clock()
		prompt.Text = "BITE! CLICK FAST!"
		showExclamation(castPosition)
		task.delay(data.catchWindow, function()
			if state == "Biting" then
				clearFishing()
				result.Text = "The catch escaped!"
				result.TextColor3 = Color3.fromRGB(255, 112, 112)
				result.Visible = true
				task.wait(1.5)
				result.Visible = false
			end
		end)
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if state == "Idle" and indicator then
		startFishing()
	elseif state == "Biting" then
		clicks += 1
		fill:TweenSize(UDim2.fromScale(math.clamp(clicks / requiredClicks, 0, 1), 1), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.06, true)
		if clicks >= requiredClicks then
			local caught = remote:InvokeServer("Finish")
			clearFishing()
			if caught then
				result.Text = "You just fished a " .. caught.name .. "!"
				result.TextColor3 = caught.color
				result.Visible = true
				TweenService:Create(result, TweenInfo.new(0.25), {TextTransparency = 0}):Play()
				task.wait(2.5)
				result.Visible = false
			end
		end
	end
end)
