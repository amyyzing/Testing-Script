-- Demonology ghost catalogue and evidence helpers.
--
-- Internal evidence keys intentionally retain the names used by the original
-- monolith. DisplayName and CurrentName expose the current in-game/wiki names.

-- Evidence catalog, candidate resolver, and Journal-selection policy live with
-- the ghost domain. UI/button orchestration consumes this module but does not
-- own any ghost conclusions.
local GhostModule = {}

local EVIDENCE_ORDER = {
	"EMFLevel5",
	"SpiritBox",
	"GhostWriting",
	"FreezingTemperatures",
	"GhostOrb",
	"Handprints",
	"LaserProjector",
	"Wither",
}

local EVIDENCE = {
	EMFLevel5 = {
		Key = "EMFLevel5",
		CurrentName = "EMF Level 5",
		DisplayName = "EMF Level 5",
		Aliases = {"EMF 5", "EMF5", "EMF Level 5"},
	},
	SpiritBox = {
		Key = "SpiritBox",
		CurrentName = "Spirit Box",
		DisplayName = "Spirit Box",
		Aliases = {"Spirit Box"},
	},
	GhostWriting = {
		Key = "GhostWriting",
		CurrentName = "Inscription",
		DisplayName = "Inscription",
		LegacyName = "Ghost Writing",
		Aliases = {"Inscription", "Ghost Writing", "Writing", "Spirit Book"},
	},
	FreezingTemperatures = {
		Key = "FreezingTemperatures",
		CurrentName = "Freezing Temperatures",
		DisplayName = "Freezing Temperatures",
		Aliases = {"Freezing", "Freezing Temps", "Freezing Temperatures"},
	},
	GhostOrb = {
		Key = "GhostOrb",
		CurrentName = "Ghost Orb",
		DisplayName = "Ghost Orb",
		Aliases = {"Orb", "Orbs", "Ghost Orb", "Ghost Orbs"},
	},
	Handprints = {
		Key = "Handprints",
		CurrentName = "Prints",
		DisplayName = "Prints",
		LegacyName = "Handprints",
		Aliases = {"Print", "Prints", "Handprint", "Handprints", "Fingerprint", "Fingerprints"},
	},
	LaserProjector = {
		Key = "LaserProjector",
		CurrentName = "Laser Projector",
		DisplayName = "Laser Projector",
		Aliases = {"Laser", "Laser Projector", "Projector", "LIDAR Projection"},
	},
	Wither = {
		Key = "Wither",
		CurrentName = "Wither",
		DisplayName = "Wither",
		Aliases = {"Wither", "Withering", "Decay"},
	},
}

local function normalizedToken(value)
	if value == nil then
		return nil
	end
	return string.lower(tostring(value)):gsub("[^%w]", "")
end

local evidenceAliases = {}
for _, evidenceKey in ipairs(EVIDENCE_ORDER) do
	local definition = EVIDENCE[evidenceKey]
	evidenceAliases[normalizedToken(evidenceKey)] = evidenceKey
	evidenceAliases[normalizedToken(definition.CurrentName)] = evidenceKey
	evidenceAliases[normalizedToken(definition.DisplayName)] = evidenceKey
	if definition.LegacyName then
		evidenceAliases[normalizedToken(definition.LegacyName)] = evidenceKey
	end
	for _, alias in ipairs(definition.Aliases) do
		evidenceAliases[normalizedToken(alias)] = evidenceKey
	end
end

local function normalizeEvidence(evidence)
	if type(evidence) == "table" then
		evidence = evidence.Key or evidence.Name or evidence.DisplayName or evidence.CurrentName
	end
	return evidenceAliases[normalizedToken(evidence)]
end

