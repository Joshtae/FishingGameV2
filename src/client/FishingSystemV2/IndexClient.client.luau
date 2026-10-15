--[[ Client-only Phase 6 Index presentation. The server owns discovery, claims, and luck. ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Characters = require(shared:WaitForChild("Characters"))
local Rarities = require(shared:WaitForChild("Rarities"))
local Colors = require(shared:WaitForChild("RarityColors"))
local Config = require(shared:WaitForChild("IndexConfig"))
local Remotes = shared:WaitForChild("Remotes")
local gui = playerGui:WaitForChild("FishingSystemV2Index")
local window = gui:WaitForChild("IndexWindow")
local header = window:WaitForChild("Header")
local closeButton = header:WaitForChild("CloseButton")
local claimAllButton = header:WaitForChild("ClaimAllButton")
local discoveredLabel = window:WaitForChild("DiscoveredLabel")
local claimedLabel = window:WaitForChild("ClaimedLabel")
local luckLabel = window:WaitForChild("LuckLabel")
local hintLabel = window:WaitForChild("HintLabel")
local grid = window:WaitForChild("EntryGrid")
local gridLayout = grid:WaitForChild("UIGridLayout")
local template = grid:WaitForChild("EntryTemplate")
local toast = gui:WaitForChild("DiscoveryToast")
local toastLabel = toast:WaitForChild("ToastLabel")
local models = shared:WaitForChild("CharacterModels")

local showAll = false
local state = {
	open = false,
	built = false,
	discovered = {},
	claimed = {},
	entryById = {},
	pendingClaims = {},
	toastQueue = {},
	showingToast = false,
	button = nil,
	buttonConnection = nil,
}

local function formatLuck(value)
	local formatted = string.format("%.2f", value)
	formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
	return formatted .. "x"
end

local function getDefinitions()
	return showAll and Characters.GetAll(true) or Characters.GetActive()
end

local function sortedDefinitions()
	local definitions = table.clone(getDefinitions())
	table.sort(definitions, function(a, b)
		if a.rarity ~= b.rarity then return a.rarity < b.rarity end
		if a.displayName ~= b.displayName then return a.displayName < b.displayName end
		return a.id < b.id
	end)
	return definitions
end

local function applyGridLayout()
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	local columns, heightScale
	if viewport.X < 900 then
		columns, heightScale = 6, .34
	elseif viewport.X < 1500 then
		columns, heightScale = 8, .28
	else
		columns, heightScale = 9, .23
	end
	local gap = .018
	gridLayout.FillDirectionMaxCells = columns
	gridLayout.CellSize = UDim2.fromScale((1 - gap * (columns - 1)) / columns, heightScale)
	gridLayout.CellPadding = UDim2.fromScale(gap, .02)
end

local function clearPreview(viewport)
	for _, child in ipairs(viewport:GetChildren()) do child:Destroy() end
end

local function setPreview(tile, definition, discovered)
	local viewport = tile:WaitForChild("Preview")
	local fallback = tile:WaitForChild("Fallback")
	if not discovered then
		clearPreview(viewport)
		viewport.Visible = false
		fallback.Visible = true
		fallback.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
		fallback.Text.Text = "???"
		return
	end

	local source = models:FindFirstChild(definition.modelName)
	if not source or not source:IsA("Model") then
		clearPreview(viewport)
		viewport.Visible = false
		fallback.Visible = true
		fallback.BackgroundColor3 = Colors[definition.rarity] or Color3.fromRGB(72, 72, 86)
		fallback.Text.Text = definition.displayName
		return
	end

	clearPreview(viewport)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local clone = source:Clone()
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Humanoid") then
			descendant:Destroy()
		end
	end
	clone.Parent = world
	local boxCFrame, boxSize = clone:GetBoundingBox()
	local largest = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(boxCFrame.Position + Vector3.new(largest * .9, largest * .35, largest * 1.45), boxCFrame.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Visible = true
	fallback.Visible = false
end

local function updateHeader()
	local definitions = getDefinitions()
	local discoveredCount, claimedCount = 0, 0
	for _, definition in ipairs(definitions) do
		if state.discovered[definition.id] then discoveredCount += 1 end
		if state.claimed[definition.id] then claimedCount += 1 end
	end
	discoveredLabel.Text = ("Discovered: %d/%d"):format(discoveredCount, #definitions)
	claimedLabel.Text = ("Claimed: %d/%d"):format(claimedCount, #definitions)
	luckLabel.Text = "Luck: " .. formatLuck(player:GetAttribute("IndexLuck") or 1)
	hintLabel.Text = "+" .. formatLuck(Config.LuckPerClaim) .. " per claimed character"
	claimAllButton.Active = discoveredCount > claimedCount
	claimAllButton.AutoButtonColor = discoveredCount > claimedCount
	claimAllButton.TextTransparency = discoveredCount > claimedCount and 0 or .45
end

local pulses = {}
local function stopPulse(tile)
	local existing = pulses[tile]
	if existing then existing:Cancel(); pulses[tile] = nil end
	local stroke = tile:FindFirstChild("EntryStroke")
	if stroke then stroke.Transparency = 0 end
end

local function updateTile(tile, definition)
	local id = definition.id
	local discovered = state.discovered[id] == true
	local claimed = state.claimed[id] == true
	local color = Colors[definition.rarity] or Color3.fromRGB(125,125,135)
	local stroke = tile:WaitForChild("EntryStroke")
	stroke.Color = discovered and color or Color3.fromRGB(75,75,82)
	tile.BackgroundColor3 = discovered and Color3.fromRGB(53,48,61) or Color3.fromRGB(33,31,39)
	tile.NameLabel.Text = discovered and definition.displayName or "???"
	tile.RarityLabel.Text = discovered and (Rarities.List[definition.rarity] or "") or ""
	tile.RarityLabel.TextColor3 = color
	tile.CheckLabel.Visible = claimed
	if claimed then
		tile.ActionLabel.Text = "CLAIMED"
		tile.ActionLabel.TextColor3 = Color3.fromRGB(109,255,139)
	elseif discovered then
		tile.ActionLabel.Text = "CLAIM +" .. formatLuck(Config.LuckPerClaim)
		tile.ActionLabel.TextColor3 = Color3.fromRGB(255,220,145)
	else
		tile.ActionLabel.Text = "LOCKED"
		tile.ActionLabel.TextColor3 = Color3.fromRGB(165,165,175)
	end
	tile.Active = discovered and not claimed and not state.pendingClaims[id]
	tile.AutoButtonColor = tile.Active
	setPreview(tile, definition, discovered)
	stopPulse(tile)
	if discovered and not claimed then
		local pulse = TweenService:Create(stroke, TweenInfo.new(.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = .45})
		pulse:Play()
		pulses[tile] = pulse
	end
end

local function updateExistingTiles()
	for id, tile in pairs(state.entryById) do
		local definition = Characters.GetById(id)
		if definition then updateTile(tile, definition) end
	end
	updateHeader()
end

local function requestClaim(id)
	if state.pendingClaims[id] then return end
	state.pendingClaims[id] = true
	updateExistingTiles()
	Remotes.ClaimIndex:FireServer(id)
	task.delay(2, function()
		if state.pendingClaims[id] then
			state.pendingClaims[id] = nil
			updateExistingTiles()
		end
	end)
end

local function buildEntries()
	if state.built then return end
	state.built = true
	applyGridLayout()
	for order, definition in ipairs(sortedDefinitions()) do
		local tile = template:Clone()
		tile.Name = "Entry_" .. definition.id
		tile.Visible = true
		tile.LayoutOrder = order
		tile:SetAttribute("IndexId", definition.id)
		tile.Parent = grid
		state.entryById[definition.id] = tile
		tile.Activated:Connect(function()
			requestClaim(definition.id)
		end)
		updateTile(tile, definition)
		if order % Config.EntryBuildBatch == 0 then task.wait() end
	end
	updateHeader()
end

local function rebuildForDevShowAll()
	if not state.built then return end
	for _, tile in pairs(state.entryById) do tile:Destroy() end
	table.clear(state.entryById)
	state.built = false
	buildEntries()
end

-- DEV_ONLY_BEGIN IndexShowAll
if RunService:IsStudio() then
	local function updateDevShowAll()
		showAll = Workspace:GetAttribute("FishingSystemV2_IndexShowAll") == true
	end
	updateDevShowAll()
	Workspace:GetAttributeChangedSignal("FishingSystemV2_IndexShowAll"):Connect(function()
		updateDevShowAll()
		rebuildForDevShowAll()
	end)
end
-- DEV_ONLY_END IndexShowAll

local function showToast(definition)
	table.insert(state.toastQueue, "NEW! " .. definition.displayName .. " added to Index")
	if state.showingToast then return end
	state.showingToast = true
	task.spawn(function()
		while #state.toastQueue > 0 do
			toastLabel.Text = table.remove(state.toastQueue, 1)
			toast.Visible = true
			toast.BackgroundTransparency = 1
			TweenService:Create(toast, TweenInfo.new(.18), {BackgroundTransparency = 0}):Play()
			task.wait(Config.DiscoveryToastSeconds)
			local fade = TweenService:Create(toast, TweenInfo.new(.18), {BackgroundTransparency = 1})
			fade:Play()
			fade.Completed:Wait()
			toast.Visible = false
		end
		state.showingToast = false
	end)
end

local function setOpen(open)
	state.open = open
	window.Visible = open
	window.Active = open
	if open then
		buildEntries()
		updateExistingTiles()
	end
end

local function bindIndexButton()
	local left = playerGui:FindFirstChild("LeftFramesGui")
	local overall = left and left:FindFirstChild("OverallFrame")
	local frame = overall and overall:FindFirstChild("IndexFrame")
	local button = frame and frame:FindFirstChild("ShopFrameButton")
	if button == state.button then return end
	if state.buttonConnection then state.buttonConnection:Disconnect() end
	state.button, state.buttonConnection = button, nil
	if button and button:IsA("TextButton") then
		state.buttonConnection = button.Activated:Connect(function()
			setOpen(not state.open)
		end)
	end
end

closeButton.Activated:Connect(function() setOpen(false) end)
claimAllButton.Activated:Connect(function()
	if claimAllButton.Active then Remotes.ClaimAllIndex:FireServer() end
end)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "LeftFramesGui" then task.defer(bindIndexButton) end
end)

Remotes.IndexUpdate.OnClientEvent:Connect(function(kind, payload)
	if type(kind) ~= "string" or type(payload) ~= "table" then return end
	if kind == "snapshot" then
		table.clear(state.discovered)
		table.clear(state.claimed)
		for _, id in ipairs(payload.discovered or {}) do if type(id) == "string" then state.discovered[id] = true end end
		for _, id in ipairs(payload.claimed or {}) do if type(id) == "string" then state.claimed[id] = true end end
		if type(payload.indexLuck) == "number" then player:SetAttribute("IndexLuck", payload.indexLuck) end
	elseif kind == "discovered" and type(payload.id) == "string" then
		state.discovered[payload.id] = true
		local definition = Characters.GetById(payload.id)
		if definition then showToast(definition) end
	elseif kind == "claimed" then
		if type(payload.id) == "string" then
			state.claimed[payload.id] = true
			state.pendingClaims[payload.id] = nil
		end
		for _, id in ipairs(payload.ids or {}) do
			if type(id) == "string" then state.claimed[id] = true; state.pendingClaims[id] = nil end
		end
		if type(payload.indexLuck) == "number" then player:SetAttribute("IndexLuck", payload.indexLuck) end
	end
	if state.built then updateExistingTiles() else updateHeader() end
end)

player:GetAttributeChangedSignal("IndexLuck"):Connect(updateHeader)
if Workspace.CurrentCamera then Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyGridLayout) end

bindIndexButton()
setOpen(false)
updateHeader()
Remotes.IndexReady:FireServer()
