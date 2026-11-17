local createTeleportLoop = require("../teleport-loop")

local queued
local environment = {}
local loop = createTeleportLoop({
	Environment = environment,
	LoaderUrl = "https://example.test/logic.luau",
	ReadSettings = function()
		return {JobSite = "Prison", Difficulty = "Custom", CustomPreset = "john4",
			EquipmentPreset = "green", Challenges = {true, false, true}, ChallengesConfigured = true}
	end,
	QueueOnTeleport = function(source) queued = source end,
})

assert(not loop:Queue("AttemptStart"), "disabled loop should not queue")
loop:SetEnabled(true)
assert(loop:Queue("AttemptStart"), "enabled loop should queue")
assert(queued:find('Context = "AttemptStart"', 1, true), "context was not handed off")
assert(queued:find("task.wait(4)", 1, true), "queued execution must wait four seconds")
assert(queued:find("for attempt = 1, 3", 1, true), "queued download must retry transient failures")
assert(not queued:find("previous.Destroy", 1, true), "queued handoffs must leave session cleanup to the serialized loader")
assert(queued:find("DemonologyLoopEnabled", 1, true), "queued source must remain cancellable")
assert(queued:find('JobSite = "Prison"', 1, true), "settings were not captured in the handoff")

print("teleport-loop.spec: cancellable four-second cross-place handoff passed")

local emergencySource
local recovery = createTeleportLoop({
	Environment = {},
	ArmOnEnable = true,
	LoaderUrl = "https://example.test/loader.luau",
	QueueOnTeleport = function(source) emergencySource = source end,
})
recovery:SetEnabled(true)
assert(emergencySource, "round automation must queue before a death-triggered return")
local armed = emergencySource
assert(recovery:Queue("ReturnToLobby") and emergencySource == armed,
	"a planned return should reuse the already armed arrival")

local arrived = {}
local executions, downloads = 0, 0
local failDownload = true
local globals = setmetatable({
	getgenv = function() return arrived end,
	game = {
		JobId = "death-return-lobby",
		PlaceId = 18199615050,
		IsLoaded = function() return true end,
		HttpGet = function()
			downloads += 1
			if failDownload then error("temporary network error") end
			return "return true"
		end,
	},
	task = {wait = function() end},
	loadstring = function()
		return function() executions += 1 end
	end,
}, {__index = getfenv()})
local runArrival = assert(loadstring(armed))
setfenv(runArrival, globals)
assert(not pcall(runArrival) and downloads == 3, "failed downloads should exhaust bounded retries")
assert(arrived.DemonologyArrivalJob == nil and arrived.DemonologyHandoffToken == nil,
	"a failed arrival must remain retryable")
assert(arrived.DemonologyArrivalLoading == nil, "failed arrival must release the startup lock")
failDownload = false
assert(pcall(runArrival))
assert(executions == 1 and arrived.DemonologyAutoHandoff.Context == "ReturnToLobby",
	"unexpected round exits should resume the lobby")
assert(pcall(runArrival) and executions == 1, "repeated queued scripts should not load twice")
arrived = {}
executions = 0
globals.game.HttpGet = function()
	coroutine.yield("download pending")
	return "return true"
end
local pending = coroutine.create(runArrival)
assert(coroutine.resume(pending))
assert(arrived.DemonologyArrivalLoading and executions == 0, "arrival must claim its lock before downloading")
assert(pcall(runArrival) and executions == 0, "overlapping queued arrivals must not initialize a second loader")
assert(coroutine.resume(pending) and executions == 1, "the original arrival must finish once")
assert(arrived.DemonologyArrivalLoading == nil, "successful arrival must release its lock")
local saved
local service = {
	SetTeleportSetting = function(_, _, value) saved = value end,
	GetTeleportSetting = function() return saved end,
}
local persisted = createTeleportLoop({Environment = {}, TeleportService = service,
	LoaderUrl = "https://example.test/loader.luau", QueueOnTeleport = function() end})
persisted:SetEnabled(true)
assert(saved == true, "enabled state must survive the old Lua environment")
persisted:SetEnabled(false)
assert(saved == false, "disabled state must cancel a previously queued continuation")
globals.game.GetService = function() return service end
arrived = {}
executions = 0
assert(pcall(runArrival) and executions == 0 and arrived.DemonologyArrivalLoading == nil,
	"a cancelled loop must stay cancelled in a fresh arrival environment")
print("teleport-loop.spec: death return, failed download retry and arrival deduplication passed")
