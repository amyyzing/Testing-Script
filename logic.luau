local requestedAuto, requestedArrivalContext = ...

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local BASE_URL = "https://raw.githubusercontent.com/amyyzing/Testing-Script/main/"
local RUN_VERSION = tostring(os.time())
local environment = (getgenv and getgenv()) or _G
local HttpService = game:GetService("HttpService")
local SETTINGS_DIRECTORY = "DemonologyAssistant"
local SETTINGS_FILE = SETTINGS_DIRECTORY .. "/Settings.json"

local function executorApi(name)
	if type(environment[name]) == "function" then
		return environment[name]
	end
	for _, namespaceName in ipairs({"syn", "fluxus", "krnl"}) do
		local namespace = environment[namespaceName]
		if type(namespace) == "table" and type(namespace[name]) == "function" then
			return namespace[name]
		end
	end
	return nil
end

local executorFiles = {
	IsFile = executorApi("isfile"),
	IsFolder = executorApi("isfolder"),
	MakeFolder = executorApi("makefolder"),
	ReadFile = executorApi("readfile"),
	WriteFile = executorApi("writefile"),
}

local function readSettingsFile()
	if type(executorFiles.ReadFile) ~= "function" then
		return nil
	end
	if type(executorFiles.IsFile) == "function" then
		local checked, exists = pcall(executorFiles.IsFile, SETTINGS_FILE)
		if not checked or not exists then
			return nil
		end
	end
	local read, source = pcall(executorFiles.ReadFile, SETTINGS_FILE)
	if not read or type(source) ~= "string" or source == "" then
		return nil
	end
	local decoded, settings = pcall(HttpService.JSONDecode, HttpService, source)
	if decoded and type(settings) == "table" then
		return settings
	end
	return nil
end

local fileLobbySettings = readSettingsFile()
local memoryLobbySettings = type(environment.DemonologyLobbySettings) == "table"
	and environment.DemonologyLobbySettings
	or nil
local rememberedLobbySettings = {}
for key, value in pairs(fileLobbySettings or {}) do
	rememberedLobbySettings[key] = value
end
for key, value in pairs(memoryLobbySettings or {}) do
	rememberedLobbySettings[key] = value
end
if type(fileLobbySettings) == "table"
	and type(fileLobbySettings.Challenges) == "table"
	and type(memoryLobbySettings) == "table"
	and type(memoryLobbySettings.Challenges) == "table" then
	rememberedLobbySettings.Challenges = {}
	for index = 1, 3 do
		local memoryValue = memoryLobbySettings.Challenges[index]
		if type(memoryValue) == "boolean" then
			rememberedLobbySettings.Challenges[index] = memoryValue
		else
			rememberedLobbySettings.Challenges[index] = fileLobbySettings.Challenges[index]
		end
	end
end
local autoEnabled
if type(requestedAuto) == "boolean" then
	autoEnabled = requestedAuto
elseif type(rememberedLobbySettings.Auto) == "boolean" then
	autoEnabled = rememberedLobbySettings.Auto
elseif type(environment.DemonologyAuto) == "boolean" then
	autoEnabled = environment.DemonologyAuto
elseif type(environment.Auto) == "boolean" then
	autoEnabled = environment.Auto
else
	autoEnabled = false
end
local arrivalContext = type(requestedArrivalContext) == "string"
	and requestedArrivalContext
	or nil
local rememberedChallenges = type(rememberedLobbySettings.Challenges) == "table"
	and rememberedLobbySettings.Challenges
	or {}
