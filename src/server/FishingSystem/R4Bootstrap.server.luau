-- Starts the isolated R4 playtime/tag service without altering earlier bootstraps.
local root = script.Parent
require(root.PlaytimeService).Start()
