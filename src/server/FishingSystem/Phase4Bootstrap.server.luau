-- Starts Phase 4 server-authoritative inventory replication and held-character cleanup.
local root = script.Parent
require(root.InventoryController).Start()
