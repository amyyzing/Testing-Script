local profiles = {
	require("../Aswang"), require("../Banshee"), require("../Demon"),
	require("../Dullahan"), require("../Dybbuk"), require("../Entity"),
	require("../Ghoul"), require("../Keres"), require("../Leviathan"),
	require("../Nightmare"), require("../Oni"), require("../Phantom"),
	require("../Ravager"), require("../Revenant"), require("../Shadow"),
	require("../Siren"), require("../Skinwalker"), require("../Specter"),
	require("../Spirit"), require("../Umbra"), require("../Vesper"),
	require("../Vex"), require("../Wendigo"), require("../Wisp"),
	require("../Wraith"),
}

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function newApi()
	local api = {Entries = {}}
	local function add(self, polarity, ghost, reason, confidence, event)
		table.insert(self.Entries, {Polarity = polarity, Ghost = ghost, Reason = reason, Confidence = confidence, Event = event})
	end
	function api:Record(ghost, event) add(self, "Observation", ghost, event.Reason or event.Type, nil, event) end
	function api:Positive(ghost, reason, confidence, event) add(self, "Positive", ghost, reason, confidence, event) end
	function api:Negative(ghost, reason, confidence, event) add(self, "Negative", ghost, reason, confidence, event) end
	function api:RuleOut(ghost, reason, confidence, event) add(self, "RuleOut", ghost, reason, confidence, event) end
	return api
end

local function last(api, polarity)
	for index = #api.Entries, 1, -1 do
		if api.Entries[index].Polarity == polarity then return api.Entries[index] end
	end
	return nil
end

