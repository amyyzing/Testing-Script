local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSpeedFilter = require("../filter/speed-filter")
local createWendigoSpeed = require("../dormant-trackers/wendigo-speed")
local Wendigo = require("../ghosts/Wendigo")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function harness(energies, mapSize, speed)
	local players = {}
	for _, energy in ipairs(energies) do
		table.insert(players, {GetAttribute = function(_, name)
			return name == "Energy" and energy or nil
		end})
	end
	local Players = {GetPlayers = function() return players end}
	local Map = {GetAttribute = function(_, name)
		return name == "MapSize" and mapSize or nil
	end}
	local World = {FindFirstChild = function(_, name) return name == "Map" and Map or nil end}
	local Humanoid = {WalkSpeed = speed}
	local delayed = {}
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local processor = Wendigo.new({Traffic = Traffic})
	local filter = createSpeedFilter({Traffic = Traffic, Workspace = World})
	local tracker = createWendigoSpeed({
		Traffic = Traffic,
		Players = Players,
		Humanoid = Humanoid,
		DelayTask = function(_, callback) table.insert(delayed, callback) end,
	})
	local result = {
		Traffic = Traffic,
		Verdict = Verdict,
		Humanoid = Humanoid,
		RunDelayed = function()
			local pending = delayed
			delayed = {}
			for _, callback in ipairs(pending) do callback() end
		end,
	}
	function result:Destroy()
		tracker:Destroy()
		filter:Destroy()
		processor:Destroy()
	end
	return result
end

local startup = harness({100, 100}, "Small", 9 * 1.75)
startup.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 0})
expect(startup.Verdict.Confidence[23] == nil, "startup speed should wait for replication settling")
startup.RunDelayed()
expect(startup.Verdict.Confidence[23] == 99,
	"execution during non-hunting should match 100 Energy to base 9 with the 175 percent state factor")
startup:Destroy()

local hunting = harness({20, 60}, "Medium", 12 * 1.05 * 2)
hunting.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 10})
hunting.RunDelayed()
expect(hunting.Verdict.Confidence[23] == 99,
	"average Energy 40 should map to base 12 and accept a configured hunting multiplier")
hunting:Destroy()

local rejected = harness({0}, "Small", 11)
rejected.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 20})
rejected.RunDelayed()
expect(table.find(rejected.Verdict.RuledOut, 23),
	"Energy 0 should expect base 14 and reject an impossible hunting speed")
rejected:Destroy()

print("wendigo.spec: startup and hunt-state linear Energy speed checks passed")
