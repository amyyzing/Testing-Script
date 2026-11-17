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
local missing = createResume({Environment = {}, Game = {}, Player = player,
	ModuleUrl = "https://repo.example/module", Wait = function() end})
assert(not missing.Queued and missing.LastError, "unsupported queue API must report unavailability")
print("mcp-teleport.spec: independent multi-hop queue, stale flags, retries and duplicate prevention passed")
