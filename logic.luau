if not game:IsLoaded() then
	game.Loaded:Wait()
end

local BASE_URL = "https://raw.githubusercontent.com/amyyzing/Testing-Script/main/"
local RUN_VERSION = tostring(os.time())
local environment = (getgenv and getgenv()) or _G
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
local generation = (tonumber(environment.DemonologyGeneration) or 0) + 1
environment.DemonologyGeneration = generation

local previousSession = environment.DemonologySession
if previousSession and type(previousSession.Destroy) == "function" then
	pcall(previousSession.Destroy, previousSession)
elseif environment.UntitledGuiCleanup then
	pcall(environment.UntitledGuiCleanup)
end

local session = {
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

local LOBBY_MACRO_DELAY = 0.5
local LOBBY_DIFFICULTY_SETTINGS = {
	NewActionInterval = 4,
	GhostWalkSpeedMultiplier = 6,
	CursedPossessionAmount = 1,
	EvidenceProbabilityTimeIncrease = 4,
	GhostType = 1,
	PercentageOfDoorsOpen = 5,
	EMFChanceModifier = 4,
	FuseBoxOnByDefault = 2,
	AggressionInterval = 4,
	FlashlightsBroken = 1,
	HuntDuration = 3,
	HandprintDuration = 1,
	DisableHunts = 1,
	Weather = 4,
	KillIncreaseAmount = 6,
	EvidenceGiven = 4,
	EnergyMonitorBroken = 2,
	GhostLowerTemperatureRange = 4,
	KillsEndHunt = 2,
	StartingEnergy = 1,
	HuntInteractionMultiplier = 4,
	MinimumHuntCooldown = 1,
	GhostCanChangeFavoriteRoom = 1,
	MaxStamina = 1,
	HuntGracePeriod = 2,
	SetUpPhaseLength = 4,
	HuntProbabilityCoefficient = 7,
	HuntEnergyThreshold = 5,
	EnergyDecayRate = 8,
	EnergyDrinkRestoration = 1,
	DefaultWalkSpeed = 1,
	SpiritBoxChanceModifier = 4,
}

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
	local updateJobSite = requireRemote("UpdateJobSite")
	local updateDifficulty = requireRemote("UpdateAllCustomDifficultySettings")
	local applyPreset = requireRemote("ApplyEquipmentPreset")
	local attemptStart = requireRemote("AttemptStart")
	local fireSignal = environment.firesignal
	if type(fireSignal) ~= "function" then
		error("firesignal is unavailable for the lobby macro", 0)
	end

	local function waitForDispatch()
		assertCurrent()
		task.wait(LOBBY_MACRO_DELAY)
		assertCurrent()
	end

	waitForDispatch()
	fireSignal(updateJobSite.OnClientEvent, "School")

	waitForDispatch()
	fireSignal(
		updateDifficulty.OnClientEvent,
		LOBBY_DIFFICULTY_SETTINGS,
		2.47
	)

	waitForDispatch()
	applyPreset:FireServer("green")

	waitForDispatch()
	attemptStart:FireServer()
end

-- Discardable loader probe: take exactly one snapshot and create no listener.
-- A missing Workspace.Ghost means this execution is in the lobby setup path,
-- so run the ordered macro and do not construct the in-round interface.
local loaderGhost = workspace:FindFirstChild("Ghost")
local shouldLoadRoundGui = loaderGhost ~= nil and loaderGhost:IsA("Model")
loaderGhost = nil
if not shouldLoadRoundGui then
	session.Mode = "LobbyMacro"
	local started, startFailure = xpcall(runLobbyStartMacro, debug.traceback)
	if not started then
		session:Destroy()
		error(startFailure, 0)
	end
	return session
end

local function fetchRemoteSource(path)
	if sourceCache[path] then
		return sourceCache[path]
	end
	local url = BASE_URL .. path .. "?v=" .. RUN_VERSION
	local lastFailure
	for attempt = 1, 3 do
		assertCurrent()
		local fetched, source = pcall(game.HttpGet, game, url)
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
	local workerCount = math.min(6, #paths)
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

	loader:SetStage("Loading interface theme and copy…", 1, 9)
	local Aesthetic = loadRemoteModule("gui/aesthetic.luau")
	assertCurrent()

	loader:SetStage("Loading ghost catalog…", 2, 9)
	local GhostModule = loadRemoteModule("logic/ghost-module.luau")
	assertCurrent()
	prefetchRemoteSources(GHOST_PACKAGE_PATHS, function(completed, total, path)
		local label = tostring(path):match("([^/]+)%.luau$") or tostring(path)
		loader:SetStage(
			("Loading ghost modules %d/%d: %s..."):format(completed, total, label),
			2,
			9
		)
	end)
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
