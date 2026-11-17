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
		if dependencies.TeleportService then
			pcall(dependencies.TeleportService.SetTeleportSetting,
				dependencies.TeleportService, "DemonologyAutomation", self.Enabled)
		end
		if self.Enabled and dependencies.ArmOnEnable then
			local ok, failure = self:Queue("Teleport")
			self.LastError = ok and nil or failure
		end
		return self.Enabled
	end

	function controller:Destroy()
		self:SetEnabled(false)
		self.QueuedContext = nil
		if self.Connection then self.Connection:Disconnect() end
	end

	function controller:Queue(context)
		if not self.Enabled then return false, "automation loop is disabled" end
		if type(queue) ~= "function" then return false, "queue_on_teleport is unavailable" end
		context = tostring(context or "Teleport")
		if self.QueuedContext == context or self.QueuedContext == "Teleport" then return true end
		serial += 1
		local settings = dependencies.ReadSettings and dependencies.ReadSettings() or {}
		local challenges = type(settings.Challenges) == "table" and settings.Challenges or {}
		local token = table.concat({tostring(os.time()), tostring(os.clock()), tostring(serial), context}, ":")
		local source = string.format([[
local environment = (getgenv and getgenv()) or _G
if environment.DemonologyLoopEnabled == false then return end
if not game:IsLoaded() then game.Loaded:Wait() end
local readSetting, enabled = pcall(function()
	return game:GetService("TeleportService"):GetTeleportSetting("DemonologyAutomation")
end)
if readSetting and enabled == false then return end
local arrival = tostring(game.JobId)
if environment.DemonologyArrivalGame == game and environment.DemonologyArrivalJob == arrival then return end
local activeArrival = environment.DemonologyArrivalLoading
if activeArrival and activeArrival.Game == game and activeArrival.JobId == arrival then return end
local current = environment.DemonologySession
if current and current.Game == game and current.JobId == arrival and current.Ready and not current.Destroyed then return end
local owner = {Game = game, JobId = arrival}
environment.DemonologyArrivalLoading = owner
local completed, failure = xpcall(function()
environment.DemonologyLoopEnabled = true
local token = %q
if environment.DemonologyHandoffToken == token then return end
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
environment.DemonologyAutoHandoff.Context = game.PlaceId == 18199615050 and "ReturnToLobby" or "AttemptStart"
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
local ok, result = xpcall(chunk, debug.traceback)
if not ok then
	environment.DemonologyHandoffToken = nil
	error(result, 0)
end
environment.DemonologyArrivalJob = arrival
environment.DemonologyArrivalGame = game
environment.DemonologyHandoffToken = token
end, debug.traceback)
if environment.DemonologyArrivalLoading == owner then environment.DemonologyArrivalLoading = nil end
if not completed then error(failure, 0) end
]], token, context,
			tostring(settings.JobSite or ""),
			tostring(settings.Difficulty or ""),
			tostring(settings.CustomPreset or ""),
			tostring(settings.EquipmentPreset or "Current equipment"),
			tostring(tonumber(settings.GhostWalkSpeedMultiplier) or "nil"),
			tostring(challenges[1] == true), tostring(challenges[2] == true),
			tostring(challenges[3] == true), tostring(settings.ChallengesConfigured == true),
			loaderUrl)
		local ok, failure = pcall(queue, source)
		if not ok then return false, tostring(failure) end
		self.QueuedContext = context
		return true
	end

	local player = dependencies.Player
	if player and player.OnTeleport then
		controller.Connection = player.OnTeleport:Connect(function(state)
			if tostring(state) == "Enum.TeleportState.Failed" then
				controller.QueuedContext = nil
				if controller.Enabled then controller:Queue("Teleport") end
			end
		end)
	end
	return controller
end