local function shallowCopy(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

local function copyArray(source)
	local result = {}
	if type(source) == "table" then
		for index, value in ipairs(source) do
			result[index] = value
		end
	end
	return result
end

local function note(text, sourceUrl, status, mimickable, kind, conditions)
	local result = {
		Text = text,
		Source = sourceUrl,
		SourceUrl = sourceUrl,
		SourceURL = sourceUrl,
		Status = status,
		Mimickable = mimickable == true,
		Kind = kind or "Trait",
	}
	if conditions then
		result.Conditions = conditions
	end
	return result
end

local SOURCE = {
	Aswang = "https://demonology.fandom.com/wiki/Aswang",
	Banshee = "https://demonology.fandom.com/wiki/Banshee",
	Demon = "https://demonology.fandom.com/wiki/Demon",
	Dullahan = "https://demonology.fandom.com/wiki/Dullahan",
	Dybbuk = "https://demonology.fandom.com/wiki/Dybbuk",
	Entity = "https://demonology.fandom.com/wiki/Entity",
	Ghoul = "https://demonology.fandom.com/wiki/Ghoul",
	Keres = "https://demonology.fandom.com/wiki/Keres",
	Leviathan = "https://demonology.fandom.com/wiki/Leviathan",
	Nightmare = "https://demonology.fandom.com/wiki/Nightmare",
	Oni = "https://demonology.fandom.com/wiki/Oni",
	Phantom = "https://demonology.fandom.com/wiki/Phantom",
	Ravager = "https://demonology.fandom.com/wiki/Ravager",
	Revenant = "https://demonology.fandom.com/wiki/Revenant",
	Shadow = "https://demonology.fandom.com/wiki/Shadow",
	Siren = "https://demonology.fandom.com/wiki/Siren",
	Doppelganger = "live-game:ReplicatedStorage.Modules.GhostTypes.Doppelganger",
	Specter = "https://demonology.fandom.com/wiki/Specter",
	Spirit = "https://demonology.fandom.com/wiki/Spirit",
	Wisp = "https://demonology.fandom.com/wiki/The_Wisp",
	Umbra = "https://demonology.fandom.com/wiki/Umbra",
	Vesper = "live-game:ReplicatedStorage.Modules.GhostTypes.Vesper",
	Vex = "https://demonology.fandom.com/wiki/Vex",
	Wretch = "live-game:ReplicatedStorage.Modules.GhostTypes.Wretch",
	Wraith = "https://demonology.fandom.com/wiki/Wraith",
}

local function perks(prettySure, maybe, idk)
	-- These are deliberately the only keys in every Perks table.
	return {
		["Pretty Sure"] = prettySure or {},
		["Maybe"] = maybe or {},
		["Idk"] = idk or {},
	}
end

local function profile(name, evidence, sourceStatus, profilePerks, aliases, falseEvidence)
	local evidenceCopy = copyArray(evidence)
	local evidenceSet = {}
	local evidenceDisplay = {}
	for index, evidenceKey in ipairs(evidenceCopy) do
		evidenceSet[evidenceKey] = true
		evidenceDisplay[index] = EVIDENCE[evidenceKey].DisplayName
	end
	local falseEvidenceCopy = copyArray(falseEvidence)
	local falseEvidenceSet = {}
	for _, evidenceKey in ipairs(falseEvidenceCopy) do
		falseEvidenceSet[evidenceKey] = true
	end
	return {
		Name = name,
		DisplayName = name == "Wisp" and "The Wisp" or name,
		Aliases = copyArray(aliases),
		Evidence = evidenceCopy,
		EvidenceSet = evidenceSet,
		EvidenceDisplay = evidenceDisplay,
		DisplayEvidence = evidenceDisplay,
		FalseEvidence = falseEvidenceCopy,
		FalseEvidenceSet = falseEvidenceSet,
		Perks = profilePerks,
		Source = SOURCE[name],
		SourceUrl = SOURCE[name],
		SourceURL = SOURCE[name],
		SourceStatus = sourceStatus or "wiki-documented",
	}
end

local Profiles = {
	profile("Aswang", {"EMFLevel5", "GhostWriting", "Wither"}, "user-observed", perks({
		note("During a hunt, direct contact with the same salt pile disturbs it, temporarily lowers WalkSpeed, and is followed by a return to the pre-contact hunting baseline.", SOURCE.Aswang, "user-observed", false, "Trait"),
	}, {
		note("Stable hunting speed permanently rises after a qualified unique player kill.", SOURCE.Aswang, "user-observed", false, "Trait"),
	}, {
		note("A qualified hunting salt contact with no temporary slowdown is a 99% negative; a qualified unique kill with no permanent rise is also a 99% negative.", SOURCE.Aswang, "user-observed", false, "RuleOut"),
		note("Salt contact outside a hunt can identify Wraith behavior but cannot identify Aswang.", SOURCE.Aswang, "user-observed", false, "Caveat"),
	})),
	profile("Banshee", {"FreezingTemperatures", "GhostOrb", "Handprints"}, "evidence-only", perks()),
	profile("Demon", {"EMFLevel5", "FreezingTemperatures", "Handprints"}, "user-observed", perks({
		note("An eligible burning Cross floats and rotates.", SOURCE.Demon, "user-observed", false, "Weakness"),
	}, {}, {
		note("An eligible Cross that finishes burning without floating and rotating is a 99% negative.", SOURCE.Demon, "user-observed", false, "RuleOut"),
	})),
	profile("Dullahan", {"FreezingTemperatures", "LaserProjector", "Wither"}, "user-observed", perks({
		note("The current LineOfSightSpeedIncreasePerSecond flag is 0.1. Repeated rising visible speed provides supporting evidence, not certainty from arbitrary distinct speeds.", SOURCE.Dullahan, "live-game", false, "Trait"),
	}, {}, {
		note("Flat speed without verified sustained target line of sight cannot rule Dullahan out. Decreases or resets make this uncontrolled trial inconclusive.", SOURCE.Dullahan, "live-game", false, "Caveat"),
	})),
	profile("Dybbuk", {"FreezingTemperatures", "Handprints", "Wither"}, "live-game", perks({
		note("A fresh native Music Box first-play transition coincides with a deep WalkSpeed drop followed by recovery to the pre-play speed after about three seconds. The observation requires unchanged hunting state and no item/ghost ancestry gap.", SOURCE.Dybbuk, "live-game", false, "Trait"),
	}, {}, {
		note("Missing, late, short, or interrupted Music Box responses remain inconclusive. Corpse motion alone is not a reliable automatic identification.", SOURCE.Dybbuk, "live-game", false, "Caveat"),
	})),
	profile("Entity", {"Handprints", "LaserProjector", "SpiritBox"}, "user-observed", perks({
		note("A rapid object relocation matches a SmokeHolder at its departure point within three seconds. Native short and same-room relocations also qualify.", SOURCE.Entity, "live-game", true, "Ability"),
	}, {}, {
		note("A long cross-room jump without matching origin smoke is only a 50% negative. A matching signature supersedes tentative motion negatives; uncorroborated short movement stays inconclusive.", SOURCE.Entity, "live-game", true, "Caveat"),
	})),
	profile("Ghoul", {"FreezingTemperatures", "GhostOrb", "SpiritBox"}, "user-observed", perks({}, {}, {
		note("Electronics becoming disabled while every player is more than 15 studs away is a 99% negative for Ghoul.", SOURCE.Ghoul, "user-observed", false, "RuleOut"),
		note("No positive automatic Ghoul observation is currently trusted.", SOURCE.Ghoul, "user-observed", false, "Caveat"),
	})),
	profile("Keres", {"Handprints", "SpiritBox", "Wither"}, "user-observed", perks({
		note("Stable hunting speed permanently decreases after a qualified unique player kill.", SOURCE.Keres, "user-observed", false, "Trait"),
	}, {
		note("Model gender is exclusion-only. A female VisualModel does not support Keres.", SOURCE.Keres, "user-observed", false, "Caveat"),
	}, {
		note("No speed decrease after a qualified unique kill, or a verified male VisualModel, is a 99% negative.", SOURCE.Keres, "user-observed", false, "RuleOut"),
	})),
	profile("Leviathan", {"GhostOrb", "GhostWriting", "Handprints"}, "user-observed", perks({
		note("An electronic item receives the native LeviathanGlitch attribute. An ordinary seven-toggle burst provides only weak support.", SOURCE.Leviathan, "live-game", true, "Ability"),
	}, {}, {
		note("One isolated toggle or an automation-caused toggle is not Leviathan evidence.", SOURCE.Leviathan, "user-observed", true, "Caveat"),
	})),
	profile("Nightmare", {"EMFLevel5", "GhostOrb", "SpiritBox"}, "evidence-only", perks()),
	profile("Oni", {"FreezingTemperatures", "LaserProjector", "SpiritBox"}, "user-observed", perks({
		note("The current WalkSpeedDuringHunts flag is 14. A matching flat hunting window supports Oni but can also match Wretch's low-Energy speed.", SOURCE.Oni, "live-game", false, "Trait"),
	}, {}, {
		note("A mismatch against an inferred difficulty multiplier is only a weak negative, not a rule-out.", SOURCE.Oni, "live-game", false, "Caveat"),
	})),
	profile("Phantom", {"EMFLevel5", "GhostOrb", "Handprints"}, "user-observed", perks({
		note("The current WalkSpeedWhileBlinking flag is 13.5. Seven hunt blink pairs must repeat a stable visible speed and a strictly faster invisible speed.", SOURCE.Phantom, "live-game", true, "Trait"),
	}, {}, {
		note("Any complete seven-pair window that is flat, drifting, decrease-only, or a stable A/B with invalid absolute bases rules Phantom out unless a confirmed unique Phantom match is already locked.", SOURCE.Phantom, "user-observed", true, "RuleOut"),
	})),
	profile("Ravager", {"EMFLevel5", "GhostWriting", "SpiritBox"}, "user-observed", perks({
		note("At least three distinct item or interactable models sustain XZ rotation around the moving ghost in one direction.", SOURCE.Ravager, "user-observed", false, "Trait"),
	}, {}, {
		note("Ordinary throws and one moving object are not a vortex.", SOURCE.Ravager, "user-observed", false, "Caveat"),
	})),
	profile("Revenant", {"EMFLevel5", "FreezingTemperatures", "GhostWriting"}, "user-observed", perks({}, {
		note("A hunt stopping abruptly after a qualified kill is low support, including solo; custom difficulty or round ending can cause the same behavior for other ghosts.", SOURCE.Revenant, "live-game", false, "Weakness"),
	}, {
		note("Hunt continuation is inconclusive. Solo deaths retain a measurable hunt window; abrupt stopping remains low because settings or round ending can imitate it. Unknown kill observations are ignored.", SOURCE.Revenant, "live-game", false, "Caveat"),
	})),
	profile("Shadow", {"EMFLevel5", "GhostWriting", "LaserProjector"}, "user-observed", perks({
		note("The current TemperatureAlterCoefficient is 0.5. Slow cooling provides weak support, since room conditions affect absolute temperature changes.", SOURCE.Shadow, "live-game", false, "Trait"),
	}, {}, {
		note("An uncontrolled cooling average cannot rule Shadow out. Temperature increases and unchanged readings are ignored.", SOURCE.Shadow, "live-game", false, "Caveat"),
	})),
	profile("Siren", {"EMFLevel5", "SpiritBox", "Wither"}, "user-observed", perks({
		note("The Spirit Box responds with - HUMMING -.", SOURCE.Siren, "user-observed", true, "Ability"),
		note("A 0.8x slowdown was also observed on a native-revealed Revenant. Speed change alone is weak support, not a Siren identity cue.", SOURCE.Siren, "user-observed", false, "Trait"),
	}, {
		note("Model gender is exclusion-only. A female VisualModel does not support Siren.", SOURCE.Siren, "user-observed", false, "Caveat"),
	}, {
		note("A verified male VisualModel is a 99% negative. A line-of-sight trial without slowdown is inconclusive.", SOURCE.Siren, "user-observed", false, "RuleOut"),
	})),
	profile("Doppelganger", {"FreezingTemperatures", "GhostWriting", "SpiritBox"}, "live-game", perks({}, {
		note("Ghost Orb may be false and keeps Doppelganger as Maybe. Extra or conflicting clues do not prove its identity.", SOURCE.Doppelganger, "live-game", false, "Trait"),
	}, {
		note("Outside the Mimicry challenge, confirmed EMF Level 5, Handprints, Laser Projector or Wither rules Doppelganger out. Mimicry allows every ghost one extra fake clue. Freezing, Writing and Spirit Box remain compatible.", SOURCE.Doppelganger, "live-game", false, "RuleOut"),
		note("SpiritCandle is shared with Spirit and supports both candidates. False Ghost Orb evidence remains the distinguishing evidence path.", SOURCE.Doppelganger, "live-game", false, "Caveat"),
	}), nil, {"GhostOrb"}),
	profile("Specter", {"EMFLevel5", "FreezingTemperatures", "LaserProjector"}, "user-observed", perks({
		note("The native roam coefficient is zero. Continuous non-hunting residence supplies a low lead after 30 seconds and medium after 90, never definite identification. These are heuristic timing grades, not native thresholds. Throwing frequency is not tracked as a perk.", SOURCE.Specter, "live-game", false, "Caveat"),
	}, {}, {
		note("Leaving the unchanged favourite room before that trial's hunt begins is a Specter negative; room-change trials are discarded.", SOURCE.Specter, "user-observed", false, "RuleOut"),
	})),
	profile("Spirit", {"GhostWriting", "Handprints", "SpiritBox"}, "user-observed", perks({
		note("Qualified burning Holy Oil produces a blue fire colour.", SOURCE.Spirit, "user-observed", true, "Ability"),
	}, {}, {
		note("A stable qualified Holy Oil fire colour that is not blue is a 99% negative.", SOURCE.Spirit, "user-observed", true, "RuleOut"),
	})),
	profile("Umbra", {"GhostOrb", "Handprints", "LaserProjector"}, "user-observed", perks({
		note("The native footstep object is a root Sound named CurrentSound. Its absence is checked after replication grace.", SOURCE.Umbra, "user-observed", false, "Trait"),
		note("Doppelganger can share this missing-footstep cue; confirmed evidence must distinguish them before automatic completion.", SOURCE.Umbra, "user-observed", false, "Caveat"),
	}, {}, {
		note("A root Sound named CurrentSound contradicts silent footsteps; other Sound names do not.", SOURCE.Umbra, "user-observed", false, "RuleOut"),
	})),
	profile("Vesper", {"GhostWriting", "Handprints", "Wither"}, "evidence-only", perks()),
	profile("Vex", {"FreezingTemperatures", "GhostOrb", "Wither"}, "user-observed", perks({
		note("The replicated InvisibleOnLIDAR flag is true. Late-arriving values are observed.", SOURCE.Vex, "live-game", false, "Trait"),
	}, {}, {
		note("A missing or false replicated flag is not an automatic Vex rule-out.", SOURCE.Vex, "live-game", false, "Caveat"),
	})),
	profile("Wretch", {"GhostOrb", "GhostWriting", "LaserProjector"}, "live-game", perks({
		note("Two alternating settled hunt-state transitions match the WalkSpeed curve for average player Energy captured at each exact switch; the sanity spread must be large enough to exceed speed tolerance.", SOURCE.Wretch, "user-observed", false, "Trait"),
	}, {}, {
		note("Only qualified hunt-transition snapshots are used for the curve. Energy restoration alone did not refresh speed in the native no-kill control; kill-triggered refreshes are confounded and ignored.", SOURCE.Wretch, "user-observed", false, "RuleOut"),
		note("The native CantHuntNearLitCandle flag is true. Missing hunts cannot support Wretch; a candle-based negative requires qualified proximity and an eligible hunt, which are not yet established.", SOURCE.Wretch, "live-game", false, "Caveat"),
	})),
	profile("Wisp", {"GhostOrb", "LaserProjector", "Wither"}, "user-observed", perks({
		note("While hunting through burning Holy Oil, GhostWall.CanCollide is false.", SOURCE.Wisp, "user-observed", false, "Ability"),
		note("Hunt location is negative-only: repeated starts in the favourite room do not support Wisp.", SOURCE.Wisp, "user-observed", false, "Caveat"),
	}, {}, {
		note("GhostWall.CanCollide remaining true during a qualified burning-oil passage, or a hunt starting outside the favourite room, is a strong negative.", SOURCE.Wisp, "user-observed", false, "RuleOut"),
	}), {"The Wisp", "Will-o-the-Wisp", "Will o the Wisp"}),
	profile("Wraith", {"EMFLevel5", "LaserProjector", "SpiritBox"}, "user-observed", perks({
		note("The ghost is directly observed touching a SaltLine and the contacted pile remains undisturbed through its four-second creation grace; hunting state does not matter.", SOURCE.Wraith, "user-observed", false, "Weakness"),
	}, {}, {
		note("Any DisturbedSaltLine appearing anywhere in Workspace.SaltPiles rules Wraith out at 99%.", SOURCE.Wraith, "user-observed", false, "RuleOut"),
	})),
}

local Order = {}
local ByName = {}
local lookupByToken = {}
local orderIndex = {}
for index, ghostProfile in ipairs(Profiles) do
	ghostProfile.Index = index
	Order[index] = ghostProfile.Name
	ByName[ghostProfile.Name] = ghostProfile
	lookupByToken[normalizedToken(ghostProfile.Name)] = ghostProfile
	lookupByToken[normalizedToken(ghostProfile.DisplayName)] = ghostProfile
	orderIndex[ghostProfile.Name] = index
	for _, alias in ipairs(ghostProfile.Aliases) do
		lookupByToken[normalizedToken(alias)] = ghostProfile
	end
end

-- Conservative defaults for detections without independent corroboration.
local PerkConfidence = {
	Aswang = 65,
	Demon = 65,
	Dullahan = 65,
	Dybbuk = 65,
	Entity = 65,
	Doppelganger = 65,
	Keres = 65,
	Leviathan = 65,
	Oni = 65,
	Phantom = 65,
	Ravager = 65,
	Revenant = 35,
	Shadow = 35,
	Siren = 65,
	Specter = 0,
	Spirit = 65,
	Umbra = 65,
	Vex = 65,
	Wretch = 65,
	Wisp = 65,
	Wraith = 65,
}

local PerkTTL = {
	Dullahan = 25,
	Dybbuk = 120,
	Entity = 30,
	Doppelganger = 120,
	Leviathan = 30,
	Oni = 25,
	Phantom = 30,
	Ravager = 6,
	Siren = 25,
	Specter = 120,
	Umbra = 60,
	Vex = 2,
	Wretch = 20,
	Wisp = 120,
	Wraith = 120,
}

local TIER_NAMES = {
	[0] = "Idk",
	[1] = "Idk",
	[2] = "Maybe",
	[3] = "Pretty Sure",
}

local function confidenceTier(score)
	score = tonumber(score) or 0
	if score >= 80 then
		return 3, "Pretty Sure"
	elseif score >= 50 then
		return 2, "Maybe"
	elseif score > 0 then
		return 1, "Idk"
	end
	return 0, "Idk"
end

local function find(name)
	if type(name) == "table" then
		if name.Name then
			name = name.Name
		elseif name.DisplayName then
			name = name.DisplayName
		else
			return nil
		end
	end
	return lookupByToken[normalizedToken(name)]
end

local function supportsEvidence(profileOrName, evidence, options)
	local ghostProfile = find(profileOrName)
	local evidenceKey = normalizeEvidence(evidence)
	if not ghostProfile or not evidenceKey then
		return false, nil
	end
	if ghostProfile.EvidenceSet[evidenceKey] then
		return true, "real"
	end
	options = options or {}
	if options.RealOnly ~= true
		and options.IncludeFalseEvidence ~= false
		and ghostProfile.FalseEvidenceSet[evidenceKey] then
		return true, "false"
	end
	return false, nil
end

local function addEvidenceValue(target, value)
	local evidenceKey = normalizeEvidence(value)
	if evidenceKey then
		target[evidenceKey] = true
	end
end

local function collectEvidence(input, options)
	options = options or {}
	local observed = {}
	local disproved = {}
	if type(input) == "string" then
		addEvidenceValue(observed, input)
	elseif type(input) == "table" then
		if type(input.Evidence) == "table" and input.Evidence ~= input then
			input = input.Evidence
		end
		for _, value in ipairs(input) do
			addEvidenceValue(observed, value)
		end
		for key, value in pairs(input) do
			if type(key) == "string" then
				local evidenceKey = normalizeEvidence(key)
				if evidenceKey then
					if value == true then
						observed[evidenceKey] = true
					elseif value == false and options.FalseMeansDisproved == true then
						disproved[evidenceKey] = true
					end
				end
			end
		end
	end
	local explicitDisproved = options.DisprovedEvidence
	if type(explicitDisproved) == "string" then
		addEvidenceValue(disproved, explicitDisproved)
	elseif type(explicitDisproved) == "table" then
		for _, value in ipairs(explicitDisproved) do
			addEvidenceValue(disproved, value)
		end
		for key, value in pairs(explicitDisproved) do
			if type(key) == "string" and value then
				addEvidenceValue(disproved, key)
			end
		end
	end
	return observed, disproved
end

local function collectRuleOuts(input)
	local ruledOut = {}
	if type(input) == "string" then
		local ghostProfile = find(input)
		if ghostProfile then
			ruledOut[ghostProfile.Name] = true
		end
	elseif type(input) == "table" then
		if type(input.RuleOuts) == "table" and input.RuleOuts ~= input then
			input = input.RuleOuts
		end
		for _, value in ipairs(input) do
			local ghostProfile = find(value)
			if ghostProfile then
				ruledOut[ghostProfile.Name] = true
			end
		end
		for key, value in pairs(input) do
			if type(key) == "string" and value then
				local ghostProfile = find(key)
				if ghostProfile then
					ruledOut[ghostProfile.Name] = true
				end
			end
		end
	end
	return ruledOut
end

local function candidatePool(options)
	options = options or {}
	local requested = options.Candidates or options.Profiles
	if type(requested) ~= "table" then
		return Profiles
	end
	local allowed = {}
	for _, value in ipairs(requested) do
		local ghostProfile = find(value)
		if ghostProfile then
			allowed[ghostProfile.Name] = true
		end
	end
	for key, value in pairs(requested) do
		if type(key) == "string" and value then
			local ghostProfile = find(key)
			if ghostProfile then
				allowed[ghostProfile.Name] = true
			end
		end
	end
	local result = {}
	for _, ghostProfile in ipairs(Profiles) do
		if allowed[ghostProfile.Name] then
			table.insert(result, ghostProfile)
		end
	end
	return result
end

local function filterCandidates(evidence, ruleOuts, options)
	options = options or {}
	local observed, disproved = collectEvidence(evidence, options)
	local ruledOut = collectRuleOuts(ruleOuts)
	local result = {}
	for _, ghostProfile in ipairs(candidatePool(options)) do
		local compatible = options.IgnoreRuleOuts == true or not ruledOut[ghostProfile.Name]
		if compatible then
			for evidenceKey in pairs(observed) do
				if not supportsEvidence(ghostProfile, evidenceKey, options) then
					compatible = false
					break
				end
			end
		end
		if compatible then
			for evidenceKey in pairs(disproved) do
				-- A missing fake Orb does not disprove Doppelganger, so negative
				-- evidence considers real evidence only.
				if supportsEvidence(ghostProfile, evidenceKey, {RealOnly = true}) then
					compatible = false
					break
				end
			end
		end
		if compatible then
			if options.NamesOnly == true then
				table.insert(result, ghostProfile.Name)
			else
				table.insert(result, ghostProfile)
			end
		end
	end
	return result
end

local function classifyOrbCombination(evidence, evidenceLimit)
	evidenceLimit = tonumber(evidenceLimit)
	if not evidenceLimit or evidenceLimit < 0 or evidenceLimit > 3 or evidenceLimit % 1 ~= 0 then
		evidenceLimit = 3
	end
	local observed = collectEvidence(evidence)
	local evidenceCount = 0
	for _, evidenceKey in ipairs(EVIDENCE_ORDER) do
		if observed[evidenceKey] then
			evidenceCount = evidenceCount + 1
		end
	end
	local orbObserved = observed.GhostOrb == true
	local realCandidates = {}
	if orbObserved then
		realCandidates = filterCandidates(observed, {}, {
			NamesOnly = true,
			RealOnly = true,
			IncludeFalseEvidence = false,
		})
	end
	local fourthEvidence = orbObserved and evidenceCount >= 4
	local excessEvidence = orbObserved and evidenceCount > evidenceLimit
	local impossibleCombination = orbObserved
		and evidenceCount >= 3
		and #realCandidates == 0
	return {
		OrbObserved = orbObserved,
		EvidenceCount = evidenceCount,
		FourthEvidence = fourthEvidence,
		EvidenceLimit = evidenceLimit,
		ExcessEvidence = excessEvidence,
		ImpossibleCombination = impossibleCombination,
		Qualified = excessEvidence or impossibleCombination,
		RealCandidates = realCandidates,
		Evidence = observed,
	}
end

local function detectionName(detection, fallback)
	if type(detection) == "table" then
		return detection.Ghost or detection.Name or detection.GhostName or fallback
	end
	return fallback
end

local function detectionScore(detection)
	if type(detection) == "number" then
		return detection
	elseif type(detection) == "table" then
		return tonumber(detection.Confidence or detection.Score or detection.Value) or 0
	end
	return 0
end

local function highestConfidenceTies(ranked)
	if type(ranked) ~= "table" or type(ranked[1]) ~= "table" then
		return {}
	end
	local topScore = detectionScore(ranked[1])
	local names = {}
	for _, candidate in ipairs(ranked) do
		if math.abs(detectionScore(candidate) - topScore) > 0.0001 then
			break
		end
		local name = detectionName(candidate)
		if type(name) == "string" and name ~= "" then
			table.insert(names, name)
		end
	end
	return names
end

local function selectHighestConfidenceGuess(options)
	if type(options) ~= "table" or type(options.Candidates) ~= "table" then
		return nil
	end

	local candidates = {}
	local allowed = {}
	local function addCandidate(value)
		if type(value) ~= "string" then
			return
		end
		local name = value:match("^%s*(.-)%s*$")
		if name == "" or allowed[name] then
			return
		end
		allowed[name] = true
		table.insert(candidates, name)
	end

	for _, value in ipairs(options.Candidates) do
		addCandidate(value)
	end
	local keyedCandidates = {}
	for key, value in pairs(options.Candidates) do
		if type(key) == "string" and value then
			table.insert(keyedCandidates, key)
		end
	end
	table.sort(keyedCandidates)
	for _, name in ipairs(keyedCandidates) do
		addCandidate(name)
	end
	if #candidates == 0 then
		return nil
	end

	-- A confirmed evidence observation is harder evidence than a behavioral
	-- confidence score. Restrict the timeout pool to profiles with the fewest
	-- conflicts before comparing perk detections. Normally this means exact
	-- compatibility; the best-fit fallback only matters if the observations
	-- themselves are contradictory.
	local confirmedEvidence = collectEvidence(options.ConfirmedEvidence)
	if next(confirmedEvidence) ~= nil then
		local fewestConflicts = math.huge
		local evidenceCandidates = {}
		for _, name in ipairs(candidates) do
			local conflicts = 0
			for evidenceKey in pairs(confirmedEvidence) do
				if not supportsEvidence(name, evidenceKey, {IncludeFalseEvidence = true}) then
					conflicts += 1
				end
			end
			-- A fake Orb cannot explain an incompatible real evidence type.
			if name ~= "Doppelganger" or conflicts == 0 then
				if conflicts < fewestConflicts then
					fewestConflicts = conflicts
					evidenceCandidates = {name}
				elseif conflicts == fewestConflicts then
					table.insert(evidenceCandidates, name)
				end
			end
		end
		candidates = evidenceCandidates
		allowed = {}
		for _, name in ipairs(candidates) do allowed[name] = true end
		if #candidates == 0 then return nil end
	end

	local scores: {[string]: number} = {}
	local detections = type(options.Detections) == "table" and options.Detections or {}
	local negativeConfidence = type(options.NegativeConfidence) == "table"
		and options.NegativeConfidence
		or {}
	for _, name in ipairs(candidates) do
		local detection = detections[name]
		local score = type(detection) == "table"
			and tonumber(detection.NetConfidence)
			or nil
		if score == nil then
			score = detectionScore(detection)
				- math.max(0, tonumber(negativeConfidence[name]) or 0)
		end
		if score ~= score then
			score = 0
		end
		scores[name] = score
	end

	local currentScore = options.CurrentScore
	if type(currentScore) == "number" and currentScore == currentScore and currentScore > 0
		and type(options.CurrentGuess) == "string" then
		local currentNames: {string} = {}
		for name in string.gmatch(options.CurrentGuess, "[^/]+") do
			name = name:match("^%s*(.-)%s*$")
			if allowed[name] then
				table.insert(currentNames, name)
			end
		end
		-- A composite GUI label has one aggregate confidence, not that score for
		-- every ghost named inside it. Promoting each member made stale 25% clues
		-- tie a real 35% leader during the final randomized selection.
		if #currentNames == 1 then
			local name = currentNames[1]
			if (tonumber(negativeConfidence[name]) or 0) <= 0 then
				scores[name] = math.max(scores[name] or 0, currentScore)
			end
		end
	end

	local maximumScore = -math.huge
	for _, name in ipairs(candidates) do
		maximumScore = math.max(maximumScore, scores[name] or 0)
	end
	local tied = {}
	for _, name in ipairs(candidates) do
		if (scores[name] or 0) == maximumScore then
			table.insert(tied, name)
		end
	end

	local orbObserved = options.OrbObserved == true
		or confirmedEvidence.GhostOrb == true
	local doppelgangerTied = false
	if #tied > 1 and not orbObserved then
		for _, name in ipairs(tied) do
			if name == "Doppelganger" then
				doppelgangerTied = true
				break
			end
		end
	end
	if doppelgangerTied then
		local redistributed = 0.5 / math.max(#tied - 1, 1)
		local totalWeight = 0
		local weights = {}
		for index, name in ipairs(tied) do
			local weight = name == "Doppelganger"
				and 0.5
				or 1 + redistributed
			weights[index] = weight
			totalWeight = totalWeight + weight
		end
		local unit
		if type(options.RandomUnit) == "function" then
			local ok, value = pcall(options.RandomUnit)
			if ok and type(value) == "number" and value == value then
				unit = math.clamp(value, 0, 0.999999999)
			end
		end
		unit = unit or math.random()
		local roll = unit * totalWeight
		local cumulative = 0
		for index, name in ipairs(tied) do
			cumulative = cumulative + weights[index]
			if roll < cumulative then
				return name
			end
		end
		return tied[#tied]
	end

	local index
	if options.RandomIndex ~= nil then
		if type(options.RandomIndex) ~= "function" then
			return nil
		end
		local ok, selected = pcall(options.RandomIndex, #tied)
		if not ok or type(selected) ~= "number" or selected ~= math.floor(selected)
			or selected < 1 or selected > #tied then
			return nil
		end
		index = selected
	else
		index = math.random(#tied)
	end
	return tied[index]
end

local function rankDetections(detections, evidence, ruleOuts, options)
	options = options or {}
	local candidateOptions = shallowCopy(options)
	candidateOptions.NamesOnly = true
	local compatibleNames = filterCandidates(evidence, ruleOuts, candidateOptions)
	local compatible = {}
	for _, ghostName in ipairs(compatibleNames) do
		compatible[ghostName] = true
	end

	local bestByName = {}
	local function consider(detection, fallbackName, insertionIndex)
		local ghostProfile = find(detectionName(detection, fallbackName))
		if not ghostProfile or not compatible[ghostProfile.Name] then
			return
		end
		local score = detectionScore(detection)
		if score < (tonumber(options.MinimumConfidence) or 0) then
			return
		end
		local source = type(detection) == "table" and shallowCopy(detection) or {Confidence = score}
		local persistent = source.Persistent == true or score >= 80
		local expiresAt = tonumber(source.ExpiresAt)
		local detectedAt = tonumber(source.DetectedAt or source.At)
		local ttl = tonumber(source.TTL or PerkTTL[ghostProfile.Name])
		if not expiresAt and detectedAt and ttl and not persistent then
			expiresAt = detectedAt + ttl
		end
		local expired = options.Now ~= nil
			and expiresAt ~= nil
			and tonumber(options.Now) ~= nil
			and tonumber(options.Now) > expiresAt
		if expired and options.IncludeExpired ~= true then
			return
		end
		local tier, tierName = confidenceTier(score)
		local ranked = {
			Ghost = ghostProfile.Name,
			Name = ghostProfile.Name,
			Profile = ghostProfile,
			Detection = source,
			Confidence = score,
			Score = score,
			Tier = tier,
			TierName = tierName,
			Reason = source.Reason,
			Persistent = persistent,
			ExpiresAt = expiresAt,
			Expired = expired == true,
			InsertionIndex = insertionIndex,
		}
		local previous = bestByName[ghostProfile.Name]
		if not previous or ranked.Score > previous.Score then
			bestByName[ghostProfile.Name] = ranked
		elseif ranked.Score == previous.Score
			and insertionIndex < previous.InsertionIndex then
			bestByName[ghostProfile.Name] = ranked
		end
	end

	if type(detections) == "table" then
		local insertionIndex = 0
		for _, detection in ipairs(detections) do
			insertionIndex = insertionIndex + 1
			consider(detection, nil, insertionIndex)
		end
		local mapKeys = {}
		for key in pairs(detections) do
			if type(key) == "string" then
				table.insert(mapKeys, key)
			end
		end
		table.sort(mapKeys)
		for _, key in ipairs(mapKeys) do
			insertionIndex = insertionIndex + 1
			consider(detections[key], key, insertionIndex)
		end
	end

	local result = {}
	for _, ranked in pairs(bestByName) do
		table.insert(result, ranked)
	end
	table.sort(result, function(left, right)
		if left.Tier ~= right.Tier then
			return left.Tier > right.Tier
		elseif left.Score ~= right.Score then
			return left.Score > right.Score
		end
		return (orderIndex[left.Ghost] or math.huge) < (orderIndex[right.Ghost] or math.huge)
	end)
	for _, ranked in ipairs(result) do
		ranked.InsertionIndex = nil
	end
	return result
end

local Tracker = {}
Tracker.__index = Tracker

local function copyNestedMap(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = type(value) == "table" and shallowCopy(value) or value
		end
	end
	return result
end

local function newTracker(initial)
	initial = initial or {}
	local tracker = setmetatable({
		Evidence = {},
		DisprovedEvidence = {},
		RuleOuts = {},
		Detections = {},
	}, Tracker)

	local initialEvidence = initial.Evidence or initial.ObservedEvidence
	local observed, disproved = collectEvidence(initialEvidence, {
		FalseMeansDisproved = initial.FalseMeansDisproved == true,
		DisprovedEvidence = initial.DisprovedEvidence,
	})
	tracker.Evidence = observed
	tracker.DisprovedEvidence = disproved
	tracker.RuleOuts = copyNestedMap(initial.RuleOuts or initial.RuledOut)
	tracker.Detections = copyNestedMap(initial.Detections)
	return tracker
end

function Tracker:SetEvidence(evidence, value)
	local evidenceKey = normalizeEvidence(evidence)
	if not evidenceKey then
		return false
	end
	if value == true then
		self.Evidence[evidenceKey] = true
		self.DisprovedEvidence[evidenceKey] = nil
	elseif value == false then
		self.Evidence[evidenceKey] = nil
		self.DisprovedEvidence[evidenceKey] = true
	else
		self.Evidence[evidenceKey] = nil
		self.DisprovedEvidence[evidenceKey] = nil
	end
	return true
end

function Tracker:ObserveEvidence(evidence)
	return self:SetEvidence(evidence, true)
end

function Tracker:DisproveEvidence(evidence)
	return self:SetEvidence(evidence, false)
end

function Tracker:ClearEvidence(evidence)
	return self:SetEvidence(evidence, nil)
end

function Tracker:RuleOut(ghostName, reason, confidence)
	local ghostProfile = find(ghostName)
	if not ghostProfile then
		return false
	end
	self.RuleOuts[ghostProfile.Name] = {
		Reason = reason,
		Confidence = tonumber(confidence) or 100,
	}
	return true
end

function Tracker:ClearRuleOut(ghostName)
	local ghostProfile = find(ghostName)
	if not ghostProfile or self.RuleOuts[ghostProfile.Name] == nil then
		return false
	end
	self.RuleOuts[ghostProfile.Name] = nil
	return true
end

function Tracker:IsRuledOut(ghostName)
	local ghostProfile = find(ghostName)
	return ghostProfile ~= nil and self.RuleOuts[ghostProfile.Name] ~= nil
end

function Tracker:RecordDetection(ghostName, reasonOrDetection, confidence)
	local ghostProfile = find(ghostName)
	if not ghostProfile then
		return false
	end
	local detection
	if type(reasonOrDetection) == "table" then
		detection = shallowCopy(reasonOrDetection)
	else
		detection = {
			Reason = reasonOrDetection,
			Confidence = tonumber(confidence) or PerkConfidence[ghostProfile.Name] or 0,
		}
	end
	detection.Ghost = ghostProfile.Name
	detection.Confidence = detectionScore(detection)
	local existing = self.Detections[ghostProfile.Name]
	if not existing or detection.Confidence >= detectionScore(existing) then
		self.Detections[ghostProfile.Name] = detection
		return true
	end
	return false
end

function Tracker:ClearDetection(ghostName)
	local ghostProfile = find(ghostName)
	if not ghostProfile or self.Detections[ghostProfile.Name] == nil then
		return false
	end
	self.Detections[ghostProfile.Name] = nil
	return true
end

function Tracker:GetCandidates(options)
	options = shallowCopy(options)
	options.DisprovedEvidence = self.DisprovedEvidence
	return filterCandidates(self.Evidence, self.RuleOuts, options)
end

Tracker.Candidates = Tracker.GetCandidates

function Tracker:Rank(options)
	options = shallowCopy(options)
	options.DisprovedEvidence = self.DisprovedEvidence
	return rankDetections(self.Detections, self.Evidence, self.RuleOuts, options)
end

Tracker.RankDetections = Tracker.Rank

function Tracker:Snapshot()
	return {
		Evidence = shallowCopy(self.Evidence),
		DisprovedEvidence = shallowCopy(self.DisprovedEvidence),
		RuleOuts = copyNestedMap(self.RuleOuts),
		Detections = copyNestedMap(self.Detections),
		Candidates = self:GetCandidates({NamesOnly = true}),
		Ranked = self:Rank(),
	}
end

function Tracker:Clone()
	return newTracker(self:Snapshot())
end

function Tracker:WithEvidence(evidence, value)
	local clone = self:Clone()
	clone:SetEvidence(evidence, value)
	return clone
end

function Tracker:WithRuleOut(ghostName, reason, confidence)
	local clone = self:Clone()
	clone:RuleOut(ghostName, reason, confidence)
	return clone
end

function Tracker:WithDetection(ghostName, reasonOrDetection, confidence)
	local clone = self:Clone()
	clone:RecordDetection(ghostName, reasonOrDetection, confidence)
	return clone
end

function Tracker:Reset()
	self.Evidence = {}
	self.DisprovedEvidence = {}
	self.RuleOuts = {}
	self.Detections = {}
	return self
end

GhostModule.Order = Order
GhostModule.Profiles = Profiles
GhostModule.ByName = ByName
GhostModule.Evidence = EVIDENCE
GhostModule.EvidenceOrder = EVIDENCE_ORDER
GhostModule.PerkConfidence = PerkConfidence
GhostModule.PerkTTL = PerkTTL
GhostModule.TierNames = TIER_NAMES
GhostModule.ConfidenceTier = confidenceTier
GhostModule.Find = find
GhostModule.NormalizeEvidence = normalizeEvidence
GhostModule.SupportsEvidence = supportsEvidence
GhostModule.FilterCandidates = filterCandidates
GhostModule.ClassifyOrbCombination = classifyOrbCombination
GhostModule.RankDetections = rankDetections
GhostModule.HighestConfidenceTies = highestConfidenceTies
GhostModule.SelectHighestConfidenceGuess = selectHighestConfidenceGuess
GhostModule.NewTracker = newTracker

return GhostModule
