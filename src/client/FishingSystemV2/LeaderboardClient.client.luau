-- Client-only leaderboard presentation. It reads server-written attributes and never writes player data.
-- All leaderboard geometry lives in StarterGui. See applyApprovedExceptions for the two approved runtime layout exceptions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local warnedPaths = {}
local function warnMissing(path)
	if warnedPaths[path] then return end
	warnedPaths[path] = true
	warn("[FishingSystemV2.Leaderboard] Missing UI after 10 seconds: " .. path)
end

local function waitForChild(parent, name, path)
	if not parent then
		warnMissing(path)
		return nil
	end
	local child = parent:WaitForChild(name, 10)
	if not child then
		warnMissing(path)
	end
	return child
end

-- Run before any leaderboard UI lookup so Roblox's player list cannot reappear because of a later UI rename.
local function hideDefaultPlayerList()
	task.spawn(function()
		for _ = 1, 15 do
			if pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end) then
				return
			end
			task.wait(0.2)
		end
		warn("[FishingSystemV2.Leaderboard] Could not disable the default Roblox player list.")
	end)
end

hideDefaultPlayerList()

local player = Players.LocalPlayer
if not player then
	warnMissing("Players.LocalPlayer")
	return
end

local playerGui = waitForChild(player, "PlayerGui", "Players." .. player.Name .. ".PlayerGui")
local shared = waitForChild(ReplicatedStorage, "FishingSystemV2", "ReplicatedStorage.FishingSystemV2")
if not playerGui or not shared then return end

local configModule = waitForChild(shared, "LeaderboardConfig", "ReplicatedStorage.FishingSystemV2.LeaderboardConfig")
local numberFormatModule = waitForChild(shared, "NumberFormat", "ReplicatedStorage.FishingSystemV2.NumberFormat")
if not configModule or not numberFormatModule then return end

local Config = require(configModule)
local NumberFormat = require(numberFormatModule)
local gui = waitForChild(playerGui, "FishingSystemV2Leaderboard", playerGui:GetFullName() .. ".FishingSystemV2Leaderboard")
local panel = waitForChild(gui, "LeaderboardPanel", "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel")
local content = waitForChild(panel, "LeaderboardContent", "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel.LeaderboardContent")
local header = waitForChild(content, "HeaderToggle", "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel.LeaderboardContent.HeaderToggle")
local headerHitArea = waitForChild(header, "HeaderHitArea", "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel.LeaderboardContent.HeaderToggle.HeaderHitArea")
local list = waitForChild(content, "Players", "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel.LeaderboardContent.Players")
local widthConstraint = waitForChild(panel, "PanelWidthConstraint", "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel.PanelWidthConstraint")
if not gui or not panel or not content or not header or not headerHitArea or not list or not widthConstraint then return end

local rowNames = {"Row1", "Row2", "Row3", "Row4", "Row5", "Row6", "Row7", "Row8"}
local rows = {}
for _, name in ipairs(rowNames) do
	local rowPath = "PlayerGui.FishingSystemV2Leaderboard.LeaderboardPanel.LeaderboardContent.Players." .. name
	local row = waitForChild(list, name, rowPath)
	local avatarFrame = waitForChild(row, "AvatarFrame", rowPath .. ".AvatarFrame")
	local avatar = waitForChild(avatarFrame, "Avatar", rowPath .. ".AvatarFrame.Avatar")
	local username = waitForChild(row, "Username_TextLabel", rowPath .. ".Username_TextLabel")
	local rebirths = waitForChild(row, "RebirthsAmount_TextLabel", rowPath .. ".RebirthsAmount_TextLabel")
	local catches = waitForChild(row, "CatchesAmount_TextLabel", rowPath .. ".CatchesAmount_TextLabel")
	if row and avatar and username and rebirths and catches then
		rows[#rows + 1] = {
			frame = row,
			avatar = avatar,
			username = username,
			rebirths = rebirths,
			catches = catches,
		}
	end
end

local connections = {}
local thumbnailCache = {}
local thumbnailPending = {}
local rowByPlayer = {}
local rowFillWarnings = {}
local state = {
	collapsed = false,
	preview = false,
}

local function setText(label, shadowName, value)
	local text = tostring(value)
	label.Text = text
	local shadow = label.Parent:FindFirstChild(shadowName)
	if shadow then
		shadow.Text = text
	end
end

local function attributeInteger(target, name)
	local value = target:GetAttribute(name)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 or value % 1 ~= 0 then
		return 0
	end
	return value
end

local function sortPlayers(a, b)
	local rebirthA, rebirthB = attributeInteger(a, "Rebirths"), attributeInteger(b, "Rebirths")
	if rebirthA ~= rebirthB then return rebirthA > rebirthB end
	local catchesA, catchesB = attributeInteger(a, "Catches"), attributeInteger(b, "Catches")
	if catchesA ~= catchesB then return catchesA > catchesB end
	local lowerA, lowerB = string.lower(a.Name), string.lower(b.Name)
	if lowerA ~= lowerB then return lowerA < lowerB end
	return a.Name < b.Name
end

local function visiblePlayers()
	local ordered = Players:GetPlayers()
	table.sort(ordered, sortPlayers)
	return ordered
end

