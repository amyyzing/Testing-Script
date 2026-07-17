local createLobbyAutomation = require("../lobby-automation")

local calls = {}
local ready = false
local remotes = {}
function remotes:Get(name)
	return function(...)
		local arguments = {...}
		table.insert(calls, name .. (arguments[1] and ":" .. tostring(arguments[1]) or ""))
		if name == "ChangeStatus" then ready = true end
	end
end
local player = {
	GetAttribute = function(_, name)
		if name == "IsReady" then return ready end
		return nil
	end,
	FindFirstChildOfClass = function() return nil end,
}
local controller = createLobbyAutomation({
	Player = player,
	Remotes = remotes,
	PrepareTeleport = function(context)
		table.insert(calls, "Queue:" .. context)
		return true
	end,
	ReadJobSite = function() return "School" end,
	ReadDifficulty = function() return "Custom" end,
	Wait = function() end,
	Spawn = function(callback) callback() end,
})

controller:SetEnabled(true, true)
assert(table.concat(calls, ",") == table.concat({
	"LoadingFinished", "ApplyDifficultyPreset:john4", "ApplyEquipmentPreset:green",
	"ChangeStatus", "Queue:AttemptStart", "AttemptStart",
}, ","), "lobby macro order changed or toggled the selected Job Site: " .. table.concat(calls, ","))

print("lobby-automation.spec: return handshake, settings, ready check, and start order passed")
