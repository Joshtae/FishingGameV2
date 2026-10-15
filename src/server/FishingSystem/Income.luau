-- Server-only passive income and exact per-podium collection APIs.
-- GetPodiumCPS(player,podiumId), GetTotalCPS(player), CollectPodium(player,podiumId), and Start() are supported.
local Players = game:GetService("Players")
local root = script.Parent
local Data = require(root.Data)
local Currency = require(root.Currency)
local Plots = require(root.Plots)
local Characters = require(game:GetService("ReplicatedStorage").FishingSystemV2.Characters)
local Rebirths = require(game:GetService("ReplicatedStorage").FishingSystemV2.Rebirths)
local Income = {}
local BaseCPSGrowth = 8
local rates = {}
for i = 1, 11 do
	rates[i] = BaseCPSGrowth ^ (i - 1)
end
local started = false
local function findCharacter(data, uid)
	for _, character in ipairs(data.Characters) do if character.uid == uid then return character end end
end
function Income.GetPodiumCPS(player, podiumId)
	local data = Data.Get(player)
	local state = data and data.Plot and data.Plot.Podiums[podiumId]
	if not state or state.unlocked ~= true or not state.characterUid then return 0 end
	local character = findCharacter(data, state.characterUid)
	local definition = character and Characters.GetById(character.id)
	local base = definition and rates[definition.rarity]
	return base and base * (Rebirths.GetMult(data.Rebirths) or 1) or 0
end
function Income.GetTotalCPS(player)
	local total, plot = 0, Plots.Get(player)
	if plot then for podiumId in pairs(Plots.GetPodiums(plot)) do total += Income.GetPodiumCPS(player, podiumId) end end
	return total
end
function Income.CollectPodium(player, podiumId)
	local data = Data.Get(player)
	local state = data and data.Plot and data.Plot.Podiums[podiumId]
	if not state or state.unlocked ~= true then return 0 end
	local amount = state.storedCash
	if type(amount) ~= "number" or amount <= 0 then return 0 end
	if not Currency.AddCash(player, amount) then return 0 end
	state.storedCash = 0
	return amount
end
function Income.Start()
	if started then return end
	started = true
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local data, plot = Data.Get(player), Plots.Get(player)
				if data and plot then
					for podiumId in pairs(Plots.GetPodiums(plot)) do
						local cps = Income.GetPodiumCPS(player, podiumId)
						if cps > 0 then data.Plot.Podiums[podiumId].storedCash += cps end
					end
				end
			end
		end
	end)
end
return Income
