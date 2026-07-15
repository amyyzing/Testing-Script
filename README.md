```luau
local HttpService = game:GetService("HttpService")
local cacheBust = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local revision
local revisionRequestFinished = false
local resolved, response
task.spawn(function()
	resolved, response = pcall(
		game.HttpGet,
		game,
		"https://api.github.com/repos/amyyzing/Testing-Script/git/ref/heads/main?v=" .. cacheBust
	)
	revisionRequestFinished = true
end)
local revisionDeadline = os.clock() + 4
while not revisionRequestFinished and os.clock() < revisionDeadline do
	task.wait(0.03)
end
if revisionRequestFinished and resolved and type(response) == "string" then
	local decoded, payload = pcall(HttpService.JSONDecode, HttpService, response)
	local candidate = decoded
		and type(payload) == "table"
		and type(payload.object) == "table"
		and payload.object.sha
		or nil
	if type(candidate) == "string"
		and #candidate == 40
		and string.match(candidate, "^[%da-fA-F]+$") then
		revision = string.lower(candidate)
	end
end
local sourceRevision = revision or "main"
local url = "https://raw.githubusercontent.com/amyyzing/Testing-Script/"
	.. sourceRevision
	.. "/logic.luau?v="
	.. cacheBust
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local source = game:HttpGet(url)
local chunk, compileError = compiler(source, "@DemonologyLoader")
assert(chunk, compileError)
chunk(nil, nil, revision)
```

## Ghost tracker architecture

Ghost behavior is resolved by the modules under `ghost/`; GUI and round automation code consume the coordinator result and do not own separate guessing rules.

- Active trackers bind the fixed `Workspace.Ghost` once and publish hunt-state, blink-state, WalkSpeed, and player-death edges.
- Dormant trackers arm only for a relevant observation window, emit one qualified result, then wait for the next hunt or trigger.
- Discardable trackers read immutable round facts such as `InvisibleOnLIDAR`, HumanoidRootPart sounds, VisualModel sex, and Holy Oil fire colour once.
- Each `ghost/<Name>.luau` profile converts canonical observations into positive or negative ledger entries. Supersession replaces a provisional result without deleting its audit history.
- Evidence compatibility, behavior confidence, Journal cross-outs, and the final round selection all consume the same resolved state.
