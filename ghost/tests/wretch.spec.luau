local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSpeedFilter = require("../filter/speed-filter")
local createWretchSpeed = require("../dormant-trackers/wretch-speed")
local Wretch = require("../ghosts/Wretch")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function harness(energies, mapSize, speed, unknown)
	local players = {}
	for index in ipairs(energies) do
		table.insert(players, {GetAttribute = function(_, name)
			return name == "Energy" and energies[index] or nil
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
		if signal ~= "WretchEnergySnapshot" and signal ~= "WretchSpeedSample" then return end
		table.insert(display, {Signal = signal, Payload = payload})
	end)
	local Verdict = createVerdict({Traffic = Traffic})
	local processor = Wretch.new({Traffic = Traffic})
	local filter = createSpeedFilter({Traffic = Traffic, Workspace = World, ReadScale = function() return {Known = not unknown, CustomMultiplier = not unknown and 2 or nil} end})
	local tracker = createWretchSpeed({
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
			for _ = 1, 4 do
				local pending = delayed
				delayed = {}
				for _, callback in ipairs(pending) do callback() end
			end
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
startup.RunDelayed()
expect(startup.Verdict.Confidence[23] == nil and #startup.Display == 0,
	"the initial non-hunting state should only establish a baseline")
startup.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 1})
expect(#startup.Display == 1
	and startup.Display[1].Signal == "WretchEnergySnapshot"
	and startup.Display[1].Payload.AverageEnergy == 100,
	"the first transition into hunting should start Energy tracking")
startup.RunDelayed()
expect(startup.Verdict.Confidence[23] == 35,
	"one speed match with an inferred multiplier should only offer weak support")
expect(#startup.Display == 2
	and startup.Display[2].Signal == "WretchSpeedSample"
	and startup.Display[2].Payload.Speed == 18,
	"the settled state speed should be logged after its Energy snapshot")
startup.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 2})
startup.RunDelayed()
expect(#startup.Display == 4
	and startup.Display[3].Payload.Hunting == false
	and startup.Display[4].Payload.Hunting == false,
	"non-hunting transitions should be tracked after the first hunt")
expect(startup.Verdict.Confidence[23] == 35,
	"repeated speed at unchanged Energy must not increase confidence")
startup:Destroy()

local alreadyHunting = harness({0}, "Small", 28)
alreadyHunting.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 3})
alreadyHunting.RunDelayed()
expect(#alreadyHunting.Display == 0,
	"execution during an existing hunt should not start tracking")
alreadyHunting.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 4})
alreadyHunting.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 5})
alreadyHunting.RunDelayed()
expect(#alreadyHunting.Display == 2 and alreadyHunting.Verdict.Confidence[23] == 35,
	"an existing hunt should start tracking only after the next transition into hunting")
alreadyHunting:Destroy()

local zeroEnergy = harness({0}, "Small", 28)
zeroEnergy.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 6})
zeroEnergy.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 7})
zeroEnergy.RunDelayed()
expect(zeroEnergy.Verdict.Confidence[23] == 35,
	"0 Energy and WalkSpeed 28 should match base 14 at the configured 200 percent multiplier")
zeroEnergy:Destroy()

local hunting = harness({20, 60}, "Medium", 12 * 1.05 * 2)
hunting.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 9})
hunting.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 10})
hunting.RunDelayed()
expect(hunting.Verdict.Confidence[23] == 35,
	"average Energy 40 should map to base 12 and accept a configured hunting multiplier")
hunting:Destroy()

local energies = {100}
local changing = harness(energies, "Small", 18)
changing.Traffic:Broadcast("HuntingState", {Hunting = false})
changing.Traffic:Broadcast("HuntingState", {Hunting = true})
changing.RunDelayed()
energies[1], changing.Humanoid.WalkSpeed = 99.5, 18.05
changing.Traffic:Broadcast("HuntingState", {Hunting = false})
changing.RunDelayed()
expect(changing.Verdict.Confidence[23] == 35,
	"an insignificant change within the speed tolerance is not corroboration")
energies[1], changing.Humanoid.WalkSpeed = 80, 20
changing.Traffic:Broadcast("HuntingState", {Hunting = true})
changing.RunDelayed()
expect((changing.Verdict.Confidence[23] == 65 and changing.Verdict.SourceConfidence[23] == 95),
	"changing Energy and matching speed under the same multiplier should corroborate Wretch")
changing:Destroy()

