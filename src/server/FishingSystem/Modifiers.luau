--[[ Server-side Phase 3 modifiers. Upgrade, potion, event, and EXE systems extend these stubs later. ]]
-- DEV_ONLY_BEGIN DevToggleSupport
local RunService = game:GetService("RunService")
local toggles = {}
-- DEV_ONLY_END DevToggleSupport
local Modifiers = {}
local indexService

-- Resolves IndexService only on first use to keep module initialization acyclic.
function Modifiers.GetLuckMultiplier(player)
	if not indexService then
		indexService = require(script.Parent.IndexService)
	end
	return indexService.GetIndexLuck(player)
end
function Modifiers.GetCastLuck(player) return Modifiers.GetLuckMultiplier(player) end
function Modifiers.HasFasterReel(player) return toggles[player] and toggles[player].fasterreel == true or false end
function Modifiers.HasAutoFish(player) return toggles[player] and toggles[player].autofish == true or false end
function Modifiers.ReelPotionMult(_player) return 1 end
function Modifiers.EventReelMult() return 1 end
-- DEV_ONLY_BEGIN SetDevToggleAndClear
function Modifiers.SetDevToggle(player, name, enabled)
	if not RunService:IsStudio() or (name ~= "fasterreel" and name ~= "autofish") then return false end
	toggles[player] = toggles[player] or {}
	toggles[player][name] = enabled == true
	return true
end
function Modifiers.Clear(player) toggles[player] = nil end
-- DEV_ONLY_END SetDevToggleAndClear
return Modifiers
