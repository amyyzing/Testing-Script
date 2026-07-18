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
	Skinwalker = "https://demonology.fandom.com/wiki/Skinwalker",
	Specter = "https://demonology.fandom.com/wiki/Specter",
	Spirit = "https://demonology.fandom.com/wiki/Spirit",
	Wisp = "https://demonology.fandom.com/wiki/The_Wisp",
	Umbra = "https://demonology.fandom.com/wiki/Umbra",
	Vesper = "https://demonology.fandom.com/wiki/Vesper",
	Vex = "https://demonology.fandom.com/wiki/Vex",
	Wendigo = "https://demonology.fandom.com/wiki/Wendigo",
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
	profile("Banshee", {"FreezingTemperatures", "GhostOrb", "Handprints"}, "user-observed", perks({
		note("At least two new BrokenGlass models appear within one five-second window.", SOURCE.Banshee, "user-observed", false, "Trait"),
	}, {}, {
		note("The absence of a glass burst is not a Banshee negative.", SOURCE.Banshee, "user-observed", false, "Caveat"),
	})),
	profile("Demon", {"EMFLevel5", "FreezingTemperatures", "Handprints"}, "user-observed", perks({
		note("An eligible burning Cross floats and rotates.", SOURCE.Demon, "user-observed", false, "Weakness"),
	}, {}, {
		note("An eligible Cross that finishes burning without floating and rotating is a 99% negative.", SOURCE.Demon, "user-observed", false, "RuleOut"),
	})),
	profile("Dullahan", {"FreezingTemperatures", "LaserProjector", "Wither"}, "user-observed", perks({
		note("After seven complete invisible/visible pairs exclude valid Phantom and exactly-flat patterns, any upward speed step of nonzero magnitude identifies Dullahan; decreases and resets are ignored.", SOURCE.Dullahan, "user-observed", false, "Trait"),
	}, {}, {
		note("A valid Phantom pattern or one exactly-flat seven-pair sequence rules Dullahan out. Decreases and resets are ignored; an invalid stable A/B sequence still supports Dullahan when its tracked direction contains a nonzero rise.", SOURCE.Dullahan, "user-observed", false, "RuleOut"),
	})),
	profile("Dybbuk", {"FreezingTemperatures", "Handprints", "Wither"}, "tracker-pending", perks({}, {}, {
		note("No automatic Dybbuk behavior observation is currently trusted.", SOURCE.Dybbuk, "tracker-pending", false, "Caveat"),
	})),
	profile("Entity", {"Handprints", "LaserProjector", "SpiritBox"}, "user-observed", perks({
		note("A confirmed object teleport is accompanied by a SmokeHolder appearing anywhere in Workspace.", SOURCE.Entity, "user-observed", true, "Ability"),
	}, {}, {
		note("A confirmed object teleport without a SmokeHolder is a 50% negative, not a full rule-out.", SOURCE.Entity, "user-observed", true, "Caveat"),
	})),
	profile("Ghoul", {"FreezingTemperatures", "GhostOrb", "SpiritBox"}, "user-observed", perks({}, {}, {
		note("Electronics becoming disabled while every player is more than 15 studs away is a 99% negative for Ghoul.", SOURCE.Ghoul, "user-observed", false, "RuleOut"),
		note("No positive automatic Ghoul observation is currently trusted.", SOURCE.Ghoul, "user-observed", false, "Caveat"),
	})),
	profile("Keres", {"Handprints", "SpiritBox", "Wither"}, "user-observed", perks({
		note("Stable hunting speed permanently decreases after a qualified unique player kill.", SOURCE.Keres, "user-observed", false, "Trait"),
	}, {
		note("A verified female VisualModel is weak supporting evidence.", SOURCE.Keres, "user-observed", false, "Model"),
	}, {
		note("No speed decrease after a qualified unique kill, or a verified male VisualModel, is a 99% negative.", SOURCE.Keres, "user-observed", false, "RuleOut"),
	})),
	profile("Leviathan", {"GhostOrb", "GhostWriting", "Handprints"}, "user-observed", perks({
		note("A Spirit Box, Laser Projector, or Blacklight cleanly toggles at least seven times within 2.5 seconds.", SOURCE.Leviathan, "user-observed", true, "Ability"),
	}, {}, {
		note("One isolated toggle or an automation-caused toggle is not Leviathan evidence.", SOURCE.Leviathan, "user-observed", true, "Caveat"),
	})),
	profile("Nightmare", {"EMFLevel5", "GhostOrb", "SpiritBox"}, "tracker-pending", perks({}, {}, {
		note("No automatic Nightmare behavior observation is currently trusted.", SOURCE.Nightmare, "tracker-pending", false, "Caveat"),
	})),
	profile("Oni", {"FreezingTemperatures", "LaserProjector", "SpiritBox"}, "user-observed", perks({
		note("A complete seven-pair flat hunting window normalizes to base WalkSpeed 13.5 after map and configured-speed factors are removed.", SOURCE.Oni, "user-observed", false, "Trait"),
	}, {}, {
		note("A complete qualified flat hunting window that does not normalize to 13.5 is a 99% negative. Non-hunting speed is expected to normalize to 11.", SOURCE.Oni, "user-observed", false, "RuleOut"),
	})),
	profile("Phantom", {"EMFLevel5", "GhostOrb", "Handprints"}, "user-observed", perks({
		note("Across exactly seven hunt blink pairs, the same visible A and invisible B repeat and one allowed hunting multiplier fits map-normalized absolute bases 11 and 13.5. Ratio alone is insufficient.", SOURCE.Phantom, "user-observed", true, "Trait"),
	}, {}, {
		note("Any complete seven-pair window that is flat, drifting, decrease-only, or a stable A/B with invalid absolute bases rules Phantom out unless a confirmed unique Phantom match is already locked.", SOURCE.Phantom, "user-observed", true, "RuleOut"),
	})),
	profile("Ravager", {"EMFLevel5", "GhostWriting", "SpiritBox"}, "user-observed", perks({
		note("At least three distinct item or interactable models orbit the moving ghost in one direction for at least half a second.", SOURCE.Ravager, "user-observed", false, "Trait"),
	}, {}, {
		note("Ordinary throws and one moving object are not a vortex.", SOURCE.Ravager, "user-observed", false, "Caveat"),
	})),
	profile("Revenant", {"EMFLevel5", "FreezingTemperatures", "GhostWriting"}, "user-observed", perks({
		note("A hunt ends within one second of a valid multiplayer kill.", SOURCE.Revenant, "user-observed", false, "Weakness"),
	}, {}, {
		note("If the hunt is still active 1.5 seconds after a valid multiplayer kill, Revenant is ruled out at 99%.", SOURCE.Revenant, "user-observed", false, "RuleOut"),
	})),
	profile("Shadow", {"EMFLevel5", "GhostWriting", "LaserProjector"}, "user-observed", perks({
		note("After the round begins, seven actual unrounded cooling changes from the room occupied by the ghost have a direct arithmetic average below 0.08 C.", SOURCE.Shadow, "user-observed", false, "Trait"),
	}, {}, {
		note("A complete seven-change average greater than or equal to 0.08 C rules Shadow out. Temperature increases and unchanged readings are ignored.", SOURCE.Shadow, "user-observed", false, "RuleOut"),
	})),
	profile("Siren", {"EMFLevel5", "SpiritBox", "Wither"}, "user-observed", perks({
		note("The Spirit Box responds with - HUMMING -.", SOURCE.Siren, "user-observed", true, "Ability"),
		note("A sprinting player is slowed while inside the ghost's line of sight.", SOURCE.Siren, "user-observed", false, "Trait"),
	}, {
		note("A verified female VisualModel is weak supporting evidence.", SOURCE.Siren, "user-observed", false, "Model"),
	}, {
		note("A verified male VisualModel or a completed line-of-sight trial with no slowdown is a 99% negative.", SOURCE.Siren, "user-observed", false, "RuleOut"),
	})),
	profile("Skinwalker", {"FreezingTemperatures", "GhostWriting", "SpiritBox"}, "user-observed", perks({
		note("Ghost Orb forms a fourth evidence observation or completes an impossible three-evidence combination.", SOURCE.Skinwalker, "user-observed", false, "Trait"),
		note("Spirit Box humming paired with a verified male VisualModel identifies a Siren-mimicking Skinwalker.", SOURCE.Skinwalker, "user-observed", false, "Ability"),
	}, {
		note("It can mimic Wisp by crossing qualified burning Holy Oil without catching fire, or mimic Umbra by having no HumanoidRootPart sound other than Hunting.", SOURCE.Skinwalker, "user-observed", false, "Ability"),
	}, {
		note("Catching fire after qualified Holy Oil passage is a 99% Skinwalker negative. Orb alone is not sufficient.", SOURCE.Skinwalker, "user-observed", false, "RuleOut"),
	}), nil, {"GhostOrb"}),
	profile("Specter", {"EMFLevel5", "FreezingTemperatures", "LaserProjector"}, "user-observed", perks({
		note("Across a completed five-second arm trial, the non-hunting ghost remains stationary in its unchanged favourite room until the next hunt begins.", SOURCE.Specter, "user-observed", false, "Trait"),
	}, {}, {
		note("Leaving the unchanged favourite room before that trial's hunt begins is a Specter negative; room-change trials are discarded.", SOURCE.Specter, "user-observed", false, "RuleOut"),
	})),
	profile("Spirit", {"GhostWriting", "Handprints", "SpiritBox"}, "user-observed", perks({
		note("Qualified burning Holy Oil produces a blue fire colour.", SOURCE.Spirit, "user-observed", true, "Ability"),
	}, {}, {
		note("A stable qualified Holy Oil fire colour that is not blue is a 99% negative.", SOURCE.Spirit, "user-observed", true, "RuleOut"),
	})),
	profile("Umbra", {"GhostOrb", "Handprints", "LaserProjector"}, "user-observed", perks({
		note("A one-time HumanoidRootPart scan finds no Sound object other than Hunting.", SOURCE.Umbra, "user-observed", true, "Trait"),
	}, {}, {
		note("Finding any other HumanoidRootPart Sound object is a 99% negative.", SOURCE.Umbra, "user-observed", true, "RuleOut"),
	})),
	profile("Vesper", {"GhostWriting", "Handprints", "Wither"}, "tracker-pending", perks({}, {}, {
		note("No automatic Vesper behavior observation is currently trusted.", SOURCE.Vesper, "tracker-pending", false, "Caveat"),
	})),
	profile("Vex", {"FreezingTemperatures", "GhostOrb", "Wither"}, "user-observed", perks({
		note("The replicated InvisibleOnLIDAR value exists on the fixed ghost model.", SOURCE.Vex, "user-observed", false, "Trait"),
	}, {}, {
		note("The replicated InvisibleOnLIDAR value does not exist on the fixed ghost model.", SOURCE.Vex, "user-observed", false, "RuleOut"),
	})),
	profile("Wendigo", {"GhostOrb", "GhostWriting", "LaserProjector"}, "user-observed", perks({
		note("Two alternating settled hunt-state transitions match the WalkSpeed curve for average player Energy captured at each exact switch; the sanity spread must be large enough to exceed speed tolerance.", SOURCE.Wendigo, "user-observed", false, "Trait"),
	}, {}, {
		note("A qualified transition-time WalkSpeed does not match its same-transition average-Energy prediction. Live sanity changes between transitions do not change speed.", SOURCE.Wendigo, "user-observed", false, "RuleOut"),
	})),
	profile("Wisp", {"GhostOrb", "LaserProjector", "Wither"}, "user-observed", perks({
		note("While hunting through burning Holy Oil, GhostWall.CanCollide is false.", SOURCE.Wisp, "user-observed", false, "Ability"),
		note("A hunt begins inside the current favourite room.", SOURCE.Wisp, "user-observed", false, "Trait"),
	}, {}, {
		note("GhostWall.CanCollide remaining true during a qualified burning-oil passage, or a hunt starting outside the favourite room, is a strong negative.", SOURCE.Wisp, "user-observed", false, "RuleOut"),
	}), {"The Wisp", "Will-o-the-Wisp", "Will o the Wisp"}),
	profile("Wraith", {"EMFLevel5", "LaserProjector", "SpiritBox"}, "user-observed", perks({
		note("The ghost is directly observed touching a SaltLine and the contacted pile remains undisturbed for at least 1.25 seconds; hunting state does not matter.", SOURCE.Wraith, "user-observed", false, "Weakness"),
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

-- Exact compatibility tables copied from the original monolith. Missing keys
-- intentionally remain missing because recordPerkDetection used their absence
-- to ignore unsupported automatic detections.
local PerkConfidence = {
	Aswang = 99,
	Banshee = 99,
	Demon = 99,
	Dullahan = 99,
	Entity = 99,
	Skinwalker = 100,
	Keres = 99,
	Leviathan = 99,
	Oni = 99,
	Phantom = 99,
	Ravager = 99,
	Revenant = 99,
	Shadow = 99,
	Siren = 99,
	Specter = 95,
	Spirit = 99,
	Umbra = 99,
	Vex = 99,
	Wendigo = 99,
	Wisp = 99,
	Wraith = 99,
}

local PerkTTL = {
	Banshee = 30,
	Dullahan = 25,
	Dybbuk = 120,
	Entity = 30,
	Skinwalker = 120,
	Leviathan = 30,
	Oni = 25,
	Phantom = 30,
	Ravager = 6,
	Siren = 25,
	Specter = 120,
	Umbra = 60,
	Vex = 2,
	Wendigo = 20,
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
				-- A missing fake Orb does not disprove Skinwalker, so negative
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

local function classifyOrbCombination(evidence)
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
	local impossibleCombination = orbObserved
		and evidenceCount >= 3
		and #realCandidates == 0
	return {
		OrbObserved = orbObserved,
		EvidenceCount = evidenceCount,
		FourthEvidence = fourthEvidence,
		ImpossibleCombination = impossibleCombination,
		Qualified = fourthEvidence or impossibleCombination,
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
		local orbCombination = classifyOrbCombination(confirmedEvidence)
		if orbCombination.Qualified and allowed.Skinwalker then
			candidates = {"Skinwalker"}
			allowed = {Skinwalker = true}
		else
			local fewestConflicts = math.huge
			local evidenceCandidates = {}
			for _, name in ipairs(candidates) do
				local conflicts = 0
				for evidenceKey in pairs(confirmedEvidence) do
					-- With fewer than three confirmed observations, Orb is still a
					-- valid partial Skinwalker clue and must not push it behind every
					-- real-Orb ghost. At three observations a valid real combination
					-- wins; impossible/fourth combinations are handled above.
					local partialSkinwalkerOrb = name == "Skinwalker"
						and evidenceKey == "GhostOrb"
						and orbCombination.OrbObserved
						and orbCombination.EvidenceCount < 3
					if not partialSkinwalkerOrb and not supportsEvidence(name, evidenceKey, {
						RealOnly = true,
						IncludeFalseEvidence = false,
					}) then
						conflicts = conflicts + 1
					end
				end
				if conflicts < fewestConflicts then
					fewestConflicts = conflicts
					evidenceCandidates = {name}
				elseif conflicts == fewestConflicts then
					table.insert(evidenceCandidates, name)
				end
			end
			candidates = evidenceCandidates
			allowed = {}
			for _, name in ipairs(candidates) do
				allowed[name] = true
			end
		end
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
	local skinwalkerTied = false
	if #tied > 1 and not orbObserved then
		for _, name in ipairs(tied) do
			if name == "Skinwalker" then
				skinwalkerTied = true
				break
			end
		end
	end
	if skinwalkerTied then
		local redistributed = 0.5 / math.max(#tied - 1, 1)
		local totalWeight = 0
		local weights = {}
		for index, name in ipairs(tied) do
			local weight = name == "Skinwalker"
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
