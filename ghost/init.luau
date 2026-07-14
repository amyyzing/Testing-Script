return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local loadModule = dependencies.LoadModule
	local function dependency(name, path)
		if dependencies[name] ~= nil then return dependencies[name] end
		if type(loadModule) == "function" then return loadModule(path) end
		return nil
	end
	local Events = assert(dependency("Events", "ghost/events.luau"), "ghost core requires Events")
	local EvidenceLedger = assert(dependency("EvidenceLedger", "ghost/evidence-ledger.luau"), "ghost core requires EvidenceLedger")
	local Resolver = assert(dependency("Resolver", "ghost/resolver.luau"), "ghost core requires Resolver")
	local CoordinatorFactory = assert(dependency("Coordinator", "ghost/coordinator.luau"), "ghost core requires the Coordinator factory")
	local Coordinator = CoordinatorFactory({
		Events = Events,
		EvidenceLedger = EvidenceLedger,
		Resolver = Resolver,
	})
	local Catalog = dependency("Catalog", "ghost/catalog.luau")
	local defaultProfiles = dependencies.Profiles
	local profilesByName = dependencies.ProfilesByName
	if defaultProfiles == nil and type(Catalog) == "table"
		and type(Catalog.Load) == "function" and type(loadModule) == "function" then
		defaultProfiles, profilesByName = Catalog.Load(loadModule)
	end

	local Core = {
		Events = Events,
		EvidenceLedger = EvidenceLedger,
		Resolver = Resolver,
		Coordinator = Coordinator,
		Catalog = Catalog,
		Profiles = defaultProfiles,
		ProfilesByName = profilesByName,
	}

	local function classFromFactory(name)
		local paths = {
			HuntState = "ghost/trackers/active/hunt-state.luau",
			SignalBridge = "ghost/trackers/active/signal-bridge.luau",
			SpeedPairs = "ghost/trackers/dormant/speed-pairs.luau",
			SpeedProbe = "ghost/trackers/dormant/speed-probe.luau",
			RoomTemperature = "ghost/trackers/dormant/room-temperature.luau",
			ObservationWindow = "ghost/trackers/dormant/observation-window.luau",
			StaticGhostFacts = "ghost/trackers/discardable/static-ghost-facts.luau",
			QualifiedOneShot = "ghost/trackers/discardable/qualified-one-shot.luau",
			SpeedPattern = "ghost/analyzers/speed-pattern.luau",
			SpeedMath = "ghost/analyzers/speed-math.luau",
		}
		local module = dependency(name, paths[name])
		if type(module) == "function" then
			return module({Events = Events})
		end
		return module
	end

	Core.Classes = {
		HuntState = classFromFactory("HuntState"),
		SignalBridge = classFromFactory("SignalBridge"),
		SpeedPairs = classFromFactory("SpeedPairs"),
		SpeedProbe = classFromFactory("SpeedProbe"),
		RoomTemperature = classFromFactory("RoomTemperature"),
		ObservationWindow = classFromFactory("ObservationWindow"),
		StaticGhostFacts = classFromFactory("StaticGhostFacts"),
		QualifiedOneShot = classFromFactory("QualifiedOneShot"),
		SpeedPattern = classFromFactory("SpeedPattern"),
		SpeedMath = classFromFactory("SpeedMath"),
	}

	local function append(target, value)
		if value ~= nil then
			table.insert(target, value)
		end
	end

	local function instantiate(class, options)
		if type(class) ~= "table" then
			return nil
		end
		local constructor = class.new or class.New
		if type(constructor) ~= "function" then
			return nil
		end
		return constructor(options)
	end

	function Core.Create(options)
		options = type(options) == "table" and options or {}
		local trackers = {}
		local analyzers = {}

		append(trackers, instantiate(Core.Classes.HuntState, options.HuntState))
		append(trackers, instantiate(Core.Classes.SpeedPairs, options.SpeedPairs))
		append(trackers, instantiate(Core.Classes.SpeedProbe, options.SpeedProbe))
		append(trackers, instantiate(Core.Classes.RoomTemperature, options.RoomTemperature))
		if options.IncludeStaticGhostFacts ~= false
			and type(options.RuntimeContext) == "table"
			and options.RuntimeContext.GhostModel ~= nil then
			append(trackers, instantiate(Core.Classes.StaticGhostFacts, options.StaticGhostFacts))
		end
		if type(options.SignalSources) == "table" then
			local bridge = Core.Classes.SignalBridge
			if type(bridge) == "table" and type(bridge.new or bridge.New) == "function" then
				append(trackers, (bridge.new or bridge.New)(options.SignalSources, options.SignalBridge))
			end
		end
		for _, tracker in ipairs(type(options.AdditionalTrackers) == "table" and options.AdditionalTrackers or {}) do
			append(trackers, tracker)
		end

		append(analyzers, instantiate(Core.Classes.SpeedPattern, options.SpeedPattern))
		append(analyzers, instantiate(Core.Classes.SpeedMath, options.SpeedMath))
		for _, analyzer in ipairs(type(options.AdditionalAnalyzers) == "table" and options.AdditionalAnalyzers or {}) do
			append(analyzers, analyzer)
		end

		local coordinator = Coordinator.new({
			Name = options.Name,
			Clock = options.Clock,
			Schedule = options.Schedule,
			OnError = options.OnError,
			OnChanged = options.OnChanged,
			RecordEvents = options.RecordEvents,
			RecordTransientEvents = options.RecordTransientEvents,
			HistoryLimit = options.HistoryLimit,
			Round = options.Round,
			Catalog = options.Catalog or defaultProfiles,
			Definitions = options.Definitions or options.Profiles or defaultProfiles,
			Trackers = trackers,
			Analyzers = analyzers,
		})
		if options.AutoStart ~= false then
			coordinator:Start(options.RuntimeContext or {})
		end
		return coordinator
	end

	Core.New = Core.Create
	return Core
end
