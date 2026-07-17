local createLobbyAutomation = require("../lobby-automation")

local calls, dispatchTimes, now = {}, {}, 0
local state = {
	JobSite = "Prison",
	Difficulty = "Nightmare",
	Challenges = {false, false, true},
	Ready = false,
}
local remotes = {}
local observers = {}
function remotes:Get(name)
	if name == "UpdateJobSite" or name == "UpdateDifficulty"
		or name == "UpdateAllCustomDifficultySettings" then
		return {
			Connect = function(callback)
				observers[name] = callback
				return {Disconnect = function() observers[name] = nil end}
			end,
			Signal = function(value)
				table.insert(calls, name .. ":" .. tostring(value))
			end,
		}
	end
	return function(value)
		table.insert(calls, name .. (value ~= nil and ":" .. tostring(value) or ""))
		table.insert(dispatchTimes, now)
		if name == "ChangeJobSite" then
			state.JobSite = value
			if observers.UpdateJobSite then observers.UpdateJobSite(value) end
		end
		if name == "ChangeDifficulty" then
			state.Difficulty = "Custom"
			if observers.UpdateDifficulty then observers.UpdateDifficulty("Custom") end
		end
		if name == "ApplyDifficultyPreset" and observers.UpdateAllCustomDifficultySettings then
			observers.UpdateAllCustomDifficultySettings({Applied = 1, GhostWalkSpeedMultiplier = 6}, 2.47)
		end
		if name == "ToggleChallenge" then state.Challenges[value] = not state.Challenges[value] end
		if name == "ChangeStatus" then state.Ready = not state.Ready end
	end
end
local player = {
	GetAttribute = function(_, name)
		if name == "IsReady" then return state.Ready end
	end,
}
local SettingsApi = {
	ReadCustomPresets = function() return {"john4"} end,
	ReadEquipmentPresets = function() return {"green"} end,
	CustomDifficultyMatches = function(_, payload) return payload.Applied == 1 end,
	ChallengeStatesMatch = function(current, wanted)
		for index = 1, 3 do if current[index] ~= wanted[index] then return false end end
		return true
	end,
}
local view = {
	SetStatus = function() end,
	SetBusy = function() end,
}
local settings = {
	Auto = true,
	JobSite = "School",
	Difficulty = "Custom",
	CustomPreset = "john4",
	EquipmentPreset = "green",
	Challenges = {true, false, true},
	ChallengesConfigured = true,
}
local controller = createLobbyAutomation({
	Player = player,
	Remotes = remotes,
	LobbySettings = SettingsApi,
	Settings = settings,
	View = view,
	PrepareTeleport = function(context)
		table.insert(calls, "Queue:" .. context)
		return true
	end,
	ReadSelectedJobSite = function() return state.JobSite, true end,
	ReadSelectedDifficulty = function() return state.Difficulty, true end,
	ReadChallengeStates = function() return table.clone(state.Challenges) end,
	CustomDifficultyMatches = function(payload) return payload.Applied == 1 end,
	Wait = function(seconds) now += seconds end,
	Clock = function() return now end,
	Spawn = function(callback) callback() end,
})

assert(controller:Start(false, true), "manual lobby start should run")
assert(table.concat(calls, ",") == table.concat({
	"LoadingFinished", "ChangeJobSite:School", "ChangeDifficulty:Plus",
	"UpdateDifficulty:Custom", "ApplyDifficultyPreset:john4",
	"ApplyEquipmentPreset:green", "ToggleChallenge:1", "ChangeStatus",
	"Queue:AttemptStart", "AttemptStart",
}, ","), "confirmed lobby sequence changed: " .. table.concat(calls, ","))
assert(state.JobSite == "School" and state.Difficulty == "Custom" and state.Ready,
	"final lobby state did not match the saved settings")
assert(dispatchTimes[1] >= 4.75, "the first lobby remote skipped the four-second grace or 0.75 delay")
for index = 2, #dispatchTimes do
	assert(dispatchTimes[index] - dispatchTimes[index - 1] >= 0.75,
		"lobby server remotes were dispatched less than 0.75 seconds apart")
end

print("lobby-automation.spec: confirmed prior lobby sequence and handoff order passed")
