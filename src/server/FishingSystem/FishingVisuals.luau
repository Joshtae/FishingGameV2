--[[ Server-created rod, bobber, and Beam visuals. Public: Create, PullBack, Destroy. ]]
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local FishingVisuals = {}

local function safePart(part)
	part.Anchored = part.Name ~= "RodHandle"
	part.CanCollide = false; part.CanQuery = false; part.CanTouch = false; part.Massless = true
end

local function cancelTween(tween)
	if tween then tween:Cancel() end
end

local function stopIdleBob(visual)
	cancelTween(visual.idleBobTween)
	visual.idleBobTween = nil
end

local function startIdleBob(visual)
	if not visual.model.Parent then return end
	stopIdleBob(visual)
	visual.bobber.CFrame = visual.bobberBaseCFrame
	visual.idleBobTween = TweenService:Create(
		visual.bobber,
		TweenInfo.new(Config.BobberIdleBobPeriod * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{CFrame = visual.bobberBaseCFrame * CFrame.new(0, Config.BobberIdleBobAmplitude, 0)}
	)
	visual.idleBobTween:Play()
end
function FishingVisuals.Create(player, target, isAlive)
	local character = player.Character
	local hand = character and character:FindFirstChild(Config.RodAttachHand)
	if not hand or not hand:IsA("BasePart") then return nil end
	local model = Instance.new("Model")
	model.Name = "FishingVisual_" .. player.UserId
	model.Parent = character
	local rod = Instance.new("Part")
	rod.Name = "RodHandle"; rod.Size = Vector3.new(.16, .16, Config.RodLength); rod.Material = Enum.Material.Wood; rod.Color = Color3.fromRGB(92, 55, 28)
	safePart(rod); rod.CFrame = hand.CFrame * Config.RodGripOffset * CFrame.new(0, 0, -Config.RodLength * .45); rod.Parent = model
	local weld = Instance.new("WeldConstraint"); weld.Part0 = hand; weld.Part1 = rod; weld.Parent = rod
	local rodAttachment = Instance.new("Attachment"); rodAttachment.Name = "LineStart"; rodAttachment.Position = Vector3.new(0,0,-Config.RodLength*.5); rodAttachment.Parent = rod
	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"; bobber.Shape = Enum.PartType.Ball; bobber.Size = Vector3.new(.55,.55,.55); bobber.Material = Enum.Material.Neon; bobber.Color = Color3.fromRGB(255, 97, 97)
	bobber.Transparency = 1; safePart(bobber); bobber.Position = target; bobber.Parent = model
	local bobberAttachment = Instance.new("Attachment"); bobberAttachment.Name = "LineEnd"; bobberAttachment.Parent = bobber
	local beam = Instance.new("Beam")
	beam.Name = "FishingLine"; beam.Attachment0 = rodAttachment; beam.Attachment1 = bobberAttachment; beam.Width0 = .035; beam.Width1 = .025; beam.FaceCamera = true; beam.Enabled = false; beam.Color = ColorSequence.new(Color3.fromRGB(235,235,235)); beam.Parent = rod
	local visual = {model=model, rod=rod, bobber=bobber, beam=beam, target=target, bobberBaseCFrame=CFrame.new(target), idleBobTween=nil, dipTween=nil}
	local delaySeconds = Config.MaxWindupWaitSeconds + Config.CastThrowSeconds * Config.ThrowReleaseFraction
	task.delay(delaySeconds, function()
		if isAlive and isAlive() and model.Parent then
			bobber.Transparency = 0
			beam.Enabled = true
			startIdleBob(visual)
		end
	end)
	return visual
end
function FishingVisuals.Bite(visual)
	if not visual or not visual.model.Parent then return end
	stopIdleBob(visual)
	cancelTween(visual.dipTween)
	visual.bobber.CFrame = visual.bobberBaseCFrame
	local down = TweenService:Create(
		visual.bobber,
		TweenInfo.new(Config.BobberDipDownSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{CFrame = visual.bobberBaseCFrame * CFrame.new(0, -Config.BobberDipDepth, 0)}
	)
	visual.dipTween = down
	down.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or not visual.model.Parent then return end
		local up = TweenService:Create(
			visual.bobber,
			TweenInfo.new(Config.BobberDipUpSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{CFrame = visual.bobberBaseCFrame}
		)
		visual.dipTween = up
		up:Play()
	end)
	down:Play()
end

function FishingVisuals.PullBack(visual, destination)
	if not visual or not visual.model.Parent then return end
	stopIdleBob(visual)
	cancelTween(visual.dipTween)
	visual.dipTween = nil
	visual.beam.Enabled = true
	local origin = visual.bobber.Position
	for step=1,10 do
		if not visual.model.Parent then return end
		visual.bobber.Position = origin:Lerp(destination, step/10)
		task.wait(Config.CancelCooldown/10)
	end
end
function FishingVisuals.Destroy(visual)
	if not visual then return end
	stopIdleBob(visual)
	cancelTween(visual.dipTween)
	visual.dipTween = nil
	if visual.model then visual.model:Destroy() end
end
return FishingVisuals
