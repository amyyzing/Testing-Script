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
local Model = {Transparency = 0}
function Model:GetAttribute() return self.Transparency end
function Model:GetAttributeChangedSignal() return visibility end

local speedChanged = signal()
local Humanoid = {WalkSpeed = 11}
function Humanoid:GetPropertyChangedSignal(name)
	expect(name == "WalkSpeed", "speed tracker should observe WalkSpeed changes")
	return speedChanged
end
local Ghost = {Hunting = false}
function Ghost:GetAttribute(name) return name == "Hunting" and self.Hunting or nil end
function Ghost:FindFirstChildOfClass() return Humanoid end
function Ghost:FindFirstChild() return nil end

local Traffic = createTraffic()
local now = 0
local kills, salts, huntLog = {}, {}, {}
Traffic:Receive("Aswang", function(signalName, payload)
	if signalName == "KillSpeed" then table.insert(kills, payload) end
	if signalName == "SaltSpeed" then table.insert(salts, payload) end
end)
Traffic:Receive("SpeedArrayLog", function(signalName, payload)
	table.insert(huntLog, {signal = signalName, payload = payload})
end)
local tracker = createSpeedTracker({
	Traffic = Traffic,
	Ghost = Ghost,
	GhostModel = Model,
	Clock = function() return now end,
	KillMatchWindow = 0.75,
})

Traffic("PlayerKilled", {userId = 1}):SendTo("SpeedTracker")
expect(#kills == 0, "non-hunting deaths must not start kill sections")

Ghost.Hunting = true
Traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
expect(huntLog[1].signal == "HuntSpeedReset" and huntLog[2].signal == "HuntSpeedSample",
	"hunt start should reset the displayed array and publish its first sample")
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
Humanoid.WalkSpeed = 12
now = 1
speedChanged:Fire()
local preSignalSpeedIndex = #tracker.samples
now = 1.1
Model.Transparency = 1
visibility:Fire()
now = 1.2
Model.Transparency = 0
visibility:Fire()
now = 1.3
Traffic("PlayerKilled", {userId = 1, Time = now}):SendTo("SpeedTracker")
expect(huntLog[#huntLog].signal == "HuntSpeedMarker"
	and huntLog[#huntLog].payload.Index == preSignalSpeedIndex,
	"timing should correlate a delayed PlayerKilled signal past intervening visibility samples")
now = 1.4
Model.Transparency = 1
visibility:Fire()
now = 1.5
Model.Transparency = 0
visibility:Fire()

expect(#kills >= 1, "hunting deaths should produce kill speed updates")
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
	and huntLog[#huntLog].payload.Label == "KILL SPLIT #2",
	"player deaths should mark their exact split in the displayed speed array")

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
