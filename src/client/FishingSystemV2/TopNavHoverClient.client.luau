-- Hover-only top-nav polish. This script never changes navigation bindings or authored UI layout.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = {
	SwayAngle = 6,
	SwayHalfPeriod = 0.35,
	ReturnSeconds = 0.15,
	SafetyPollSeconds = 0.2,
	TouchWiggleSeconds = 0.3,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local warnedPaths = {}
local bindings = {}
local boundTopFrames = nil

local function warnMissing(path)
	if warnedPaths[path] then return end
	warnedPaths[path] = true
	warn("[FishingSystemV2.TopNavHover] Missing UI after 10 seconds: " .. path)
end

local function waitForChild(parent, name, path)
	if not parent then
		warnMissing(path)
		return nil
	end
	local child = parent:WaitForChild(name, 10)
	if not child then
		warnMissing(path)
	end
	return child
end

local function isTouchOnly()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function cancelTween(tween)
	if tween then
		tween:Cancel()
	end
end

local function cancelAnimations(binding)
	binding.token += 1
	cancelTween(binding.swayTween)
	cancelTween(binding.returnTween)
	cancelTween(binding.wiggleTween)
	binding.swayTween = nil
	binding.returnTween = nil
	binding.wiggleTween = nil
end

local function returnToRest(binding)
	cancelTween(binding.swayTween)
	cancelTween(binding.wiggleTween)
	binding.swayTween = nil
	binding.wiggleTween = nil
	cancelTween(binding.returnTween)
	binding.token += 1
	local tween = TweenService:Create(
		binding.frame,
		TweenInfo.new(Config.ReturnSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Rotation = binding.restRotation}
	)
	binding.returnTween = tween
	tween:Play()
end

local function mouseIsOver(frame)
	local mousePosition = UserInputService:GetMouseLocation()
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(mousePosition.X, mousePosition.Y)) do
		if guiObject == frame or guiObject:IsDescendantOf(frame) then
			return true
		end
	end
	return false
end

local function startSway(binding)
	if isTouchOnly() then return end
	cancelAnimations(binding)
	binding.frame.Rotation = binding.restRotation - Config.SwayAngle
	local tween = TweenService:Create(
		binding.frame,
		TweenInfo.new(Config.SwayHalfPeriod, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{Rotation = binding.restRotation + Config.SwayAngle}
	)
	binding.swayTween = tween
	local token = binding.token
	tween:Play()

	task.spawn(function()
		while binding.swayTween == tween and binding.token == token do
			task.wait(Config.SafetyPollSeconds)
			if binding.swayTween ~= tween or binding.token ~= token then return end
			if not mouseIsOver(binding.frame) then
				returnToRest(binding)
				return
			end
		end
	end)
end

local function stopSwayIfOutside(binding)
	if isTouchOnly() then return end
	task.defer(function()
		if binding.swayTween and not mouseIsOver(binding.frame) then
			returnToRest(binding)
		end
	end)
end

local function playTouchWiggle(binding)
	if not isTouchOnly() then return end
	cancelAnimations(binding)
	local token = binding.token
	local sideSeconds = Config.TouchWiggleSeconds / 3

	local function playStep(targetRotation, nextStep)
		if binding.token ~= token then return end
		local tween = TweenService:Create(
			binding.frame,
			TweenInfo.new(sideSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{Rotation = targetRotation}
		)
		binding.wiggleTween = tween
		tween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and binding.token == token and nextStep then
				nextStep()
			end
		end)
		tween:Play()
	end

	playStep(binding.restRotation + Config.SwayAngle, function()
		playStep(binding.restRotation - Config.SwayAngle, function()
			playStep(binding.restRotation)
		end)
	end)
end

local function disconnectBinding(binding)
	for _, connection in ipairs(binding.connections) do
		connection:Disconnect()
	end
	cancelAnimations(binding)
	binding.frame.Rotation = binding.restRotation
end

local function connectHoverTarget(binding, target)
	table.insert(binding.connections, target.MouseEnter:Connect(function()
		startSway(binding)
	end))
	table.insert(binding.connections, target.MouseLeave:Connect(function()
		stopSwayIfOutside(binding)
	end))
end

local function findButton(frame, buttonPath, framePath)
	local parent = frame
	for _, name in ipairs(buttonPath) do
		parent = waitForChild(parent, name, framePath .. "." .. name)
		if not parent then return nil end
	end
	return parent:IsA("GuiButton") and parent or nil
end

local function bindFrame(overall, frameName, buttonPath)
	local framePath = "PlayerGui.TopFrames.OverallTopFrame." .. frameName
	local frame = waitForChild(overall, frameName, framePath)
	if not frame or not frame:IsA("GuiObject") then return end
	local button = findButton(frame, buttonPath, framePath)
	if not button then return end

	local binding = {
		frame = frame,
		restRotation = frame.Rotation,
		connections = {},
		token = 0,
		swayTween = nil,
		returnTween = nil,
		wiggleTween = nil,
	}
	table.insert(bindings, binding)

	connectHoverTarget(binding, frame)
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			connectHoverTarget(binding, descendant)
		end
	end
	table.insert(binding.connections, button.Activated:Connect(function()
		playTouchWiggle(binding)
	end))
end

local function disconnectAll()
	for _, binding in ipairs(bindings) do
		disconnectBinding(binding)
	end
	table.clear(bindings)
	boundTopFrames = nil
end

local function bindTopFrames(preferredTopFrames)
	local topFrames = preferredTopFrames or playerGui:FindFirstChild("TopFrames")
	if topFrames == boundTopFrames then return end

	disconnectAll()
	if not topFrames then
		warnMissing("PlayerGui.TopFrames")
		return
	end
	boundTopFrames = topFrames

	local overall = waitForChild(topFrames, "OverallTopFrame", "PlayerGui.TopFrames.OverallTopFrame")
	if not overall then return end

	bindFrame(overall, "FishingFrame", {"TextButton"})
	bindFrame(overall, "PlotFrame", {"TextButton"})
	bindFrame(overall, "ShopFrame", {"Glossy face", "TextButton"})
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TopFrames" then
		task.defer(function()
			bindTopFrames(child)
		end)
	end
end)

bindTopFrames(playerGui:FindFirstChild("TopFrames"))
