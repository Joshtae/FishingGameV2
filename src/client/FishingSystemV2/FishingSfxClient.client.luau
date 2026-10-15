-- Client-only Phase 4 fishing verdict SFX. The server decides every Hit, Miss, and session type.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local shared = ReplicatedStorage:WaitForChild("FishingSystemV2")
local Config = require(shared.SfxConfig)
local Remotes = shared:WaitForChild("Remotes")
local sounds = shared:WaitForChild("Sounds")
local hit = sounds:WaitForChild("HitSfx")
local miss = sounds:WaitForChild("MissSfx")
local bite = sounds:WaitForChild("BiteSfx")
local currentSession

local function play(sound, volume, speed)
	if sound.SoundId == "" then return end
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	SoundService:PlayLocalSound(sound)
end

Remotes.CastAccepted.OnClientEvent:Connect(function(sessionId, _, auto)
	if type(sessionId) == "string" then
		currentSession = {id = sessionId, auto = auto == true}
	end
end)

Remotes.CastResult.OnClientEvent:Connect(function(data)
	if currentSession and type(data) == "table" and data.sessionId == currentSession.id and not currentSession.auto then
		play(bite, Config.SfxHitVolume, 1)
	end
end)

Remotes.PressResult.OnClientEvent:Connect(function(data)
	if not currentSession or type(data) ~= "table" or data.sessionId ~= currentSession.id or currentSession.auto then return end
	if data.result == "Hit" then
		local hits = type(data.hits) == "number" and data.hits or 1
		play(hit, Config.SfxHitVolume, math.min(1 + Config.SfxHitPitchStep * (hits - 1), Config.SfxHitPitchMax))
	elseif data.result == "Miss" then
		play(miss, Config.SfxMissVolume, 1)
	end
end)

Remotes.SessionEnd.OnClientEvent:Connect(function(sessionId)
	if currentSession and currentSession.id == sessionId then currentSession = nil end
end)
