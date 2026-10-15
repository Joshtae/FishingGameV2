-- Starts isolated R3 display and navigation services without changing earlier bootstraps.
local root = script.Parent
require(root.ClaimDisplayService).Start()
require(root.NavigationService).Start()
