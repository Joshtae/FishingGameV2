-- Cosmetic Phase 4 podium prompt text. Server prompt validation remains authoritative.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Characters = require(shared.Characters)
local Remotes = shared:WaitForChild("Remotes")
local entries, hotbar, activeSlot = {}, {}, 0
local promptInfo = {}

local function heldEntry()
	local uid = hotbar[tostring(activeSlot)]
	return uid and entries[uid] or nil
end

local function displayNameOn(podium)
	for _, descendant in ipairs(podium:GetDescendants()) do
		if CollectionService:HasTag(descendant, "PlacedCharacter") then
			return descendant:GetAttribute("DisplayName")
		end
	end
	return nil
end

local function apply(prompt)
	local info = promptInfo[prompt]
	if not info or info.applying then return end
	info.applying = true
	local owner = info.plot:GetAttribute("OwnerUserId")
	if owner ~= player.UserId or not info.serverEnabled then
		prompt.Enabled = false
	else
		prompt.Enabled = true
		local name = displayNameOn(info.podium)
		if name then
			prompt.ActionText = "Remove " .. name
		else
			local entry = heldEntry()
			local definition = entry and Characters.GetById(entry.id)
			prompt.ActionText = definition and ("Place " .. definition.displayName) or "Hold a character to place"
		end
		prompt.ObjectText = info.podium.Name
	end
	info.applying = false
end

local function watchPrompt(plot, podium, prompt)
	local info = {plot = plot, podium = podium, serverEnabled = prompt.Enabled, applying = false}
	promptInfo[prompt] = info
	local function reapply()
		if not info.applying then
			info.serverEnabled = prompt.Enabled
			task.defer(function() apply(prompt) end)
		end
	end
	prompt:GetPropertyChangedSignal("Enabled"):Connect(reapply)
	prompt:GetPropertyChangedSignal("ActionText"):Connect(reapply)
	prompt:GetPropertyChangedSignal("ObjectText"):Connect(reapply)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function() apply(prompt) end)
	podium.DescendantAdded:Connect(function() task.defer(function() apply(prompt) end) end)
	podium.DescendantRemoving:Connect(function() task.defer(function() apply(prompt) end) end)
	apply(prompt)
end

for plotIndex = 1, 8 do
	local plot = workspace:FindFirstChild("Plot" .. plotIndex)
	if plot then
		for _, podium in ipairs(plot:GetChildren()) do
			if podium:IsA("Model") then
				local prompt = podium:FindFirstChild("PlacePrompt", true)
				if prompt and prompt:IsA("ProximityPrompt") then watchPrompt(plot, podium, prompt) end
			end
		end
	end
end

local function refreshAll()
	for prompt in pairs(promptInfo) do apply(prompt) end
end

Remotes.InventoryUpdate.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then return end
	entries, hotbar = {}, type(snapshot.hotbar) == "table" and snapshot.hotbar or {}
	for _, entry in ipairs(snapshot.characters or {}) do
		if type(entry) == "table" and type(entry.uid) == "string" then entries[entry.uid] = entry end
	end
	refreshAll()
end)
Remotes.ActiveSlotUpdate.OnClientEvent:Connect(function(slot)
	activeSlot = type(slot) == "number" and slot or 0
	refreshAll()
end)
