-- Shared non-layout leaderboard constants. All UI geometry is authored in StarterGui.
local LeaderboardConfig = {
	MaxPlayers = 8,
	SortOrder = {"RebirthsDescending", "CatchesDescending", "UsernameAscendingCaseInsensitive"},
	ToggleKey = Enum.KeyCode.Tab,
	PhoneViewportWidth = 800,
	Phone = {
		PanelWidthPixels = 150,
	},
}
return LeaderboardConfig