local byName = {}
for _, profile in ipairs(profiles) do
	expect(type(profile.Name) == "string", "profile needs Name")
	expect(type(profile.Evidence) == "table" and #profile.Evidence == 3, profile.Name .. " needs three evidence types")
	expect(type(profile.ObservationEvents) == "table", profile.Name .. " needs ObservationEvents")
	expect(type(profile.Perks) == "table", profile.Name .. " needs Perks")
	expect(type(profile.CreateObserver) == "function", profile.Name .. " needs CreateObserver")
	expect(byName[profile.Name] == nil, "duplicate profile " .. profile.Name)
	byName[profile.Name] = profile
	local observer = profile.CreateObserver(newApi())
	expect(type(observer.OnEvent) == "function", profile.Name .. " observer needs OnEvent")
	expect(type(observer.Reset) == "function", profile.Name .. " observer needs Reset")
	expect(type(observer.Snapshot) == "function", profile.Name .. " observer needs Snapshot")
	expect(type(observer.Destroy) == "function", profile.Name .. " observer needs Destroy")
end
expect(#profiles == 25, "catalog must contain 25 ghost profiles")

do
	local catalog = require("../catalog")
	local localByPath = {}
	for _, profile in ipairs(profiles) do
		localByPath["ghost/" .. profile.Name .. ".luau"] = profile
	end
	local loaded, loadedByName = catalog.Load(function(path)
		return localByPath[path]
	end)
	expect(#loaded == 25, "catalog loader must return all profiles")
	for _, name in ipairs(catalog.Names) do
		expect(loadedByName[name] == byName[name], "catalog must preserve profile identity for " .. name)
	end
end

local function exercise(name, event, expectedPolarity)
	local api = newApi()
	local observer = byName[name].CreateObserver(api)
	expect(observer:OnEvent(event) == true, name .. " should consume " .. tostring(event.Type))
	local entry = last(api, expectedPolarity)
	expect(entry ~= nil, name .. " should emit " .. expectedPolarity)
	expect(entry.Ghost == name, name .. " must only decide its own profile")
	observer:Destroy()
	expect(observer:OnEvent(event) == false, name .. " must stop after Destroy")
	return api, observer
end

exercise("Aswang", {
	Type = "SpeedProbeRecovery", Trigger = "SaltContact", Hunting = true,
	DirectContact = true, SaltDisturbed = true, ContactId = "salt-1",
	DisturbedContactId = "salt-1", BaselineSpeed = 11, EventSpeed = 8,
	RecoverySpeed = 10.8,
}, "Positive")
exercise("Aswang", {
	Type = "SpeedProbeResult", Trigger = "SaltContact", Hunting = false,
	HuntingAtContact = true, HuntEndedBeforeSample = true,
	DirectContact = true, SaltDisturbed = true, ContactId = "salt-edge",
	DisturbedContactId = "salt-edge", BaselineSpeed = 11, CurrentSpeed = 8,
	Delta = -3,
}, "Positive")
exercise("Banshee", {Type = "BrokenGlassBurst", Qualified = true, Count = 2, Window = 2.5}, "Positive")
exercise("Demon", {Type = "CrossMotion", TrialId = "cross-1", Eligible = true, Completed = true, FloatedAndRotated = true}, "Positive")
exercise("Dullahan", {
	Type = "DullahanPattern", Hunting = true, Qualified = true,
	DifferentPairCount = 7, DifferentPairs = 7, SampleCount = 14,
	PairCount = 7, RequiredPairs = 7,
}, "Positive")
exercise("Entity", {
	Type = "ObjectTeleportResult", ConfirmedTeleport = true, Completed = true,
	SmokeFound = true, TeleportId = "object-1",
}, "Positive")
exercise("Ghoul", {Type = "HuntElectronicDisabled", Hunting = true, Qualified = true, PlayerCaused = false, AutomationCaused = false}, "RuleOut")
exercise("Keres", {Type = "SpeedProbeResult", Trigger = "PlayerDeath", Hunting = true, Unique = true, Qualified = true, HuntId = "hunt-1", BaselineSpeed = 11, CurrentSpeed = 10, Delta = -1}, "Positive")
exercise("Leviathan", {Type = "RoomLightOff", Hunting = false, Qualified = true, WorkingCircuit = true, PlayerCaused = false, AutomationCaused = false, FuseCaused = false}, "Positive")
exercise("Oni", {Type = "HuntSpeedMathResult", Hunting = true, Qualified = true, PairCount = 7, RequiredPairs = 7, Best = "Oni", Fits = {Oni = {Matched = true}}}, "Positive")
exercise("Phantom", {Type = "PhantomPattern", Hunting = true, PairCount = 7, RequiredPairs = 7, VisibleSpeed = 11, InvisibleSpeed = 13.5, Ratio = 13.5 / 11}, "Positive")
exercise("Ravager", {Type = "VortexPattern", Hunting = true, Qualified = true, DistinctObjects = 3, Duration = 0.5, Intervals = 10, GoodShare = 0.7, AccumulatedAngle = 35}, "Positive")
exercise("Revenant", {Type = "HuntEndedAfterDeath", DeathEventId = "death-1", Elapsed = 1.4, OtherAlive = 1, ValidMultiplayerKill = true}, "Positive")
exercise("Siren", {Type = "SpiritBoxResponse", Qualified = true, Response = "- HUMMING -"}, "Positive")
exercise("Skinwalker", {Type = "FalseOrb", Qualified = true, FourthEvidence = true}, "Positive")
exercise("Spirit", {Type = "HolyOilColor", Hunting = true, Burning = true, Qualified = true, Stable = true, Blue = true}, "Positive")
exercise("Wendigo", {Type = "WendigoCurveResult", Qualified = true, Matched = true, Snapshots = {}}, "Positive")
exercise("Wisp", {Type = "HolyOilCollision", Hunting = true, Burning = true, Qualified = true, CanCollide = false}, "Positive")

exercise("Entity", {
	Type = "GhostTeleportResult", ConfirmedTeleport = true, Completed = true,
	Qualified = true, FromRoom = "Hall", ToRoom = "Storage",
}, "Positive")
exercise("Keres", {Type = "GhostModelSex", Qualified = true, Sex = "Female"}, "Positive")
exercise("Siren", {Type = "GhostModelSex", Qualified = true, Sex = "Female"}, "Positive")

do
	local skinwalkerApi = newApi()
	local skinwalker = byName.Skinwalker.CreateObserver(skinwalkerApi)
	skinwalker:OnEvent({Type = "GhostModelSex", Qualified = true, Sex = "Male"})
	skinwalker:OnEvent({Type = "SpiritBoxResponse", Qualified = true, Response = "- HUMMING -"})
	local skinwalkerMatch = last(skinwalkerApi, "Positive")
	expect(skinwalkerMatch ~= nil and skinwalkerMatch.Confidence == 99, "male model plus humming must identify Skinwalker")

	local sirenApi = newApi()
	local siren = byName.Siren.CreateObserver(sirenApi)
	siren:OnEvent({Type = "SpiritBoxResponse", Qualified = true, Response = "- HUMMING -"})
	siren:OnEvent({Type = "GhostModelSex", Qualified = true, Sex = "Male"})
	local sirenConflict = last(sirenApi, "RuleOut")
	expect(sirenConflict ~= nil and sirenConflict.Confidence == 99, "humming plus male model must rule Siren out")
end

do
	local api = newApi()
	local observer = byName.Skinwalker.CreateObserver(api)
	observer:OnEvent({Type = "SpiritBoxResponse", Qualified = true, Response = "- HUMMING -"})
	observer:OnEvent({Type = "GhostModelSex", Qualified = true, Sex = "Female"})
	expect(last(api, "Positive") == nil, "humming with a female model must not falsely identify Skinwalker")
end

do
	local api = newApi()
	local observer = byName.Aswang.CreateObserver(api)
	observer:OnEvent({
		Type = "SpeedProbeRecovery", Trigger = "SaltContact", Hunting = true,
		DirectContact = true, SaltDisturbed = false, ContactId = "salt-1",
		DisturbedContactId = "salt-1", BaselineSpeed = 11, EventSpeed = 8,
		RecoverySpeed = 11,
	})
	observer:OnEvent({
		Type = "SpeedProbeRecovery", Trigger = "SaltContact", Hunting = true,
		DirectContact = true, SaltDisturbed = true, ContactId = "salt-1",
		DisturbedContactId = "salt-2", BaselineSpeed = 11, EventSpeed = 8,
		RecoverySpeed = 11,
	})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil, "Aswang requires hunting, direct contact, disturbance, and matching salt identity")
end

do
	local api = newApi()
	local observer = byName.Aswang.CreateObserver(api)
	observer:OnEvent({
		Type = "SpeedProbeResult", Trigger = "SaltContact", Hunting = true,
		DirectContact = true, SaltDisturbed = true, ContactId = "salt-1",
		DisturbedContactId = "salt-1", BaselineSpeed = 11, CurrentSpeed = 11,
		Delta = 0, Completed = false,
	})
	expect(last(api, "RuleOut") == nil, "one early no-drop sample must not rule Aswang out before the salt observation window completes")
	observer:OnEvent({
		Type = "SpeedProbeResult", Trigger = "SaltContact", Hunting = true,
		DirectContact = true, SaltDisturbed = true, ContactId = "salt-1",
		DisturbedContactId = "salt-1", BaselineSpeed = 11, CurrentSpeed = 11,
		Delta = 0, Completed = true,
	})
	expect(last(api, "RuleOut") ~= nil, "a completed qualified salt window with no slowdown may rule Aswang out")
end

do
	local api = newApi()
	local observer = byName.Keres.CreateObserver(api)
	observer:OnEvent({Type = "SpeedProbeResult", Trigger = "PlayerDeath", Hunting = true, Unique = false, Qualified = true, HuntId = "hunt-1", Delta = -1})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil, "Keres requires a qualified unique death in the active hunt")
end

do
	local api = newApi()
	local observer = byName.Revenant.CreateObserver(api)
	observer:OnEvent({Type = "HuntEndedAfterDeath", DeathEventId = "death-invalid", Elapsed = 1, OtherAlive = 1})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil, "Revenant requires an explicitly valid multiplayer kill")
