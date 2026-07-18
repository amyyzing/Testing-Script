local createTraffic = require("../traffic")
local createSpeedTracker = require("../active-trackers/speed-tracker")

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
		Fire = function(_)
			for _, callback in ipairs(callbacks) do callback() end
		end,
	}
end

local visibility = signal()
local speedChanged = signal()
local Humanoid = {WalkSpeed = 11}
function Humanoid:GetPropertyChangedSignal(name)
	expect(name == "WalkSpeed", "speed tracker should observe WalkSpeed changes")
	return speedChanged
end
local Ghost = {Hunting = false, Transparency = 0}
function Ghost:GetAttribute(name)
	if name == "Hunting" then return self.Hunting end
	if name == "Transparency" then return self.Transparency end
end
function Ghost:GetAttributeChangedSignal(name)
	expect(name == "Transparency", "speed tracker should observe Workspace.Ghost Transparency")
	return visibility
end
function Ghost:FindFirstChildOfClass() return Humanoid end
function Ghost:FindFirstChild() return nil end

local Traffic = createTraffic()
local now = 0
local kills, keresKills, salts, huntLog = {}, {}, {}, {}
Traffic:Receive("Aswang", function(signalName, payload)
	if signalName == "KillSpeed" then table.insert(kills, payload) end
	if signalName == "SaltSpeed" then table.insert(salts, payload) end
end)
Traffic:Receive("Keres", function(signalName, payload)
	if signalName == "KillSpeed" then table.insert(keresKills, payload) end
end)
Traffic:Receive("SpeedArrayLog", function(signalName, payload)
	table.insert(huntLog, {signal = signalName, payload = payload})
end)
local tracker = createSpeedTracker({
	Traffic = Traffic,
	Ghost = Ghost,
	Clock = function() return now end,
	KillMatchWindow = 0.75,
})

Traffic("PlayerKilled", {userId = 1}):SendTo("SpeedTracker")
expect(#kills == 0, "non-hunting deaths must not start kill sections")

Ghost.Hunting = true
Traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
expect(#huntLog == 1 and huntLog[1].signal == "HuntSpeedReset",
	"hunt start should reset the display without duplicating seven-pair samples")
Traffic("SaltHit", {ContactId = 1}):SendTo("SpeedTracker")
expect(huntLog[#huntLog].signal == "HuntSpeedMarker"
	and huntLog[#huntLog].payload.Label == "SALT SPLIT",
	"salt contact should mark the exact split in the displayed array")
Humanoid.WalkSpeed = 9
now = 0.1
speedChanged:Fire()
Traffic("SaltStateAfterHit", {ContactId = 1, State = "disturbed"}):SendTo("SpeedTracker")
expect(#salts == 1 and salts[1].afterSalt[#salts[1].afterSalt].s == 9,
	"a post-contact WalkSpeed change should be captured without waiting for a blink")
Humanoid.WalkSpeed = 11
now = 0.2
speedChanged:Fire()
expect(#salts == 2 and salts[2].afterSalt[#salts[2].afterSalt].s == 11,
	"the same split should capture recovery to the pre-salt speed")
local beforeNextSalt = #salts
now = 0.3
Traffic("SaltHit", {ContactId = 20}):SendTo("SpeedTracker")
expect(#salts == beforeNextSalt + 1 and salts[#salts].completed == true,
	"a second salt hit should finalize the prior section before hunt end")
Traffic("SaltStateAfterHit", {
	ContactId = 20,
	State = "disturbed",
}):SendTo("SpeedTracker")
local nextSalt = salts[#salts]
expect(nextSalt.beforeSalt[#nextSalt.beforeSalt] == nextSalt.afterSalt[1],
	"consecutive salt sections should share their boundary sample")
Humanoid.WalkSpeed = 12
now = 1
speedChanged:Fire()
Traffic("HuntSpeedSample", {Index = 4}):SendTo("SpeedTracker")
now = 1.1
Ghost.Transparency = 1
visibility:Fire()
now = 1.2
Ghost.Transparency = 0
visibility:Fire()
now = 1.3
Traffic("PlayerKilled", {userId = 1, Time = now}):SendTo("SpeedTracker")
expect(huntLog[#huntLog].signal == "HuntSpeedMarker"
	and huntLog[#huntLog].payload.Index == 4,
	"a delayed PlayerKilled marker should align with the latest paced display sample")
now = 1.4
Ghost.Transparency = 1
visibility:Fire()
now = 1.5
Ghost.Transparency = 0
visibility:Fire()

expect(#kills >= 1, "hunting deaths should produce kill speed updates")
expect(#keresKills == #kills and keresKills[#keresKills] == kills[#kills],
	"Keres should receive the same unique-kill speed section as Aswang")
local kill = kills[#kills]
expect(kill.userId == 1, "kill speed sections should retain the unique player id")
expect(kill.baselineKill.s == 11,
	"a speed change just before PlayerKilled should not replace the earlier stable baseline")
expect(kill.beforeKill[#kill.beforeKill] == kill.afterKill[1],
	"kill arrays should share their transition sample")
expect(#salts >= 4 and #salts[#salts].afterSalt >= 5,
	"salt and kill sections should collect the same visibility samples")

now = 3
Traffic("PlayerKilled", {userId = 2, Time = now}):SendTo("SpeedTracker")
expect(kills[#kills].completed == true,
	"a second unique kill should finalize the previous kill section")
expect(huntLog[#huntLog].signal == "HuntSpeedMarker"
	and huntLog[#huntLog].payload.Label == "KILL",
	"player deaths should mark their exact split in the displayed speed array")

for _, entry in ipairs(huntLog) do
	expect(entry.signal ~= "HuntSpeedSample",
		"the active tracker must not duplicate paced seven-pair samples")
end

Ghost.Hunting = false
Traffic("HuntingState", {Hunting = false}):SendTo("SpeedTracker")
expect(kills[#kills].completed == true, "hunt end should finalize the active kill section")
expect(huntLog[#huntLog].signal == "HuntSpeedEnded",
	"hunt end should retain and mark the completed displayed array")

Ghost.Hunting, Humanoid.WalkSpeed = true, 11
Traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
Traffic("SaltHit", {ContactId = 2}):SendTo("SpeedTracker")
Humanoid.WalkSpeed = 8
speedChanged:Fire()
local saltCount = #salts
Ghost.Hunting = false
Traffic("HuntingState", {Hunting = false}):SendTo("SpeedTracker")
Traffic("SaltStateAfterHit", {ContactId = 2, State = "disturbed"}):SendTo("SpeedTracker")
expect(#salts == saltCount + 1 and salts[#salts].completed == true
	and salts[#salts].afterSalt[#salts[#salts].afterSalt].s == 8,
	"a disturbed result arriving after hunt end should retain the completed salt split")

tracker:Destroy()
print("speed-tracker.spec: kill splits, salt coexistence, and hunt finalization passed")
