--[[
	Display-only ClaimPart cash labels for R3. Start() clones the approved template once per
	ClaimPart and refreshes labels from server-owned profile data; it never collects or writes data.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = script.Parent
local ClaimButtons = require(root.ClaimButtons)
local Data = require(root.Data)
local Plots = require(root.Plots)
local NumberFormat = require(ReplicatedStorage.FishingSystemV2.NumberFormat)
local WorldConfig = require(ReplicatedStorage.FishingSystemV2.WorldConfig)
local template = ReplicatedStorage.FishingSystemV2.ClaimDisplayTemplate

local ClaimDisplayService = {}
local started = false
local displayName = "FishingSystemV2ClaimDisplay"

local function claimParts(button)
	local result = {}
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "ClaimPart" then
			table.insert(result, descendant)
		end
	end
	return result
end

local function ensureDisplay(claimPart)
	local display = claimPart:FindFirstChild(displayName)
	if not display then
		display = template:Clone()
		display.Name = displayName
		display.Parent = claimPart
	end
	return display
end

local function setDisplay(display, visible, text)
	display.Enabled = visible
	local label = display:FindFirstChild("Amount")
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
	end
end

local function refreshPlot(plot)
	local ownerUserId = Plots.GetOwnerUserId(plot)
	local player = ownerUserId and Players:GetPlayerByUserId(ownerUserId)
	local data = player and Data.Get(player)
	for buttonName, podiumId in pairs(ClaimButtons.CLAIM_BUTTON_TO_PODIUM) do
		local button = plot:FindFirstChild(buttonName, true)
		if button then
			local state = data and data.Plot and data.Plot.Podiums and data.Plot.Podiums[podiumId]
			local visible = state ~= nil and state.unlocked == true
			local text = "$" .. NumberFormat.Format(visible and state.storedCash or 0)
			for _, claimPart in ipairs(claimParts(button)) do
				setDisplay(ensureDisplay(claimPart), visible, text)
			end
		end
	end
end

local function refreshAll()
	for index = 1, 8 do
		local plot = Workspace:FindFirstChild("Plot" .. index)
		if plot and plot:IsA("Model") then
			refreshPlot(plot)
		end
	end
end

-- Creates and updates display-only labels; collection remains solely in ClaimButtons.
function ClaimDisplayService.Start()
	if started then return end
	started = true
	refreshAll()
	task.spawn(function()
		while started do
			refreshAll()
			task.wait(WorldConfig.ClaimDisplayRefreshSeconds)
		end
	end)
end

return ClaimDisplayService
