return function(dependencies)
	local environment = dependencies.Environment or _G
	local loaderUrl = assert(dependencies.LoaderUrl, "teleport-loop requires LoaderUrl")
	local queue = dependencies.QueueOnTeleport
	if type(queue) ~= "function" then
		queue = environment.queue_on_teleport or environment.queueonteleport
	end
	if type(queue) ~= "function" then
		for _, name in ipairs({"syn", "fluxus", "krnl"}) do
			local namespace = environment[name]
			local candidate = type(namespace) == "table"
				and (namespace.queue_on_teleport or namespace.queueonteleport)
			if type(candidate) == "function" then queue = candidate break end
		end
	end
	local serial = 0
	local controller = {Enabled = environment.DemonologyLoopEnabled == true}

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		environment.DemonologyLoopEnabled = self.Enabled
		return self.Enabled
	end

	function controller:Destroy()
		self:SetEnabled(false)
		self.QueuedContext = nil
	end

	function controller:Queue(context)
		if not self.Enabled then return false, "automation loop is disabled" end
		if type(queue) ~= "function" then return false, "queue_on_teleport is unavailable" end
		context = tostring(context or "Teleport")
		if self.QueuedContext == context then return true end
		serial += 1
		local settings = dependencies.ReadSettings and dependencies.ReadSettings() or {}
		local challenges = type(settings.Challenges) == "table" and settings.Challenges or {}
		local token = table.concat({tostring(os.time()), tostring(os.clock()), tostring(serial), context}, ":")
		local source = string.format([[
local environment = (getgenv and getgenv()) or _G
if environment.DemonologyLoopEnabled == false then return end
local previous = environment.DemonologySession
if previous and type(previous.Destroy) == "function" then
	pcall(previous.Destroy, previous)
end
environment.DemonologySession = nil
environment.DemonologyLoopEnabled = true
local token = %q
if environment.DemonologyHandoffToken == token then return end
environment.DemonologyHandoffToken = token
environment.DemonologyAutoHandoff = {
	Auto = true,
	Context = %q,
	Settings = {
		Auto = true,
		JobSite = %q,
		Difficulty = %q,
		CustomPreset = %q,
		EquipmentPreset = %q,
		GhostWalkSpeedMultiplier = %s,
		Challenges = {%s, %s, %s},
		ChallengesConfigured = %s,
	},
}
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(4)
if environment.DemonologyLoopEnabled == false then return end
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local url = %q .. "?v=" .. tostring(os.time())
local source, failure
for attempt = 1, 3 do
	local ok, result = pcall(game.HttpGet, game, url)
	if ok and type(result) == "string" and result ~= "" then
		source = result
		break
	end
	failure = result
	if attempt < 3 then task.wait(attempt) end
end
assert(source, "Demonology auto-loader download failed: " .. tostring(failure))
local chunk, compileError = compiler(source, "@DemonologyAutoLoop")
assert(chunk, compileError)
chunk()
]], token, context,
			tostring(settings.JobSite or "School"),
			tostring(settings.Difficulty or "Nightmare"),
			tostring(settings.CustomPreset or ""),
			tostring(settings.EquipmentPreset or "green"),
			tostring(tonumber(settings.GhostWalkSpeedMultiplier) or "nil"),
			tostring(challenges[1] == true), tostring(challenges[2] == true),
			tostring(challenges[3] == true), tostring(settings.ChallengesConfigured == true),
			loaderUrl)
		local ok, failure = pcall(queue, source)
		if not ok then return false, tostring(failure) end
		self.QueuedContext = context
		return true
	end

	return controller
end
