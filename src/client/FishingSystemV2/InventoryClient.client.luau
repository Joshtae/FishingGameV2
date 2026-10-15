--[[
	Phase 4 inventory presentation. The server owns all inventory, hotbar, capacity, and held state.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Config = require(shared.FishingConfig)
local Characters = require(shared.Characters)
local Rarities = require(shared.Rarities)
local Colors = require(shared.RarityColors)
local Remotes = shared:WaitForChild("Remotes")
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("FishingSystemV2")
local hotbar = gui:WaitForChild("Phase4Hotbar")
local buttonGui = gui:WaitForChild("InventoryButtonGui")
local inventoryButton = buttonGui:WaitForChild("InventoryButton")
local window = gui:WaitForChild("InventoryWindow")
local characterGrid = window:WaitForChild("CharacterGrid")
local counter = window:WaitForChild("Counter")
local closeButton = window:WaitForChild("CloseButton")
local plusButton = window:WaitForChild("PlusButton")
local plusTooltip = window:WaitForChild("PlusTooltip")

local state = {characters = {}, hotbar = {}, used = 0, capacity = Config.BackpackCapacity, activeSlot = 0, mobile = UserInputService.TouchEnabled, sessionActive = false}
local tileByUid, assignedByTile = {}, {}

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title = "Inventory", Text = text, Duration = 2})
	end)
end

local function definitionFor(entry)
	return entry and Characters.GetById(entry.id)
end

local function slotForUid(uid)
	for slot = 1, Config.HotbarSlots do
		if state.hotbar[tostring(slot)] == uid then return slot end
	end
	return nil
end

local entryTemplate = characterGrid:WaitForChild("Entry1"):Clone()
entryTemplate.Name = "RuntimeInventoryEntryTemplate"
entryTemplate.Visible = false
entryTemplate:SetAttribute("Uid", nil)
entryTemplate.Parent = nil
local boundTiles, runtimeTileCount = {}, 0

local function bindEntryTile(tile)
	if boundTiles[tile] then return end
	boundTiles[tile] = true
	tile.Activated:Connect(function()
		local uid = tile:GetAttribute("Uid")
		if type(uid) ~= "string" then return end
		if slotForUid(uid) then
			Remotes.ClearHotbarSlot:FireServer(uid)
		else
			Remotes.SetHotbarSlot:FireServer(uid)
		end
	end)
end

local function makeOverflowTile()
	runtimeTileCount += 1
	local tile = entryTemplate:Clone()
	tile.Name = "EntryRuntime" .. runtimeTileCount
	tile.Visible = false
	tile:SetAttribute("Uid", nil)
	tile.Parent = characterGrid
	bindEntryTile(tile)
	return tile
end

local function applyHotbarLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local layout = hotbar:WaitForChild("UIListLayout")
	local slotSize
	if state.mobile then
		hotbar.Position = UDim2.fromScale(.5, .934)
		hotbar.Size = UDim2.fromScale(.672, .146)
		layout.Padding = UDim.new(0, 3)
		local barWidth = hotbar.AbsoluteSize.X > 0 and hotbar.AbsoluteSize.X or viewport.X * .672
		slotSize = math.clamp(math.floor((barWidth - 8 * 3) / 9), 44, 60)
	else
		hotbar.Position = UDim2.new(.5, 0, .984, 0)
		hotbar.Size = UDim2.fromOffset(9 * 60 + 8 * 4, 60)
		layout.Padding = UDim.new(0, 4)
		slotSize = 60
	end
	for slot = 1, Config.HotbarSlots do
		local button = hotbar:WaitForChild("Slot" .. slot)
		button.Size = UDim2.fromOffset(slotSize, slotSize)
		local constraint = button:FindFirstChildWhichIsA("UISizeConstraint")
		if constraint then
			constraint.MinSize = Vector2.new(44, 44)
			constraint.MaxSize = Vector2.new(state.mobile and 60 or 80, state.mobile and 60 or 80)
		end
	end
	hotbar.Visible = not (state.mobile and state.sessionActive)
end

local function renderHotbar()
	for slot = 1, Config.HotbarSlots do
		local button = hotbar:WaitForChild("Slot" .. slot)
		local inner = button.InnerFrame
		local tile = inner.Tile
		local tag = inner.MutationTag
		local stroke = button.SlotStroke
		local uid = state.hotbar[tostring(slot)]
		local entry = uid and state.characters[uid]
		local definition = definitionFor(entry)
		local active = state.activeSlot == slot
		if definition then
			tile.Text = definition.displayName
			tile.BackgroundColor3 = Colors[definition.rarity] or Color3.fromRGB(66,74,88)
			tile.TextTransparency = 0
			tag.Text = entry.mutation or ""
			tag.Visible = entry.mutation ~= nil and entry.mutation ~= ""
			button.BackgroundTransparency = 0
			stroke.Color = active and Color3.fromRGB(255,210,76) or (Colors[definition.rarity] or Color3.fromRGB(53,53,53))
		else
			tile.Text = ""
			tile.BackgroundColor3 = Color3.fromRGB(66,74,88)
			tile.TextTransparency = 1
			tag.Visible = false
			button.BackgroundTransparency = .38
			stroke.Color = Color3.fromRGB(53,53,53)
		end
		local target = active and 1.08 or 1
		TweenService:Create(button.ActiveScale, TweenInfo.new(.12), {Scale = target}):Play()
	end
