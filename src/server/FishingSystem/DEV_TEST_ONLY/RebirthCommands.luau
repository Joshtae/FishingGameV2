-- Studio-only Phase 5 rebirth commands. Delete with DEV_TEST_ONLY before launch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return {} end

local root = script.Parent.Parent
local Data = require(root.Data)
local Currency = require(root.Currency)
local Plots = require(root.Plots)
local Podiums = require(root.Podiums)
local RebirthService = require(root.RebirthService)
local RebirthSelfTest = require(script.Parent.RebirthSelfTest)
local Rebirths = require(ReplicatedStorage.FishingSystemV2.Rebirths)

local Commands = {}
local DEV_USER_IDS = {[50571834] = true}

local function authorized(player)
	return DEV_USER_IDS[player.UserId] == true
end

local function finiteNonNegative(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value >= 0
end

local function refreshPodiums(player)
	local plot = Plots.Get(player)
	if not plot then return end
	for podiumId in pairs(Plots.GetPodiums(plot)) do
		Podiums.RefreshPodium(player, podiumId)
	end
end

local function setRebirths(player, level)
	if type(level) ~= "number" or level % 1 ~= 0 or level < 0 or level > Rebirths.MaxRebirths then
		warn("[DEV_TEST_ONLY] Rebirths must be an integer from 0 to " .. Rebirths.MaxRebirths .. ".")
		return
	end
	local data = Data.Get(player)
	if not data then
		warn("[DEV_TEST_ONLY] No loaded data.")
		return
	end
	data.Rebirths = level
	player:SetAttribute("Rebirths", level)
	Currency.Refresh(player)
	refreshPodiums(player)
	print("[DEV_TEST_ONLY] Rebirths set to " .. level .. ".")
end

function Commands.HandleChat(player, message)
	if not authorized(player) then return end
	local command, argument = string.match(message, "^(%S+)%s*(.*)$")
	if command == "/devrebirths" then
		setRebirths(player, tonumber(argument))
	elseif command == "/devrebirthspam" then
		local count = tonumber(argument)
		if type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > 100 then
			warn("[DEV_TEST_ONLY] /devrebirthspam count must be 1-100.")
			return
		end
		local success, rejected, rateLimited = 0, 0, 0
		for _ = 1, count do
			local ok, reason = RebirthService.HandleRequest(player)
			if ok then success += 1
			elseif reason == "Rate limited" then rateLimited += 1
			else rejected += 1 end
		end
		print(("[DEV_TEST_ONLY] Rebirth spam count=%d success=%d rejected=%d rateLimited=%d")
			:format(count, success, rejected, rateLimited))
	elseif command == "/devfood" then
		local amount = tonumber(argument)
		if not finiteNonNegative(amount) then
			warn("[DEV_TEST_ONLY] Food must be finite and non-negative.")
			return
		end
		local data = Data.Get(player)
		if not data then
			warn("[DEV_TEST_ONLY] No loaded data.")
			return
		end
		data.Food = amount
		print("[DEV_TEST_ONLY] Food set to " .. amount .. ".")
	elseif command == "/devrebirthtest" then
		RebirthSelfTest.Run()
	end
end

return Commands
