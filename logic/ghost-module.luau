-- Demonology ghost catalogue and evidence helpers.
--
-- Internal evidence keys intentionally retain the names used by the original
-- monolith. DisplayName and CurrentName expose the current in-game/wiki names.

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
	profile("Aswang", {"EMFLevel5", "GhostWriting", "Wither"}, "wiki-documented", perks({
		note("During one hunt, the same touched SaltLine becomes DisturbedSaltLine, WalkSpeed temporarily falls below its reliable pre-touch baseline, then returns to that baseline.", SOURCE.Aswang, "wiki-documented", false, "Trait", "Require the contact, disturbance, repeated slowdown samples, and later recovery from the same hunt."),
	}, {
		note("A hunting ghost directly disturbed salt and showed a repeated speed dip, but recovery has not been sampled yet.", SOURCE.Aswang, "wiki-documented", false, "Trait", "Keep sampling through the temporary slowdown window before upgrading confidence."),
		note("Across controlled hunt-state comparisons, WalkSpeed rises by about 20% after each unique hunter kill.", SOURCE.Aswang, "wiki-documented", false, "Trait", "Compare stable speeds before and after the kill rather than relying on one estimate."),
	}, {
		note("Disturbed salt by itself, a non-hunt speed change, or an unreliable pre-touch baseline is not diagnostic.", SOURCE.Aswang, "wiki-documented", false, "Caveat"),
	})),
	profile("Banshee", {"FreezingTemperatures", "GhostOrb", "Handprints"}, "wiki-documented", perks({
		note("A distinct, subtitle-supported wail occurred at the start of a hunt after Skinwalker was ruled out.", SOURCE.Banshee, "wiki-documented", true, "Ability", "Skinwalker may mimic the wail."),
	}, {
		note("Glass, windows, bulbs, or cups break unusually often.", SOURCE.Banshee, "wiki-documented", false, "Trait"),
	}, {
		note("One glass break is weak evidence: any ghost can break glass and a Banshee may break none.", SOURCE.Banshee, "wiki-documented", false, "Caveat"),
	})),
	profile("Demon", {"EMFLevel5", "FreezingTemperatures", "Handprints"}, "wiki-documented", perks({
		note("A Cross visibly floats or spins while burning; Crosses also work from a larger range.", SOURCE.Demon, "wiki-documented", false, "Weakness"),
	}, {
		note("It hunts consistently as soon as the 85% average-energy threshold and hunt cooldown permit.", SOURCE.Demon, "wiki-documented", true, "Ability"),
	}, {
		note("Frequent hunts alone overlap with Revenant behavior and difficulty modifiers.", SOURCE.Demon, "wiki-documented", true, "Caveat"),
	})),
	profile("Dullahan", {"FreezingTemperatures", "LaserProjector", "Wither"}, "wiki-documented", perks({
		note("A clear Photo Camera image shows it without a head.", SOURCE.Dullahan, "wiki-documented", false, "Weakness"),
		note("During a hunt, WalkSpeed rises in several short intervals; line of sight is not required and intervening decreases do not invalidate the pattern.", SOURCE.Dullahan, "wiki-documented", false, "Trait"),
	}, {
		note("At least three upward WalkSpeed steps appear across five roughly 0.1-second hunting samples.", SOURCE.Dullahan, "wiki-documented", false, "Trait"),
	}, {
		note("A fast ghost or a naturally partial-head model can be mistaken for this tell.", SOURCE.Dullahan, "wiki-documented", false, "Caveat"),
	})),
	profile("Dybbuk", {"FreezingTemperatures", "Handprints", "Wither"}, "wiki-documented", perks({
		note("The first Music Box play visibly stuns it for about three seconds.", SOURCE.Dybbuk, "wiki-documented", false, "Weakness", "The Music Box is not guaranteed to spawn and is absent on Nightmare difficulty."),
	}, {
		note("A corpse was directly observed being thrown.", SOURCE.Dybbuk, "wiki-documented", true, "Ability"),
	}, {
		note("A corpse was merely found displaced; ordinary physics can move bodies.", SOURCE.Dybbuk, "wiki-documented", true, "Caveat"),
	})),
	profile("Entity", {"Handprints", "LaserProjector", "SpiritBox"}, "wiki-documented", perks({
		note("After Skinwalker is excluded, a witnessed teleport or an object teleport with same-colored smoke strongly identifies Entity.", SOURCE.Entity, "wiki-documented", true, "Ability"),
	}, {
		note("Equipment changed rooms, or salt placement implies an impossible path without teleporting.", SOURCE.Entity, "wiki-documented", true, "Ability"),
	}, {
		note("Frequent roaming or a missed salt line does not establish teleportation.", SOURCE.Entity, "wiki-documented", true, "Caveat"),
	})),
	profile("Ghoul", {"FreezingTemperatures", "GhostOrb", "SpiritBox"}, "wiki-documented", perks({
		note("Nearby electronics and Video Camera remain enabled and do not static during a hunt.", SOURCE.Ghoul, "wiki-documented", false, "Weakness", "The EMF Reader can still malfunction because it is not switched off."),
	}, {
		note("Repeated Spirit Box use or talking appears to trigger a hunt below the normal energy threshold.", SOURCE.Ghoul, "wiki-documented", false, "Trait"),
	}, {
		note("Electronics looked normal without confirming the hunting ghost was nearby.", SOURCE.Ghoul, "wiki-documented", false, "Caveat"),
	})),
	profile("Keres", {"Handprints", "SpiritBox", "Wither"}, "wiki-documented", perks({
		note("A controlled hunt targets the lowest-energy hunter while ignoring higher-energy hunters; solo it ignores a hunter at or above 90% energy.", SOURCE.Keres, "wiki-documented", false, "Trait"),
		note("Movement speed drops about 10% after each unique hunter kill.", SOURCE.Keres, "wiki-documented", false, "Weakness"),
	}, {
		note("It appears to prioritize the party member with the least energy.", SOURCE.Keres, "wiki-documented", false, "Trait"),
	}, {
		note("A feminine VisualModel only narrows the ghost to Keres or Siren.", SOURCE.Keres, "wiki-documented", false, "Model"),
	})),
	profile("Leviathan", {"GhostOrb", "GhostWriting", "Handprints"}, "wiki-stub", perks({
		note("Both nearby-equipment flicker and actual light-switch shutoff outside hunts were observed.", SOURCE.Leviathan, "wiki-stub", true, "Ability", "The current wiki recommends observing both because Skinwalker may copy one."),
	}, {
		note("Either nearby-equipment flicker or a light switch turning off outside a hunt was observed.", SOURCE.Leviathan, "wiki-stub", true, "Ability"),
	}, {
		note("A broken fuse box or general power outage is explicitly not the Leviathan tell.", SOURCE.Leviathan, "wiki-stub", true, "Caveat"),
	})),
	profile("Nightmare", {"EMFLevel5", "GhostOrb", "SpiritBox"}, "wiki-documented", perks({
		note("After Skinwalker is excluded, corroboration proves an auditory cue had no matching real interaction.", SOURCE.Nightmare, "wiki-documented", true, "Ability"),
	}, {
		note("It hunts more often while its current room is dark.", SOURCE.Nightmare, "wiki-documented", false, "Trait"),
	}, {
		note("An unexplained noise or general activity in darkness is not enough by itself.", SOURCE.Nightmare, "wiki-documented", true, "Caveat"),
	})),
	profile("Oni", {"FreezingTemperatures", "LaserProjector", "SpiritBox"}, "wiki-documented", perks({
		note("Across repeated hunts it consistently moves at a sprinting player's speed.", SOURCE.Oni, "wiki-documented", false, "Trait", "Speed estimates are safer when compared with a known baseline."),
	}, {
		note("Rapid or high-pitched footsteps accompany unusually frequent visible manifestations.", SOURCE.Oni, "wiki-documented", false, "Trait"),
	}, {
		note("One fast hunt or one manifestation is a risky relative-speed/activity tell.", SOURCE.Oni, "wiki-documented", false, "Caveat"),
	})),
	profile("Phantom", {"EMFLevel5", "GhostOrb", "Handprints"}, "wiki-documented", perks({
		note("At 100% configured speed its stable visible/invisible hunt speeds are 11/13.5 on Small maps, 11.55/14.175 on Medium maps, and 12.1/14.85 on Large maps; both modes scale together at other speed settings.", SOURCE.Phantom, "wiki-documented", true, "Trait", "Retain Skinwalker as an equal possibility in Mimicry mode."),
	}, {
		note("A stable paired phase shows the ghost moving about 13.5/11 times faster while invisible than while visible.", SOURCE.Phantom, "wiki-documented", true, "Trait"),
	}, {
		note("A transition edge or an unpaired speed sample is not diagnostic; compare stable visible and invisible phases at the same configured speed.", SOURCE.Phantom, "wiki-documented", true, "Caveat"),
	})),
	profile("Ravager", {"EMFLevel5", "GhostWriting", "SpiritBox"}, "wiki-recent-stub", perks({
		note("A vortex pulls nearby objects into a tornado during a hunt.", SOURCE.Ravager, "wiki-recent-stub", false, "Trait", "The guide reports roughly a one-in-three activation chance."),
		note("A ghost event produces EMF Level 5 even in a zero-evidence custom run.", SOURCE.Ravager, "wiki-recent-stub", false, "Weakness"),
	}, {
		note("Multiple objects are thrown simultaneously or cause a chain reaction.", SOURCE.Ravager, "wiki-recent-stub", true, "Ability"),
	}, {
		note("Frequent single-object throws overlap with Specter and ordinary activity.", SOURCE.Ravager, "wiki-recent-stub", true, "Caveat"),
	})),
	profile("Revenant", {"EMFLevel5", "FreezingTemperatures", "GhostWriting"}, "wiki-documented", perks({
		note("The hunt ends immediately after it kills a hunter.", SOURCE.Revenant, "wiki-documented", false, "Weakness", "This is clearest outside Easy and Medium difficulty."),
	}, {
		note("The cooldown between hunts is short but less mechanically consistent than a Demon.", SOURCE.Revenant, "wiki-documented", false, "Trait"),
	}, {
		note("Frequent hunts alone overlap with Demon behavior and difficulty settings.", SOURCE.Revenant, "wiki-documented", false, "Caveat"),
	})),
	profile("Shadow", {"EMFLevel5", "GhostWriting", "LaserProjector"}, "wiki-documented", perks({}, {
		note("A confirmed ghost room changes temperature only by small decimal steps and stays unusually warm.", SOURCE.Shadow, "wiki-documented", false, "Trait"),
		note("A controlled light-on versus light-off comparison shows reduced activity in the lit room.", SOURCE.Shadow, "wiki-documented", false, "Weakness"),
	}, {
		note("A quiet ghost or a room that is difficult to locate is only absence-based evidence.", SOURCE.Shadow, "wiki-documented", false, "Caveat"),
	})),
	profile("Siren", {"EMFLevel5", "SpiritBox", "Wither"}, "wiki-documented", perks({
		note("A hunter is clearly slowed while inside the Siren's line of sight; this trait is not listed as Skinwalker-mimickable.", SOURCE.Siren, "wiki-documented", false, "Trait"),
		note("The Spirit Box returns - HUMMING - after Skinwalker has been excluded.", SOURCE.Siren, "wiki-documented", true, "Ability"),
	}, {
		note("The Spirit Box returns - HUMMING -, which can also be a mimicking Skinwalker.", SOURCE.Siren, "wiki-documented", true, "Ability"),
	}, {
		note("A feminine model only narrows the ghost to Siren or Keres.", SOURCE.Siren, "wiki-documented", false, "Model"),
		note("Spirit Box humming paired with a male VisualModel rules Siren out and identifies a mimicking Skinwalker.", SOURCE.Siren, "wiki-documented", false, "Caveat"),
	})),
	profile("Skinwalker", {"FreezingTemperatures", "GhostWriting", "SpiritBox"}, "wiki-disputed", perks({
		note("Four evidence observations resolve to its three real evidences plus a fake Ghost Orb.", SOURCE.Skinwalker, "wiki-disputed", false, "Trait"),
		note("A confirmed Ghost Orb completes at least three evidence observations that no normal ghost's real three-evidence set can contain.", SOURCE.Skinwalker, "wiki-disputed", false, "Trait"),
		note("A Ghost Orb appears in a custom run with all real evidence disabled.", SOURCE.Skinwalker, "wiki-disputed", false, "Trait"),
		note("It copies Wisp fire-walking but crosses Holy Oil without catching fire.", SOURCE.Skinwalker, "wiki-disputed", false, "Ability"),
		note("Spirit Box humming paired with a male VisualModel identifies it mimicking Siren.", SOURCE.Skinwalker, "wiki-disputed", false, "Ability"),
		note("Multiple mutually inconsistent ghost abilities are observed in one job.", SOURCE.Skinwalker, "wiki-disputed", false, "Ability"),
	}, {
		note("A single ability looks copied, or an Orb is present with fewer than three total evidence observations.", SOURCE.Skinwalker, "wiki-disputed", false, "Ability"),
	}, {
		note("Frequent roaming or a Ghost Orb alone in normal evidence mode is weak evidence.", SOURCE.Skinwalker, "wiki-disputed", false, "Caveat"),
	}), nil, {"GhostOrb"}),
	profile("Specter", {"EMFLevel5", "FreezingTemperatures", "LaserProjector"}, "wiki-documented", perks({
		note("Repeated position or salt tracking establishes that it never leaves the favorite room except to hunt.", SOURCE.Specter, "wiki-documented", false, "Trait"),
	}, {
		note("It remains fixed to its favorite room while frequently throwing one object at a time.", SOURCE.Specter, "wiki-documented", false, "Trait"),
	}, {
		note("Frequent throwing alone overlaps with Ravager and ordinary ghost activity.", SOURCE.Specter, "wiki-documented", false, "Caveat"),
	})),
	profile("Spirit", {"GhostWriting", "Handprints", "SpiritBox"}, "wiki-documented", perks({
		note("After Skinwalker is excluded, a candle, lantern, Summoning Circle, or Holy Oil flame changes blue and remains blue after relighting.", SOURCE.Spirit, "wiki-documented", true, "Ability"),
	}, {
		note("One blue flame was observed while Skinwalker remains possible.", SOURCE.Spirit, "wiki-documented", true, "Ability"),
	}, {
		note("Low or mostly harmless activity is not an identifying trait by itself.", SOURCE.Spirit, "wiki-documented", true, "Caveat"),
	})),
	profile("Umbra", {"GhostOrb", "Handprints", "LaserProjector"}, "wiki-documented", perks({
		note("After Skinwalker is excluded, hunt footsteps are completely silent and movement slows in lit rooms.", SOURCE.Umbra, "wiki-documented", true, "Ability"),
	}, {
		note("Either silent hunt footsteps or a controlled lit-room slowdown was observed.", SOURCE.Umbra, "wiki-documented", true, "Trait"),
	}, {
		note("Footsteps were merely difficult to hear over other sounds.", SOURCE.Umbra, "wiki-documented", true, "Caveat"),
	})),
	profile("Vesper", {"GhostWriting", "Handprints", "Wither"}, "wiki-recent-stub", perks({
		note("A controlled silent/still test is followed by a sound that immediately causes tracking through a wall.", SOURCE.Vesper, "wiki-recent-stub", false, "Trait"),
	}, {
		note("It repeatedly tracks noisy equipment or hunters through walls.", SOURCE.Vesper, "wiki-recent-stub", false, "Trait"),
	}, {
		note("It simply failed to path toward a stationary hunter; this test is easy to misread.", SOURCE.Vesper, "wiki-recent-stub", false, "Caveat"),
	})),
	profile("Vex", {"FreezingTemperatures", "GhostOrb", "Wither"}, "wiki-documented", perks({
		note("It passes through a wall and repeatedly remains absent from LIDAR while its location is independently known.", SOURCE.Vex, "wiki-documented", true, "Trait", "Skinwalker may copy wall-walking but is not documented to copy LIDAR invisibility."),
	}, {
		note("It visibly walks through a wall, indicating Vex or a mimicking Skinwalker.", SOURCE.Vex, "wiki-documented", true, "Ability"),
	}, {
		note("Cutting a corner or missing from one scan without confirmed range is weak evidence.", SOURCE.Vex, "wiki-documented", true, "Caveat"),
	})),
	profile("Wendigo", {"GhostOrb", "GhostWriting", "LaserProjector"}, "wiki-documented", perks({
		note("Controlled energy changes correlate with hunt speed, and it refuses to begin a hunt near a lit candle or lantern.", SOURCE.Wendigo, "wiki-documented", false, "Trait"),
	}, {
		note("It becomes very fast at low average energy or repeatedly avoids starting near lit flames.", SOURCE.Wendigo, "wiki-documented", false, "Trait"),
	}, {
		note("One fast hunt or a hunt starting away from fire is not distinctive.", SOURCE.Wendigo, "wiki-documented", false, "Caveat"),
	})),
	profile("Wisp", {"GhostOrb", "LaserProjector", "Wither"}, "wiki-documented", perks({
		note("It crosses ignited Holy Oil and visibly catches fire; a mimicking Skinwalker does not ignite.", SOURCE.Wisp, "wiki-documented", false, "Ability"),
	}, {
		note("It lights an unlit candle or walks through a line of fire, both of which Skinwalker may mimic.", SOURCE.Wisp, "wiki-documented", true, "Ability"),
	}, {
		note("Hunts only seemed to start in the favorite room; that room can change on higher difficulty.", SOURCE.Wisp, "wiki-documented", false, "Trait"),
	}), {"The Wisp", "Will-o-the-Wisp", "Will o the Wisp"}),
	profile("Wraith", {"EMFLevel5", "LaserProjector", "SpiritBox"}, "wiki-documented", perks({
		note("It is directly observed crossing a salt line without disturbing it.", SOURCE.Wraith, "wiki-documented", false, "Weakness"),
		note("Measured passive energy drain is roughly 0.2-0.4% per second faster than normal.", SOURCE.Wraith, "wiki-documented", false, "Trait"),
	}, {
		note("The party's energy falls unusually quickly across a sustained sample.", SOURCE.Wraith, "wiki-documented", false, "Trait"),
	}, {
		note("Untouched salt is not useful unless the ghost was known to cross it.", SOURCE.Wraith, "wiki-documented", false, "Caveat"),
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
	Aswang = 95,
	Banshee = 60,
	Demon = 99,
	Dullahan = 99,
	Dybbuk = 60,
	Entity = 95,
	Skinwalker = 65,
	Keres = 95,
	Leviathan = 95,
	Oni = 97,
	Phantom = 99,
	Ravager = 95,
	Revenant = 35,
	Siren = 95,
	Specter = 35,
	Spirit = 99,
	Umbra = 95,
	Vex = 95,
	Wendigo = 98,
	Wisp = 35,
	Wraith = 95,
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
		local fewestConflicts = math.huge
		local evidenceCandidates = {}
		for _, name in ipairs(candidates) do
			local conflicts = 0
			for evidenceKey in pairs(confirmedEvidence) do
				if not supportsEvidence(name, evidenceKey, {
					IncludeFalseEvidence = true,
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

	local scores = {}
	local detections = type(options.Detections) == "table" and options.Detections or {}
	for _, name in ipairs(candidates) do
		local score = detectionScore(detections[name])
		if score ~= score or score < 0 then
			score = 0
		end
		scores[name] = score
	end

	local currentScore = options.CurrentScore
	if type(currentScore) == "number" and currentScore == currentScore and currentScore > 0
		and type(options.CurrentGuess) == "string" then
		for name in string.gmatch(options.CurrentGuess, "[^/]+") do
			name = name:match("^%s*(.-)%s*$")
			if allowed[name] then
				scores[name] = math.max(scores[name], currentScore)
			end
		end
	end

	local maximumScore = 0
	for _, name in ipairs(candidates) do
		maximumScore = math.max(maximumScore, scores[name])
	end
	local tied = {}
	for _, name in ipairs(candidates) do
		if scores[name] == maximumScore then
			table.insert(tied, name)
		end
	end

	local skinwalkerTied = false
	if #tied > 1 and options.OrbObserved ~= true then
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