end

local function sortedEntries()
	local rows = {}
	for _, entry in pairs(state.characters) do table.insert(rows, entry) end
	table.sort(rows, function(a, b)
		local da, db = definitionFor(a), definitionFor(b)
		local ra, rb = da and da.rarity or 0, db and db.rarity or 0
		if ra ~= rb then return ra > rb end
		local na, nb = da and da.displayName or "", db and db.displayName or ""
		if na ~= nb then return na < nb end
		return a.uid < b.uid
	end)
	return rows
end

local function renderInventory()
	local cap = state.capacity == math.huge and "∞" or tostring(state.capacity)
	counter.Text = tostring(state.used) .. "/" .. cap
	local rows = sortedEntries()
	local nextUid = {}
	for _, entry in ipairs(rows) do nextUid[entry.uid] = true end
	for uid, tile in pairs(tileByUid) do
		if not nextUid[uid] then
			tile.Visible = false
			tile:SetAttribute("Uid", nil)
			tileByUid[uid] = nil
			assignedByTile[tile] = nil
		end
	end
	local available = {}
	for _, tile in ipairs(characterGrid:GetChildren()) do
		if tile:IsA("TextButton") and string.match(tile.Name, "^Entry") and not assignedByTile[tile] then
			table.insert(available, tile)
		end
	end
	for layoutOrder, entry in ipairs(rows) do
		local tile = tileByUid[entry.uid]
		if not tile then
			tile = table.remove(available, 1) or makeOverflowTile()
			tileByUid[entry.uid] = tile
			assignedByTile[tile] = entry.uid
		end
		local definition = definitionFor(entry)
		local rarity = definition and definition.rarity or 1
		tile.LayoutOrder = layoutOrder
		tile.Visible = true
		tile:SetAttribute("Uid", entry.uid)
		tile.Tile.Text = definition and definition.displayName or entry.id
		tile.Tile.BackgroundColor3 = Colors[rarity] or Color3.fromRGB(66,74,88)
		tile.NameLabel.Text = definition and definition.displayName or entry.id
		tile.RarityLabel.Text = Rarities.List[rarity] or ""
		tile.RarityLabel.TextColor3 = Colors[rarity] or Color3.new(1,1,1)
		tile.EntryStroke.Color = Colors[rarity] or Color3.fromRGB(53,53,53)
		tile.MutationTag.Text = entry.mutation or ""
		tile.MutationTag.Visible = entry.mutation ~= nil and entry.mutation ~= ""
		local slot = slotForUid(entry.uid)
		tile.SlotMarker.Text = slot and ("SLOT " .. slot) or ""
		tile.SlotMarker.Visible = slot ~= nil
	end
end

local function render()
	renderHotbar()
	renderInventory()
end

local function setWindowVisible(visible)
	window.Visible = visible
	if visible then renderInventory() end
end

for slot = 1, Config.HotbarSlots do
	hotbar:WaitForChild("Slot" .. slot).Activated:Connect(function()
		Remotes.EquipSlot:FireServer(slot)
	end)
end

for index = 1, 100 do
	bindEntryTile(characterGrid:WaitForChild("Entry" .. index))
end

inventoryButton.Activated:Connect(function()
	setWindowVisible(not window.Visible)
end)
closeButton.Activated:Connect(function()
	setWindowVisible(false)
end)
plusButton.MouseEnter:Connect(function() plusTooltip.Visible = true end)
plusButton.MouseLeave:Connect(function() plusTooltip.Visible = false end)

UserInputService.LastInputTypeChanged:Connect(function(input)
	state.mobile = input == Enum.UserInputType.Touch
	applyHotbarLayout()
end)

Remotes.CastAccepted.OnClientEvent:Connect(function(sessionId)
	if type(sessionId) == "string" then
		state.sessionActive = true
		applyHotbarLayout()
	end
end)
Remotes.SessionEnd.OnClientEvent:Connect(function()
	state.sessionActive = false
	applyHotbarLayout()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local slots = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	}
	local slot = slots[input.KeyCode]
	if slot then Remotes.EquipSlot:FireServer(slot) end
end)

Remotes.InventoryUpdate.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.characters) ~= "table" or type(snapshot.hotbar) ~= "table" then return end
	state.characters = {}
	for _, entry in ipairs(snapshot.characters) do
		if type(entry) == "table" and type(entry.uid) == "string" then state.characters[entry.uid] = entry end
	end
	state.hotbar = snapshot.hotbar
	state.used = snapshot.used or 0
	state.capacity = snapshot.capacity or Config.BackpackCapacity
	render()
end)

Remotes.ActiveSlotUpdate.OnClientEvent:Connect(function(slot)
	state.activeSlot = type(slot) == "number" and slot or 0
	renderHotbar()
end)
Remotes.InventoryMessage.OnClientEvent:Connect(notify)

task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then break end
		task.wait(.5)
	end
end)

local oldBottom = playerGui:FindFirstChild("BottomHUD")
local oldFrame = oldBottom and oldBottom:FindFirstChild("OverallBottomFrame")
if oldFrame then oldFrame.Visible = false end
applyHotbarLayout()
local camera = Workspace.CurrentCamera
if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyHotbarLayout) end
render()
