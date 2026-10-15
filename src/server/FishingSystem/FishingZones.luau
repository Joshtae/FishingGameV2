--[[ Runtime fishing-zone discovery and authoritative Terrain-water validation. ]]
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)

local FishingZones = {}
local zones = {}
local started = false
local tag = "FishableWater"

local function isZone(instance)
	return instance:IsA("BasePart") and string.match(instance.Name, "^FishingPart%d+$") ~= nil
end
local function refresh(instance)
	if isZone(instance) then
		zones[instance] = true
		CollectionService:AddTag(instance, tag)
		instance:SetAttribute("Spot", instance.Name)
	elseif zones[instance] then
		zones[instance] = nil
	end
end
function FishingZones.Start()
	if started then return end
	started = true
	for _, descendant in ipairs(Workspace:GetDescendants()) do refresh(descendant) end
	Workspace.DescendantAdded:Connect(refresh)
	Workspace.DescendantRemoving:Connect(function(instance) zones[instance] = nil end)
end
function FishingZones.GetZones()
	local result = {}
	for zone in pairs(zones) do if zone.Parent then table.insert(result, zone) end end
	table.sort(result, function(a,b) return a.Name < b.Name end)
	return result
end
function FishingZones.IsInside(zone, point)
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size * 0.5
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Z) <= half.Z
		and math.abs(localPoint.Y) <= half.Y + Config.ZoneVerticalPadding
end
function FishingZones.GetZoneAt(point)
	for _, zone in ipairs(FishingZones.GetZones()) do
		if FishingZones.IsInside(zone, point) then return zone end
	end
	return nil
end
local function finiteVector3(value)
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < math.huge and math.abs(value.Y) < math.huge and math.abs(value.Z) < math.huge
end
local function rayParams(character)
	local filter = FishingZones.GetZones()
	if character then table.insert(filter, character) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = false
	return params
end
function FishingZones.GetWaterHit(point, character)
	return Workspace:Raycast(point + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), rayParams(character))
end
local function nearestSand(point)
	local best, bestDistance
	for _, object in ipairs(Workspace:GetDescendants()) do
		if string.match(object.Name, "^Sand%d+$") and (object:IsA("BasePart") or object:IsA("Model")) then
			local position = object:IsA("BasePart") and object.Position or object:GetPivot().Position
			local distance = (position - point).Magnitude
			if not bestDistance or distance < bestDistance then best, bestDistance = object, distance end
		end
	end
	return best
end
function FishingZones.GetNearestSand(point) return nearestSand(point) end
function FishingZones.GetStandPoint(target)
	local sand = nearestSand(target)
	if not sand then return nil, "no nearby sand" end
	local box, size
	if sand:IsA("BasePart") then box, size = sand.CFrame, sand.Size else box, size = sand:GetBoundingBox() end
	local localTarget = box:PointToObjectSpace(target)
	local x = math.clamp(localTarget.X, -size.X * .45, size.X * .45)
	local z = math.clamp(localTarget.Z, -size.Z * .45, size.Z * .45)
	local point = box:PointToWorldSpace(Vector3.new(x, size.Y * .5 + 3, z))
	return point, sand
end
function FishingZones.ValidateTarget(player, target)
	if not finiteVector3(target) then return nil, "Invalid fishing target" end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil, "You need to be alive to fish." end
	if (root.Position - target).Magnitude > Config.MaxCastDistance then return nil, "That water is too far away." end
	local zone = FishingZones.GetZoneAt(target)
	if not zone then return nil, "That water is not fishable." end
	local hit = FishingZones.GetWaterHit(target, character)
	if not hit or hit.Material ~= Enum.Material.Water then return nil, "That water is not fishable." end
	if Config.RequireNearSpot then
		local sand = nearestSand(target)
		local sandPosition = sand and (sand:IsA("BasePart") and sand.Position or sand:GetPivot().Position)
		if not sandPosition or (root.Position - sandPosition).Magnitude > Config.SpotRadius then return nil, "Move closer to a fishing spot." end
	end
	return {target = hit.Position, spot = zone.Name, zone = zone, sand = nearestSand(hit.Position), origin = root.Position}
end
return FishingZones
