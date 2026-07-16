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
local kills, salts = {}, {}
Traffic:Receive("Aswang", function(signalName, payload)
	if signalName == "KillSpeed" then table.insert(kills, payload) end
	if signalName == "SaltSpeed" then table.insert(salts, payload) end
end)
local tracker = createSpeedTracker({Traffic = Traffic, Ghost = Ghost, GhostModel = Model})

Traffic("PlayerKilled", {userId = 1}):SendTo("SpeedTracker")
expect(#kills == 0, "non-hunting deaths must not start kill sections")

Ghost.Hunting = true
Traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
Traffic("SaltHit", {ContactId = 1}):SendTo("SpeedTracker")
Humanoid.WalkSpeed = 9
speedChanged:Fire()
Traffic("SaltStateAfterHit", {ContactId = 1, State = "disturbed"}):SendTo("SpeedTracker")
expect(#salts == 1 and salts[1].afterSalt[#salts[1].afterSalt].s == 9,
	"a post-contact WalkSpeed change should be captured without waiting for a blink")
Traffic("PlayerKilled", {userId = 1}):SendTo("SpeedTracker")
Humanoid.WalkSpeed, Model.Transparency = 12, 1
visibility:Fire()
Humanoid.WalkSpeed, Model.Transparency = 12, 0
visibility:Fire()

expect(#kills >= 1, "hunting deaths should produce kill speed updates")
local kill = kills[#kills]
expect(kill.beforeKill[#kill.beforeKill] == kill.afterKill[1],
	"kill arrays should share their transition sample")
expect(#salts >= 3 and #salts[#salts].afterSalt >= 4,
	"salt and kill sections should collect the same visibility samples")

Traffic("PlayerKilled", {userId = 2}):SendTo("SpeedTracker")
expect(kills[#kills].completed == true,
	"a second unique kill should finalize the previous kill section")

Ghost.Hunting = false
Traffic("HuntingState", {Hunting = false}):SendTo("SpeedTracker")
expect(kills[#kills].completed == true, "hunt end should finalize the active kill section")

tracker:Destroy()
print("speed-tracker.spec: kill splits, salt coexistence, and hunt finalization passed")
