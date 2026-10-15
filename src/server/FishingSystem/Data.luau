--[[
	Server-only player data API for Phase 1.
	Public API:
	- Data.Get(player) -> live data table or nil
	- Data.WaitFor(player) -> yields for a loaded table, or nil after failure/leave
	- Data.IsLoaded(player) -> boolean
	- Data.Loaded:Connect(function(player, data) end)
	- Data.Releasing:Connect(function(player, data) end)
	- Data.Template, Data.CurrentVersion, Data.Migrations, Data.StoreName
	- Data.NewUid() -> a new GUID string for unique character records
	Internal lifecycle helpers used only by Bootstrap / DEV_TEST_ONLY:
	- Data.LoadPlayer(player), Data.Release(player, beforeRelease, afterRelease)
	- Data.GetProfile(player), Data.ForceSave(player)
	Studio-only test hook: set this ModuleScript's DEV_TEST_ProfileArrivalDelaySeconds
	attribute to a finite positive number. It is absent/off by default and ignored outside Studio.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signal = require(script.Parent.Signal)
local Plots = require(script.Parent.Plots)
local ProfileStore = require(script.Parent.Dependencies.ProfileStore)
local Config = require(ReplicatedStorage.FishingSystemV2.FishingConfig)
local Rebirths = require(ReplicatedStorage.FishingSystemV2.Rebirths)
local Characters = require(ReplicatedStorage.FishingSystemV2.Characters)

local Data = {}
Data.CurrentVersion = 4
Data.StoreName = "FishAFemRNG_PlayerData_v1"
Data.Loaded = Signal.new()
Data.Releasing = Signal.new()
Data.Migrations = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function buildPodiumDefaults()
	local defaults = {}
	for plotIndex = 1, 8 do
		local plot = Workspace:FindFirstChild("Plot" .. plotIndex)
		if plot and plot:IsA("Model") then
			for podiumId in pairs(Plots.GetPodiums(plot)) do
				if not defaults[podiumId] then
					defaults[podiumId] = {
						unlocked = string.match(podiumId, "^Podium%d+$") ~= nil,
						storedCash = 0,
					}
				end
			end
		end
	end
	return defaults
end

Data.Template = {
	DataVersion = Data.CurrentVersion,
	Cash = 0,
	Gems = 0,
	Rebirths = 0,
	Food = 0,
	PlaytimeSeconds = 0,
	TotalCatches = 0,
	Index = {
		Discovered = {},
		Claimed = {},
	},
	Rods = {
		Owned = {"Steel"},
		Equipped = "Steel",
	},
	Characters = {},
	Hotbar = {},
	ExtraSlots = 0,
	Settings = {
		AutoFish = {
			enabled = false,
			spot = nil,
			target = nil,
		},
	},
	Plot = {
		Podiums = buildPodiumDefaults(),
	},
}

-- Returns a new globally unique string for character records created by server systems.
function Data.NewUid()
	return HttpService:GenerateGUID(false)
end

local PlayerStore = ProfileStore.New(Data.StoreName, Data.Template)
local profiles = {}
local states = {}
local stateEvents = {}
local leftDuringLoad = {}
local warnedMock = false
local warnedUnknownPodiums = {}
local printedMissingPodiums = {}

-- DEV_ONLY_BEGIN ProfileArrivalDelayHook
local function getDevTestProfileArrivalDelaySeconds()
	if not RunService:IsStudio() then
		return 0
	end
	local delaySeconds = script:GetAttribute("DEV_TEST_ProfileArrivalDelaySeconds")
	if type(delaySeconds) == "number"
		and delaySeconds == delaySeconds
		and delaySeconds > 0
		and delaySeconds ~= math.huge then
		return delaySeconds
	end
	return 0
end
-- DEV_ONLY_END ProfileArrivalDelayHook

local function stateEventFor(player)
	if not stateEvents[player] then
		stateEvents[player] = Instance.new("BindableEvent")
	end
	return stateEvents[player]
end

local function publishState(player, state)
	states[player] = state
	local event = stateEvents[player]
	if event then
		event:Fire()
	end
end

local function warnInvalid(player, field)
	warn(("[FishingSystem.Data] Reset invalid %s for UserId %d"):format(field, player.UserId))
end

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function isFiniteNonNegativeNumber(value)
	return isFiniteNumber(value) and value >= 0
end

local function isNonNegativeInteger(value)
	return isFiniteNonNegativeNumber(value) and value % 1 == 0
end

local function sanitizeNumber(player, data, key, integer)
	local value = data[key]
	local valid = integer and isNonNegativeInteger(value) or (not integer and isFiniteNonNegativeNumber(value))
	if not valid then
		warnInvalid(player, key)
		data[key] = Data.Template[key]
	end
end

local function sanitizeRebirths(player, data)
	local value = data.Rebirths
	if not isNonNegativeInteger(value) or value > Rebirths.MaxRebirths then
		warnInvalid(player, "Rebirths")
		data.Rebirths = Data.Template.Rebirths
	end
end

local function sanitizeRods(player, data)
	local rods = data.Rods
	local valid = type(rods) == "table" and type(rods.Owned) == "table"
	if valid then
		for index, rodName in ipairs(rods.Owned) do
			if type(rodName) ~= "string" or rodName == "" or index % 1 ~= 0 then
				valid = false
				break
			end
		end
	end
	if valid then
		valid = type(rods.Equipped) == "string" and table.find(rods.Owned, rods.Equipped) ~= nil
	end
	if not valid then
		warnInvalid(player, "Rods")
		data.Rods = deepCopy(Data.Template.Rods)
	end
end

local function formatIndexes(indexes)
	local labels = table.create(#indexes)
	for position, index in ipairs(indexes) do
		labels[position] = tostring(index)
	end
	return "[" .. table.concat(labels, ", ") .. "]"
end

local function warnCharacterIssue(player, issue, indexes)
	warn(("[FishingSystem.Data] %s: %d issue(s) for UserId %d at indexes %s")
		:format(issue, #indexes, player.UserId, formatIndexes(indexes)))
end

local function sanitizeCharacters(player, data)
	local characters = data.Characters
	if type(characters) ~= "table" then
		warn(("[FishingSystem.Data] Reset Characters list: 1 issue for UserId %d (Characters is not a table)")
			:format(player.UserId))
		data.Characters = {}
		return
	end

	local indexes = {}
	local invalidKeyIndexes = {}
	for key in pairs(characters) do
		if type(key) == "number" and key % 1 == 0 and key >= 1 then
			table.insert(indexes, key)
		else
			table.insert(invalidKeyIndexes, tostring(key))
		end
	end
	table.sort(indexes)

	local sanitized = {}
	local usedUids = {}
	local droppedIndexes = {}
	local repairedUidIndexes = {}
	local removedMutationIndexes = {}

	for _, index in ipairs(indexes) do
		local character = characters[index]
		if type(character) ~= "table" or type(character.id) ~= "string" or character.id == "" then
			table.insert(droppedIndexes, index)
		else
			local uid = character.uid
			if type(uid) ~= "string" or uid == "" or usedUids[uid] then
				repeat
					uid = Data.NewUid()
				until not usedUids[uid]
				table.insert(repairedUidIndexes, index)
			end
			usedUids[uid] = true

			local sanitizedCharacter = {
				uid = uid,
				id = character.id,
			}
			if character.mutation ~= nil then
				if type(character.mutation) == "string" then
					sanitizedCharacter.mutation = character.mutation
				else
					table.insert(removedMutationIndexes, index)
				end
			end
			table.insert(sanitized, sanitizedCharacter)
		end
	end

	if #invalidKeyIndexes > 0 then
		warn(("[FishingSystem.Data] Dropped invalid Characters keys: %d issue(s) for UserId %d at keys [%s]")
			:format(#invalidKeyIndexes, player.UserId, table.concat(invalidKeyIndexes, ", ")))
	end
	if #droppedIndexes > 0 then
		warnCharacterIssue(player, "Dropped Characters entries with missing or invalid id", droppedIndexes)
	end
	if #repairedUidIndexes > 0 then
		warnCharacterIssue(player, "Repaired missing, invalid, or duplicate Character uids", repairedUidIndexes)
	end
	if #removedMutationIndexes > 0 then
		warnCharacterIssue(player, "Removed invalid Character mutations", removedMutationIndexes)
	end

	data.Characters = sanitized
end

local function sanitizePodiumEntry(player, podiumId, entry, defaultEntry)
	if type(entry) ~= "table"
		or type(entry.unlocked) ~= "boolean"
		or (entry.characterUid ~= nil and type(entry.characterUid) ~= "string") then
		warnInvalid(player, "Plot.Podiums." .. podiumId)
		return deepCopy(defaultEntry)
	end
	if not isFiniteNonNegativeNumber(entry.storedCash) then
		warnInvalid(player, "Plot.Podiums." .. podiumId .. ".storedCash")
		entry.storedCash = 0
	end
	return {
		unlocked = entry.unlocked,
		characterUid = entry.characterUid,
		storedCash = entry.storedCash,
	}
end

local function sanitizePlot(player, data)
	if type(data.Plot) ~= "table" then
		warnInvalid(player, "Plot")
		data.Plot = {Podiums = {}}
	end
	if type(data.Plot.Podiums) ~= "table" then
		warnInvalid(player, "Plot.Podiums")
		data.Plot.Podiums = {}
	end

	local podiums = data.Plot.Podiums
	local addedPodiumCount = 0
	for podiumId, defaultEntry in pairs(Data.Template.Plot.Podiums) do
		if podiums[podiumId] == nil then
			podiums[podiumId] = deepCopy(defaultEntry)
			addedPodiumCount += 1
		else
			podiums[podiumId] = sanitizePodiumEntry(player, podiumId, podiums[podiumId], defaultEntry)
		end
	end
	if addedPodiumCount > 0 and not printedMissingPodiums[player.UserId] then
		print(("[FishingSystem.Data] Added %d missing saved podium entr%s for UserId %d")
			:format(addedPodiumCount, addedPodiumCount == 1 and "y" or "ies", player.UserId))
		printedMissingPodiums[player.UserId] = true
	end

	for podiumId in pairs(podiums) do
		if Data.Template.Plot.Podiums[podiumId] == nil then
			warnedUnknownPodiums[player.UserId] = warnedUnknownPodiums[player.UserId] or {}
			if not warnedUnknownPodiums[player.UserId][podiumId] then
				warnedUnknownPodiums[player.UserId][podiumId] = true
				warn(("[FishingSystem.Data] Keeping saved removed podium %q for UserId %d"):format(tostring(podiumId), player.UserId))
			end
		end
	end
end

-- Applies versioned migrations in ascending order before reconciliation.
local function applyMigrations(player, data)
	if not isNonNegativeInteger(data.DataVersion) then
		warnInvalid(player, "DataVersion")
		data.DataVersion = 0
	end
	if data.DataVersion > Data.CurrentVersion then
		warn(("[FishingSystem.Data] Future DataVersion %d for UserId %d; using current schema %d")
			:format(data.DataVersion, player.UserId, Data.CurrentVersion))
		data.DataVersion = Data.CurrentVersion
	end
	while data.DataVersion < Data.CurrentVersion do
		local migration = Data.Migrations[data.DataVersion]
		if migration then
			migration(data)
		end
		if not isNonNegativeInteger(data.DataVersion) or data.DataVersion < 0 then
			data.DataVersion = data.DataVersion + 1
		elseif data.DataVersion < Data.CurrentVersion then
			data.DataVersion += 1
		end
	end
end

Data.Migrations[0] = function(data)
	data.DataVersion = 1
end

-- Adds the Phase 3 Auto Fish preference without changing any existing game data.
Data.Migrations[1] = function(data)
	data.Settings = data.Settings or {
		AutoFish = {
			enabled = false,
			spot = nil,
			target = nil,
		},
	}
	data.DataVersion = 2
end

-- Adds Phase 4 inventory state without deleting or moving character records.
Data.Migrations[2] = function(data)
	if type(data.Hotbar) ~= "table" then data.Hotbar = {} end
	if data.ExtraSlots == nil then data.ExtraSlots = 0 end
	data.DataVersion = 3
end

-- Backfills the Phase 6 Index from currently owned active characters without claiming any entry.
local activeIndexIds = {}
for _, definition in ipairs(Characters.GetActive()) do
	activeIndexIds[definition.id] = true
end
Data.Migrations[3] = function(data)
	if type(data.Index) ~= "table" then data.Index = {} end
	if type(data.Index.Discovered) ~= "table" then data.Index.Discovered = {} end
	if type(data.Index.Claimed) ~= "table" then data.Index.Claimed = {} end
	if type(data.Characters) == "table" then
		for _, entry in ipairs(data.Characters) do
			if type(entry) == "table" and activeIndexIds[entry.id] then
				data.Index.Discovered[entry.id] = true
			end
		end
	end
	data.DataVersion = 4
end

local function isKnownFishingSpot(spot)
	local zone = Workspace:FindFirstChild(spot)
	return zone ~= nil and zone:IsA("BasePart") and string.match(zone.Name, "^FishingPart%d+$") ~= nil
end

local function sanitizeHotbar(player, data)
	if type(data.ExtraSlots) ~= "number" or not isNonNegativeInteger(data.ExtraSlots) then
		warnInvalid(player, "ExtraSlots")
		data.ExtraSlots = 0
	end
	if type(data.Hotbar) ~= "table" then
		warnInvalid(player, "Hotbar")
		data.Hotbar = {}
		return
	end

	local known, placed = {}, {}
	for _, character in ipairs(data.Characters) do
		if type(character) == "table" and type(character.uid) == "string" then known[character.uid] = true end
	end
	for _, podium in pairs(data.Plot.Podiums) do
		if type(podium) == "table" and type(podium.characterUid) == "string" then placed[podium.characterUid] = true end
	end

	local clean, seen = {}, {}
	local badKey, badUid, duplicate = 0, 0, 0
	for index = 1, Config.HotbarSlots do
		local key = tostring(index)
		local uid = data.Hotbar[key]
		if uid ~= nil then
			if type(uid) ~= "string" or not known[uid] or placed[uid] then
				badUid += 1
			elseif seen[uid] then
				duplicate += 1
			else
				clean[key] = uid
				seen[uid] = true
			end
		end
	end
	for key in pairs(data.Hotbar) do
		local numberKey = tonumber(key)
		if type(key) ~= "string" or not numberKey or numberKey % 1 ~= 0 or numberKey < 1 or numberKey > Config.HotbarSlots or tostring(numberKey) ~= key then
			badKey += 1
		end
	end
	if badKey > 0 then warn(("[FishingSystem.Data] Dropped %d invalid Hotbar key(s) for UserId %d"):format(badKey, player.UserId)) end
	if badUid > 0 then warn(("[FishingSystem.Data] Dropped %d invalid, missing, or placed Hotbar uid(s) for UserId %d"):format(badUid, player.UserId)) end
	if duplicate > 0 then warn(("[FishingSystem.Data] Dropped %d duplicate Hotbar uid(s) for UserId %d; kept lowest slot"):format(duplicate, player.UserId)) end
	data.Hotbar = clean
end

local function sanitizeIndex(player, data)
	if type(data.Index) ~= "table" then
		warnInvalid(player, "Index")
		data.Index = {Discovered = {}, Claimed = {}}
		return
	end

	local function sanitizeDictionary(name)
		local source = data.Index[name]
		if type(source) ~= "table" then
			warnInvalid(player, "Index." .. name)
			data.Index[name] = {}
			return data.Index[name]
		end
		local clean, dropped = {}, 0
		for id, value in pairs(source) do
			if type(id) == "string" and id ~= "" and value == true then
				clean[id] = true
			else
				dropped += 1
			end
		end
		if dropped > 0 then
			warn(("[FishingSystem.Data] Dropped %d invalid Index.%s entr%s for UserId %d")
				:format(dropped, name, dropped == 1 and "y" or "ies", player.UserId))
		end
		data.Index[name] = clean
		return clean
	end

	local discovered = sanitizeDictionary("Discovered")
	local claimed = sanitizeDictionary("Claimed")
	local droppedClaims = 0
	for id in pairs(claimed) do
		if not discovered[id] then
			claimed[id] = nil
			droppedClaims += 1
		end
	end
	if droppedClaims > 0 then
		warn(("[FishingSystem.Data] Dropped %d claimed Index id%s not present in Discovered for UserId %d")
			:format(droppedClaims, droppedClaims == 1 and "" or "s", player.UserId))
	end
end

local function sanitizeSettings(player, data)
	if type(data.Settings) ~= "table" then
		warnInvalid(player, "Settings")
		data.Settings = deepCopy(Data.Template.Settings)
		return
	end
	if type(data.Settings.AutoFish) ~= "table" then
		warnInvalid(player, "Settings.AutoFish")
		data.Settings.AutoFish = deepCopy(Data.Template.Settings.AutoFish)
		return
	end

	local autoFish = data.Settings.AutoFish
	if type(autoFish.enabled) ~= "boolean" then
		warnInvalid(player, "Settings.AutoFish.enabled")
		autoFish.enabled = false
	end
	if autoFish.spot ~= nil and (type(autoFish.spot) ~= "string" or not isKnownFishingSpot(autoFish.spot)) then
		warnInvalid(player, "Settings.AutoFish.spot")
		autoFish.spot = nil
	end
	if autoFish.target ~= nil then
		local target = autoFish.target
		if type(target) ~= "table"
			or not isFiniteNumber(target.x)
			or not isFiniteNumber(target.y)
			or not isFiniteNumber(target.z) then
			warnInvalid(player, "Settings.AutoFish.target")
			autoFish.target = nil
		else
			autoFish.target = {x = target.x, y = target.y, z = target.z}
		end
	end
end

-- Sanitizes the complete phase-one schema after migrations and Reconcile.
function Data.Sanitize(player, data)
	sanitizeNumber(player, data, "Cash", false)
	sanitizeNumber(player, data, "Gems", false)
	sanitizeNumber(player, data, "Food", false)
	sanitizeNumber(player, data, "PlaytimeSeconds", false)
	sanitizeNumber(player, data, "TotalCatches", true)
	sanitizeRebirths(player, data)
	if not isNonNegativeInteger(data.DataVersion) then
		warnInvalid(player, "DataVersion")
		data.DataVersion = Data.CurrentVersion
	end
	sanitizeRods(player, data)
	sanitizeCharacters(player, data)
	sanitizeIndex(player, data)
	sanitizeSettings(player, data)
	sanitizePlot(player, data)
	sanitizeHotbar(player, data)
end

-- Returns the live server-only profile data table for player, or nil.
function Data.Get(player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

-- Returns true only after the session-locked profile is loaded and sanitized.
function Data.IsLoaded(player)
	return profiles[player] ~= nil and states[player] == "loaded"
end

-- Waits for loading to finish; returns nil if player left or loading failed.
function Data.WaitFor(player)
	while states[player] == "loading" do
		stateEventFor(player).Event:Wait()
	end
	return Data.Get(player)
end

-- Loads, migrates, reconciles, sanitizes, and publishes a player's profile.
function Data.LoadPlayer(player)
	if Data.IsLoaded(player) then
		return Data.Get(player)
	end
	if states[player] == "loading" then
		return Data.WaitFor(player)
	end

	leftDuringLoad[player] = false
	publishState(player, "loading")

	local profile
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
				Cancel = function()
					return player.Parent ~= Players or leftDuringLoad[player] == true
				end,
			})
		end)
		if ok then
			profile = result
		else
			warn(("[FishingSystem.Data] Profile load attempt %d failed for UserId %d: %s")
				:format(attempt, player.UserId, tostring(result)))
		end
		if profile then
			break
		end
		task.wait(0.5)
	end

	if not profile then
		publishState(player, "failed")
		if player.Parent == Players then
			player:Kick("Could not load your data. Please rejoin.")
		end
		return nil
	end

	-- DEV_ONLY_BEGIN ProfileArrivalDelayWait
	local delaySeconds = getDevTestProfileArrivalDelaySeconds()
	if delaySeconds > 0 then
		task.wait(delaySeconds)
	end
	-- DEV_ONLY_END ProfileArrivalDelayWait

	if player.Parent ~= Players or leftDuringLoad[player] then
		profile:EndSession()
		publishState(player, "left")
		return nil
	end

	profile:AddUserId(player.UserId)
	applyMigrations(player, profile.Data)
	profile:Reconcile()
	Data.Sanitize(player, profile.Data)

	profiles[player] = profile
	publishState(player, "loaded")

	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" and not warnedMock then
		warnedMock = true
		warn(("[FishingSystem.Data] DataStore access is %s; ProfileStore is using its Studio mock store. Enable Studio API Services to test persistence.")
			:format(ProfileStore.DataStoreState))
	end

	Data.Loaded:Fire(player, profile.Data)
	return profile.Data
end

-- Releases a loaded profile. beforeRelease runs after Data.Releasing and before EndSession;
-- afterRelease runs after EndSession, allowing Bootstrap to clear the assigned plot in order.
function Data.Release(player, beforeRelease, afterRelease)
	local profile = profiles[player]
	if not profile then
		if states[player] == "loading" then
			leftDuringLoad[player] = true
		end
		return false
	end

	publishState(player, "releasing")
	local liveData = profile.Data
	Data.Releasing:Fire(player, liveData)
	if beforeRelease then
		beforeRelease(player, liveData)
	end

	profiles[player] = nil
	profile:EndSession()

	if afterRelease then
		afterRelease(player, liveData)
	end
	publishState(player, "released")
	return true
end

-- DEV_ONLY_BEGIN GetProfile
-- Returns the ProfileStore profile for Studio-only diagnostics, or nil.
function Data.GetProfile(player)
	return profiles[player]
end
-- DEV_ONLY_END GetProfile

-- Immediately saves an active profile; DEV_TEST_ONLY is the only caller.
function Data.ForceSave(player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
		return true
	end
	return false
end

-- DEV_ONLY_BEGIN RunMigrationsForTest
-- Runs the normal migration/reconcile/sanitize sequence for Studio diagnostics.
function Data.RunMigrationsForTest(player, data)
	applyMigrations(player, data)
	local profile = profiles[player]
	if profile then
		profile:Reconcile()
	end
	Data.Sanitize(player, data)
end
-- DEV_ONLY_END RunMigrationsForTest

return Data