local lobbySettings = {
	Auto = autoEnabled,
	JobSite = type(rememberedLobbySettings.JobSite) == "string"
		and rememberedLobbySettings.JobSite
		or "School",
	Difficulty = type(rememberedLobbySettings.Difficulty) == "string"
		and rememberedLobbySettings.Difficulty
		or "Nightmare",
	CustomPreset = type(rememberedLobbySettings.CustomPreset) == "string"
		and rememberedLobbySettings.CustomPreset ~= ""
		and rememberedLobbySettings.CustomPreset
		or nil,
	EquipmentPreset = type(rememberedLobbySettings.EquipmentPreset) == "string"
		and rememberedLobbySettings.EquipmentPreset ~= ""
		and rememberedLobbySettings.EquipmentPreset
		or "green",
	Challenges = {
		[1] = rememberedChallenges[1] == true,
		[2] = rememberedChallenges[2] == true,
		[3] = rememberedChallenges[3] == true,
	},
	ChallengesConfigured = rememberedLobbySettings.ChallengesConfigured == true,
}
environment.DemonologyAuto = autoEnabled
environment.DemonologyLobbySettings = lobbySettings
local Services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	TweenService = game:GetService("TweenService"),
	UserInputService = game:GetService("UserInputService"),
	Lighting = game:GetService("Lighting"),
	CoreGui = game:GetService("CoreGui"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	CollectionService = game:GetService("CollectionService"),
	HttpService = HttpService,
}
local player = Services.Players.LocalPlayer
local SUPERSEDED = "__DEMONOLOGY_SUPERSEDED__"
local moduleCache = {}
local sourceCache = {}
local GHOST_PACKAGE_PATHS = {
	"ghost/init.luau",
	"ghost/events.luau",
	"ghost/evidence-ledger.luau",
	"ghost/resolver.luau",
	"ghost/coordinator.luau",
	"ghost/catalog.luau",
	"ghost/Aswang.luau",
	"ghost/Banshee.luau",
	"ghost/Demon.luau",
	"ghost/Dullahan.luau",
	"ghost/Dybbuk.luau",
	"ghost/Entity.luau",
	"ghost/Ghoul.luau",
	"ghost/Keres.luau",
	"ghost/Leviathan.luau",
	"ghost/Nightmare.luau",
	"ghost/Oni.luau",
	"ghost/Phantom.luau",
	"ghost/Ravager.luau",
	"ghost/Revenant.luau",
	"ghost/Shadow.luau",
	"ghost/Siren.luau",
	"ghost/Skinwalker.luau",
	"ghost/Specter.luau",
	"ghost/Spirit.luau",
	"ghost/Umbra.luau",
	"ghost/Vesper.luau",
	"ghost/Vex.luau",
	"ghost/Wendigo.luau",
	"ghost/Wisp.luau",
	"ghost/Wraith.luau",
	"ghost/trackers/active/hunt-state.luau",
	"ghost/trackers/active/signal-bridge.luau",
	"ghost/trackers/dormant/speed-pairs.luau",
	"ghost/trackers/dormant/speed-probe.luau",
	"ghost/trackers/dormant/observation-window.luau",
	"ghost/trackers/discardable/static-ghost-facts.luau",
	"ghost/trackers/discardable/qualified-one-shot.luau",
	"ghost/analyzers/speed-pattern.luau",
	"ghost/analyzers/speed-math.luau",
}
local RUNTIME_MODULE_PATHS = {
	"gui/aesthetic.luau",
	"gui/gui-logic.luau",
	"logic/ghost-module.luau",
	"logic/round-automation.luau",
	"logic/logic.luau",
}
for _, path in ipairs(GHOST_PACKAGE_PATHS) do
	table.insert(RUNTIME_MODULE_PATHS, path)
end
local generation = (tonumber(environment.DemonologyGeneration) or 0) + 1
environment.DemonologyGeneration = generation

local previousSession = environment.DemonologySession
if previousSession and type(previousSession.Destroy) == "function" then
	pcall(previousSession.Destroy, previousSession)
elseif environment.UntitledGuiCleanup then
	pcall(environment.UntitledGuiCleanup)
end

local session = {
	Auto = autoEnabled,
	ArrivalContext = arrivalContext,
	Destroyed = false,
	Generation = generation,
	LobbySettings = lobbySettings,
	AutoRevision = 0,
}
environment.DemonologySession = session

local function isCurrent()
	return not session.Destroyed
		and environment.DemonologyGeneration == generation
		and environment.DemonologySession == session
end

local function assertCurrent()
	if not isCurrent() then
		error(SUPERSEDED, 0)
	end
end

function session:Destroy(keepLoader)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	local ownsSession = environment.DemonologySession == self
		and environment.DemonologyGeneration == self.Generation
	local ownsGui = environment.DemonologyGuiGeneration == self.Generation

	if self.Controller then
		pcall(self.Controller.Destroy, self.Controller)
	elseif self.LobbyView and type(self.LobbyView.Destroy) == "function" then
		pcall(self.LobbyView.Destroy, self.LobbyView)
	elseif self.View and self.View.Gui then
		pcall(self.View.Gui.Destroy, self.View.Gui)
	elseif ownsGui and environment.UntitledGuiInstance then
		pcall(environment.UntitledGuiInstance.Destroy, environment.UntitledGuiInstance)
	end
	if not keepLoader and self.Loader then
		pcall(self.Loader.Destroy, self.Loader)
	end
	if self.TeleportConnection and self.TeleportConnection.Connected then
		self.TeleportConnection:Disconnect()
	end
	if self.IdleConnection and self.IdleConnection.Connected then
		self.IdleConnection:Disconnect()
	end
	if self.LobbyReadyConnection and self.LobbyReadyConnection.Connected then
		self.LobbyReadyConnection:Disconnect()
	end

	if ownsSession then
		environment.DemonologySession = nil
		environment.UntitledGuiLoaded = nil
		environment.DemonologyUI = nil
	end
	if ownsGui then
		environment.DemonologyGuiGeneration = nil
		environment.UntitledGuiInstance = nil
		environment.UntitledGuiCleanup = nil
	end
