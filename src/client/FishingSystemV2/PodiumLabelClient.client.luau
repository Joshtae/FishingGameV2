-- Local-only R3 visibility for the existing placed-character billboards.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local WorldConfig = require(ReplicatedStorage.FishingSystemV2.WorldConfig)
local billboardName = "FishingSystemV2Billboard"

local function localRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then return nil end
	return root
end

local function apply(billboard, root)
	if not billboard:IsA("BillboardGui") or billboard.Name ~= billboardName then return end
	local model = billboard.Parent
	if not model or not model:IsA("Model") then billboard.Enabled = false; return end
	local position = model:GetPivot().Position
	billboard.Enabled = root ~= nil and (root.Position - position).Magnitude <= WorldConfig.PodiumLabelShowDistance
end

local function scan()
	local root = localRoot()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("BillboardGui") and descendant.Name == billboardName then
			apply(descendant, root)
		end
	end
end

-- A new local clone is hidden/shown before the next visual scan can render it.
Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BillboardGui") and descendant.Name == billboardName then
		task.defer(function()
			if descendant.Parent then apply(descendant, localRoot()) end
		end)
	end
end)
CollectionService:GetInstanceAddedSignal("PlacedCharacter"):Connect(function()
	task.defer(scan)
end)
player.CharacterAdded:Connect(function()
	task.defer(scan)
end)

task.spawn(function()
	while true do
		scan()
		task.wait(WorldConfig.PodiumLabelScanSeconds)
	end
end)
