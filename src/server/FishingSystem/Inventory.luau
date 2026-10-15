--[[
	Server-only inventory API.
	GetUsedSlots(player) -> number of unplaced character records.
	GetCapacity(player) -> base capacity plus permanent extra slots.
	HasRoom(player, n) -> boolean.
	IsPlaced(player, uid) -> boolean.
	AddExtraSlots(player, n) -> boolean.
	FirstEmptyHotbarSlot(player) -> number or nil.
	GetHotbar(player) -> live hotbar dictionary or nil.
	SetHotbarSlot(player, uid, slot?) -> boolean, reason.
	ClearHotbarSlot(player, uid) -> boolean.
	GetHeldUid(player) -> uid or nil.
	GetActiveSlot(player) -> slot number or nil.
	EquipSlot(player, slot) -> boolean, reason.
	PutAway(player) -> boolean.
	CharacterAdded fires (player, entry) after a successful append.
	InventoryChanged fires (player) after inventory, hotbar, or held state changes.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = script.Parent
local Data = require(root.Data)
local Signal = require(root.Signal)
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local Characters = require(ReplicatedStorage.FishingSystemV2.Characters)

local Inventory = {}
Inventory.CharacterAdded = Signal.new()
Inventory.InventoryChanged = Signal.new()

local heldByPlayer = {}

-- Central placement resolver. Phase 9 adds Lemon Stand ownership here, leaving callers unchanged.
local function getPlacedLocation(data, uid)
	if type(data) ~= "table" or type(uid) ~= "string" or uid == "" then return nil end
	local podiums = data.Plot and data.Plot.Podiums
	if type(podiums) == "table" then
		for podiumId, podium in pairs(podiums) do
			if type(podium) == "table" and podium.characterUid == uid then
				return {kind = "Podium", id = podiumId}
			end
		end
	end
	return nil
end

local function characterByUid(data, uid)
	if not data or type(data.Characters) ~= "table" then return nil end
	for _, entry in ipairs(data.Characters) do
		if type(entry) == "table" and entry.uid == uid then return entry end
	end
	return nil
end

local function validSlot(slot)
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= Config.HotbarSlots
end

function Inventory.IsPlaced(player, uid)
	return getPlacedLocation(Data.Get(player), uid) ~= nil
end

function Inventory.GetUsedSlots(player)
	local data = Data.Get(player)
	if not data or type(data.Characters) ~= "table" then return 0 end
	local used = 0
	for _, entry in ipairs(data.Characters) do
		if type(entry) == "table" and type(entry.uid) == "string" and not Inventory.IsPlaced(player, entry.uid) then
			used += 1
		end
	end
	return used
end

function Inventory.GetCapacity(player)
	local data = Data.Get(player)
	local extra = data and data.ExtraSlots
	if type(extra) ~= "number" or extra % 1 ~= 0 or extra < 0 then extra = 0 end
	return Config.BackpackCapacity + extra
end

function Inventory.HasRoom(player, n)
	n = type(n) == "number" and n or 1
	return n >= 0 and Inventory.GetUsedSlots(player) + n <= Inventory.GetCapacity(player)
end

function Inventory.GetHotbar(player)
	local data = Data.Get(player)
	return data and data.Hotbar or nil
end

function Inventory.FirstEmptyHotbarSlot(player)
	local hotbar = Inventory.GetHotbar(player)
	if type(hotbar) ~= "table" then return nil end
	for slot = 1, Config.HotbarSlots do
		if hotbar[tostring(slot)] == nil then return slot end
	end
	return nil
end

function Inventory.GetActiveSlot(player)
	local held = heldByPlayer[player]
	return held and held.slot or nil
end

function Inventory.GetHeldUid(player)
	local held = heldByPlayer[player]
	return held and held.uid or nil
end

function Inventory.NotifyChanged(player)
	Inventory.InventoryChanged:Fire(player)
end

function Inventory.PutAway(player)
	local held = heldByPlayer[player]
	heldByPlayer[player] = nil
	if held then
		held.destroying = true
		if held.model and held.model.Parent then held.model:Destroy() end
	end
	Inventory.NotifyChanged(player)
	return held ~= nil
end

function Inventory.ClearHotbarSlot(player, uid)
	local data = Data.Get(player)
	if not data or type(uid) ~= "string" or uid == "" or not characterByUid(data, uid) then return false end
	local hotbar = data.Hotbar
	if type(hotbar) ~= "table" then return false end
	local changed = false
	for slot = 1, Config.HotbarSlots do
		local key = tostring(slot)
		if hotbar[key] == uid then hotbar[key] = nil; changed = true end
	end
	if Inventory.GetHeldUid(player) == uid then Inventory.PutAway(player) else
		if changed then Inventory.NotifyChanged(player) end
	end
	return changed
end

function Inventory.SetHotbarSlot(player, uid, requestedSlot)
	local data = Data.Get(player)
	if not data or type(uid) ~= "string" or uid == "" or not characterByUid(data, uid) or Inventory.IsPlaced(player, uid) then
		return false, "invalid character"
	end
	local hotbar = data.Hotbar
	if type(hotbar) ~= "table" then data.Hotbar = {}; hotbar = data.Hotbar end
	local slot = requestedSlot
	if slot ~= nil and not validSlot(slot) then return false, "invalid slot" end
	if slot == nil then slot = Inventory.FirstEmptyHotbarSlot(player) end
	if not slot then return false, "Hotbar full" end
	local key = tostring(slot)
	if hotbar[key] ~= nil and hotbar[key] ~= uid then return false, "slot occupied" end
	for index = 1, Config.HotbarSlots do
		if hotbar[tostring(index)] == uid then hotbar[tostring(index)] = nil end
	end
	hotbar[key] = uid
	Inventory.NotifyChanged(player)
	return true
end

function Inventory.AddExtraSlots(player, n)
	local data = Data.Get(player)
	if not data or type(n) ~= "number" or n % 1 ~= 0 or n <= 0 then return false end
	data.ExtraSlots = (type(data.ExtraSlots) == "number" and data.ExtraSlots or 0) + n
	Inventory.NotifyChanged(player)
	return true
end

local function makeHeldCharacter(player, entry, slot)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local leftHand = character and character:FindFirstChild("LeftHand")
	if not character or not humanoid or humanoid.Health <= 0 or not leftHand or not leftHand:IsA("BasePart") then return nil, "character unavailable" end
	local definition = Characters.GetById(entry.id)
	local source = definition and ReplicatedStorage.FishingSystemV2.CharacterModels:FindFirstChild(definition.modelName)
	if not source then return nil, "model unavailable" end
	local model = source:Clone()
	model.Name = "HeldCharacter"
	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			table.insert(parts, descendant)
		elseif descendant:IsA("Humanoid") then
			descendant:Destroy()
		end
	end
	local root = parts[1]
	if not root then model:Destroy(); return nil, "model has no parts" end
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then model:ScaleTo(Config.HeldModelSize / longest) end
	local grip = CFrame.new(Config.HeldGripOffsetX, Config.HeldGripOffsetY, Config.HeldGripOffsetZ)
		* CFrame.Angles(math.rad(Config.HeldGripRotationX), math.rad(Config.HeldGripRotationY), math.rad(Config.HeldGripRotationZ))
	model:PivotTo(leftHand.CFrame * grip)
	for _, part in ipairs(parts) do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
	local handWeld = Instance.new("WeldConstraint")
	handWeld.Name = "HeldCharacterWeld"
	handWeld.Part0 = leftHand
	handWeld.Part1 = root
	handWeld.Parent = root
	model.Parent = character
	local record = {uid = entry.uid, slot = slot, model = model, destroying = false}
	heldByPlayer[player] = record
	model.AncestryChanged:Connect(function()
		if heldByPlayer[player] ~= record or record.destroying then return end
		if not model:IsDescendantOf(character) then
			record.destroying = true
			heldByPlayer[player] = nil
			if model.Parent then model:Destroy() end
			Inventory.NotifyChanged(player)
		end
	end)
	return true
end

function Inventory.EquipSlot(player, slot)
	if not validSlot(slot) then return false, "invalid slot" end
	local data = Data.Get(player)
	local uid = data and data.Hotbar and data.Hotbar[tostring(slot)]
	if type(uid) ~= "string" or not characterByUid(data, uid) or Inventory.IsPlaced(player, uid) then return false, "empty slot" end
	if Inventory.GetActiveSlot(player) == slot then Inventory.PutAway(player); return true, "put away" end
	Inventory.PutAway(player)
	local ok, reason = makeHeldCharacter(player, characterByUid(data, uid), slot)
	if not ok then return false, reason end
	Inventory.NotifyChanged(player)
	return true
end

function Inventory.CleanupPlayer(player)
	local held = heldByPlayer[player]
	if held then
		held.destroying = true
		if held.model and held.model.Parent then held.model:Destroy() end
	end
	heldByPlayer[player] = nil
end

function Inventory.AddCharacter(player, id, mutation, options)
	local data = Data.Get(player)
	if not data then return nil, "data not loaded" end
	local definition = Characters.GetById(id)
	if not definition then return nil, "unknown character id" end
	if mutation ~= nil and type(mutation) ~= "string" then return nil, "invalid mutation" end
	options = options or {}
	if not options.bypassCapacity and not Inventory.HasRoom(player, 1) then return nil, "Backpack full" end
	local uid = Data.NewUid()
	local entry = {uid = uid, id = id}
	if mutation ~= nil then entry.mutation = mutation end
	table.insert(data.Characters, entry)
	local slot = Inventory.FirstEmptyHotbarSlot(player)
	if slot then data.Hotbar[tostring(slot)] = uid end
	Inventory.CharacterAdded:Fire(player, entry)
	Inventory.NotifyChanged(player)
	return uid
end

return Inventory
