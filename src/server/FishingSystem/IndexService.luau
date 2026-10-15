--[[
	Server-authoritative Phase 6 Index service.
	API: Discover(player, id), Claim(player, id), ClaimAll(player),
	GetClaimedCount(player), GetIndexLuck(player), GetSnapshot(player),
	RefreshPlayer(player), Start(characterAddedSignal).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent
local Data = require(root.Data)
local Currency = require(root.Currency)
local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Characters = require(shared:WaitForChild("Characters"))
local Config = require(shared:WaitForChild("IndexConfig"))
local Remotes = shared:WaitForChild("Remotes")

local IndexService = {}
local started = false
local activeById = {}
local activeList = {}
local releasing = {}
local claimLocks = {}
local claimCalls = {}
local lastSnapshot = {}
local pendingSnapshot = {}
local pendingReady = {}
local warnedUnknownIds = {}

for _, definition in ipairs(Characters.GetActive()) do
	activeById[definition.id] = definition
	table.insert(activeList, definition)
end

local function validId(id)
	return type(id) == "string" and #id >= 1 and #id <= Config.MaxIdLength
end

local function loadedData(player)
	if releasing[player] or not Data.IsLoaded(player) then return nil end
	local data = Data.Get(player)
	if type(data) ~= "table" or type(data.Index) ~= "table" then return nil end
	if type(data.Index.Discovered) ~= "table" or type(data.Index.Claimed) ~= "table" then return nil end
	return data
end

local function warnUnknownSavedIds(data)
	local index = data.Index
	for _, dictionary in ipairs({index.Discovered, index.Claimed}) do
		for id in pairs(dictionary) do
			if not activeById[id] and not warnedUnknownIds[id] then
				warnedUnknownIds[id] = true
				warn("[FishingSystem.IndexService] Keeping unknown saved Index id " .. tostring(id) .. "; it is ignored until active.")
			end
		end
	end
end

local function activeCounts(data)
	local discovered, claimed = 0, 0
	for _, definition in ipairs(activeList) do
		local id = definition.id
		if data.Index.Discovered[id] then discovered += 1 end
		if data.Index.Claimed[id] then claimed += 1 end
	end
	return discovered, claimed
end

local function setIndexLuckAttribute(player, data)
	local _, claimed = activeCounts(data)
	player:SetAttribute("IndexLuck", 1 + Config.LuckPerClaim * claimed)
end

local function fireUpdate(player, kind, payload)
	if player.Parent == Players then
		Remotes.IndexUpdate:FireClient(player, kind, payload)
	end
end

local function sendSnapshotNow(player)
	pendingSnapshot[player] = nil
	local snapshot = IndexService.GetSnapshot(player)
	if not snapshot then return false end
	lastSnapshot[player] = os.clock()
	fireUpdate(player, "snapshot", snapshot)
	return true
end

local function sendSnapshot(player)
	if not loadedData(player) then
		pendingReady[player] = true
		return false
	end
	local interval = 1 / Config.SnapshotMaxPerSecond
	local elapsed = os.clock() - (lastSnapshot[player] or -math.huge)
	if elapsed >= interval then
		return sendSnapshotNow(player)
	end
	if not pendingSnapshot[player] then
		pendingSnapshot[player] = true
		task.delay(interval - elapsed, function()
			if pendingSnapshot[player] and player.Parent == Players then
				sendSnapshotNow(player)
			end
		end)
	end
	return true
end

local function rateAllowed(player)
	local stamp = os.clock()
	local calls = claimCalls[player] or {}
	claimCalls[player] = calls
	for index = #calls, 1, -1 do
		if stamp - calls[index] >= 1 then table.remove(calls, index) end
	end
	if #calls >= Config.ClaimRateLimitPerSecond then return false end
	table.insert(calls, stamp)
	return true
end

local function repairOwnedActiveCharacters(player, data)
	local repaired = 0
	for _, entry in ipairs(data.Characters or {}) do
		local id = type(entry) == "table" and entry.id
		if activeById[id] and not data.Index.Discovered[id] then
			data.Index.Discovered[id] = true
			repaired += 1
		end
	end
	if repaired > 0 then
		print(("[FishingSystem.IndexService] Silently repaired %d discovered Index entr%s for UserId %d")
			:format(repaired, repaired == 1 and "y" or "ies", player.UserId))
	end
	return repaired
end

function IndexService.GetClaimedCount(player)
	local data = loadedData(player)
	if not data then return 0 end
	local _, claimed = activeCounts(data)
	return claimed
end

function IndexService.GetIndexLuck(player)
	local data = loadedData(player)
	if not data then return 1 end
	local _, claimed = activeCounts(data)
	return 1 + Config.LuckPerClaim * claimed
end

function IndexService.GetSnapshot(player)
	local data = loadedData(player)
	if not data then return nil end
	warnUnknownSavedIds(data)
	local discovered, claimed = {}, {}
	for _, definition in ipairs(activeList) do
		local id = definition.id
		if data.Index.Discovered[id] then table.insert(discovered, id) end
		if data.Index.Claimed[id] then table.insert(claimed, id) end
	end
	return {
		discovered = discovered,
		claimed = claimed,
		indexLuck = IndexService.GetIndexLuck(player),
		discoveredCount = #discovered,
		claimedCount = #claimed,
		total = #activeList,
	}
end

function IndexService.Discover(player, id)
	local data = loadedData(player)
	local definition = validId(id) and activeById[id] or nil
	if not data or not definition or data.Index.Discovered[id] then return false end
	data.Index.Discovered[id] = true
	local gems = Config.IndexDiscoveryGems[definition.rarity] or 0
	if gems > 0 then Currency.AddGems(player, gems) end
	fireUpdate(player, "discovered", {id = id})
	return true
end

function IndexService.Claim(player, id)
	if not validId(id) or not activeById[id] or not rateAllowed(player) or claimLocks[player] then return false end
	local data = loadedData(player)
	if not data or not data.Index.Discovered[id] or data.Index.Claimed[id] then return false end
	claimLocks[player] = true
	data.Index.Claimed[id] = true
	setIndexLuckAttribute(player, data)
	claimLocks[player] = nil
	fireUpdate(player, "claimed", {id = id, indexLuck = IndexService.GetIndexLuck(player)})
	return true
end

function IndexService.ClaimAll(player)
	if not rateAllowed(player) or claimLocks[player] then return 0 end
	local data = loadedData(player)
	if not data then return 0 end
	claimLocks[player] = true
	local claimedIds = {}
	for _, definition in ipairs(activeList) do
		local id = definition.id
		if data.Index.Discovered[id] and not data.Index.Claimed[id] then
			data.Index.Claimed[id] = true
			table.insert(claimedIds, id)
		end
	end
	setIndexLuckAttribute(player, data)
	claimLocks[player] = nil
	if #claimedIds > 0 then
		fireUpdate(player, "claimed", {ids = claimedIds, indexLuck = IndexService.GetIndexLuck(player)})
	end
	return #claimedIds
end

-- Server-side resync used after authoritative state changes, including Studio-only reset commands.
function IndexService.RefreshPlayer(player)
	local data = loadedData(player)
	if not data then return false end
	setIndexLuckAttribute(player, data)
	return sendSnapshot(player)
end

function IndexService.Start(characterAddedSignal)
	if started then return end
	started = true

	characterAddedSignal:Connect(function(player, entry)
		if releasing[player] or not Data.IsLoaded(player) or type(entry) ~= "table" then return end
		IndexService.Discover(player, entry.id)
	end)

	Data.Loaded:Connect(function(player, data)
		if releasing[player] then return end
		repairOwnedActiveCharacters(player, data)
		setIndexLuckAttribute(player, data)
		pendingReady[player] = nil
		sendSnapshot(player)
	end)
	Data.Releasing:Connect(function(player)
		releasing[player] = true
		claimLocks[player], claimCalls[player], lastSnapshot[player], pendingSnapshot[player], pendingReady[player] = nil, nil, nil, nil, nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		releasing[player], claimLocks[player], claimCalls[player], lastSnapshot[player], pendingSnapshot[player], pendingReady[player] = nil, nil, nil, nil, nil, nil
	end)

	Remotes.ClaimIndex.OnServerEvent:Connect(function(player, id)
		IndexService.Claim(player, id)
	end)
	Remotes.ClaimAllIndex.OnServerEvent:Connect(function(player)
		IndexService.ClaimAll(player)
	end)
	Remotes.IndexReady.OnServerEvent:Connect(function(player)
		sendSnapshot(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		local data = loadedData(player)
		if data then
			repairOwnedActiveCharacters(player, data)
			setIndexLuckAttribute(player, data)
			sendSnapshot(player)
		end
	end
end

return IndexService
