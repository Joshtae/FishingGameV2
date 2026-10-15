-- TopNavHoverClient v3: hover sway for the top nav (FishingFrame, PlotFrame, ShopFrame).
-- Only animates each frame's Rotation; never changes navigation bindings or authored layout.
--
-- Hover comes from MouseEnter/MouseLeave on each frame and its button (no screen-coordinate
-- math). A fallback stops a sway if a MouseLeave is missed. Touch taps play one wiggle.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local VERSION = "v3"

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

local function lastInputWasTouch()
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

local function cancelTween(binding)
	if binding.tween then
		binding.tween:Cancel()
		binding.tween = nil
	end
end

local function startSway(binding)
	if binding.swaying then return end
	cancelTween(binding)
	binding.wiggleToken = nil
	binding.swaying = true
	-- Begin the sine wave at the phase matching the current rotation, so there is no jump.
	local offset = math.clamp((binding.frame.Rotation - binding.restRotation) / Config.SwayAngle, -1, 1)
	binding.swayClock = math.asin(offset) / (2 * math.pi) * (Config.SwayHalfPeriod * 2)
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

local function clearHover(binding)
	table.clear(binding.inside)
	stopSway(binding)
end

local function evaluate(binding)
	if next(binding.inside) ~= nil then
		startSway(binding)
	else
		stopSway(binding)
	end
end

local function playTouchWiggle(binding)
	table.clear(binding.inside)
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

-- Padding (pixels) around a frame's unrotated bounds, so the rotated corners still count.
local FALLBACK_PADDING = 16

-- True if the point is on or near the frame. Uses plain bounds (AbsolutePosition and
-- AbsoluteSize ignore Rotation) and tries the point with and without the top-bar inset, so a
-- coordinate-space mismatch can only keep a sway running a little longer, never cancel it.
local function frameUnderPoint(binding, x, y)
	local inset = GuiService:GetGuiInset()
	local position = binding.frame.AbsolutePosition
	local size = binding.frame.AbsoluteSize
	local minX, minY = position.X - FALLBACK_PADDING, position.Y - FALLBACK_PADDING
	local maxX, maxY = position.X + size.X + FALLBACK_PADDING, position.Y + size.Y + FALLBACK_PADDING
	for _, point in ipairs({ Vector2.new(x, y), Vector2.new(x - inset.X, y - inset.Y), Vector2.new(x + inset.X, y + inset.Y) }) do
		if point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY then
			return true
		end
	end
	return false
end

local function watchHover(binding, target, key)
	table.insert(binding.connections, target.MouseEnter:Connect(function()
		if lastInputWasTouch() then return end -- taps also fire MouseEnter; touch never hovers
		binding.inside[key] = true
		evaluate(binding)
	end))
	table.insert(binding.connections, target.MouseLeave:Connect(function()
		binding.inside[key] = nil
		task.defer(evaluate, binding)
	end))
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
	if not frame or not frame:IsA("GuiObject") then return false end
	local button = findButton(frame, spec.button, framePath)

	local binding = {
		frame = frame,
		restRotation = frame.Rotation,
		connections = {},
		inside = {},
		swaying = false,
		swayClock = 0,
		tween = nil,
		wiggleToken = nil,
	}
	table.insert(bindings, binding)

	watchHover(binding, frame, "frame")
	if button then
		watchHover(binding, button, "button")
		table.insert(binding.connections, button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				playTouchWiggle(binding)
			end
		end))
	end
	return true
end

local function bindTopFrames(topFrames)
	topFrames = topFrames or playerGui:FindFirstChild("TopFrames")
	if topFrames == boundTopFrames then return end
	disconnectAll()
	if not topFrames then return end -- ChildAdded binds it when it arrives
	boundTopFrames = topFrames

	local overall = waitForChild(topFrames, "OverallTopFrame", "PlayerGui.TopFrames.OverallTopFrame")
	if not overall or boundTopFrames ~= topFrames then return end
	local count = 0
	for _, spec in ipairs(FRAME_SPECS) do
		if bindFrame(overall, spec) then
			count += 1
		end
	end
	-- One line so it is easy to confirm in Output which version is running.
	print(string.format("[FishingSystemV2.TopNavHover] %s bound %d/3 top nav frames", VERSION, count))
end

-- Fallback: if a MouseLeave was missed, stop the sway once the mouse is clearly elsewhere.
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	for _, binding in ipairs(bindings) do
		if binding.swaying and not frameUnderPoint(binding, input.Position.X, input.Position.Y) then
			clearHover(binding)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		for _, binding in ipairs(bindings) do
			if binding.swaying then
				clearHover(binding)
			end
		end
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	for _, binding in ipairs(bindings) do
		clearHover(binding)
	end
end)

-- Advance every swaying frame once per rendered frame.
RunService.RenderStepped:Connect(function(deltaTime)
	local period = Config.SwayHalfPeriod * 2
	for _, binding in ipairs(bindings) do
		if binding.swaying then
			binding.swayClock += deltaTime
			binding.frame.Rotation = binding.restRotation
				+ Config.SwayAngle * math.sin((binding.swayClock / period) * 2 * math.pi)
		end
	end
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TopFrames" then
		task.defer(bindTopFrames, child)
	end
end)

task.spawn(bindTopFrames, playerGui:FindFirstChild("TopFrames"))
