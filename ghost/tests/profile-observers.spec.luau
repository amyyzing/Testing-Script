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
	RecoverySpeed = 11,
}, "Positive")
exercise("Aswang", {
	Type = "SpeedProbeResult", Trigger = "SaltContact", Hunting = false,
	HuntingAtContact = true, HuntEndedBeforeSample = true,
	PostHuntReferenceQualified = true,
	DirectContact = true, SaltDisturbed = true, ContactId = "salt-edge",
	DisturbedContactId = "salt-edge", BaselineSpeed = 11, CurrentSpeed = 8,
	Delta = -3,
}, "Positive")
local bansheeGlass = exercise("Banshee", {Type = "BrokenGlassBurst", Qualified = true, Count = 2, Window = 2.5}, "Positive")
expect(last(bansheeGlass, "Positive").Confidence == 99,
	"two distinct new glass breaks within five seconds must be Pretty Sure Banshee")
exercise("Demon", {Type = "CrossMotion", TrialId = "cross-1", Eligible = true, Completed = true, FloatedAndRotated = true}, "Positive")
exercise("Dullahan", {
	Type = "DullahanPattern", Hunting = true, Qualified = true,
	Completed = true, PhantomExcluded = true,
	DifferentPairCount = 7, DifferentPairs = 7, SampleCount = 14,
	UpwardStepCount = 1,
	PairCount = 7, RequiredPairs = 7,
}, "Positive")
exercise("Entity", {
	Type = "ObjectTeleportResult", Qualified = true, ConfirmedTeleport = true, Completed = true,
	SmokeFound = true, TeleportId = "object-1",
}, "Positive")
exercise("Ghoul", {Type = "HuntElectronicDisabled", Hunting = false, Qualified = true, NearestPlayerDistance = 15.001, PlayerCaused = false, AutomationCaused = false}, "RuleOut")
exercise("Keres", {Type = "SpeedProbeResult", Trigger = "PlayerDeath", Hunting = true, Unique = true, Qualified = true, Completed = true, Stable = true, HuntId = "hunt-1", BaselineSpeed = 11, CurrentSpeed = 10, Delta = -1}, "Positive")
exercise("Leviathan", {Type = "DeviceToggleBurst", Hunting = true, Qualified = true, SingleDevice = true, Clean = true, Alternating = true, Rapid = true, ToggleCount = 7, Duration = 2.5, PlayerCaused = false, AutomationCaused = false, FuseCaused = false}, "Positive")
exercise("Oni", {Type = "HuntSpeedMathResult", Hunting = true, Qualified = true, Completed = true, PairCount = 7, RequiredPairs = 7, Best = "Oni", BaseSpeed = 13.5, Fits = {Oni = {Matched = true}}}, "Positive")
exercise("Phantom", {Type = "PhantomPattern", Hunting = true, Qualified = true, Completed = true, PairCount = 7, RequiredPairs = 7, VisibleSpeed = 11, InvisibleSpeed = 13.5, Ratio = 13.5 / 11, AbsoluteBaseFit = true, Multiplier = 1}, "Positive")
exercise("Ravager", {Type = "VortexPattern", Hunting = false, Qualified = true, DistinctObjects = 3, Duration = 0.5, Intervals = 10, GoodShare = 0.7, AccumulatedAngle = 35}, "Positive")
exercise("Revenant", {Type = "HuntEndedAfterDeath", DeathEventId = "death-1", Elapsed = 1, OtherAlive = 1, ValidMultiplayerKill = true}, "Positive")
exercise("Siren", {Type = "SpiritBoxResponse", Qualified = true, Response = "- HUMMING -"}, "Positive")
exercise("Skinwalker", {Type = "FalseOrb", Qualified = true, FourthEvidence = true}, "Positive")
local spiritBlue = exercise("Spirit", {Type = "HolyOilColor", Hunting = false, Burning = true, Qualified = true, Stable = true, Blue = true}, "Positive")
expect(last(spiritBlue, "Positive").Confidence == 99,
	"one qualified stable blue flame must identify Spirit")
