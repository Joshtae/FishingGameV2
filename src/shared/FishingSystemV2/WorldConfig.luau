-- Shared R3 world and navigation tuning. Clients may read these values; the server remains authoritative.
local WorldConfig = {
	PodiumLabelShowDistance = 20,
	PodiumLabelScanSeconds = 0.2,
	ClaimDisplayRefreshSeconds = 0.5,
	NavigateCooldownSeconds = 1.0,
	NavigateRateLimit = 2,
	SpawnHeightOffset = 3,
	SandCrowdRadius = 15,
	PlotSpawnWaitSeconds = 10,
}

return WorldConfig
