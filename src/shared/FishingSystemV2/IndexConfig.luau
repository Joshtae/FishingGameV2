-- Shared Phase 6 Index tuning. Keep every Index number in this module.
local IndexConfig = {}

IndexConfig.LuckPerClaim = 0.25
IndexConfig.IndexDiscoveryGems = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
IndexConfig.ClaimRateLimitPerSecond = 5
IndexConfig.SnapshotMaxPerSecond = 10
IndexConfig.MaxIdLength = 64
IndexConfig.EntryBuildBatch = 20
IndexConfig.DiscoveryToastSeconds = 2

return IndexConfig
