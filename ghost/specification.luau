-- Canonical observation contract for one Demonology round. Trackers, analyzers,
-- and profile observers read this table so timing and decision boundaries cannot
-- silently drift apart.
return {
	MapSize = {
		Factors = {
			Small = 1,
			Medium = 1.05,
			Large = 1.1,
		},
		JobSites = {
			["Lincoln St"] = "Small",
			["Fenway Drive"] = "Small",
			["Juniper Road"] = "Small",
			Bodega = "Small",
			["Lilim Lane"] = "Medium",
			Cafe = "Medium",
			["Bridgewood Drive"] = "Medium",
			["Oakbridge Estates"] = "Medium",
			Prison = "Large",
			School = "Large",
			Asylum = "Large",
		},
	},
	SpeedPairs = {
		RequiredPairs = 7,
		RequiredSamples = 14,
		-- Blink phases can be short. These two confirmations stay below one
		-- normal 0.1-second phase while still avoiding the previous phase's
		-- WalkSpeed value.
		SettleDelay = 0.04,
		PhaseConfirmDelay = 0.01,
		PhantomVisibleBase = 11,
		PhantomInvisibleBase = 13.5,
		PhantomBaseTolerance = 0.1,
		HuntingMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
		OniHuntingBase = 13.5,
		NormalHuntingBase = 11,
		NormalNonHuntingBase = 11,
		NonHuntingMultiplier = 1.75,
	},
	SpeedMath = {
		-- Speeds are replicated from deterministic WalkSpeed formulas. Compare
		-- after removing the map/difficulty factor so neighbouring Normal/Oni
		-- combinations cannot both qualify.
		FlatBaseTolerance = 0.1,
		WendigoBaseTolerance = 0.02,
	},
	Wendigo = {
		RequiredTransitions = 2,
		MinimumSanitySpread = 0.5,
		BaseIntercept = 14,
		SanitySlope = 0.05,
		NonHuntMultiplier = 1.75,
	},
	Salt = {
		PlacementGrace = 4,
		UndisturbedDelay = 1.25,
		MatchRadius = 3.5,
		PostHuntProbeGrace = 1.25,
	},
	HolyOil = {
		FireProbeDelay = 0.25,
	},
	RoomTemperature = {
		SampleInterval = 0.25,
		ResidenceSeconds = 5,
		RequiredCoolingChanges = 7,
		ShadowThreshold = 0.08,
		ComparisonEpsilon = 1e-9,
	},
	Banshee = {
		RequiredBrokenGlass = 2,
		WindowSeconds = 5,
	},
	Leviathan = {
		RequiredToggles = 7,
		WindowSeconds = 2.5,
	},
	Revenant = {
		PositiveMaxSeconds = 1,
		NegativeMinSeconds = 1.5,
	},
	SpeedProbe = {
		StableEpsilon = 0.0001,
		MinimumEventDelta = 0.01,
		DeathRequiredStableReads = 3,
		DeathInitialDelay = 0.35,
		DeathSampleInterval = 0.2,
		DeathProbeWindow = 1.4,
		DeathStableTolerance = 0.01,
	},
	LineOfSight = {
		RequiredExposure = 4,
		RequiredSlowEdges = 1,
		SlowEpsilon = 0.25,
	},
	Entity = {
		SampleInterval = 0.4,
		MaximumElapsed = 0.65,
		MinimumDisplacement = 25,
		MinimumSpeed = 80,
		ResolveDelay = 1.8,
		SmokeCorrelationWindow = 1.8,
		SmokeRetention = 3,
	},
	Ravager = {
		SampleInterval = 0.1,
		ScanRadius = 45,
		MinimumRadius = 2.5,
		MaximumRadius = 40,
		MinimumDuration = 0.5,
		MinimumIntervals = 5,
		MinimumGoodShare = 0.7,
		MinimumAngularTotal = 45,
		MinimumDirectionShare = 0.65,
		RequiredObjects = 3,
	},
}
