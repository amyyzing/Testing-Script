local requestedAuto, requestedArrivalContext = ...

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local BASE_URL = "https://raw.githubusercontent.com/amyyzing/Testing-Script/main/"
local RUN_VERSION = tostring(os.time())
local environment = (getgenv and getgenv()) or _G
local autoEnabled
if type(requestedAuto) == "boolean" then
	autoEnabled = requestedAuto
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
environment.DemonologyAuto = autoEnabled
local Services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	TweenService = game:GetService("TweenService"),
	UserInputService = game:GetService("UserInputService"),
	Lighting = game:GetService("Lighting"),
	CoreGui = game:GetService("CoreGui"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	CollectionService = game:GetService("CollectionService"),
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
	return string.format([[
local environment = (getgenv and getgenv()) or _G
if environment.DemonologyAutoExecuted then
	return
end
environment.DemonologyAutoExecuted = true
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local url = %q .. "?v=" .. tostring(os.time())
local source = game:HttpGet(url)
local chunk, compileError = compiler(source, "@DemonologyAutoLoader")
assert(chunk, compileError)
chunk(true, %q)
]], BASE_URL .. "logic.luau", tostring(context or "Teleport"))
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

local LOBBY_MACRO_DELAY = 0.5

local function runLobbyStartMacro()
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

	-- Resolve everything before dispatch so a missing endpoint cannot leave the
	-- lobby only partially configured.
	local loadingFinished = arrivalContext == "ReturnToLobby"
		and requireRemote("LoadingFinished")
		or nil
	local changeJobSite = requireRemote("ChangeJobSite")
	local changeDifficulty = requireRemote("ChangeDifficulty")
	local applyDifficultyPreset = requireRemote("ApplyDifficultyPreset")
	local applyEquipmentPreset = requireRemote("ApplyEquipmentPreset")
	local changeStatus = requireRemote("ChangeStatus")
	local attemptStart = requireRemote("AttemptStart")
	local prepared, prepareFailure = session:PrepareTeleport("AttemptStart")
	if not prepared then
		session.TeleportQueueFailure = prepareFailure
			or "AttemptStart teleport execution was not prepared"
	end

	local function waitForDispatch()
		assertCurrent()
		task.wait(LOBBY_MACRO_DELAY)
		assertCurrent()
	end

	if loadingFinished then
		waitForDispatch()
		loadingFinished:FireServer()
	end

	waitForDispatch()
	changeJobSite:FireServer("School")

	waitForDispatch()
	changeDifficulty:FireServer("Minus")

	waitForDispatch()
	applyDifficultyPreset:FireServer("john4")

	waitForDispatch()
	applyEquipmentPreset:FireServer("green")

	waitForDispatch()
	changeStatus:FireServer()

	waitForDispatch()
	attemptStart:FireServer()
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
	session.Mode = "LobbyMacro"
	local started, startFailure = xpcall(runLobbyStartMacro, debug.traceback)
	if not started then
		session:Destroy()
		error(startFailure, 0)
	end
	return session
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
		AutoStart = autoEnabled,
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