end

do
	local api = newApi()
	local observer = byName.Wendigo.CreateObserver(api)
	observer:OnEvent({Type = "WendigoCurveResult", Qualified = false, Matched = true})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil, "Wendigo requires a qualified transition curve")
end

do
	local api = newApi()
	local observer = byName.Specter.CreateObserver(api)
	local base = {Type = "SpecterTrial", TrialId = "trial-1", Qualified = true, Completed = true, FavouriteRoomUnchanged = true, ArmedSeconds = 5}
	local residence = table.clone(base); residence.Outcome = "Residence"
	local departure = table.clone(base); departure.Outcome = "Departure"
	observer:OnEvent(residence)
	observer:OnEvent(departure)
	expect(last(api, "Positive") ~= nil, "Specter residence should be positive")
	expect(last(api, "RuleOut") == nil, "one Specter TrialId must not emit both outcomes")
end

do
	local api = newApi()
	local observer = byName.Umbra.CreateObserver(api)
	observer:OnEvent({Type = "RootSoundScan", HasOtherSound = false})
	observer:OnEvent({Type = "RootSoundScan", HasOtherSound = true})
	expect(last(api, "Positive") ~= nil and last(api, "RuleOut") == nil, "Umbra must stop after one valid scan")
end

do
	local api = newApi()
	local observer = byName.Vex.CreateObserver(api)
	observer:OnEvent({Type = "LidarState", Exists = false})
	observer:OnEvent({Type = "LidarState", Exists = true})
	expect(last(api, "RuleOut") ~= nil and last(api, "Positive") == nil, "Vex must stop after one valid scan")
