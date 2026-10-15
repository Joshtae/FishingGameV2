-- TopNavHoverClient v4: hover sway for the top nav (FishingFrame, PlotFrame, ShopFrame).
-- Only animates each frame's Rotation; never changes navigation bindings or authored layout.
--
-- Hover is read every frame from the button's own GuiState (Hover/Press), which is the same
-- engine state that shows the hand cursor. No MouseEnter events, no screen coordinates.
-- Touch taps play one wiggle.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local VERSION = "v4"

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

-- DEV_ONLY_BEGIN TopNavHoverDebug
-- Temporary Studio-only readout to diagnose the hover sway. Remove once R7 passes.
local DEBUG = RunService:IsStudio()
local function debugLog(message)
	if DEBUG then
		print("[FishingSystemV2.TopNavHover][debug] " .. message)
	end
end
-- DEV_ONLY_END TopNavHoverDebug

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

local function startSway(binding)
	if binding.swaying then return end
	cancelTween(binding)
	binding.wiggleToken = nil
	binding.swaying = true
	-- Begin the sine wave at the phase matching the current rotation, so there is no jump.
	local offset = math.clamp((binding.frame.Rotation - binding.restRotation) / Config.SwayAngle, -1, 1)
	binding.swayClock = math.asin(offset) / (2 * math.pi) * (Config.SwayHalfPeriod * 2)
	-- DEV_ONLY_BEGIN TopNavHoverDebug
	debugLog(binding.frame.Name .. " hover start")
	local frame = binding.frame
	task.delay(0.5, function()
		if binding.swaying then
			debugLog(string.format("%s Rotation after 0.5 s = %.2f (rest %.2f)", frame.Name, frame.Rotation, binding.restRotation))
		end
	end)
	-- DEV_ONLY_END TopNavHoverDebug
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
	-- DEV_ONLY_BEGIN TopNavHoverDebug
	debugLog(binding.frame.Name .. " hover end")
	-- DEV_ONLY_END TopNavHoverDebug
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

local function isHovered(binding)
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		return false -- touch never hovers; taps play the wiggle
	end
	local state = binding.button.GuiState
	return state == Enum.GuiState.Hover or state == Enum.GuiState.Press
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
	if not node:IsA("GuiButton") then
		warnMissing(framePath .. " (button is not a GuiButton)")
		return nil
	end
	return node
end

local function bindFrame(overall, spec)
	local framePath = "PlayerGui.TopFrames.OverallTopFrame." .. spec.name
	local frame = waitForChild(overall, spec.name, framePath)
	if not frame or not frame:IsA("GuiObject") then return false end
	local button = findButton(frame, spec.button, framePath)
	if not button then return false end

	local binding = {
		frame = frame,
		button = button,
		restRotation = frame.Rotation,
		connections = {},
		swaying = false,
		swayClock = 0,
		tween = nil,
		wiggleToken = nil,
	}
	table.insert(bindings, binding)

	table.insert(binding.connections, button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			playTouchWiggle(binding)
		end
	end))
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
	print(string.format("[FishingSystemV2.TopNavHover] %s bound %d/3 top nav frames", VERSION, count))
end

UserInputService.WindowFocusReleased:Connect(function()
	for _, binding in ipairs(bindings) do
		stopSway(binding)
	end
end)

-- DEV_ONLY_BEGIN TopNavHoverDebug
local lastLoggedState = {}
-- DEV_ONLY_END TopNavHoverDebug

-- Every rendered frame: read hover state, then advance the sway.
RunService.RenderStepped:Connect(function(deltaTime)
	local period = Config.SwayHalfPeriod * 2
	for _, binding in ipairs(bindings) do
		-- DEV_ONLY_BEGIN TopNavHoverDebug
		local guiState = binding.button.GuiState
		if lastLoggedState[binding] ~= guiState then
			lastLoggedState[binding] = guiState
			debugLog(binding.frame.Name .. " button GuiState = " .. guiState.Name)
		end
		-- DEV_ONLY_END TopNavHoverDebug

		if isHovered(binding) then
			startSway(binding)
		else
			stopSway(binding)
		end

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