exercise("Wendigo", {Type = "WendigoCurveResult", Qualified = true, Completed = true, Matched = true, Outcome = "Matched", Snapshots = {}}, "Positive")
exercise("Wisp", {Type = "HolyOilCollision", Hunting = true, Burning = true, Qualified = true, CanCollide = false}, "Positive")

exercise("Keres", {Type = "GhostModelSex", Qualified = true, Sex = "Female"}, "Positive")
exercise("Siren", {Type = "GhostModelSex", Qualified = true, Sex = "Female"}, "Positive")

do
	for _, ghostName in ipairs({"Keres", "Siren"}) do
		local api = newApi()
		local observer = byName[ghostName].CreateObserver(api)
		observer:OnEvent({
			Type = "GhostModelSex",
			Qualified = true,
			Sex = "Male",
		})
		local negative = last(api, "Negative")
		expect(
			negative ~= nil and negative.Confidence == 99,
			ghostName .. " must receive a 99% negative from a male VisualModel"
		)
	end
end

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
	local sirenConflict = last(sirenApi, "Negative")
	expect(sirenConflict ~= nil and sirenConflict.Confidence == 99, "humming plus male model must apply Siren's hard negative")
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
	local observer = byName.Skinwalker.CreateObserver(api)
	observer:OnEvent({
		Type = "RootSoundScan",
		Qualified = true,
		Hunting = true,
		HasOtherSound = false,
	})
	local rootMimic = last(api, "Positive")
	expect(rootMimic ~= nil and rootMimic.Confidence == 60,
		"a qualified empty root scan must be one Skinwalker mimic fact regardless of hunt state")
	observer:OnEvent({
		Type = "GhostFireEffect",
		Qualified = true,
		Completed = true,
		DirectContact = true,
		Burning = true,
		CaughtFire = false,
	})
	expect(last(api, "Positive").Confidence == 99,
		"two distinct qualified Skinwalker mimic facts must upgrade to 99%")
end

do
	local api = newApi()
	local observer = byName.Skinwalker.CreateObserver(api)
	observer:OnEvent({Type = "FalseOrb", Qualified = true, FourthEvidence = true})
	observer:OnEvent({Type = "FalseOrb", Qualified = true, ImpossibleCombination = true})
	observer:OnEvent({Type = "RootSoundScan", Qualified = true, HasOtherSound = false})
	observer:OnEvent({Type = "RootSoundScan", Qualified = true, HasOtherSound = false})
	local orbCount, rootCount = 0, 0
	for _, entry in ipairs(api.Entries) do
		if entry.Polarity == "Positive" and entry.Confidence == 100 then
			orbCount = orbCount + 1
		elseif entry.Polarity == "Positive" and entry.Confidence == 60 then
			rootCount = rootCount + 1
		end
	end
	expect(orbCount == 1 and rootCount == 1,
		"durable FalseOrb and root-sound mimic facts must not accumulate duplicate support")
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
	local keresApi = newApi()
	local keres = byName.Keres.CreateObserver(keresApi)
	keres:OnEvent({
		Type = "SpeedProbeResult", Trigger = "PlayerDeath", Hunting = true,
		Unique = true, Qualified = true, HuntId = "noise-hunt",
		BaselineSpeed = 11, CurrentSpeed = 10.99, Delta = -0.01,
		Completed = true, Stable = true,
	})
	expect(last(keresApi, "Positive") == nil,
		"tiny post-death replication noise must not identify Keres")

	local aswangApi = newApi()
	local aswang = byName.Aswang.CreateObserver(aswangApi)
	aswang:OnEvent({
		Type = "SpeedProbeResult", Trigger = "PlayerDeath", Hunting = true,
		Unique = true, Qualified = true, HuntId = "noise-hunt",
		BaselineSpeed = 11, CurrentSpeed = 11.01, Delta = 0.01,
		Completed = true, Stable = true,
	})
	expect(last(aswangApi, "Positive") == nil,
		"tiny post-death replication noise must not identify Aswang")
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
	observer:OnEvent({Type = "RootSoundScan", Qualified = true, HasOtherSound = false})
	observer:OnEvent({Type = "RootSoundScan", Qualified = true, HasOtherSound = true})
	expect(last(api, "Positive") ~= nil and last(api, "RuleOut") == nil, "Umbra must stop after one valid scan")