end

local queueOnTeleport = environment.queue_on_teleport
	or environment.queueonteleport
local executorNamespace = environment.syn or environment.fluxus or environment.krnl
if type(queueOnTeleport) ~= "function" and type(executorNamespace) == "table" then
	queueOnTeleport = executorNamespace.queue_on_teleport
		or executorNamespace.queueonteleport
end

local function queuedLoaderSource(context)
	local saved = type(environment.DemonologyLobbySettings) == "table"
		and environment.DemonologyLobbySettings
		or lobbySettings
	return string.format([[
local environment = (getgenv and getgenv()) or _G
if environment.DemonologyAutoExecuted then
	return
end
environment.DemonologyAutoExecuted = true
environment.DemonologyAuto = %s
environment.DemonologyLobbySettings = {
	Auto = %s,
	JobSite = %q,
	Difficulty = %q,
	CustomPreset = %q,
	EquipmentPreset = %q,
	Challenges = {%s, %s, %s},
	ChallengesConfigured = %s,
}
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local url = %q .. "?v=" .. tostring(os.time())
local source = game:HttpGet(url)
local chunk, compileError = compiler(source, "@DemonologyAutoLoader")
assert(chunk, compileError)
chunk(%s, %q)
]],
		tostring(session.Auto == true),
		tostring(session.Auto == true),
		tostring(saved.JobSite or "School"),
		tostring(saved.Difficulty or "Nightmare"),
		tostring(saved.CustomPreset or ""),
		tostring(saved.EquipmentPreset or "green"),
		tostring(type(saved.Challenges) == "table" and saved.Challenges[1] == true),
		tostring(type(saved.Challenges) == "table" and saved.Challenges[2] == true),
		tostring(type(saved.Challenges) == "table" and saved.Challenges[3] == true),
		tostring(saved.ChallengesConfigured == true),
		BASE_URL .. "logic.luau",
		tostring(session.Auto == true),
		tostring(context or "Teleport")
	)
end

function session:PrepareTeleport(context)
	if not self.Auto then
		return true
	end
	if type(queueOnTeleport) ~= "function" then
		return false, "this executor does not provide queue_on_teleport"
	end
	if not self.TeleportConnection then
		return false, self.TeleportConnectionFailure
			or "the teleport listener could not be connected"
	end
	self.PendingTeleportContext = tostring(context or "Teleport")
	self.TeleportQueued = false
	self.TeleportQueueFailure = nil
	return true
end

local teleportConnected, teleportConnection = pcall(function()
	return player.OnTeleport:Connect(function()
		if not isCurrent()
			or not session.Auto
			or session.TeleportQueued
			or not session.PendingTeleportContext then
			return
		end
		local queued, queueFailure = pcall(
			queueOnTeleport,
			queuedLoaderSource(session.PendingTeleportContext)
		)
		if queued then
			session.TeleportQueued = true
		else
			session.TeleportQueueFailure = tostring(queueFailure)
		end
	end)
end)
if teleportConnected then
	session.TeleportConnection = teleportConnection
else
	session.TeleportConnectionFailure = tostring(teleportConnection)
end

local idleConnected, idleConnection = pcall(function()
	local virtualUser = game:GetService("VirtualUser")
	return player.Idled:Connect(function()
		if not isCurrent() then
			return
		end
		local camera = workspace.CurrentCamera
		local cameraCFrame = camera and camera.CFrame or CFrame.new()
		pcall(function()
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.new(0, 0), cameraCFrame)
		end)
	end)
end)
if idleConnected then
	session.IdleConnection = idleConnection
else
	session.IdleConnectionFailure = tostring(idleConnection)
end

local LOBBY_MACRO_DELAY = 0.75
local LOBBY_DATA_LOAD_GRACE = 4

local function waitForLobbyDataLoad(cancellationReason)
	-- game:IsLoaded() only confirms that the place replicated. The game's
	-- server-side player profile can still be loading, and sending
	-- LoadingFinished/AttemptStart during that window can trigger the
	-- "data couldn't load" kick. Keep this grace separate from the requested
	-- 0.75-second spacing between macro remotes.
	local deadline = os.clock() + LOBBY_DATA_LOAD_GRACE
	while os.clock() < deadline do
		if type(cancellationReason) == "function" then
			local reason = cancellationReason()
			if reason then
				return false, reason
			end
		end
		assertCurrent()
		task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
	end
	assertCurrent()
	return true
end