local shiftingEnergy = {100}
local shifting = harness(shiftingEnergy, "Small", 18)
shifting.Traffic:Broadcast("HuntingState", {Hunting = false})
shifting.Traffic:Broadcast("HuntingState", {Hunting = true})
shifting.RunDelayed()
shiftingEnergy[1], shifting.Humanoid.WalkSpeed = 40, 18
shifting.Traffic:Broadcast("HuntingState", {Hunting = false})
shifting.RunDelayed()
expect(shifting.Verdict.Confidence[23] == 35,
	"a constant speed that needs a different inferred multiplier must not corroborate Wretch")
shifting:Destroy()

local rejected = harness({0}, "Small", 11)
rejected.Traffic:Broadcast("HuntingState", {Hunting = false, Time = 19})
rejected.Traffic:Broadcast("HuntingState", {Hunting = true, Time = 20})
rejected.RunDelayed()
expect(not table.find(rejected.Verdict.RuledOut, 23), "one mismatch is not enough")
rejected.Traffic:Broadcast("HuntingState", {Hunting = false})
rejected.RunDelayed()
rejected.Traffic:Broadcast("HuntingState", {Hunting = true})
rejected.RunDelayed()
expect(table.find(rejected.Verdict.RuledOut, 23),
	"Energy 0 should expect base 14 and reject an impossible hunting speed")
rejected:Destroy()

print("wretch.spec: first-hunt gate and transition Energy speed checks passed")

local function unknownCurve(speeds, expected)
 local energy = {100}
 local h = harness(energy, "Small", speeds[1], true)
 h.Traffic:Broadcast("HuntingState", {Hunting = false})
 for i, value in ipairs({100, 60, 20}) do
  energy[1], h.Humanoid.WalkSpeed = value, speeds[i]
  h.Traffic:Broadcast("HuntingState", {Hunting = true}) h.RunDelayed()
  if i < 3 then
   expect(h.Verdict.Confidence[23] == nil and not table.find(h.Verdict.RuledOut, 23), "unknown scale needs three Energy levels")
  end
  h.Traffic:Broadcast("HuntingState", {Hunting = false}) h.RunDelayed()
 end
 if expected then expect((h.Verdict.Confidence[23] == 65 and h.Verdict.SourceConfidence[23] == 95), "consistent relative Energy response supports Wretch")
 else expect(table.find(h.Verdict.RuledOut, 23), "constant speed across three Energy levels excludes Wretch") end
 h:Destroy()
end
unknownCurve({18, 22, 26}, true)
unknownCurve({21, 21, 21}, false)

local postKill = harness({0}, "Small", 21)
postKill.Traffic("PlayerKilled", {}):SendTo("Wretch")
postKill.Traffic:Broadcast("HuntingState", {Hunting = false})
for _ = 1, 2 do
	postKill.Traffic:Broadcast("HuntingState", {Hunting = true})
	postKill.RunDelayed()
	postKill.Traffic:Broadcast("HuntingState", {Hunting = false})
	postKill.RunDelayed()
end
expect(not table.find(postKill.Verdict.RuledOut, 23), "post-kill mismatches must not exclude Wretch")
postKill:Destroy()

local lostEnergy = {100}
local interrupted = harness(lostEnergy, "Small", 18)
interrupted.Traffic:Broadcast("HuntingState", {Hunting = false})
interrupted.Traffic:Broadcast("HuntingState", {Hunting = true})
lostEnergy[1] = nil
interrupted.Traffic:Broadcast("HuntingState", {Hunting = false})
interrupted.RunDelayed()
expect(interrupted.Verdict.Confidence[23] == nil and #interrupted.Display == 1,
	"a hunt ending before samples settle must cancel them even when Energy becomes unavailable")
interrupted:Destroy()

local restoredEnergy = {0}
local restored = harness(restoredEnergy, "Small", 28)
restored.Traffic:Broadcast("HuntingState", {Hunting = false})
restored.Traffic:Broadcast("HuntingState", {Hunting = true})
restored.RunDelayed()
restoredEnergy[1] = 25
for time = 1, 8 do
	restored.Traffic("GhostSpeedObserved", {Hunting = true, AverageEnergy = 25,
		Speed = 28, Time = time, Visible = time % 2 == 0}):SendTo("WretchSpeed")
end
expect(restored.Verdict.SourceConfidence[23] ~= 95 and not table.find(restored.Verdict.RuledOut, 23),
	"native Energy restoration without a speed refresh must not identify or exclude Wretch")
restored.Humanoid.WalkSpeed = 25.5
restored.Traffic:Broadcast("HuntingState", {Hunting = false})
restored.RunDelayed()
expect(restored.Verdict.SourceConfidence[23] ~= 95, "a non-hunting refresh is not corroboration")
restored.Traffic:Broadcast("HuntingState", {Hunting = true})
restored.RunDelayed()
expect(restored.Verdict.SourceConfidence[23] == 95,
	"the next actual hunting refresh must still corroborate the changed Energy curve")
restored:Destroy()
