--[[
	Server-authoritative rebirth action.
	Start() registers the Rebirth remote and load/release listeners once.
	HandleRequest(player, ...) validates and performs one rebirth; remote arguments are ignored.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent
local Data = require(root.Data)
local Currency = require(root.Currency)
local Inventory = require(root.Inventory)
local Plots = require(root.Plots)
local Podiums = require(root.Podiums)
local Rebirths = require(ReplicatedStorage.FishingSystemV2.Rebirths)
local Remotes = ReplicatedStorage.FishingSystemV2.Remotes

local RebirthService = {}
local started = false
local busy = {}
local lastRequest = {}

local function clearPlayerState(player)
	busy[player] = nil
	lastRequest[player] = nil
end

local function reject(player, message)
	Remotes.RebirthMessage:FireClient(player, message, "Rejected")
	return false, message
end

local function refreshPodiums(player)
	local plot = Plots.Get(player)
	if not plot then return end
	for podiumId in pairs(Plots.GetPodiums(plot)) do
		Podiums.RefreshPodium(player, podiumId)
	end
end

-- Validates and executes a rebirth with no client-controlled values.
function RebirthService.HandleRequest(player, ...)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "Invalid player" end
	if not Data.IsLoaded(player) then return reject(player, "Data not loaded") end
	if busy[player] then return false, "Busy" end

	local now = os.clock()
	local interval = 1 / Rebirths.RateLimitPerSecond
	if now - (lastRequest[player] or -math.huge) < interval then
		return false, "Rate limited"
	end
	lastRequest[player] = now

	local data = Data.Get(player)
	local level = data and data.Rebirths
	local cost = Rebirths.GetCost(level)
	if cost == nil then return reject(player, "Max rebirths reached") end
	if Currency.GetCash(player) < cost then return reject(player, "Not enough Cash") end

	busy[player] = true
	Currency.SetCash(player, 0)
	for _, podium in pairs(data.Plot.Podiums) do
		if type(podium) == "table" then podium.storedCash = 0 end
	end
	if not Rebirths.KeepsFoodOnRebirth then data.Food = 0 end
	data.Rebirths = level + 1
	player:SetAttribute("Rebirths", data.Rebirths)
	busy[player] = nil

	Currency.Refresh(player)
	Inventory.PutAway(player)
	refreshPodiums(player)

	local multiplier = Rebirths.FormatMult(Rebirths.GetMult(data.Rebirths) or 1)
	Remotes.RebirthMessage:FireClient(player, "Rebirth complete! x" .. multiplier .. " Cash", "Success")
	return true, "Success"
end

function RebirthService.Start()
	if started then return end
	started = true
	Remotes.Rebirth.OnServerEvent:Connect(RebirthService.HandleRequest)
	Data.Loaded:Connect(function(player, data)
		player:SetAttribute("Rebirths", data.Rebirths)
	end)
	Data.Releasing:Connect(clearPlayerState)
	Players.PlayerRemoving:Connect(clearPlayerState)
	for _, player in ipairs(Players:GetPlayers()) do
		local data = Data.Get(player)
		if data then player:SetAttribute("Rebirths", data.Rebirths) end
	end
end

return RebirthService