local function runLobbyStartMacro(
	settings,
	automatic,
	customPresetExists,
	equipmentPresetExists,
	readSelectedJobSite,
	readChallengeStates,
	readyRevision,
	autoRevision
)
	local monitoredReadyRevision = tonumber(readyRevision)
		or tonumber(session.LobbyReadyRevision)
		or 0
	local monitoredAutoRevision = tonumber(autoRevision)
		or tonumber(session.AutoRevision)
		or 0
	local function cancellationReason()
		if not automatic then
			return nil
		end
		if not session.Auto then
			return "Automatic start cancelled because Auto was switched off."
		end
		if session.AutoRevision ~= monitoredAutoRevision then
			return "Automatic start cancelled because Auto was changed."
		end
		if session.LobbyReadyRevision ~= monitoredReadyRevision then
			return "Automatic start cancelled because the ready state changed."
		end
		return nil
	end
	local waitedForData, initialCancellation = waitForLobbyDataLoad(cancellationReason)
	if not waitedForData then
		return false, initialCancellation
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	if not events then
		error("ReplicatedStorage.Events was not found for the lobby macro", 0)
	end
	local function requireRemote(name)
		local remote = events:FindFirstChild(name)
		if not remote or not remote:IsA("RemoteEvent") then
			error(name .. " RemoteEvent was not found for the lobby macro", 0)
		end
		return remote
	end
	local function waitForDispatch()
		local reason = cancellationReason()
		if reason then
			return false, reason
		end
		assertCurrent()
		local deadline = os.clock() + LOBBY_MACRO_DELAY
		while os.clock() < deadline do
			task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
			reason = cancellationReason()
			if reason then
				return false, reason
			end
			assertCurrent()
		end
		assertCurrent()
		return true
	end
	local loadingFinished = arrivalContext == "ReturnToLobby"
		and requireRemote("LoadingFinished")
		or nil
	if loadingFinished and not session.LobbyLoadingFinished then
		local continued, cancelReason = waitForDispatch()
		if not continued then return false, cancelReason end
		loadingFinished:FireServer()
		session.LobbyLoadingFinished = true
	end

	-- Snapshot and validate every selection before dispatching configuration
	-- remotes. LoadingFinished above is the returning-lobby handshake.
	local selectedJobSite = tostring(settings.JobSite or "School")
	local selectedDifficulty = tostring(settings.Difficulty or "Nightmare")
	local selectedCustomPreset = type(settings.CustomPreset) == "string"
		and settings.CustomPreset
		or nil
	local selectedEquipmentPreset = type(settings.EquipmentPreset) == "string"
		and settings.EquipmentPreset
		or nil
	if selectedDifficulty == "Custom"
		and (not selectedCustomPreset
			or selectedCustomPreset == ""
			or type(customPresetExists) == "function"
				and not customPresetExists(selectedCustomPreset)) then
		return false, "Select a saved custom difficulty preset before starting."
	end
	if not selectedEquipmentPreset
		or selectedEquipmentPreset == ""
		or type(equipmentPresetExists) == "function"
			and not equipmentPresetExists(selectedEquipmentPreset) then
		return false, "Select a saved equipment preset before starting."
	end
	local currentJobSite
	local jobSiteStateReady = false
	local jobSiteDeadline = os.clock() + 2
	repeat
		if type(readSelectedJobSite) == "function" then
			currentJobSite, jobSiteStateReady = readSelectedJobSite()
		end
		if jobSiteStateReady then
			break
		end
		local cancelReason = cancellationReason()
		if cancelReason then
			return false, cancelReason
		end
		assertCurrent()
		task.wait(0.1)
	until os.clock() >= jobSiteDeadline
	if not jobSiteStateReady then
		return false, "The lobby has not reported its selected Job Site yet."
	end
	local shouldChangeJobSite = currentJobSite ~= selectedJobSite
	local currentChallenges = {}
	local challengeDeadline = os.clock() + 2
	repeat
		currentChallenges = type(readChallengeStates) == "function"
			and readChallengeStates()
			or {}
		local complete = true
		for index = 1, 3 do
			if type(currentChallenges[index]) ~= "boolean" then
				complete = false
				break
			end
		end
		if complete then
			break
		end
		local cancelReason = cancellationReason()
		if cancelReason then
			return false, cancelReason
		end
		assertCurrent()
		task.wait(0.1)
	until os.clock() >= challengeDeadline
	for index = 1, 3 do
		if type(currentChallenges[index]) ~= "boolean" then
			return false, "Challenge " .. tostring(index)
				.. " has not reported its current ON/OFF state yet."
		end
	end
	local desiredChallenges = type(settings.Challenges) == "table"
		and settings.Challenges
		or {}
	if settings.ChallengesConfigured ~= true then
		desiredChallenges = {}
		for index = 1, 3 do
			desiredChallenges[index] = currentChallenges[index] == true
		end
		settings.Challenges = desiredChallenges
		settings.ChallengesConfigured = true
	end
	local challengeChanges = {}
	for index = 1, 3 do
		if currentChallenges[index] ~= (desiredChallenges[index] == true) then
			table.insert(challengeChanges, index)
		end
	end
	local readyState = player:GetAttribute("IsReady")
	local readyDeadline = os.clock() + 2
	while type(readyState) ~= "boolean" and os.clock() < readyDeadline do
		local cancelReason = cancellationReason()
		if cancelReason then
			return false, cancelReason
		end
		assertCurrent()
		task.wait(0.1)
		readyState = player:GetAttribute("IsReady")
	end
	if type(readyState) ~= "boolean" then
		return false, "The lobby has not reported the player's ready state yet."
	end
	local fireSignal = environment.firesignal or firesignal
	if type(fireSignal) ~= "function" then
		error("this executor does not provide firesignal for UpdateDifficulty", 0)
	end
	local changeJobSite = shouldChangeJobSite
		and requireRemote("ChangeJobSite")
		or nil
	local updateDifficulty = requireRemote("UpdateDifficulty")
	local applyDifficultyPreset = selectedDifficulty == "Custom"
		and requireRemote("ApplyDifficultyPreset")
		or nil
	local applyEquipmentPreset = requireRemote("ApplyEquipmentPreset")
	local toggleChallenge = #challengeChanges > 0
		and requireRemote("ToggleChallenge")
		or nil
	local changeStatus = readyState == false
		and requireRemote("ChangeStatus")
		or nil
	local attemptStart = requireRemote("AttemptStart")
	local prepared, prepareFailure = session:PrepareTeleport("AttemptStart")
	if not prepared then
		session.TeleportQueueFailure = prepareFailure
			or "AttemptStart teleport execution was not prepared"
	end

	local continued, cancelReason
	if changeJobSite then
		continued, cancelReason = waitForDispatch()
		if not continued then return false, cancelReason end
		changeJobSite:FireServer(selectedJobSite)
	end

	continued, cancelReason = waitForDispatch()
	if not continued then return false, cancelReason end
	fireSignal(updateDifficulty.OnClientEvent, selectedDifficulty)

	if applyDifficultyPreset then
		continued, cancelReason = waitForDispatch()
		if not continued then return false, cancelReason end
		applyDifficultyPreset:FireServer(selectedCustomPreset)
	end

	continued, cancelReason = waitForDispatch()
	if not continued then return false, cancelReason end
	applyEquipmentPreset:FireServer(selectedEquipmentPreset)

	for _, challengeIndex in ipairs(challengeChanges) do
		continued, cancelReason = waitForDispatch()
		if not continued then return false, cancelReason end
		toggleChallenge:FireServer(challengeIndex)
	end

	if changeStatus then
		continued, cancelReason = waitForDispatch()
		if not continued then return false, cancelReason end
		local readyRevisionBeforeDispatch = session.LobbyReadyRevision
		changeStatus:FireServer()
		local readyDeadline = os.clock() + 2
		while player:GetAttribute("IsReady") ~= true
			and os.clock() < readyDeadline do
			if automatic and (not session.Auto
				or session.AutoRevision ~= monitoredAutoRevision) then
				return false, "Automatic start cancelled because Auto was changed."
			end
			assertCurrent()
			task.wait(0.05)
		end
		if player:GetAttribute("IsReady") ~= true then
			return false, "ChangeStatus did not confirm the ready state."
		end
		if automatic
			and session.LobbyReadyRevision > readyRevisionBeforeDispatch + 1 then
			return false, "Automatic start cancelled because the ready state changed again."
		end
		-- Absorb only the transition produced by the remote above. Any later
		-- player-driven ready-state change cancels at the next dispatch gate.
		monitoredReadyRevision = tonumber(session.LobbyReadyRevision)
			or monitoredReadyRevision
	end

	continued, cancelReason = waitForDispatch()
	if not continued then return false, cancelReason end
	attemptStart:FireServer()
	return true
