local createTraffic = require("../traffic")
local createKillCount = require("../active-trackers/kill-count")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(callbacks) do callback(...) end
		end,
	}
end

local function player(id, dead)
	local changed = signal()
	local humanoid = {Died = signal()}
	local character = {ChildAdded = signal()}
	function character:FindFirstChildOfClass() return humanoid end
	local object = {
		UserId = id,
		Dead = dead,
		Changed = changed,
		Character = character,
		CharacterAdded = signal(),
		Humanoid = humanoid,
	}
	function object:GetAttribute(name) return name == "Dead" and self.Dead or nil end
	function object:GetAttributeChangedSignal() return self.Changed end
	function object:SetDead(value)
		if self.Dead == value then return end
		self.Dead = value
		self.Changed:Fire()
	end
	return object
end

local alive, initiallyDead = player(1, false), player(2, true)
local Players = {List = {alive, initiallyDead}, PlayerAdded = signal(), PlayerRemoving = signal()}
function Players:GetPlayers() return self.List end

local Traffic = createTraffic()
local deaths, revenantDeaths = {}, {}
Traffic:Receive("SpeedTracker", function(signalName, payload)
	if signalName == "PlayerKilled" then table.insert(deaths, payload) end
end)
Traffic:Receive("Revenant", function(signalName, payload)
	if signalName == "PlayerKilled" then table.insert(revenantDeaths, payload) end
end)
local tracker = createKillCount({Traffic = Traffic, Players = Players})

expect(#tracker.Alive == 1 and tracker.Alive[1] == 1, "alive players should initialize once")
expect(#tracker.Dead == 1 and tracker.Dead[1] == 2, "initial dead players should be remembered")
expect(#deaths == 0, "initial dead players must not emit a kill")

alive.Humanoid.Died:Fire()
alive:SetDead(true)
expect(#deaths == 1 and deaths[1].userId == 1 and type(deaths[1].Time) == "number",
	"Humanoid.Died should emit immediately and the later Dead attribute should not duplicate it")
expect(#revenantDeaths == 1 and revenantDeaths[1] == deaths[1]
	and revenantDeaths[1].PlayerCount == 2,
	"the same multiplayer kill event should reach Revenant and SpeedTracker")
alive:SetDead(false)
alive:SetDead(true)
expect(#deaths == 1, "a revived player's later death must not emit again")

tracker:Destroy()
print("kill-count.spec: unique alive and dead player tracking passed")
