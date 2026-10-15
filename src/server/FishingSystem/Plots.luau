--[[
	Plot ownership API for Phase 1.
	Public API:
	- Plots.Get(player) -> Model?
	- Plots.GetOwnerUserId(plot) -> number?
	- Plots.GetPodiums(plot) -> {[string]: Model}
	- Plots.ClearPlot(plot) -> ()
	Signals:
	- Plots.Assigned:Connect(function(player, plot) end)
	- Plots.Releasing:Connect(function(player, plot) end)
	Internal lifecycle helpers used only by Bootstrap:
	- Plots.Assign(player) -> Model?
	- Plots.PrepareRelease(player) -> Model?
	- Plots.FinishRelease(player, plot) -> ()
]]
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Signal = require(script.Parent.Signal)

local Plots = {}
Plots.PlacedCharacterTag = "PlacedCharacter"
Plots.Assigned = Signal.new()
Plots.Releasing = Signal.new()

local assignedByPlayer = {}

local PODIUM_IDS = {
	"Podium1", "Podium2", "Podium3", "Podium4",
	"Podium5", "Podium6", "Podium7", "Podium8",
	"AdditionalPodium1", "AdditionalPodium2",
}

local function getPlotByIndex(index)
	local plot = Workspace:FindFirstChild("Plot" .. index)
	if plot and plot:IsA("Model") then
		return plot
	end
	return nil
end

-- Returns the plot currently assigned to player, or nil.
function Plots.Get(player)
	local plot = assignedByPlayer[player]
	if plot and plot.Parent then
		return plot
	end

	for index = 1, 8 do
		local candidate = getPlotByIndex(index)
		if candidate and candidate:GetAttribute("OwnerUserId") == player.UserId then
			assignedByPlayer[player] = candidate
			return candidate
		end
	end
	return nil
end

-- Returns the numeric OwnerUserId attribute for a plot, or nil when free.
function Plots.GetOwnerUserId(plot)
	local ownerUserId = plot:GetAttribute("OwnerUserId")
	if type(ownerUserId) == "number" then
		return ownerUserId
	end
	return nil
end

-- Returns every recognized podium model in a plot, keyed by its stable model name.
function Plots.GetPodiums(plot)
	local podiums = {}
	for _, podiumId in ipairs(PODIUM_IDS) do
		local podium = plot:FindFirstChild(podiumId)
		if podium and podium:IsA("Model") then
			podiums[podiumId] = podium
		end
	end
	return podiums
end

-- Removes only CollectionService-tagged PlacedCharacter instances inside plot.
-- This function never edits podiums, other plot assets, or persistent data.
function Plots.ClearPlot(plot)
	for _, instance in ipairs(CollectionService:GetTagged(Plots.PlacedCharacterTag)) do
		if instance ~= plot and instance:IsDescendantOf(plot) then
			instance:Destroy()
		end
	end
end

-- Claims the first free plot in Plot1..Plot8 order without yielding.
function Plots.Assign(player)
	local existing = Plots.Get(player)
	if existing then
		return existing
	end

	local claimedPlot = nil
	for index = 1, 8 do
		local plot = getPlotByIndex(index)
		if plot and Plots.GetOwnerUserId(plot) == nil then
			plot:SetAttribute("OwnerUserId", player.UserId)
			claimedPlot = plot
			break
		end
	end

	if claimedPlot then
		assignedByPlayer[player] = claimedPlot
		Plots.Assigned:Fire(player, claimedPlot)
	else
		warn(("[FishingSystem.Plots] No free plot available for UserId %d"):format(player.UserId))
	end

	return claimedPlot
end

-- Fires Plots.Releasing before any placed character is removed.
function Plots.PrepareRelease(player)
	local plot = Plots.Get(player)
	if plot then
		Plots.Releasing:Fire(player, plot)
	end
	return plot
end

-- Clears tagged placed characters, then clears ownership so the plot becomes claimable.
function Plots.FinishRelease(player, plot)
	if not plot then
		return
	end
	Plots.ClearPlot(plot)
	plot:SetAttribute("OwnerUserId", nil)
	assignedByPlayer[player] = nil
end

return Plots