end

do
	local api = newApi()
	local observer = byName.Vex.CreateObserver(api)
	observer:OnEvent({Type = "LidarState", Qualified = true, Exists = false})
	observer:OnEvent({Type = "LidarState", Qualified = true, Exists = true})
	expect(last(api, "RuleOut") ~= nil and last(api, "Positive") == nil, "Vex must stop after one valid scan")
end

do
	local api = newApi()
	local observer = byName.Wraith.CreateObserver(api)
	observer:OnEvent({
		Type = "SaltContactResult",
		ContactId = "salt-1",
		DirectContact = true,
		Disturbed = false,
		Completed = true,
		Elapsed = 1.25,
		HuntingAtContact = false,
	})
	expect(last(api, "Positive") ~= nil,
		"Wraith should consume the salt tracker's completed undisturbed result without a hunt gate")
end

do
	local api = newApi()
	local observer = byName.Wraith.CreateObserver(api)
	observer:OnEvent({Type = "SaltDisturbed", ContactId = "salt-missed-touch", DirectContact = false, Disturbed = true, Time = 20})
	expect(last(api, "RuleOut") ~= nil, "a replicated disturbed pile must rule Wraith out when Touched was missed")
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
		Completed = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 7,
		DecreaseCount = 7,
		AverageDecrease = 0.059999,
		RequiredCoolingChanges = 7,
		Outcome = "Shadow",
		ShadowAverageThreshold = 0.06,
	})
	local matched = last(api, "Positive")
	expect(matched ~= nil and matched.Confidence == 99,
		"an exact sub-0.08 full cooling window must identify Shadow at 99%")
end

do
	local api = newApi()
	local observer = byName.Shadow.CreateObserver(api)
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		Completed = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 7,
		DecreaseCount = 7,
		AverageDecrease = 0.09,
		RequiredCoolingChanges = 7,
		RequiredRuleOutWindows = 1,
		RuleOutStreak = 1,
		Outcome = "RuleOut",
		ShadowAverageThreshold = 0.06,
		RuleOutAverageThreshold = 0.08,
	})
	local ruledOut = last(api, "RuleOut")
	expect(ruledOut ~= nil and ruledOut.Confidence == 99,
		"one exact seven-change average above 0.08 must rule Shadow out")
end

do
	local api = newApi()
	local observer = byName.Shadow.CreateObserver(api)
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		Completed = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 7,
		DecreaseCount = 7,
		RequiredCoolingChanges = 7,
		AverageDecrease = 0.07,
		Outcome = "Inconclusive",
		RuleOutPatternObserved = true,
	})
	expect(last(api, "Positive") ~= nil and last(api, "RuleOut") == nil,
		"the Shadow observer must recompute the canonical sub-0.08 boundary instead of trusting stale outcome flags")
end

do
	local api = newApi()
	local observer = byName.Shadow.CreateObserver(api)
	observer:OnEvent({
		Type = "RoomTemperatureWindow",
		Qualified = true,
		Completed = true,
		SameRoom = true,
		RoomName = "Library",
		ResidenceSeconds = 5,
		SampleCount = 6,
		DecreaseCount = 6,
		RequiredCoolingChanges = 7,
		AverageDecrease = 0.04,
		Outcome = "Shadow",
	})
	expect(last(api, "Positive") == nil and last(api, "RuleOut") == nil,
		"the Shadow observer must reject a decision without seven actual cooling changes")
end

for _, name in ipairs({"Dybbuk", "Nightmare", "Vesper"}) do
	local api = newApi()
	local observer = byName[name].CreateObserver(api)
	expect(observer:OnEvent({Type = "UnknownBehavior"}) == false, name .. " should remain evidence-only")
	expect(#api.Entries == 0, name .. " evidence-only observer must not invent a decision")
end

print("profile-observers.spec: all profile contracts and priority observation rules passed")