end

local REMOTE_FETCH_TIMEOUT = 8

local function fetchUrlWithTimeout(url)
	local finished = false
	local fetched = false
	local response
	task.spawn(function()
		fetched, response = pcall(game.HttpGet, game, url)
		finished = true
	end)
	local deadline = os.clock() + REMOTE_FETCH_TIMEOUT
	while not finished and os.clock() < deadline do
		assertCurrent()
		task.wait(0.03)
	end
	if not finished then
		return false, "request timed out after " .. tostring(REMOTE_FETCH_TIMEOUT) .. " seconds"
	end
	return fetched, response
end

local function fetchRemoteSource(path)
	if sourceCache[path] then
		return sourceCache[path]
	end
	local url = BASE_URL .. path .. "?v=" .. RUN_VERSION
	local lastFailure
	for attempt = 1, 3 do
		assertCurrent()
		local fetched, source = fetchUrlWithTimeout(url)
		if fetched and type(source) == "string" and source ~= "" then
			sourceCache[path] = source
			return source
		end
		lastFailure = fetched
			and "GitHub returned an empty module"
			or tostring(source)
		if attempt < 3 then
			task.wait(0.12 * attempt)
		end
	end
	error(("HTTP fetch failed for %s after three attempts: %s")
		:format(path, tostring(lastFailure)), 0)
