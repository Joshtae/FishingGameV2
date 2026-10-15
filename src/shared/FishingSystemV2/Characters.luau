-- Server/shared character catalogue and display helpers.
-- GetAll(includePlaceholders), GetActive(includePlaceholders), GetActiveByRarity(rarity, includePlaceholders),
-- GetById(id), Validate(), and CreateDisplay(definition, standPart) are the supported APIs.
local CollectionService = game:GetService("CollectionService")
local CharacterList = require(script.Parent.CharacterList)
local Characters = {IncludePlaceholders=false}

local byId = {}
for _, definition in ipairs(CharacterList) do byId[definition.id] = definition end

function Characters.GetAll(includePlaceholders)
	local result = {}
	for _, definition in ipairs(CharacterList) do
		if includePlaceholders ~= false or not definition.placeholder then table.insert(result, definition) end
	end
	return result
end
function Characters.GetActive(includePlaceholders)
	if includePlaceholders == nil then includePlaceholders = Characters.IncludePlaceholders end
	return Characters.GetAll(includePlaceholders)
end
function Characters.GetActiveByRarity(rarity, includePlaceholders)
	local result = {}
	for _, definition in ipairs(Characters.GetActive(includePlaceholders)) do
		if definition.rarity == rarity then table.insert(result, definition) end
	end
	return result
end
function Characters.GetById(id) return byId[id] end
function Characters.GetDefinition(id) return byId[id] end
function Characters.GetIdsByRarity(rarity, includePlaceholders)
	local result = {}
	for _, definition in ipairs(Characters.GetActiveByRarity(rarity, includePlaceholders)) do table.insert(result, definition.id) end
	return result
end

function Characters.Validate()
	local report = {errors={}, total=0, real=0, placeholders=0, perRarity={}}
	local ids, names, models = {}, {}, script.Parent.CharacterModels
	for _, definition in ipairs(CharacterList) do
		report.total += 1
		report.perRarity[definition.rarity] = (report.perRarity[definition.rarity] or 0) + 1
		if ids[definition.id] then table.insert(report.errors, "duplicate id: "..definition.id) end
		ids[definition.id] = true
		if type(definition.rarity) ~= "number" or definition.rarity < 1 or definition.rarity > 11 then table.insert(report.errors, "out-of-range rarity: "..definition.id) end
		if definition.placeholder then report.placeholders += 1 else report.real += 1 end
		if names[definition.modelName] then table.insert(report.errors, "duplicate modelName: "..definition.modelName) end
		names[definition.modelName] = true
		local model = models:FindFirstChild(definition.modelName)
		if not model or not model:IsA("Model") then
			table.insert(report.errors, "missing model: "..definition.modelName)
		else
			if not model.PrimaryPart and not model:FindFirstChild("HumanoidRootPart", true) then table.insert(report.errors, "no PrimaryPart/HumanoidRootPart: "..definition.modelName) end
			for _, child in ipairs(model:GetDescendants()) do
				if child:IsA("BaseScript") then table.insert(report.errors, "model contains script: "..definition.modelName); break end
			end
		end
	end
	return report
end

function Characters.CreateDisplay(definition, standPart)
	local asset = script.Parent.CharacterModels:FindFirstChild(definition.modelName)
	if not asset or not standPart or not standPart:IsA("BasePart") then return nil, "missing asset or stand" end
	local display = asset:Clone()
	for _, descendant in ipairs(display:GetDescendants()) do
		if descendant:IsA("BaseScript") then descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	local originalHeight = display:GetExtentsSize().Y
	if originalHeight <= 0 then display:Destroy(); return nil, "invalid model height" end
	local targetHeight = 5
	display:ScaleTo(targetHeight / originalHeight)
	local _, size = display:GetBoundingBox()
	local center = standPart.Position + standPart.CFrame.UpVector * (standPart.Size.Y / 2 + size.Y / 2 + 0.02)
	display:PivotTo(CFrame.lookAt(center, center + standPart.CFrame.LookVector, standPart.CFrame.UpVector))
	display.Name = "Placed_" .. definition.id
	display:SetAttribute("CharacterId", definition.id)
	display:SetAttribute("DisplayName", definition.displayName)
	display:SetAttribute("OriginalHeight", originalHeight)
	display:SetAttribute("ScaledHeight", display:GetExtentsSize().Y)
	CollectionService:AddTag(display, "PlacedCharacter")
	return display, {originalHeight=originalHeight, scaledHeight=display:GetExtentsSize().Y}
end
return Characters
