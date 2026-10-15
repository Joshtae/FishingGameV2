--[[
	Client presentation for the Phase 5 rebirth window.
	Only opens the approved PlayerGui RebirthFrameButton and sends the no-argument Rebirth remote.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Rebirths = require(shared:WaitForChild("Rebirths"))
local NumberFormat = require(shared:WaitForChild("NumberFormat"))
local remotes = shared:WaitForChild("Remotes")

local gui = playerGui:WaitForChild("FishingSystemV2Rebirth")
local window = gui:WaitForChild("RebirthWindow")
local header = window:WaitForChild("Header")
local closeButton = window:WaitForChild("CloseButton")
local rebirthsLabel = window:WaitForChild("RebirthsLabel")
local multiplierLabel = window:WaitForChild("MultiplierLabel")
local noteLabel = window:WaitForChild("NoteLabel")
local statusLabel = window:WaitForChild("StatusLabel")
local rebirthButton = window:WaitForChild("RebirthButton")
local costLabel = window:WaitForChild("CostLabel")
local openButton

local state = {
	open = false,
	waiting = false,
	confirmUntil = 0,
	confirmToken = 0,
	text = {},
	openButtonConnection = nil,
	boundLeftFrames = nil,
}

local function setText(item, text)
	if state.text[item] == text then return end
	state.text[item] = text
	item.Text = text
end

local function currentRebirths()
	local value = player:GetAttribute("Rebirths")
	if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > Rebirths.MaxRebirths then return 0 end
	return value
end

local function currentCash()
	local value = player:GetAttribute("Cash")
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then return 0 end
	return value
end

local function render()
	if not state.open then return end
	local level = currentRebirths()
	local cost = Rebirths.GetCost(level)
	local multiplier = Rebirths.GetMult(level) or 1
	setText(header, "REBIRTH")
	setText(rebirthsLabel, "Rebirths: " .. level .. " / " .. Rebirths.MaxRebirths)
	setText(multiplierLabel, "Cash: x" .. Rebirths.FormatMult(multiplier))
	setText(noteLabel, "Resets Cash, Food, and unclaimed podium cash. Keeps characters and placements.")

	if cost == nil then
		setText(costLabel, "Maximum rebirths reached")
		setText(rebirthButton, "MAX REBIRTHS")
		rebirthButton.Active = false
		return
	end

	setText(costLabel, "Cost: $" .. NumberFormat.Format(cost))
	local affordable = currentCash() >= cost
	if state.waiting then
		setText(rebirthButton, "REBIRTHING...")
		rebirthButton.Active = false
	elseif state.confirmUntil > os.clock() then
		setText(rebirthButton, "CONFIRM REBIRTH")
		rebirthButton.Active = true
	elseif affordable then
		setText(rebirthButton, "REBIRTH")
		rebirthButton.Active = true
	else
		setText(rebirthButton, "REBIRTH")
		rebirthButton.Active = false
	end
end

local function setOpen(open)
	state.open = open
	if not open then
		state.waiting = false
		state.confirmUntil = 0
		state.confirmToken += 1
		setText(statusLabel, "")
	end
	window.Visible = open
	if open then
		render()
	end
end

local function findOpenButton(leftFrames)
	local overall = leftFrames and leftFrames:FindFirstChild("OverallFrame")
	local rebirthFrame = overall and overall:FindFirstChild("RebirthFrame")
	return rebirthFrame and rebirthFrame:FindFirstChild("RebirthFrameButton", true)
end

local function bindOpenButton()
	local leftFrames = playerGui:FindFirstChild("LeftFramesGui")
	local button = findOpenButton(leftFrames)
	if leftFrames == state.boundLeftFrames and button == openButton then return end

	if state.openButtonConnection then state.openButtonConnection:Disconnect() end
	state.openButtonConnection = nil
	state.boundLeftFrames = leftFrames
	openButton = button

	if openButton then
		state.openButtonConnection = openButton.Activated:Connect(function()
			setOpen(not state.open)
		end)
	end
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "LeftFramesGui" then task.defer(bindOpenButton) end
end)

bindOpenButton()

closeButton.Activated:Connect(function()
	setOpen(false)
end)

rebirthButton.Activated:Connect(function()
	if not state.open or state.waiting then return end
	local level = currentRebirths()
	local cost = Rebirths.GetCost(level)
	if not cost then return end
	if currentCash() < cost then
		setText(statusLabel, "Not enough Cash")
		return
	end
	if state.confirmUntil <= os.clock() then
		state.confirmUntil = os.clock() + Rebirths.ConfirmSeconds
		state.confirmToken += 1
		local token = state.confirmToken
		setText(statusLabel, "Press REBIRTH again to confirm.")
		render()
		task.delay(Rebirths.ConfirmSeconds, function()
			if state.open and state.confirmToken == token and state.confirmUntil <= os.clock() then
				state.confirmUntil = 0
				setText(statusLabel, "")
				render()
			end
		end)
		return
	end
	state.waiting = true
	state.confirmUntil = 0
	setText(statusLabel, "")
	render()
	remotes.Rebirth:FireServer()
	local token = state.confirmToken
	task.delay(2, function()
		if state.open and state.waiting and state.confirmToken == token then
			state.waiting = false
			setText(statusLabel, "No response. Please try again.")
			render()
		end
	end)
end)

remotes.RebirthMessage.OnClientEvent:Connect(function(message, kind)
	if type(message) ~= "string" then return end
	state.waiting = false
	state.confirmUntil = 0
	state.confirmToken += 1
	setText(statusLabel, message)
	render()
end)

player:GetAttributeChangedSignal("Rebirths"):Connect(render)
player:GetAttributeChangedSignal("Cash"):Connect(render)
setOpen(false)
