if not game:IsLoaded() then game.Loaded:Wait() end

local BASE_URL = "https://raw.githubusercontent.com/amyyzing/Testing-Script/refs/heads/main/"
local VERSION = tostring(os.time())
local BUNDLE_PATH = "dist/modules.luau"
local environment = (getgenv and getgenv()) or _G
local handoff = type(environment.DemonologyAutoHandoff) == "table"
	and environment.DemonologyAutoHandoff or nil
environment.DemonologyAutoHandoff = nil
local autoHandoff = handoff and handoff.Auto == true
local arrivalContext = handoff and tostring(handoff.Context or "") or ""
local Services = {
	Players = game:GetService("Players"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	UserInputService = game:GetService("UserInputService"),
	TweenService = game:GetService("TweenService"),
	RunService = game:GetService("RunService"),
	Lighting = game:GetService("Lighting"),
	CoreGui = game:GetService("CoreGui"),
	Workspace = game:GetService("Workspace"),
	HttpService = game:GetService("HttpService"),
	VirtualUser = game:GetService("VirtualUser"),
}
local player = Services.Players.LocalPlayer

local compiler = loadstring or load
assert(type(compiler) == "function", "This executor does not provide loadstring")
local function fetch(path)
	local url = BASE_URL .. path .. "?v=" .. VERSION
	local failure
	for attempt = 1, 3 do
		local ok, result = pcall(game.HttpGet, game, url)
		if ok and type(result) == "string" and result ~= "" then return result end
		failure = result
		if attempt < 3 then task.wait(attempt) end
	end
	error(("Download failed for %s: %s"):format(path, tostring(failure)), 0)
end

local bundleAttempted = false
local bundledSources
local function loadBundle()
	if bundleAttempted then return bundledSources end
	bundleAttempted = true
	local fetched, source = pcall(fetch, BUNDLE_PATH)
	if not fetched then
		warn("Demonology module bundle unavailable; using individual files: " .. tostring(source))
		return nil
	end
	local chunk, compileError = compiler(source, "@" .. BUNDLE_PATH)
	if not chunk then
		warn("Demonology module bundle did not compile; using individual files: "
			.. tostring(compileError))
		return nil
	end
	local ok, result = xpcall(chunk, debug.traceback)
	if not ok or type(result) ~= "table" then
		warn("Demonology module bundle did not initialize; using individual files: "
			.. tostring(result))
		return nil
	end
	bundledSources = result
	return bundledSources
end

local loadedModules = {}
local NIL_MODULE = {}
local function loadModule(path)
	local cached = loadedModules[path]
	if cached ~= nil then return cached ~= NIL_MODULE and cached or nil end
	local bundle = loadBundle()
	local source = bundle and bundle[path]
	if source then
		bundle[path] = nil
	else
		source = fetch(path)
	end
	assert(type(source) == "string" and source ~= "", "Empty module: " .. path)
	local chunk, compileError = compiler(source, "@" .. path)
	assert(chunk, ("Compilation failed for %s: %s"):format(path, tostring(compileError)))
	local ok, result = xpcall(chunk, debug.traceback)
	assert(ok, ("Initialization failed for %s:\n%s"):format(path, tostring(result)))
	loadedModules[path] = result == nil and NIL_MODULE or result
	return result
end

local previous = environment.DemonologySession
if previous and type(previous.Destroy) == "function" then pcall(previous.Destroy, previous) end
if autoHandoff then environment.DemonologyLoopEnabled = true end

local LoadScreen = loadModule("gui/load-screen.luau")
local loading = LoadScreen.new({Services = Services, Player = player, Title = "Demonology Assistant"})
loading:SetStage("Loading interface", 1, 10)

local Aesthetic = loadModule("gui/aesthetic.luau")
local LobbySettings = loadModule("gui/lobby-settings.luau")
loading:SetStage("Loading window controls", 2, 10)
local GuiLogic = loadModule("gui/gui-logic.luau")
loading:SetStage("Loading traffic", 3, 10)
local createTraffic = loadModule("ghost/traffic.luau")
local createRemotes = loadModule("remotes/init.luau")
local Remotes = createRemotes.new({LoadModule = loadModule})
loading:SetStage("Loading verdict", 4, 10)
local createVerdict = loadModule("ghost/verdict.luau")
local GhostCatalog = loadModule("ghost/evidence-catalog.luau")
local markJournal = Remotes:Get("EvidenceMarkedInJournal")
loading:SetStage("Loading ghost processors", 5, 10)
local Aswang = loadModule("ghost/ghosts/Aswang.luau")
local Demon = loadModule("ghost/ghosts/Demon.luau")
local Dullahan = loadModule("ghost/ghosts/Dullahan.luau")
local Entity = loadModule("ghost/ghosts/Entity.luau")
local Ghoul = loadModule("ghost/ghosts/Ghoul.luau")
local Keres = loadModule("ghost/ghosts/Keres.luau")
local Leviathan = loadModule("ghost/ghosts/Leviathan.luau")
local Oni = loadModule("ghost/ghosts/Oni.luau")
local Phantom = loadModule("ghost/ghosts/Phantom.luau")
local Ravager = loadModule("ghost/ghosts/Ravager.luau")
local Revenant = loadModule("ghost/ghosts/Revenant.luau")
local Shadow = loadModule("ghost/ghosts/Shadow.luau")
local Siren = loadModule("ghost/ghosts/Siren.luau")
local Skinwalker = loadModule("ghost/ghosts/Skinwalker.luau")
local Specter = loadModule("ghost/ghosts/Specter.luau")
local Spirit = loadModule("ghost/ghosts/Spirit.luau")
local Umbra = loadModule("ghost/ghosts/Umbra.luau")
local Vex = loadModule("ghost/ghosts/Vex.luau")
local Wendigo = loadModule("ghost/ghosts/Wendigo.luau")
local Wisp = loadModule("ghost/ghosts/Wisp.luau")
local Wraith = loadModule("ghost/ghosts/Wraith.luau")
loading:SetStage("Loading trackers", 6, 10)
local createCrossBurn = loadModule("ghost/active-trackers/cross-burn.luau")
local createEvidenceState = loadModule("ghost/active-trackers/evidence-state.luau")
local createGhostRoom = loadModule("ghost/active-trackers/ghost-room.luau")
local createHuntingState = loadModule("ghost/dormant-trackers/hunting-state.luau")
local createItemTeleport = loadModule("ghost/active-trackers/item-teleport.luau")
local createItemState = loadModule("ghost/active-trackers/item-state.luau")
local createKillCount = loadModule("ghost/active-trackers/kill-count.luau")
local createPlayerSpeed = loadModule("ghost/active-trackers/player-speed.luau")
local createSaltHit = loadModule("ghost/active-trackers/salt-hit.luau")
local createSpeedTracker = loadModule("ghost/active-trackers/speed-tracker.luau")
local createSevenPair = loadModule("ghost/filter/7-pair.luau")
local createFlickerArray = loadModule("ghost/filter/flicker-array.luau")
local createSpeedFilter = loadModule("ghost/filter/speed-filter.luau")
local createCrossAnimation = loadModule("ghost/discardable-trackers/cross-animation.luau")
local createCatchFire = loadModule("ghost/discardable-trackers/catch-fire.luau")
local createHolyOilColour = loadModule("ghost/discardable-trackers/holy-oil-colour.luau")
local createHolyOilCollidable = loadModule("ghost/discardable-trackers/holy-oil-collidable.luau")
local createHolyOilPass = loadModule("ghost/discardable-trackers/holy-oil-pass.luau")
local createFootstepSound = loadModule("ghost/discardable-trackers/footstep-sound.luau")
local createLidar = loadModule("ghost/discardable-trackers/lidar.luau")
local createModelGender = loadModule("ghost/discardable-trackers/model-gender.luau")
local createRoundStarted = loadModule("ghost/discardable-trackers/round-started.luau")
local createSaltState = loadModule("ghost/discardable-trackers/salt-state-after-hit.luau")
local createSmokeHolder = loadModule("ghost/discardable-trackers/smoke-holder.luau")
local createItemOrbit = loadModule("ghost/dormant-trackers/item-orbit.luau")
local createHumming = loadModule("ghost/dormant-trackers/humming.luau")
local createFavouriteHuntRoom = loadModule("ghost/dormant-trackers/favourite-hunt-room.luau")
local createHolyOilActivate = loadModule("ghost/dormant-trackers/holy-oil-activate.luau")
local createLOSSight = loadModule("ghost/dormant-trackers/los-sight.luau")
local createLOSSpeed = loadModule("ghost/dormant-trackers/los-speed.luau")
local createRoomTemperature = loadModule("ghost/dormant-trackers/room-temperature.luau")
local createSpecterTrial = loadModule("ghost/dormant-trackers/specter-trial.luau")
local createWendigoSpeed = loadModule("ghost/dormant-trackers/wendigo-speed.luau")
local askSpiritBox = Remotes:Get("AskSpiritBoxFromUI")
local createAutoSpiritBox = loadModule("logic/auto-spirit-box.luau")
local createAutomation = loadModule("logic/automation.luau")
local createRoundAutomation = loadModule("automation/game-round.luau")
local createRoundUtilities = loadModule("automation/shared/round-utilities.luau")
local createPreRound = loadModule("automation/pre-round/pre-round.luau")
local createLaySalt = loadModule("automation/pre-round/lay-salt.luau")
local createPourHolyOil = loadModule("automation/pre-round/pour-holy-oil.luau")
local createRound = loadModule("automation/round/round.luau")
local createRoundHuntEscape = loadModule("automation/round/hunt-escape.luau")
local createRoundItemGhostRoom = loadModule("automation/round/item-ghost-room.luau")
local createRoundMaintainItem = loadModule("automation/round/maintain-item.luau")
local createPostRound = loadModule("automation/post-round/post-round.luau")
local createRoomTeleport = loadModule("logic/room-teleport.luau")
local createRoomItemSetup = loadModule("logic/room-item-setup.luau")
local createMovement = loadModule("logic/movement.luau")
local createLobbyAutomation = loadModule("logic/lobby-automation.luau")
local createTeleportLoop = loadModule("logic/teleport-loop.luau")
local createSettingsStore = loadModule("logic/settings-store.luau")
local createAntiIdle = loadModule("logic/anti-idle.luau")
local createEscapeHunt = loadModule("logic/escape-hunt.luau")
local createBright = loadModule("logic/bright.luau")
local createGhostESP = loadModule("logic/ghost-esp.luau")
local createGhostRoomBillboard = loadModule("logic/ghost-room-billboard.luau")
local createGhostPatternLog = loadModule("logic/ghost-pattern-log.luau")
local createEvidenceLog = loadModule("logic/evidence-log.luau")

loading:SetStage("Building interface", 7, 10)
local view = Aesthetic.Create({
	Services = Services,
	Player = player,
	Environment = environment,
})
local session
local presenter = GuiLogic.new({
	Services = Services,
	Player = player,
	View = view,
	OnClose = function()
		if session then session:Destroy() end
	end,
})

session = {
	Destroyed = false,
	Connections = {},
	Trackers = {},
	View = view,
	Presenter = presenter,
	Loading = loading,
}
environment.DemonologySession = session
local settingsStore = createSettingsStore({
	Environment = environment,
	HttpService = Services.HttpService,
})
local settings = settingsStore:Load(handoff and handoff.Settings)
if not table.find(LobbySettings.JobSiteNames(), settings.JobSite) then settings.JobSite = "School" end
if not table.find(LobbySettings.Difficulties, settings.Difficulty) then settings.Difficulty = "Nightmare" end
session.Settings, session.SettingsStore = settings, settingsStore
local teleportLoop = createTeleportLoop({
	Environment = environment,
	LoaderUrl = BASE_URL .. "loader.luau",
	ReadSettings = function() return settings end,
})
session.TeleportLoop = teleportLoop

local function remember(value)
	table.insert(session.Trackers, value)
	return value
end

session.AntiIdle = remember(createAntiIdle({
	Player = player,
	VirtualUser = Services.VirtualUser,
	Workspace = Services.Workspace,
}))

local movement = createMovement({
	Services = Services,
	Player = player,
	RuntimeIsActive = function() return not session.Destroyed end,
	GetGhostModel = function() return Services.Workspace:FindFirstChild("Ghost") end,
	CreateRoomTeleport = createRoomTeleport,
})
local teleportToBaseCamp = movement.TeleportToBaseCamp
movement.CaptureBaseCampEscapePivot()
session.TeleportToBaseCamp = teleportToBaseCamp
session.Bright = remember(createBright({
	Lighting = Services.Lighting,
	Button = view.Buttons.Bright,
	EnabledColor = view.Colors.Accent,
}))
session.AutoSpirit = remember(createAutoSpiritBox({
	Player = player,
	RunService = Services.RunService,
	AskSpiritBox = askSpiritBox,
	Button = view.Buttons.AutoSpirit,
	EnabledColor = view.Colors.Accent,
}))

local initialGhost = Services.Workspace:FindFirstChild("Ghost")
if not initialGhost and arrivalContext == "AttemptStart" then
	initialGhost = Services.Workspace:WaitForChild("Ghost", 15)
end
if not initialGhost and arrivalContext ~= "AttemptStart" then
	local lobbyAutomation
	session.LobbyView = remember(LobbySettings.Create({
		View = view,
		Player = player,
		Settings = settings,
		OnChanged = function(_, source)
			settingsStore:Save(settings)
			if session.LobbyView then session.LobbyView:Render() end
			if source == "Auto" and lobbyAutomation then
				lobbyAutomation:SetLoopEnabled(settings.Auto)
			end
		end,
		OnStart = function()
			if lobbyAutomation then lobbyAutomation:Start(false, false) end
		end,
	}))
	lobbyAutomation = remember(createLobbyAutomation({
		Player = player,
		Remotes = Remotes,
		ReplicatedStorage = Services.ReplicatedStorage,
		LobbySettings = LobbySettings,
		Settings = settings,
		View = session.LobbyView,
		PrepareTeleport = function(context) return teleportLoop:Queue(context) end,
		OnEnabledChanged = function(enabled) teleportLoop:SetEnabled(enabled) end,
		OnSettingsChanged = function()
			settingsStore:Save(settings)
			session.LobbyView:Render()
		end,
		RuntimeIsActive = function() return not session.Destroyed end,
	}))
	session.LobbyAutomation = lobbyAutomation
	lobbyAutomation:SetLoopEnabled(settings.Auto)
	-- A first lobby execution never starts by itself. Only a queued return does.
	if autoHandoff and arrivalContext == "ReturnToLobby" and settings.Auto then
		lobbyAutomation:Start(true, true)
	end
end

local function disconnectWaiting()
	for _, connection in ipairs(session.Connections) do connection:Disconnect() end
	table.clear(session.Connections)
end

function session:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	if self.TeleportLoop and type(self.TeleportLoop.Destroy) == "function" then
		pcall(self.TeleportLoop.Destroy, self.TeleportLoop)
	end
	disconnectWaiting()
	for index = #self.Trackers, 1, -1 do
		local tracker = self.Trackers[index]
		if tracker and type(tracker.Destroy) == "function" then pcall(tracker.Destroy, tracker) end
	end
	self.Presenter:Destroy()
	if self.View.Gui then self.View.Gui:Destroy() end
	if self.Loading and not self.Loading.Destroyed then self.Loading:Destroy() end
	if environment.UntitledGuiInstance == self.View.Gui then environment.UntitledGuiInstance = nil end
	if environment.DemonologySession == self then environment.DemonologySession = nil end
end

if not initialGhost and arrivalContext == "AttemptStart" then
	session:Destroy()
	error("AttemptStart arrival did not replicate Workspace.Ghost within 15 seconds", 0)
end

local coreStarted, saltStarted = false, false
local descendantConnection
local function startTrackers()
	if session.Destroyed then return end
	local ghost = Services.Workspace:FindFirstChild("Ghost")
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	if not coreStarted and (not ghost or not humanoid) then
		return
	end

	if not coreStarted then
		coreStarted = true
		if descendantConnection then descendantConnection:Disconnect() end
		local Traffic = createTraffic()
		local Verdict = createVerdict({
			Traffic = Traffic,
			Player = player,
			MarkJournal = markJournal,
			EvidenceCatalog = GhostCatalog,
		})
		session.Traffic, session.Verdict, session.Ghost = Traffic, Verdict, ghost
		local journalSyncElapsed = 0
		local journalSyncConnection = Services.RunService.Heartbeat:Connect(function(delta)
			if session.Destroyed or not Verdict.JournalDirty then return end
			journalSyncElapsed += math.max(0, tonumber(delta) or 0)
			if journalSyncElapsed < 0.25 then return end
			journalSyncElapsed = 0
			Verdict:SyncJournal()
		end)
		remember({
			Destroy = function()
				if journalSyncConnection.Connected then journalSyncConnection:Disconnect() end
			end,
		})
		remember(createGhostPatternLog({
			Traffic = Traffic,
			View = view.PatternDrawer,
			PositiveColor = view.Colors.Positive,
			NegativeColor = view.Colors.Danger,
			EventColor = view.Colors.Muted,
		}))
		remember(createEvidenceLog({
			Traffic = Traffic,
			View = view.EvidenceDrawer,
			EvidenceCatalog = GhostCatalog,
			UnknownColor = view.Colors.Muted,
			PositiveColor = view.Colors.Positive,
			NegativeColor = view.Colors.Danger,
		}))
		local evidenceState = remember(createEvidenceState({
			Traffic = Traffic,
			Player = player,
			RunService = Services.RunService,
			Workspace = Services.Workspace,
			ReplicatedStorage = Services.ReplicatedStorage,
			Ghost = ghost,
			EvidenceCatalog = GhostCatalog,
			Verdict = Verdict,
			ShowSubtitle = Remotes:Get("ShowSubtitle"),
			LocalShowSubtitle = Remotes:Get("LocalShowSubtitle"),
		}))
		remember(Aswang.new({Traffic = Traffic}))
		remember(Demon.new({Traffic = Traffic}))
		remember(Dullahan.new({Traffic = Traffic}))
		remember(Entity.new({Traffic = Traffic}))
		remember(Ghoul.new({Traffic = Traffic}))
		remember(Keres.new({Traffic = Traffic}))
		remember(Leviathan.new({Traffic = Traffic}))
		remember(Oni.new({Traffic = Traffic}))
		remember(Phantom.new({Traffic = Traffic}))
		remember(Ravager.new({Traffic = Traffic}))
		remember(Revenant.new({Traffic = Traffic}))
		remember(Shadow.new({Traffic = Traffic}))
		remember(Siren.new({Traffic = Traffic}))
		remember(Skinwalker.new({Traffic = Traffic}))
		remember(Specter.new({Traffic = Traffic}))
		remember(Spirit.new({Traffic = Traffic}))
		remember(Umbra.new({Traffic = Traffic}))
		remember(Vex.new({Traffic = Traffic}))
		remember(Wendigo.new({Traffic = Traffic}))
		remember(Wisp.new({Traffic = Traffic}))
		remember(Wraith.new({Traffic = Traffic}))
		remember(createFlickerArray({Traffic = Traffic}))
		remember(createSpeedFilter({
			Traffic = Traffic,
			Workspace = Services.Workspace,
		}))
		remember(createSevenPair({
			Traffic = Traffic,
			Ghost = ghost,
			RunService = Services.RunService,
		}))
		remember(createSmokeHolder({
			Traffic = Traffic,
			Workspace = Services.Workspace,
		}))
		remember(createHumming({
			Traffic = Traffic,
			ReplicatedStorage = Services.ReplicatedStorage,
			Player = player,
		}))
		remember(createLOSSpeed({Traffic = Traffic}))
		remember(createPlayerSpeed({
			Traffic = Traffic,
			Players = Services.Players,
		}))
		remember(createLOSSight({
			Traffic = Traffic,
			Workspace = Services.Workspace,
			Ghost = ghost,
			Players = Services.Players,
			RunService = Services.RunService,
		}))
		remember(createItemTeleport({
			Traffic = Traffic,
			Workspace = Services.Workspace,
			RunService = Services.RunService,
		}))
		remember(createItemState({
			Traffic = Traffic,
			Workspace = Services.Workspace,
			Players = Services.Players,
		}))
		remember(createItemOrbit({
			Traffic = Traffic,
			Workspace = Services.Workspace,
			Ghost = ghost,
			RunService = Services.RunService,
		}))
		remember(createRoomTemperature({Traffic = Traffic}))
		remember(createModelGender({Traffic = Traffic, Ghost = ghost}))
		remember(createFootstepSound({Traffic = Traffic, Ghost = ghost}))
		remember(createLidar({Traffic = Traffic, Ghost = ghost}))
		remember(createHolyOilColour({
			Traffic = Traffic,
			Workspace = Services.Workspace,
			Ghost = ghost,
		}))
		remember(createCatchFire({Traffic = Traffic, Ghost = ghost}))
		remember(createHolyOilPass({Traffic = Traffic, Ghost = ghost}))
		remember(createHolyOilCollidable({Traffic = Traffic}))
		remember(createHolyOilActivate({
			Traffic = Traffic,
			Workspace = Services.Workspace,
		}))
		remember(createCrossAnimation({
			Traffic = Traffic,
			RunService = Services.RunService,
		}))
		remember(createCrossBurn({
			Traffic = Traffic,
			Workspace = Services.Workspace,
		}))
		session.EscapeHunt = remember(createEscapeHunt({
			Player = player,
			Ghost = ghost,
			TeleportToSafety = teleportToBaseCamp,
			FastTeleportToSafety = movement.FastTeleportToBaseCamp,
			CaptureSafetyPosition = movement.CaptureBaseCampEscapePivot,
			Button = view.Buttons.HuntEscape,
			EnabledColor = view.Colors.Accent,
		}))
		session.GhostESP = remember(createGhostESP({
			Ghost = ghost,
			RunService = Services.RunService,
			Workspace = Services.Workspace,
			GuiParent = view.Gui.Parent,
			Button = view.Buttons.GhostESP,
			EnabledColor = view.Colors.Accent,
			Red = view.Colors.Danger,
		}))
		remember(createGhostRoomBillboard({
			Ghost = ghost,
			Workspace = Services.Workspace,
			RunService = Services.RunService,
			GuiParent = view.Gui.Parent,
			Accent = view.Colors.Accent,
		}))
		remember(createSpeedTracker({Traffic = Traffic, Ghost = ghost}))
		remember(createKillCount({Traffic = Traffic, Players = Services.Players}))
		local ghostRoom = remember(createGhostRoom({
			Traffic = Traffic,
			Workspace = Services.Workspace,
			Ghost = ghost,
			RunService = Services.RunService,
		}))
		remember(createFavouriteHuntRoom({
			Traffic = Traffic,
			Ghost = ghost,
			ReadCurrentRoom = function(refresh)
				if refresh then ghostRoom:Sample() end
				return ghostRoom.Room
			end,
		}))
		remember(createSpecterTrial({
			Traffic = Traffic,
			Ghost = ghost,
			RunService = Services.RunService,
			ReadCurrentRoom = function(refresh)
				if refresh then ghostRoom:Sample() end
				return ghostRoom.Room
			end,
		}))
		remember(createWendigoSpeed({
			Traffic = Traffic,
			Players = Services.Players,
			Humanoid = humanoid,
		}))
		remember(createHuntingState({Traffic = Traffic, Ghost = ghost}))
		session.RoundStarted = remember(createRoundStarted({
			Traffic = Traffic,
			Workspace = Services.Workspace,
		}))
		session.Automation = remember(createAutomation({
			Services = Services,
			Player = player,
			Ghost = ghost,
			Verdict = Verdict,
			GhostModule = GhostCatalog,
			Movement = movement,
			FastTeleportToBaseCamp = movement.FastTeleportToBaseCamp,
			CaptureBaseCampEscapePivot = movement.CaptureBaseCampEscapePivot,
			CreateRoundAutomation = createRoundAutomation,
			CreateRoundUtilities = createRoundUtilities,
			CreatePreRound = createPreRound,
			CreateLaySalt = createLaySalt,
			CreatePourHolyOil = createPourHolyOil,
			CreateRound = createRound,
			CreateHuntEscape = createRoundHuntEscape,
			CreateItemGhostRoom = createRoundItemGhostRoom,
			CreateMaintainItem = createRoundMaintainItem,
			CreatePostRound = createPostRound,
			CreateRoomItemSetup = createRoomItemSetup,
			RoundStarted = session.RoundStarted,
			EvidenceReady = function() return evidenceState:IsSettled(2) end,
			Button = view.Buttons.Automation,
			EnabledColor = view.Colors.Accent,
			AutoSpirit = session.AutoSpirit,
			PrepareReturn = function() return teleportLoop:Queue("ReturnToLobby") end,
			RequestItemUnequip = Remotes:Get("RequestItemUnequip"),
			OnEnabledChanged = function(enabled)
				settings.Auto = enabled
				settingsStore:Save(settings)
				teleportLoop:SetEnabled(enabled)
			end,
			RuntimeIsActive = function() return not session.Destroyed end,
		}))
		if autoHandoff and arrivalContext == "AttemptStart" then
			task.spawn(function()
				local stableSince
				local deadline = os.clock() + 20
				while not session.Destroyed and os.clock() < deadline do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
					local doors = Services.Workspace:FindFirstChild("Doors")
					local events = Services.ReplicatedStorage:FindFirstChild("Events")
					local doorRemote = events and events:FindFirstChild("ClientChangeDoorState")
					local hasDoor = false
					if doors then
						for _, candidate in ipairs(doors:GetChildren()) do
							if candidate:FindFirstChild("Door") then hasDoor = true break end
						end
					end
					local ready = Services.Workspace:FindFirstChild("Ghost") == ghost
						and Services.Workspace:FindFirstChild("Map") ~= nil
						and hasDoor and doorRemote and doorRemote:IsA("RemoteEvent")
						and root ~= nil and playerHumanoid ~= nil
					if ready then
						stableSince = stableSince or os.clock()
						if os.clock() - stableSince >= 1 then
							if not session.Destroyed then session.Automation:SetEnabled(true) end
							return
						end
					else
						stableSince = nil
					end
					task.wait(0.1)
				end
			end)
		end
	end

	local saltPiles = Services.Workspace:FindFirstChild("SaltPiles")
	if not saltStarted and saltPiles then
		saltStarted = true
		remember(createSaltState({Traffic = session.Traffic, SaltFolder = saltPiles}))
		remember(createSaltHit({
			Traffic = session.Traffic,
			Ghost = session.Ghost,
			SaltFolder = saltPiles,
			Workspace = Services.Workspace,
			RunService = Services.RunService,
		}))
		disconnectWaiting()
	end
end

loading:SetStage("Starting ghost trackers", 8, 10)
table.insert(session.Connections, Services.Workspace.ChildAdded:Connect(startTrackers))
descendantConnection = Services.Workspace.DescendantAdded:Connect(startTrackers)
table.insert(session.Connections, descendantConnection)
startTrackers()
presenter:Bind()

loading:SetStage(coreStarted and "Ready" or "Waiting for round", 10, 10)
task.delay(0.2, function()
	if not loading.Destroyed then loading:Destroy() end
end)

return session