end

do
	local api = newApi()
	local observer = byName.Wraith.CreateObserver(api)
	observer:OnEvent({Type = "SaltContact", ContactId = "salt-1", DirectContact = true, Time = 10, Hunting = false})
	observer:OnEvent({Type = "Tick", Time = 11.25})
	expect(last(api, "Positive") ~= nil, "Wraith should resolve undisturbed salt without a hunt gate")
end

do
	local api = newApi()
	local observer = byName.Wisp.CreateObserver(api)
	observer:OnEvent({Type = "HolyOilCollision", Hunting = false, Burning = true, Qualified = true, CanCollide = false})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil, "Wisp oil outside a hunt must be ignored")
end

do
	local api = newApi()
	local observer = byName.Shadow.CreateObserver(api)
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 20,
		AverageDecrease = 0.049999,
		MinimumDecrease = 0.049999,
		ShadowAverageThreshold = 0.05,
		ShadowPatternObserved = true,
	})
	local matched = last(api, "Positive")
	expect(matched ~= nil and matched.Confidence == 99,
		"an exact sub-0.05 same-room average must identify Shadow at 99%")
end

do
	local api = newApi()
	local observer = byName.Shadow.CreateObserver(api)
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 20,
		AverageDecrease = 0.06,
		MinimumDecrease = 0.06,
		ShadowAverageThreshold = 0.05,
		RuleOutAverageThreshold = 0.06,
		MinimumRuleOutDecrease = 0.05,
	})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil,
		"the exact 0.06 boundary must remain inconclusive")
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5.1,
		SampleCount = 20,
		AverageDecrease = (0.072 + 0.054 + 0.053) / 3,
		MinimumDecrease = 0.053,
		ShadowAverageThreshold = 0.05,
		RuleOutAverageThreshold = 0.06,
		MinimumRuleOutDecrease = 0.05,
	})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil,
		"the reproduced 0.059666 middle-band average must remain inconclusive")
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5.25,
		SampleCount = 20,
		AverageDecrease = 0.060001,
		MinimumDecrease = 0.05,
		ShadowAverageThreshold = 0.05,
		RuleOutAverageThreshold = 0.06,
		MinimumRuleOutDecrease = 0.05,
		NoDecreaseBelowMinimum = true,
		RuleOutPatternObserved = true,
	})
	local ruledOut = last(api, "RuleOut")
	expect(ruledOut ~= nil and ruledOut.Confidence == 99,
		"an exact above-0.06 same-room average with no sub-0.05 sample must rule Shadow out")
end


do
	local api = newApi()
	local observer = byName.Shadow.CreateObserver(api)
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 20,
		AverageDecrease = 0.07,
		MinimumDecrease = 0.049999,
		ShadowAverageThreshold = 0.05,
		RuleOutAverageThreshold = 0.06,
		MinimumRuleOutDecrease = 0.05,
		NoDecreaseBelowMinimum = false,
		RuleOutPatternObserved = false,
	})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil,
		"a sub-0.05 cooling sample must block the high-average Shadow rule-out")
end

for _, name in ipairs({"Dybbuk", "Nightmare", "Vesper"}) do
	local api = newApi()
	local observer = byName[name].CreateObserver(api)
	expect(observer:OnEvent({Type = "UnknownBehavior"}) == false, name .. " should remain evidence-only")
	expect(#api.Entries == 0, name .. " evidence-only observer must not invent a decision")
end

print("profile-observers.spec: all profile contracts and priority observation rules passed")
