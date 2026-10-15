-- Server-owned R4 playtime accrual and overhead player-tag presentation.
-- Public API: Start() initializes lifecycle listeners; RefreshPlayer(player) refreshes a loaded player's attribute and tag.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent
local Data = require(root.Data)
local Config = require(ReplicatedStorage.FishingSystemV2.OverheadTagConfig)
local template = ReplicatedStorage.FishingSystemV2.OverheadTagTemplate

local PlaytimeService = {}
local started = false
local states = {}

local function finiteNonNegative(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
end

local function updateTag(player, data)
	local state = states[player]
	if not state or state.releasing then return end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local tag = head:FindFirstChild("OverheadTag")
	if not tag then
		tag = template:Clone()
		tag.Name = "OverheadTag"
		tag.Adornee = head
		tag.Parent = head
	end
	local playtime = tag:FindFirstChild("Playtime")
	local username = tag:FindFirstChild("Username")
	local loaded = data ~= nil and Data.Get(player) == data and Data.IsLoaded(player)
	local playtimeText = loaded and Config.FormatPlaytime(data.PlaytimeSeconds) or ""
	local usernameText = "@" .. player.Name
	if playtime and playtime:IsA("TextLabel") and playtime.Text ~= playtimeText then
		playtime.Text = playtimeText
	end
	if username and username:IsA("TextLabel") and username.Text ~= usernameText then
		username.Text = usernameText
	end
end

local function watchCharacter(player, character)
	task.defer(function()
		if character.Parent and states[player] then
			updateTag(player, states[player].data)
		end
	end)
end

local function ensureState(player)
	local state = states[player]
	if state then return state end
	state = {loaded = false, releasing = false, data = nil, lastAt = nil}
	state.characterConnection = player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	states[player] = state
	if player.Character then
		watchCharacter(player, player.Character)
	end
	return state
end

local function markLoaded(player, data)
	if player.Parent ~= Players or not finiteNonNegative(data.PlaytimeSeconds) then return end
	local state = ensureState(player)
	if state.releasing then return end
	if state.loaded and state.data == data then
		player:SetAttribute("Playtime", data.PlaytimeSeconds)
		updateTag(player, data)
		return
	end
	state.loaded = true
	state.data = data
	state.lastAt = os.clock()
	player:SetAttribute("Playtime", data.PlaytimeSeconds)
	updateTag(player, data)
end

local function accrue(player, state, data, now)
	if not state.loaded or state.releasing or state.data ~= data or not finiteNonNegative(data.PlaytimeSeconds) then
		return false
	end
	local elapsed = now - (state.lastAt or now)
	if not finiteNonNegative(elapsed) then
		state.lastAt = now
		return false
	end
	if elapsed > 0 then
		data.PlaytimeSeconds += elapsed
	end
	state.lastAt = now
	player:SetAttribute("Playtime", data.PlaytimeSeconds)
	updateTag(player, data)
	return true
end

local function releaseState(player)
	local state = states[player]
	if not state then return end
	if state.characterConnection then
		state.characterConnection:Disconnect()
	end
	states[player] = nil
end

-- Refreshes only a live, loaded profile. DEV_TEST_ONLY uses this after changing its own test value.
function PlaytimeService.RefreshPlayer(player)
	local state = states[player]
	local data = Data.Get(player)
	if not state or not state.loaded or state.releasing or not data or state.data ~= data then
		return false
	end
	if not finiteNonNegative(data.PlaytimeSeconds) then
		return false
	end
	player:SetAttribute("Playtime", data.PlaytimeSeconds)
	updateTag(player, data)
	return true
end

function PlaytimeService.Start()
	if started then return end
	started = true

	local function watchPlayer(player)
		ensureState(player)
		local data = Data.Get(player)
		if data and Data.IsLoaded(player) then
			markLoaded(player, data)
		else
			updateTag(player, nil)
		end
	end

	Data.Loaded:Connect(markLoaded)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	Data.Releasing:Connect(function(player, data)
		local state = states[player]
		if state and state.loaded and state.data == data then
			accrue(player, state, data, os.clock())
			state.releasing = true
		end
		releaseState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			local state = states[player]
			if state and not state.loaded then
				releaseState(player)
			end
		end)
	end)

	task.spawn(function()
		while started do
			task.wait(Config.PlaytimeTickSeconds)
			local now = os.clock()
			for player, state in pairs(states) do
				local data = Data.Get(player)
				if data and Data.IsLoaded(player) and state.data == data then
					accrue(player, state, data, now)
				end
			end
		end
	end)
end

return PlaytimeService
