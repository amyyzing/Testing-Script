return function(dependencies)
	local environment = dependencies.Environment or (getgenv and getgenv()) or _G
	local world = dependencies.Game or game
	local wait = dependencies.Wait or task.wait
	local compile = dependencies.Compile or loadstring or load
	local spawn = dependencies.Spawn or task.spawn
	local existing = environment.DemonologyMCPResume
	if existing and existing.Game == world and existing.JobId == tostring(world.JobId) then
		existing:Arm()
		if dependencies.Recover and existing.Recover then
			existing:Recover(dependencies.BridgeURL, dependencies.AuthToken)
		end
		return existing
	end
	local controller = {Game = world, JobId = tostring(world.JobId), Enabled = true, Queued = false}
	environment.DemonologyMCPResume = controller
	local moduleUrl = assert(dependencies.ModuleUrl, "MCP resume requires its module URL")
	local queue = dependencies.QueueOnTeleport or environment.queue_on_teleport or environment.queueonteleport
	if type(queue) ~= "function" then
		for _, name in ipairs({"syn", "fluxus", "krnl"}) do
			local namespace = environment[name]
			local candidate = type(namespace) == "table" and (namespace.queue_on_teleport or namespace.queueonteleport)
			if type(candidate) == "function" then queue = candidate break end
		end
	end
	function controller:Arm()
		if self.Queued then return true end
		if not self.Enabled then return false end
		if type(queue) ~= "function" then self.LastError = "queue_on_teleport is unavailable" return false end
		local bridge = dependencies.BridgeURL or environment.BridgeURL or environment.bridgeurl
		if type(bridge) ~= "string" or bridge == "" then return false end
		local token = dependencies.AuthToken or environment.MCPAuthToken or environment.BridgeAuthToken or ""
		local source = string.format([[
if not game:IsLoaded() then game.Loaded:Wait() end
local environment = (getgenv and getgenv()) or _G
local current = environment.DemonologyMCPResume
local job = tostring(game.JobId)
if current and current.Game == game and current.JobId == job and (current.Recovered or current.Recovering) then return end
local loading = environment.DemonologyMCPResumeLoading
if loading and loading.Game == game and loading.JobId == job then return end
local owner = {Game = game, JobId = job}
environment.DemonologyMCPResumeLoading = owner
local ok, failure = xpcall(function()
local source
for attempt = 1, 12 do
    local downloaded, result = pcall(game.HttpGet, game, %q .. "?v=" .. tostring(os.time()))
    if downloaded and type(result) == "string" and result ~= "" then source = result break end
    task.wait(math.min(attempt, 5))
end
assert(source, "MCP resume module download failed")
local chunk, failure = (loadstring or load)(source, "@MCPResume")
assert(chunk, failure)
return chunk()({ModuleUrl = %q, BridgeURL = %q, AuthToken = %q, Recover = true})
end, debug.traceback)
if environment.DemonologyMCPResumeLoading == owner then environment.DemonologyMCPResumeLoading = nil end
if not ok then error(failure, 0) end
]], moduleUrl, moduleUrl, bridge, type(token) == "string" and token or "")
		local ok = pcall(queue, source)
		self.Queued = ok
		self.LastError = not ok and "executor rejected the MCP resume queue" or nil
		return ok
	end
	function controller:Destroy()
		self.Enabled = false
		if self.Connection then self.Connection:Disconnect() end
	end
	controller:Arm()
	local player = dependencies.Player or world:GetService("Players").LocalPlayer
	if player and player.OnTeleport then
		controller.Connection = player.OnTeleport:Connect(function(state)
			if tostring(state) == "Enum.TeleportState.Failed" then controller.Queued = false end
			controller:Arm()
		end)
	end
	function controller:Recover(bridge, credential)
		if self.Recovering then return end
		self.Recovering = true
		local recovered = pcall(function()
		environment.BridgeURL = bridge
		environment.MCPAuthToken = credential
		local identity = table.concat({tostring(world.PlaceId), tostring(world.JobId), tostring(player and player.UserId or 0)}, ":")
		if environment.MCP_ClientIdentityKey ~= identity then
			environment.MCP_Loaded, environment.MCP_Loading, environment.MCP_AutoLoading = nil, nil, nil
			environment.MCP_ClientToken = nil
		end
		local base = bridge:gsub("/+$", ""):gsub("^wss://", "https://"):gsub("^ws://", "http://")
		if not base:match("^https?://") then base = "http://" .. base end
		local token = credential
		local url = base .. "/script.luau"
		if type(token) == "string" and token ~= "" then
			url ..= "?token=" .. world:GetService("HttpService"):UrlEncode(token)
		end
		for attempt = 1, 20 do
			if environment.MCP_Loaded then break end
			if not environment.MCP_Loading then
				pcall(function()
					local source = world:HttpGet(url)
					local chunk = assert(compile(source, "@MCPConnector"))
					spawn(function() pcall(chunk) end)
				end)
			end
			if not environment.MCP_Loaded then wait(math.min(attempt * 0.5, 5)) end
		end
		end)
		self.Recovering = false
		self.Recovered = recovered and environment.MCP_Loaded == true
		self.LastError = not self.Recovered and "MCP connector did not finish initializing" or nil
		self:Arm()
	end
	if dependencies.Recover then controller:Recover(dependencies.BridgeURL, dependencies.AuthToken) end
	return controller
end
