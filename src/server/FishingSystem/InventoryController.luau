--[[
	Server-authoritative Phase 4 inventory remote controller.
	Start() wires validated remotes and inventory replication.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = script.Parent
local Data = require(root.Data)
local Inventory = require(root.Inventory)
local FishingSessions = require(root.FishingSessions)
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local Remotes = ReplicatedStorage.FishingSystemV2.Remotes

local InventoryController = {}
local started = false
local lastSnapshot, pendingSnapshot, rateWindows = {}, {}, {}

local function validUid(uid)
	return type(uid) == "string" and uid ~= "" and #uid <= 200
end

local function allowed(player, key)
	local stamp = os.clock()
	local bucket = rateWindows[player] or {}
	rateWindows[player] = bucket
	local calls = bucket[key] or {}
	bucket[key] = calls
	for index = #calls, 1, -1 do
		if stamp - calls[index] > 1 then table.remove(calls, index) end
	end
	if #calls >= Config.RemoteRateLimit then return false end
	table.insert(calls, stamp)
	return true
end

local function snapshotFor(player)
	local data = Data.Get(player)
	if not data then return nil end
	local characters = {}
	for _, entry in ipairs(data.Characters) do
		if type(entry) == "table" and not Inventory.IsPlaced(player, entry.uid) then
			local copy = {uid = entry.uid, id = entry.id}
			if entry.mutation then copy.mutation = entry.mutation end
			table.insert(characters, copy)
		end
	end
	local hotbar = {}
	for slot = 1, Config.HotbarSlots do
		local uid = data.Hotbar and data.Hotbar[tostring(slot)]
		if type(uid) == "string" then hotbar[tostring(slot)] = uid end
	end
	return {
		characters = characters,
		hotbar = hotbar,
		used = Inventory.GetUsedSlots(player),
		capacity = Inventory.GetCapacity(player),
	}
end

local function sendNow(player)
	pendingSnapshot[player] = nil
	if not player.Parent then return end
	local snapshot = snapshotFor(player)
	if not snapshot then return end
	lastSnapshot[player] = os.clock()
	Remotes.InventoryUpdate:FireClient(player, snapshot)
	Remotes.ActiveSlotUpdate:FireClient(player, Inventory.GetActiveSlot(player) or 0)
end

local function queueSnapshot(player)
	if not Data.IsLoaded(player) then return end
	local stamp = os.clock()
	local elapsed = stamp - (lastSnapshot[player] or -math.huge)
	if elapsed >= .1 then
		sendNow(player)
	elseif not pendingSnapshot[player] then
		pendingSnapshot[player] = true
		task.delay(.1 - elapsed, function()
			if pendingSnapshot[player] and player.Parent then sendNow(player) end
		end)
	end
end

local function message(player, text)
	Remotes.InventoryMessage:FireClient(player, text)
end

function InventoryController.Start()
	if started then return end
	started = true

	Remotes.EquipSlot.OnServerEvent:Connect(function(player, slot)
		if not allowed(player, "equip") then return end
		if type(slot) ~= "number" or slot ~= slot or slot == math.huge or slot == -math.huge or slot % 1 ~= 0 then return end
		if FishingSessions.GetSession(player) then message(player, "Finish fishing first"); return end
		Inventory.EquipSlot(player, slot)
	end)

	Remotes.SetHotbarSlot.OnServerEvent:Connect(function(player, uid)
		if not allowed(player, "set") or not validUid(uid) then return end
		local ok, reason = Inventory.SetHotbarSlot(player, uid)
		if not ok and reason == "Hotbar full" then message(player, "Hotbar full") end
	end)

	Remotes.ClearHotbarSlot.OnServerEvent:Connect(function(player, uid)
		if not allowed(player, "clear") or not validUid(uid) then return end
		Inventory.ClearHotbarSlot(player, uid)
	end)

	Inventory.InventoryChanged:Connect(queueSnapshot)
	Data.Loaded:Connect(function(player)
		task.defer(function() queueSnapshot(player) end)
	end)
	Data.Releasing:Connect(function(player)
		Inventory.CleanupPlayer(player)
		lastSnapshot[player], pendingSnapshot[player], rateWindows[player] = nil, nil, nil
	end)

	local function watchCharacter(player, character)
		Inventory.PutAway(player)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				Inventory.PutAway(player)
			end)
		end
	end
	local function watchPlayer(player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then watchCharacter(player, player.Character) end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		Inventory.CleanupPlayer(player)
		lastSnapshot[player], pendingSnapshot[player], rateWindows[player] = nil, nil, nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
		if Data.IsLoaded(player) then queueSnapshot(player) end
	end
end

return InventoryController
