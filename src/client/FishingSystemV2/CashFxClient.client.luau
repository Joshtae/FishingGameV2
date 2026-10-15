-- Local-only R4 cash collection visual. The server owns Cash and emits the validated collection event.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Config = require(shared:WaitForChild("CashFxConfig"))
local remote = shared.Remotes:WaitForChild("CashCollected")
local template = shared:WaitForChild("CashIconTemplate")
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FishingSystemV2CashFx")
local layer = gui:WaitForChild("Layer")

local queue = {}
local schedulerActive = false
local queueToken = 0
local liveIcons = {}
local liveCount = 0

local function finitePositive(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
end

local function viewportScale(point)
	local size = layer.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return nil end
	return Vector2.new(point.X / size.X, point.Y / size.Y)
end

local function isInViewport(point)
	local size = layer.AbsoluteSize
	return point.Z > 0 and point.X >= 0 and point.X <= size.X and point.Y >= 0 and point.Y <= size.Y
end

local function targetScale()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not root or not camera then return nil end
	local point = camera:WorldToViewportPoint(root.Position)
	if not isInViewport(point) then return nil end
	return viewportScale(Vector2.new(point.X, point.Y))
end

local function startScale(worldPosition)
	local camera = Workspace.CurrentCamera
	if camera then
		local point = camera:WorldToViewportPoint(worldPosition)
		if isInViewport(point) then
			local result = viewportScale(Vector2.new(point.X, point.Y))
			if result then return result end
		end
	end
	return targetScale()
end

local function destroyIcon(icon)
	local record = liveIcons[icon]
	if not record then return end
	liveIcons[icon] = nil
	if record.connection then record.connection:Disconnect() end
	if record.alpha then record.alpha:Destroy() end
	if icon.Parent then icon:Destroy() end
	liveCount -= 1
end

local function clearEffects()
	queueToken += 1
	table.clear(queue)
	schedulerActive = false
	while next(liveIcons) do
		destroyIcon(next(liveIcons))
	end
end

local function playSound()
	if Config.CollectSoundId == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = Config.CollectSoundId
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 3)
end

local function playIcon(startPoint)
	if liveCount >= Config.MaxIconsOnScreen then return end
	local icon = template:Clone()
	icon.Visible = true
	icon.Active = false
	icon.ImageTransparency = 0
	icon.Rotation = math.random(-20, 20)
	icon.AnchorPoint = Vector2.new(.5, .5)
	local height = layer.AbsoluteSize.Y
	local width = math.max(1, layer.AbsoluteSize.X)
	icon.Size = UDim2.fromScale(Config.IconSizeScale * height / width, Config.IconSizeScale)
	icon.Position = UDim2.fromScale(startPoint.X, startPoint.Y)
	icon.Parent = layer
	liveCount += 1
	liveIcons[icon] = {}
	local radius = math.random() * (Config.BurstRadiusMax - Config.BurstRadiusMin) + Config.BurstRadiusMin
	local angle = math.random() * math.pi * 2
	local burstPoint = startPoint + Vector2.new(math.cos(angle) * radius * height / width, math.sin(angle) * radius)
	local burst = TweenService:Create(icon, TweenInfo.new(Config.BurstSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(burstPoint.X, burstPoint.Y),
	})
	burst:Play()

	task.delay(Config.BurstSeconds + math.random() * Config.FlyStaggerMax, function()
		if not liveIcons[icon] then return end
		local alpha = Instance.new("NumberValue")
		alpha.Value = 0
		alpha.Parent = icon
		local trail = icon:FindFirstChild("Trail")
		if trail then
			trail.Visible = true
			trail.Size = UDim2.fromScale(Config.TrailLengthScale * height / width, .18)
		end
		local prior = burstPoint
		local connection
		connection = RunService.RenderStepped:Connect(function()
			if not liveIcons[icon] then
				if connection then connection:Disconnect() end
				return
			end
			local target = targetScale()
			if not target then
				destroyIcon(icon)
				return
			end
			local current = burstPoint:Lerp(target, alpha.Value)
			icon.Position = UDim2.fromScale(current.X, current.Y)
			if trail then
				local delta = current - prior
				if delta.Magnitude > 0 then
					trail.Rotation = math.deg(math.atan2(delta.Y, delta.X))
				end
			end
			prior = current
		end)
		liveIcons[icon].connection = connection
		liveIcons[icon].alpha = alpha
		local fly = TweenService:Create(alpha, TweenInfo.new(Config.FlySeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Value = 1})
		fly.Completed:Connect(function()
			if not liveIcons[icon] then return end
			if trail then trail.Visible = false end
			local arrive = TweenService:Create(icon, TweenInfo.new(Config.ArriveShrinkSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.fromScale(0, 0),
				ImageTransparency = 1,
			})
			arrive.Completed:Connect(function()
				destroyIcon(icon)
			end)
			arrive:Play()
		end)
		fly:Play()
	end)
end

local function playEntry(entry)
	local start = startScale(entry.position)
	if not start then return end
	playSound()
	local count = math.min(Config.IconCount, math.max(0, Config.MaxIconsOnScreen - liveCount))
	for _ = 1, count do
		playIcon(start)
	end
end

local function processQueue(token)
	if token ~= queueToken then return end
	if #queue == 0 then
		schedulerActive = false
		return
	end
	local entry = table.remove(queue, 1)
	playEntry(entry)
	task.delay(Config.QueueGapSeconds, function()
		processQueue(token)
	end)
end

local function enqueue(entry)
	if not schedulerActive then
		schedulerActive = true
		table.insert(queue, entry)
		processQueue(queueToken)
		return
	end
	if #queue >= Config.MaxQueued then
		queue[#queue].amount += entry.amount
	else
		table.insert(queue, entry)
	end
end

remote.OnClientEvent:Connect(function(amount, position)
	if not finitePositive(amount) or typeof(position) ~= "Vector3" then return end
	enqueue({amount = amount, position = position})
end)

local function watchCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(clearEffects)
	end
end

player.CharacterAdded:Connect(function(character)
	clearEffects()
	watchCharacter(character)
end)
if player.Character then watchCharacter(player.Character) end
