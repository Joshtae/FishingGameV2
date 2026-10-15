-- Starts the Phase 6 server-authoritative Index without changing earlier bootstraps.
local root = script.Parent
local Inventory = require(root.Inventory)
require(root.IndexService).Start(Inventory.CharacterAdded)