end

local function loadRemoteModule(path)
	if moduleCache[path] then
		return moduleCache[path]
	end
	local source = fetchRemoteSource(path)

	local compiler = loadstring or load
	if type(compiler) ~= "function" then
		error("This executor does not provide loadstring", 0)
	end
	local chunk, compileError = compiler(source, "@" .. path)
	if not chunk then
		error(("Compilation failed for %s: %s"):format(path, tostring(compileError)), 0)
	end

	local executed, module = xpcall(chunk, debug.traceback)
	if not executed then
		error(("Initialization failed for %s:\n%s"):format(path, tostring(module)), 0)
	end
	if type(module) ~= "table" and type(module) ~= "function" then
		error(("%s must return a table or factory function"):format(path), 0)
	end
	moduleCache[path] = module
	return module
end

local function prefetchRemoteSources(paths, onProgress)
	local cursor = 0
	local completed = 0
	local firstFailure
	local workerCount = math.min(10, #paths)
	local activeWorkers = workerCount
	for _ = 1, workerCount do
		task.spawn(function()
			while isCurrent() and not firstFailure do
				cursor = cursor + 1
				local path = paths[cursor]
				if not path then
					break
				end
				local ok, failure = pcall(fetchRemoteSource, path)
				if not ok then
					firstFailure = firstFailure or failure
					break
				end
				completed = completed + 1
				if type(onProgress) == "function" then
					pcall(onProgress, completed, #paths, path)
				end
			end
			activeWorkers = activeWorkers - 1
		end)
	end
	while activeWorkers > 0 do
		assertCurrent()
		task.wait()
	end
	if firstFailure then
		error(firstFailure, 0)
	end
end

-- Discardable loader probe: take one final model snapshot and create no lasting
-- listener. A queued AttemptStart arrival gets a short replication grace period
-- so it cannot mistake a still-loading round for the lobby and start a loop.
local loaderGhost = workspace:FindFirstChild("Ghost")
if not loaderGhost and arrivalContext == "AttemptStart" then
	loaderGhost = workspace:WaitForChild("Ghost", 15)
end
local shouldLoadRoundGui = loaderGhost ~= nil and loaderGhost:IsA("Model")
loaderGhost = nil
if arrivalContext == "AttemptStart" and not shouldLoadRoundGui then
	session:Destroy()
	error("AttemptStart arrival did not replicate Workspace.Ghost within 15 seconds", 0)
end
if not shouldLoadRoundGui then
	session.Mode = "LobbySettings"
	local loaded, LobbySettings = xpcall(function()
		return loadRemoteModule("gui/lobby-settings.luau")
	end, debug.traceback)
	if not loaded then
		session:Destroy()
		error(LobbySettings, 0)
	end

	local function settingsFileSnapshot(settings)
		local challenges = type(settings.Challenges) == "table"
			and settings.Challenges
			or {}
		return {
			Version = 1,
			Auto = settings.Auto == true,
			JobSite = type(settings.JobSite) == "string" and settings.JobSite or "School",
			Difficulty = type(settings.Difficulty) == "string"
				and settings.Difficulty
				or "Nightmare",
			CustomPreset = type(settings.CustomPreset) == "string"
				and settings.CustomPreset
				or "",
			EquipmentPreset = type(settings.EquipmentPreset) == "string"
				and settings.EquipmentPreset
				or "green",
			Challenges = {
				challenges[1] == true,
				challenges[2] == true,
				challenges[3] == true,
			},
			ChallengesConfigured = settings.ChallengesConfigured == true,
		}
	end

	local function writeSettingsFile(settings)
		if type(executorFiles.WriteFile) ~= "function" then
			session.SettingsPersistence = "memory-only"
			return true
		end
		if type(executorFiles.MakeFolder) == "function" then
			local shouldCreate = true
			if type(executorFiles.IsFolder) == "function" then
				local checked, exists = pcall(executorFiles.IsFolder, SETTINGS_DIRECTORY)
				shouldCreate = not checked or not exists
			end
			if shouldCreate then
				pcall(executorFiles.MakeFolder, SETTINGS_DIRECTORY)
			end
		end
		local encoded, source = pcall(
			Services.HttpService.JSONEncode,
			Services.HttpService,
			settingsFileSnapshot(settings)
		)
		if not encoded then
			session.SettingsFileFailure = tostring(source)
			return false
		end
		local written, failure = pcall(executorFiles.WriteFile, SETTINGS_FILE, source)
		if not written then
			session.SettingsFileFailure = tostring(failure)
			return false
		end
		session.SettingsPersistence = SETTINGS_FILE
		session.SettingsFileFailure = nil
		return true
	end

	local function persistSettings(settings)
		settings.Auto = settings.Auto == true
		if session.Auto ~= settings.Auto then
			session.AutoRevision = (tonumber(session.AutoRevision) or 0) + 1
		end
		session.Auto = settings.Auto
		environment.DemonologyAuto = settings.Auto
		environment.DemonologyLobbySettings = settings
		session.LobbySettings = settings
		writeSettingsFile(settings)
	end

	session.LobbyReadyRevision = 0
	local lastReadyState = player:GetAttribute("IsReady")
	local readyConnected, readyConnection = pcall(function()
		return player:GetAttributeChangedSignal("IsReady"):Connect(function()
			if not isCurrent() then
				return
			end
			local currentReadyState = player:GetAttribute("IsReady")
			if type(lastReadyState) == "boolean"
				and type(currentReadyState) == "boolean"
				and currentReadyState ~= lastReadyState then
				session.LobbyReadyRevision = session.LobbyReadyRevision + 1
			end
			lastReadyState = currentReadyState
		end)
	end)
	if readyConnected then
		session.LobbyReadyConnection = readyConnection
	else
		session.LobbyReadyConnectionFailure = tostring(readyConnection)
	end

	local function customPresetExists(name)
		return table.find(LobbySettings.ReadCustomPresets(player), name) ~= nil
	end
	local function equipmentPresetExists(name)
		return table.find(LobbySettings.ReadEquipmentPresets(player), name) ~= nil
	end
	local function readSelectedJobSite()
		return LobbySettings.ReadSelectedJobSite(player)
	end
	local function readChallengeStates()
		return LobbySettings.ReadChallengeStates(player)
	end

	local beginLobbyStart
	local view
	beginLobbyStart = function(automatic)
		if session.LobbyStarting or not isCurrent() then
			return
		end
		session.LobbyStarting = true
		persistSettings(lobbySettings)
		local startReadyRevision = session.LobbyReadyRevision
		local startAutoRevision = session.AutoRevision
		view:SetBusy(true, automatic)
		view:SetStatus(
			automatic
				and "Auto start is waiting for lobby data; switch Auto off to cancel."
				or "Waiting for lobby data before applying the saved settings..."
		)
		task.spawn(function()
			local called, started, startFailure = xpcall(function()
				return runLobbyStartMacro(
					lobbySettings,
					automatic,
					customPresetExists,
					equipmentPresetExists,
					readSelectedJobSite,
					readChallengeStates,
					startReadyRevision,
					startAutoRevision
				)
			end, debug.traceback)
			if not isCurrent() then
				return
			end
			if not called then
				session.LobbyStarting = false
				view:SetBusy(false)
				view:SetStatus(started, true)
			elseif started ~= true then
				persistSettings(lobbySettings)
				session.LobbyStarting = false
				view:SetBusy(false)
				view:SetStatus(startFailure or "The lobby start was cancelled.", false)
			else
				persistSettings(lobbySettings)
				view:SetStatus("Settings applied; waiting for the round teleport...", false)
			end
		end)
	end

	local built, builtView = xpcall(function()
		return LobbySettings.Create({
			Services = Services,
			Player = player,
			Environment = environment,
			Generation = generation,
			Settings = lobbySettings,
			OnChanged = persistSettings,
			OnStart = function()
				beginLobbyStart(false)
			end,
		})
	end, debug.traceback)
	if not built then
		session:Destroy()
		error(builtView, 0)
	end
	view = builtView
	session.LobbyView = view
	persistSettings(lobbySettings)
	if session.Auto then
		task.defer(function()
			beginLobbyStart(true)
		end)
	end
	return session
end

local ok, failure = xpcall(function()
	assertCurrent()
	local LoadScreen = loadRemoteModule("gui/load-screen.luau")
	assertCurrent()
	local loader = LoadScreen.new({
		Services = Services,
		Player = player,
		Environment = environment,
		Generation = generation,
		Title = "Demonology Assistant",
	})
	session.Loader = loader
	assertCurrent()
	loader:SetStage(
		"Downloading runtime modules 0/" .. tostring(#RUNTIME_MODULE_PATHS),
		1,
		9
	)
	prefetchRemoteSources(RUNTIME_MODULE_PATHS, function(completed, total, path)
		local label = tostring(path):match("([^/]+)%.luau$") or tostring(path)
		loader:SetStage(
			("Downloading runtime modules %d/%d: %s..."):format(
				completed,
				total,
				label
			),
			1,
			9
		)
	end)
	assertCurrent()

	loader:SetStage("Loading interface theme and copy…", 1, 9)
	local Aesthetic = loadRemoteModule("gui/aesthetic.luau")
	assertCurrent()

	loader:SetStage("Loading ghost catalog…", 2, 9)
	local GhostModule = loadRemoteModule("logic/ghost-module.luau")
	assertCurrent()
	loader:SetStage("Assembling ghost observer package...", 2, 9)
	local createGhostPackage = loadRemoteModule("ghost/init.luau")
	local GhostPackage = createGhostPackage({
		LoadModule = function(path)
			assertCurrent()
			local label = tostring(path):match("([^/]+)%.luau$") or tostring(path)
			loader:SetStage("Loading ghost observer " .. label .. "...", 2, 9)
			return loadRemoteModule(path)
		end,
	})
	assertCurrent()

	loader:SetStage("Loading round automation…", 3, 9)
	local createRoundAutomation = loadRemoteModule("logic/round-automation.luau")
	assertCurrent()

	loader:SetStage("Loading evidence and behavior trackers…", 4, 9)
	local createLogic = loadRemoteModule("logic/logic.luau")
	assertCurrent()

	loader:SetStage("Loading interface controls…", 5, 9)
	local GuiLogic = loadRemoteModule("gui/gui-logic.luau")
	assertCurrent()

	loader:SetStage("Building the interface…", 6, 9)
	local view = Aesthetic.Create({
		Services = Services,
		Player = player,
		Environment = environment,
		Generation = generation,
	})
	session.View = view
	assertCurrent()

	loader:SetStage("Starting the presentation layer…", 7, 9)
	local presenter = GuiLogic.new({
		Services = Services,
		Player = player,
		View = view,
		OnClose = function()
			session:Destroy()
		end,
	})
	session.Presenter = presenter
	assertCurrent()

	loader:SetStage("Starting ghost trackers…", 8, 9)
	local controller = createLogic({
		Services = Services,
		Player = player,
		Environment = environment,
		Generation = generation,
		GhostModule = GhostModule,
		GhostPackage = GhostPackage,
		RoundAutomation = createRoundAutomation,
		View = view,
		Presenter = presenter,
		PrepareTeleport = function(context)
			return session:PrepareTeleport(context)
		end,
	})
	session.Controller = controller
	presenter:Bind(controller)
	assertCurrent()
	controller:Start()
	assertCurrent()
	if autoEnabled then
		-- Do not hand control to Do-Round until the replicated round, character,
		-- doors, and door remote have remained available for a full second. This
		-- gate intentionally lives outside round-automation so its proven door
		-- detection, closing, positioning, and placement routines stay untouched.
		task.spawn(function()
			local stableSince
			local deadline = os.clock() + 20
			while isCurrent() and os.clock() < deadline do
				local character = player.Character
				local root = character
					and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character
					and character:FindFirstChildOfClass("Humanoid")
				local ghost = workspace:FindFirstChild("Ghost")
				local map = workspace:FindFirstChild("Map")
				local doors = workspace:FindFirstChild("Doors")
				local events = Services.ReplicatedStorage:FindFirstChild("Events")
				local doorRemote = events
					and events:FindFirstChild("ClientChangeDoorState")
				local hasReplicatedDoor = false
				if doors then
					for _, candidate in ipairs(doors:GetChildren()) do
						if candidate:FindFirstChild("Door") then
							hasReplicatedDoor = true
							break
						end
					end
				end
				local ready = ghost ~= nil
					and ghost:IsA("Model")
					and map ~= nil
					and doors ~= nil
					and hasReplicatedDoor
					and doorRemote ~= nil
					and doorRemote:IsA("RemoteEvent")
					and root ~= nil
					and humanoid ~= nil
					and humanoid.Health > 0
				if ready then
					stableSince = stableSince or os.clock()
					if os.clock() - stableSince >= 1 then
						if isCurrent() then
							local state = controller:GetState()
							if not state.DoRound then
								controller:ToggleDoRound()
							end
						end
						return
					end
				else
					stableSince = nil
				end
				task.wait(0.1)
			end
			if isCurrent() and presenter and presenter.Notify then
				presenter:Notify(
					"Auto mode is waiting for the round doors; use Do-Round once they finish loading"
				)
			end
		end)
	end

	environment.DemonologyUI = session
	environment.UntitledGuiLoaded = true
	loader:SetStage("Ready", 9, 9)
end, debug.traceback)

if not ok then
	local superseded = string.find(tostring(failure), SUPERSEDED, 1, true) ~= nil
	local failedLoader = session.Loader
	if superseded then
		session:Destroy()
		return nil
	end
	session:Destroy(true)
	if failedLoader then
		failedLoader:Fail(tostring(failure):match("^[^\n]+") or "Module loading failed")
		task.delay(8, function()
			failedLoader:Destroy()
		end)
	end
	error(failure, 0)
end

local loader = session.Loader
task.delay(0.25, function()
	if loader and not session.Destroyed then
		loader:Destroy()
	end
end)

return session
