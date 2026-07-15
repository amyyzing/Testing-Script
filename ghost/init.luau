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
	local Specification = assert(
		dependency("Specification", "ghost/specification.luau"),
		"ghost core requires Specification"
	)
	local CoordinatorFactory = assert(dependency("Coordinator", "ghost/coordinator.luau"), "ghost core requires the Coordinator factory")
	local Coordinator = CoordinatorFactory({
		Events = Events,
		EvidenceLedger = EvidenceLedger,
		Resolver = Resolver,
		Specification = Specification,
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
		Specification = Specification,
		Coordinator = Coordinator,
		Catalog = Catalog,
		Profiles = defaultProfiles,
		ProfilesByName = profilesByName,
	}

	local function classFromFactory(name)
		local paths = {
			RuntimeSignals = "ghost/trackers/active/runtime-signals.luau",
			HuntState = "ghost/trackers/active/hunt-state.luau",
			SpeedPairs = "ghost/trackers/dormant/speed-pairs.luau",
			SpeedProbe = "ghost/trackers/dormant/speed-probe.luau",
			RoomTemperature = "ghost/trackers/dormant/room-temperature.luau",
			HuntRoom = "ghost/trackers/dormant/hunt-room.luau",
			SaltPileHit = "ghost/trackers/dormant/salt-pile-hit.luau",
			HolyOil = "ghost/trackers/dormant/holy-oil.luau",
			LineOfSightSpeed = "ghost/trackers/dormant/line-of-sight-speed.luau",
			BrokenGlass = "ghost/trackers/dormant/broken-glass.luau",
			ElectronicDevices = "ghost/trackers/dormant/electronic-devices.luau",
			CrossMotion = "ghost/trackers/dormant/cross-motion.luau",
			SpecterTrial = "ghost/trackers/dormant/specter-trial.luau",
			ObjectTeleport = "ghost/trackers/dormant/object-teleport.luau",
			VortexOrbit = "ghost/trackers/dormant/vortex-orbit.luau",
			StaticGhostFacts = "ghost/trackers/discardable/static-ghost-facts.luau",
			SpeedPattern = "ghost/analyzers/speed-pattern.luau",
			SpeedMath = "ghost/analyzers/speed-math.luau",
			EvidenceCombination = "ghost/analyzers/evidence-combination.luau",
		}
		local module = dependency(name, paths[name])
		if type(module) == "function" then
			return module({Events = Events, Specification = Specification})
		end
		return module
	end

	Core.Classes = {
		RuntimeSignals = classFromFactory("RuntimeSignals"),
		HuntState = classFromFactory("HuntState"),
		SpeedPairs = classFromFactory("SpeedPairs"),
		SpeedProbe = classFromFactory("SpeedProbe"),
		RoomTemperature = classFromFactory("RoomTemperature"),
		HuntRoom = classFromFactory("HuntRoom"),
		SaltPileHit = classFromFactory("SaltPileHit"),
		HolyOil = classFromFactory("HolyOil"),
		LineOfSightSpeed = classFromFactory("LineOfSightSpeed"),
		BrokenGlass = classFromFactory("BrokenGlass"),
		ElectronicDevices = classFromFactory("ElectronicDevices"),
		CrossMotion = classFromFactory("CrossMotion"),
		SpecterTrial = classFromFactory("SpecterTrial"),
		ObjectTeleport = classFromFactory("ObjectTeleport"),
		VortexOrbit = classFromFactory("VortexOrbit"),
		StaticGhostFacts = classFromFactory("StaticGhostFacts"),
		SpeedPattern = classFromFactory("SpeedPattern"),
		SpeedMath = classFromFactory("SpeedMath"),
		EvidenceCombination = classFromFactory("EvidenceCombination"),
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
		local runtimeContext = {}
		for key, value in pairs(type(options.RuntimeContext) == "table"
			and options.RuntimeContext or {}) do
			runtimeContext[key] = value
		end
		runtimeContext.Catalog = runtimeContext.Catalog
			or options.Catalog or defaultProfiles

		if options.IncludeRuntimeSignals ~= false
			and runtimeContext.GhostModel ~= nil then
			append(trackers, instantiate(Core.Classes.RuntimeSignals, options.RuntimeSignals))
		end
		append(trackers, instantiate(Core.Classes.HuntState, options.HuntState))
		append(trackers, instantiate(Core.Classes.SpeedPairs, options.SpeedPairs))
		append(trackers, instantiate(Core.Classes.SpeedProbe, options.SpeedProbe))
		append(trackers, instantiate(Core.Classes.RoomTemperature, options.RoomTemperature))
		append(trackers, instantiate(Core.Classes.HuntRoom, options.HuntRoom))
		append(trackers, instantiate(Core.Classes.SaltPileHit, options.SaltPileHit))
		append(trackers, instantiate(Core.Classes.HolyOil, options.HolyOil))
		append(trackers, instantiate(Core.Classes.LineOfSightSpeed, options.LineOfSightSpeed))
		append(trackers, instantiate(Core.Classes.BrokenGlass, options.BrokenGlass))
		append(trackers, instantiate(Core.Classes.ElectronicDevices, options.ElectronicDevices))
		append(trackers, instantiate(Core.Classes.CrossMotion, options.CrossMotion))
		append(trackers, instantiate(Core.Classes.SpecterTrial, options.SpecterTrial))
		append(trackers, instantiate(Core.Classes.ObjectTeleport, options.ObjectTeleport))
		append(trackers, instantiate(Core.Classes.VortexOrbit, options.VortexOrbit))
		if options.IncludeStaticGhostFacts ~= false
			and runtimeContext.GhostModel ~= nil then
			append(trackers, instantiate(Core.Classes.StaticGhostFacts, options.StaticGhostFacts))
		end
		for _, tracker in ipairs(type(options.AdditionalTrackers) == "table" and options.AdditionalTrackers or {}) do
			append(trackers, tracker)
		end

		append(analyzers, instantiate(Core.Classes.SpeedPattern, options.SpeedPattern))
		append(analyzers, instantiate(Core.Classes.SpeedMath, options.SpeedMath))
		append(analyzers, instantiate(Core.Classes.EvidenceCombination, options.EvidenceCombination))
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
			Specification = options.Specification or Specification,
			Catalog = options.Catalog or defaultProfiles,
			Definitions = options.Definitions or options.Profiles or defaultProfiles,
			Trackers = trackers,
			Analyzers = analyzers,
		})
		if options.AutoStart ~= false then
			coordinator:Start(runtimeContext)
		end
		return coordinator
	end

	Core.New = Core.Create
	return Core
end
