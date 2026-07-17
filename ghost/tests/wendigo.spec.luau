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
	local display = {}
	local Traffic = createTraffic()
	Traffic:Receive("SpeedArrayLog", function(signal, payload)
		if signal ~= "WendigoEnergySnapshot" and signal ~= "WendigoSpeedSample" then return end
		table.insert(display, {Signal = signal, Payload = payload})
	end)
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
		Display = display,
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

local startup = harness({100, 100}, "Small", 9 * 2)
startup.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 0})
expect(startup.Verdict.Confidence[23] == nil, "startup speed should wait for replication settling")
expect(#startup.Display == 1
	and startup.Display[1].Signal == "WendigoEnergySnapshot"
	and startup.Display[1].Payload.AverageEnergy == 100,
	"the Energy level should be snapshotted immediately at the state transition")
startup.RunDelayed()
expect(startup.Verdict.Confidence[23] == 99,
	"execution during non-hunting should match 100 Energy to base 9 with a configured multiplier")
expect(#startup.Display == 2
	and startup.Display[2].Signal == "WendigoSpeedSample"
	and startup.Display[2].Payload.Speed == 18,
	"the settled state speed should be logged after its Energy snapshot")
startup:Destroy()

local zeroEnergy = harness({0}, "Small", 28)
zeroEnergy.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 5})
zeroEnergy.RunDelayed()
expect(zeroEnergy.Verdict.Confidence[23] == 99,
	"0 Energy and WalkSpeed 28 should match base 14 at the configured 200 percent multiplier")
zeroEnergy:Destroy()

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
