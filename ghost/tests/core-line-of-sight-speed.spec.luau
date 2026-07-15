local Events = require("../events")
local Tracker = require("../trackers/dormant/line-of-sight-speed")({Events = Events})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function() end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(callbacks) do callback(...) end
		end,
	}
end

local now = 0
local speedSignal = signal()
local humanoid = {
	WalkSpeed = 16,
	GetPropertyChangedSignal = function(_, name)
		return name == "WalkSpeed" and speedSignal or signal()
	end,
}
local character = {
	FindFirstChildOfClass = function(_, name)
		return name == "Humanoid" and humanoid or nil
	end,
}
local player = {Character = character, CharacterAdded = signal()}
function player:GetAttribute() return nil end
local emitted = {}
local sprinting = true
local lineOfSight = true
local tracker = Tracker.new({RequiredExposure = 1, RequiredSlowEdges = 2})
tracker:Start({
	Clock = function() return now end,
	LocalPlayer = player,
	GhostModel = {},
	ReadLocalPlayerLineOfSight = function() return lineOfSight end,
	ReadLocalPlayerSprinting = function() return sprinting end,
	ReadLocalPlayerBaselineSpeed = function() return 10 end,
	Emit = function(event) table.insert(emitted, event) end,
})
tracker:OnEvent({Type = Events.Types.HuntStarted, HuntId = 1, Time = now})
now = 0.5
tracker:OnEvent({Type = Events.Types.Tick, Time = now})
humanoid.WalkSpeed = 8
speedSignal:Fire()
now = 0.7
humanoid.WalkSpeed = 7.5
speedSignal:Fire()
expect(#emitted == 1 and emitted[1].Payload.Slowed == true
	and emitted[1].Payload.Sprinting == true,
	"two qualified sprint-time LOS slow edges must emit one Siren-positive trial")

tracker:Reset()
emitted = {}
now = 0
humanoid.WalkSpeed = 16
local persistentTracker = Tracker.new({RequiredExposure = 1})
persistentTracker:Start({
	Clock = function() return now end,
	LocalPlayer = player,
	GhostModel = {},
	ReadLocalPlayerLineOfSight = function() return true end,
	ReadLocalPlayerSprinting = function() return true end,
	ReadLocalPlayerBaselineSpeed = function() return 10 end,
	Emit = function(event) table.insert(emitted, event) end,
})
persistentTracker:OnEvent({Type = Events.Types.HuntStarted, HuntId = 3, Time = now})
humanoid.WalkSpeed = 8
now = 0.25
persistentTracker:OnEvent({Type = Events.Types.Tick, Time = now})
expect(#emitted == 1 and emitted[1].Payload.Slowed == true,
	"one persistent sprint-time LOS slowdown must be detected even when its property edge was missed")
persistentTracker:Destroy()

emitted = {}
now = 0
humanoid.WalkSpeed = 16
tracker:Start({
	Clock = function() return now end,
	LocalPlayer = player,
	GhostModel = {},
	ReadLocalPlayerLineOfSight = function() return true end,
	ReadLocalPlayerSprinting = function() return true end,
	ReadLocalPlayerBaselineSpeed = function() return 10 end,
	Emit = function(event) table.insert(emitted, event) end,
})
tracker:OnEvent({Type = Events.Types.HuntStarted, HuntId = 2, Time = now})
for _, timestamp in ipairs({0.5, 1.0, 1.5}) do
	now = timestamp
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
end
expect(#emitted == 1 and emitted[1].Payload.Slowed == false
	and emitted[1].Payload.Completed == true
	and emitted[1].Payload.ExposureSeconds >= 1,
	"a completed continuous sprint-time LOS exposure without slowdown must emit one negative trial")

print("core-line-of-sight-speed.spec: sprinting LOS positive and negative trials passed")