local function requestThumbnail(target, row)
	local cached = thumbnailCache[target.UserId]
	if cached then
		row.avatar.Image = cached
		return
	end
	if thumbnailPending[target.UserId] then return end
	thumbnailPending[target.UserId] = true
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(target.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		thumbnailPending[target.UserId] = nil
		if ok and type(content) == "string" and content ~= "" then
			thumbnailCache[target.UserId] = content
			if rowByPlayer[target] == row and row.frame.Parent then
				row.avatar.Image = content
			end
		end
	end)
end

local function updateRow(target, row)
	setText(row.username, "UsernameShadow", "@" .. target.Name)
	setText(row.rebirths, "RebirthsAmountShadow", attributeInteger(target, "Rebirths"))
	setText(row.catches, "CatchesAmountShadow", NumberFormat.Format(attributeInteger(target, "Catches")))
	requestThumbnail(target, row)
end

local function fillPreviewRow(row, index)
	setText(row.username, "UsernameShadow", "@Sample" .. index)
	setText(row.rebirths, "RebirthsAmountShadow", 250 - index)
	setText(row.catches, "CatchesAmountShadow", NumberFormat.Format(index * 1250))
	row.avatar.Image = ""
end

local function warnRowFill(target, err)
	local key = tostring(target.UserId) .. ":" .. tostring(err)
	if rowFillWarnings[key] then return end
	rowFillWarnings[key] = true
	warn("[FishingSystemV2.Leaderboard] Could not fill row for " .. target.Name .. ": " .. tostring(err))
end

local function refreshRows()
	table.clear(rowByPlayer)
	local ordered = visiblePlayers()
	for index, row in ipairs(rows) do
		local target = not state.preview and ordered[index] or nil
		if target then
			local ok, err = pcall(function()
				rowByPlayer[target] = row
				updateRow(target, row)
				row.frame.Visible = true
			end)
			if not ok then
				rowByPlayer[target] = nil
				row.frame.Visible = false
				warnRowFill(target, err)
			end
		elseif state.preview then
			fillPreviewRow(row, index)
			row.frame.Visible = true
		else
			row.frame.Visible = false
		end
	end
end

local function disconnectPlayer(target)
	local targetConnections = connections[target]
	if targetConnections then
		for _, connection in ipairs(targetConnections) do
			connection:Disconnect()
		end
		connections[target] = nil
	end
end

local function trackPlayer(target)
	if connections[target] then return end
	connections[target] = {
		target:GetAttributeChangedSignal("Rebirths"):Connect(refreshRows),
		target:GetAttributeChangedSignal("Catches"):Connect(refreshRows),
	}
	refreshRows()
end

local function untrackPlayer(target)
	disconnectPlayer(target)
	refreshRows()
end

local function isPhone()
	return UserInputService.TouchEnabled and gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.X < Config.PhoneViewportWidth
end

local function setCollapsed(value)
	state.collapsed = value == true
	list.Visible = not state.collapsed
end

local function toggleCollapsed()
	setCollapsed(not state.collapsed)
end

-- The only runtime geometry changes: below-nav clearance and the phone width preset.
local function applyApprovedExceptions()
	local viewport = gui.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end

	if isPhone() then
		widthConstraint.MinSize = Vector2.new(Config.Phone.PanelWidthPixels, widthConstraint:GetAttribute("R6PhoneMinHeight") or 38.25)
		widthConstraint.MaxSize = Vector2.new(Config.Phone.PanelWidthPixels, 10000)
	end

	task.defer(function()
		if not panel.Parent or gui.AbsoluteSize.Y <= 0 then return end
		local authoredY = panel:GetAttribute("R6AuthoredYScale") or 0.0074074
		local newY = authoredY
		local topFrames = playerGui:FindFirstChild("TopFrames")
		local topNav = topFrames and topFrames:FindFirstChild("OverallTopFrame")
		if topNav and topNav:IsA("GuiObject") and topNav.Visible then
			local panelLeft = panel.AbsolutePosition.X
			local panelRight = panelLeft + panel.AbsoluteSize.X
			local navLeft = topNav.AbsolutePosition.X
			local navRight = navLeft + topNav.AbsoluteSize.X
			if panelLeft < navRight and panelRight > navLeft then
				newY = (topNav.AbsolutePosition.Y + topNav.AbsoluteSize.Y + 8) / gui.AbsoluteSize.Y
			end
		end
		panel.Position = UDim2.fromScale(panel.Position.X.Scale, newY)
	end)
end

headerHitArea.Activated:Connect(toggleCollapsed)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Config.ToggleKey then
		panel.Visible = not panel.Visible
	end
end)

for _, target in ipairs(Players:GetPlayers()) do
	trackPlayer(target)
end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(untrackPlayer)

-- DEV_ONLY_BEGIN LeaderboardPreview
local function refreshPreview()
	state.preview = RunService:IsStudio() and Workspace:GetAttribute("R6LeaderboardPreview") == true
	refreshRows()
end

if RunService:IsStudio() then
	Workspace:GetAttributeChangedSignal("R6LeaderboardPreview"):Connect(refreshPreview)
	task.defer(refreshPreview)
end
-- DEV_ONLY_END LeaderboardPreview

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyApprovedExceptions)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TopFrames" then
		task.defer(applyApprovedExceptions)
	end
end)

state.collapsed = isPhone()
setCollapsed(state.collapsed)
refreshRows()
task.defer(applyApprovedExceptions)
