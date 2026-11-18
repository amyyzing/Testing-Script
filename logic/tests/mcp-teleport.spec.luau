local createResume = require("../mcp-teleport")
local environment = {BridgeURL = "https://bridge.example", MCPAuthToken = "fixture"}
local queued = {}
local player = {UserId = 42}
local requests, failures = 0, 2
local world = {PlaceId = 1, JobId = "round"}
function world:GetService(name)
	if name == "Players" then return {LocalPlayer = player} end
	return {UrlEncode = function(_, text) return text end}
end
function world:HttpGet(url)
	requests += 1
	assert(url == "https://bridge.example/script.luau?token=fixture", "resume must reuse the authenticated bridge")
	if requests <= failures then error("transient failure") end
	return "connector"
end
local function dependencies(game, recover)
	return {
		Environment = environment, Game = game, Player = player,
		ModuleUrl = "https://repo.example/mcp-teleport.luau", Recover = recover,
		BridgeURL = environment.BridgeURL, AuthToken = environment.MCPAuthToken,
		QueueOnTeleport = function(source) table.insert(queued, source) end,
		Wait = function() end,
		Spawn = function(callback) callback() end,
		Compile = function() return function()
			environment.MCP_Loaded = true
			environment.MCP_ClientIdentityKey = "1:" .. game.JobId .. ":42"
		end end,
	}
end
local first = createResume(dependencies(world))
assert(first.Queued and #queued == 1, "first initialization must arm the next teleport")
assert(createResume(dependencies(world)) == first and #queued == 1, "duplicate initialization must not enqueue twice")
assert(queued[1]:find("DemonologyMCPResumeLoading", 1, true), "queued bootstrap must serialize recovery")
local nextWorld = {PlaceId = 1, JobId = "lobby", GetService = world.GetService, HttpGet = world.HttpGet}
environment.MCP_Loaded = true
environment.MCP_ClientIdentityKey = "1:round:42"
local nextResume = createResume(dependencies(nextWorld, true))
assert(nextResume ~= first and nextResume.Recovered and requests == 3,
	"new-place recovery must clear a stale loaded flag and retry transient failures")
assert(#queued == 2, "arrival must arm another hop without requiring the GUI")
assert(createResume(dependencies(nextWorld, true)) == nextResume and requests == 3,
	"repeated recovery must reuse the current connector")
local revisit = dependencies(nextWorld, true)
revisit.ArrivalId = "second-visit-to-the-same-lobby"
assert(createResume(revisit) == nextResume and requests == 4,
	"a new arrival at the same cached job must refresh a stale connector")
assert(createResume(revisit) == nextResume and requests == 4,
	"duplicate execution of the same arrival must not refresh twice")
assert(#queued == 3, "a revisited cached job must arm its next hop again")
nextWorld.JobId = "another-server"
local persistent = dependencies(nextWorld, true)
persistent.Compile = function() return function()
	environment.MCP_Loaded = true
	environment.MCP_ClientIdentityKey = "1:another-server:42"
	coroutine.yield("connector polling")
end end
local runtimeThread
persistent.Spawn = function(callback)
	runtimeThread = coroutine.create(callback)
	assert(coroutine.resume(runtimeThread))
end
local changedJob = createResume(persistent)
assert(changedJob ~= nextResume and changedJob.Recovered and #queued == 4,
	"a changed job must recover even if the executor reuses the same game object")
assert(coroutine.status(runtimeThread) == "suspended",
	"the long-running connector must not block recovery completion")
local missing = createResume({Environment = {}, Game = {}, Player = player,
	ModuleUrl = "https://repo.example/module", Wait = function() end, Spawn = function(callback) callback() end})
assert(not missing.Queued and missing.LastError, "unsupported queue API must report unavailability")
local legacy = {Game = world, JobId = world.JobId}
function legacy:Destroy() self.Destroyed = true end
local upgrade = dependencies(world)
upgrade.Environment = {BridgeURL = environment.BridgeURL, DemonologyMCPResume = legacy}
local upgraded = createResume(upgrade)
assert(upgraded ~= legacy and legacy.Destroyed and upgraded.Version,
	"a cached controller from the older resume implementation must be replaced")
print("mcp-teleport.spec: independent multi-hop queue, stale flags, retries and duplicate prevention passed")
