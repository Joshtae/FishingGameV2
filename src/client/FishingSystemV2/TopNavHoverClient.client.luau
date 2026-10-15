-- Hover-only top-nav polish. This script never changes navigation bindings or authored UI layout.
-- It only animates the Rotation of FishingFrame, PlotFrame and ShopFrame.
--
-- Hover is detected from mouse-movement InputObject positions (GUI space, top-bar inset already
-- removed), which is the same space PlayerGui:GetGuiObjectsAtPosition expects. Touch taps are
-- detected from the input type itself, so it also works in Studio's device emulator.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = {
	SwayAngle = 6, -- degrees either side of rest
	SwayHalfPeriod = 0.35, -- seconds from one side to the other
	ReturnSeconds = 0.15, -- ease back to rest when hover ends
	TouchWiggleSeconds = 0.3, -- one wiggle on tap
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FRAME_SPECS = {
	{ name = "FishingFrame", button = { "TextButton" } },
	{ name = "PlotFrame", button = { "TextButton" } },
	{ name = "ShopFrame", button = { "Glossy face", "TextButton" } },
}

local warnedPaths = {}
local bindings = {} -- array of binding tables
local boundTopFrames = nil
local lastMousePosition = nil -- Vector2 in GUI space, or nil when unknown

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

local function cancelTween(binding)
	if binding.tween then
		binding.tween:Cancel()
		binding.tween = nil
	end
end

-- Sway is driven every frame from a sine wave, so it can start smoothly from wherever the
-- frame currently is and never needs chained tweens.
local function startSway(binding)
	if binding.swaying then return end
	cancelTween(binding)
	binding.swaying = true
	-- Start the wave at the phase that matches the current rotation (no jump).
	local offset = math.clamp((binding.frame.Rotation - binding.restRotation) / Config.SwayAngle, -1, 1)
	local period = Config.SwayHalfPeriod * 2
	binding.swayClock = math.asin(offset) / (2 * math.pi) * period
end

local function stopSway(binding)
	if not binding.swaying then return end
	binding.swaying = false
	cancelTween(binding)
	local tween = TweenService:Create(
		binding.frame,
		TweenInfo.new(Config.ReturnSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rotation = binding.restRotation }
	)
	binding.tween = tween
	tween:Play()
end

local function playTouchWiggle(binding)
	binding.swaying = false
	cancelTween(binding)
	local step = Config.TouchWiggleSeconds / 3
	local targets = {
		binding.restRotation + Config.SwayAngle,
		binding.restRotation - Config.SwayAngle,
		binding.restRotation,
	}
	local myToken = {}
	binding.wiggleToken = myToken
	local function play(index)
		if binding.wiggleToken ~= myToken or index > #targets then return end
		local tween = TweenService:Create(
			binding.frame,
			TweenInfo.new(step, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Rotation = targets[index] }
		)
		binding.tween = tween
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				play(index + 1)
			end
		end)
		tween:Play()
	end
	play(1)
end

local function isHovered(binding, objectsAtMouse)
	for _, guiObject in ipairs(objectsAtMouse) do
		if guiObject == binding.frame or guiObject:IsDescendantOf(binding.frame) then
			return true
		end
	end
	return false
end

local function refreshHover()
	if #bindings == 0 then return end
	if not lastMousePosition then
		for _, binding in ipairs(bindings) do
			stopSway(binding)
		end
		return
	end
	local objectsAtMouse = playerGui:GetGuiObjectsAtPosition(lastMousePosition.X, lastMousePosition.Y)
	for _, binding in ipairs(bindings) do
		if isHovered(binding, objectsAtMouse) then
			startSway(binding)
		else
			stopSway(binding)
		end
	end
end

local function disconnectAll()
	for _, binding in ipairs(bindings) do
		for _, connection in ipairs(binding.connections) do
			connection:Disconnect()
		end
		binding.swaying = false
		binding.wiggleToken = nil
		cancelTween(binding)
		binding.frame.Rotation = binding.restRotation
	end
	table.clear(bindings)
	boundTopFrames = nil
end

local function findButton(frame, path, framePath)
	local node = frame
	for _, name in ipairs(path) do
		node = waitForChild(node, name, framePath .. "." .. name)
		if not node then return nil end
	end
	return node:IsA("GuiButton") and node or nil
end

local function bindFrame(overall, spec)
	local framePath = "PlayerGui.TopFrames.OverallTopFrame." .. spec.name
	local frame = waitForChild(overall, spec.name, framePath)
	if not frame or not frame:IsA("GuiObject") then return end
	local button = findButton(frame, spec.button, framePath)

	local binding = {
		frame = frame,
		restRotation = frame.Rotation,
		connections = {},
		swaying = false,
		swayClock = 0,
		tween = nil,
		wiggleToken = nil,
	}
	table.insert(bindings, binding)

	if button then
		-- One wiggle per tap. Uses the input type, not device capability flags.
		table.insert(binding.connections, button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				playTouchWiggle(binding)
			end
		end))
	end
end

local function bindTopFrames(topFrames)
	topFrames = topFrames or playerGui:FindFirstChild("TopFrames")
	if topFrames == boundTopFrames then return end
	disconnectAll()
	if not topFrames then return end -- ChildAdded below binds it when it arrives
	boundTopFrames = topFrames

	local overall = waitForChild(topFrames, "OverallTopFrame", "PlayerGui.TopFrames.OverallTopFrame")
	if not overall or boundTopFrames ~= topFrames then return end
	for _, spec in ipairs(FRAME_SPECS) do
		bindFrame(overall, spec)
	end
	refreshHover()
end

-- Track the mouse in GUI space. InputObject.Position for mouse movement already excludes the
-- top-bar inset, matching GetGuiObjectsAtPosition.
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		lastMousePosition = Vector2.new(input.Position.X, input.Position.Y)
		refreshHover()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		-- Touch never hovers.
		lastMousePosition = nil
		refreshHover()
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	lastMousePosition = nil
	refreshHover()
end)

-- Advance every swaying frame once per rendered frame.
RunService.RenderStepped:Connect(function(deltaTime)
	local period = Config.SwayHalfPeriod * 2
	for _, binding in ipairs(bindings) do
		if binding.swaying then
			binding.swayClock += deltaTime
			local phase = (binding.swayClock / period) * 2 * math.pi
			binding.frame.Rotation = binding.restRotation + Config.SwayAngle * math.sin(phase)
		end
	end
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TopFrames" then
		task.defer(bindTopFrames, child)
	end
end)

task.spawn(bindTopFrames, playerGui:FindFirstChild("TopFrames"))
