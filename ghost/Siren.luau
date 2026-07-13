local SOURCE = "https://demonology.fandom.com/wiki/Siren"
local FEMALE_MODELS = {Abaddon = true, Leech = true, Rattle = true, Watcher = true}

local function createObserver(api)
	local state = {
		LastSpiritBoxKind = nil,
		LastSpiritBoxReason = nil,
		LastFemaleReason = nil,
		LastLosSlowReason = nil,
		LastLosNegativeReason = nil,
		LosExposure = 0,
		SlowObservedThisHunt = false,
		SlowEvents = {},
	}
	local observer = {}

	local function skinwalkerPossible(event)
		if type(event.SkinwalkerPossible) == "boolean" then
			return event.SkinwalkerPossible
		end
		return api:SupportsConfirmedEvidence("Skinwalker") == true
	end

	function observer:Reset()
		state.LastSpiritBoxKind = nil
		state.LastSpiritBoxReason = nil
		state.LastFemaleReason = nil
		state.LastLosSlowReason = nil
		state.LastLosNegativeReason = nil
		state.LosExposure = 0
		state.SlowObservedThisHunt = false
		state.SlowEvents = {}
	end

	function observer:OnHuntStarted()
		state.LosExposure = 0
		state.SlowObservedThisHunt = false
		state.SlowEvents = {}
	end

	function observer:OnLosExposure(event)
		if type(event) == "table"
			and event.Hunting == true
			and event.LineOfSight == true then
			state.LosExposure = state.LosExposure
				+ math.max(0, tonumber(event.DeltaTime) or 0)
		end
	end

	function observer:OnPlayerWalkSpeedAttempt(event)
		if type(event) ~= "table"
			or event.Hunting ~= true
			or event.LineOfSight ~= true then
			return
		end
		local attemptedSpeed = tonumber(event.AttemptedSpeed)
		local referenceSpeed = tonumber(event.ReferenceSpeed)
		local now = tonumber(event.Time) or os.clock()
		if not attemptedSpeed or not referenceSpeed
			or attemptedSpeed >= math.max(referenceSpeed, 1) - 0.25 then
			return
		end
		local lightingKey = event.LightingKey
			or (event.Room ~= nil and type(event.Lit) == "boolean"
				and (string.lower(tostring(event.Room))
					.. "|" .. (event.Lit and "lit" or "dark"))
				or nil)
		if lightingKey == nil then
			return
		end
		table.insert(state.SlowEvents, {Time = now, LightingKey = lightingKey})
		while state.SlowEvents[1] and now - state.SlowEvents[1].Time > 4 do
			table.remove(state.SlowEvents, 1)
		end
		local matching = 0
		for _, sample in ipairs(state.SlowEvents) do
			if sample.LightingKey == lightingKey then
				matching = matching + 1
			end
		end
		if matching >= 2 and not state.SlowObservedThisHunt then
			state.SlowObservedThisHunt = true
			self:OnLosSlow({
				Room = event.Room,
				Lit = event.Lit,
				Source = event.Source,
			})
		end
	end

	function observer:OnHuntEnded(event)
		if state.LosExposure >= 4 and not state.SlowObservedThisHunt then
			self:OnHuntLosNegative(event)
		end
	end

	function observer:OnSpiritBox(event)
		if type(event) ~= "table" then
			return
		end
		local kind = event.Kind
		state.LastSpiritBoxKind = kind
		state.LastSpiritBoxReason = event.Reason
		if kind == "Humming" then
			local mayBeSkinwalker = skinwalkerPossible(event)
			api:Detect(
				"Siren",
				event.Reason
					or "Spirit Box returned the distinctive - HUMMING - subtitle",
				tonumber(event.Confidence)
					or (mayBeSkinwalker and 60 or 95),
				event.Source
			)
			if mayBeSkinwalker then
				api:Detect(
					"Skinwalker",
					"Skinwalker may mimic the Siren humming response",
					60,
					event.Source
				)
			end
		elseif kind == "Female" then
			local reason = event.Reason
				or "ShowSubtitle identified the Spirit Box voice category as Female"
			api:Detect("Keres", reason, 35, event.Source)
			api:Detect("Siren", reason, 35, event.Source)
			api:MarkPersistent("Keres")
			api:MarkPersistent("Siren")
		else
			return
		end
		api:Refresh()
	end

	function observer:OnSpiritBoxObservation(event)
		if type(event) ~= "table" or event.Kind ~= nil then
			return
		end
		local subtitle = string.lower(tostring(event.Subtitle or ""))
		local compactSubtitle = string.gsub(subtitle, "%s+", "")
		if compactSubtitle == "-humming-" then
			local classified = {}
			for key, value in pairs(event) do
				classified[key] = value
			end
			classified.Kind = "Humming"
			self:OnSpiritBox(classified)
		elseif event.Female == true
			or tostring(event.VoiceCategory or "") == "Female" then
			local classified = {}
			for key, value in pairs(event) do
				classified[key] = value
			end
			classified.Kind = "Female"
			self:OnSpiritBox(classified)
		end
	end

	function observer:OnFemaleIndicator(event)
		event = type(event) == "table" and event or {}
		if event.Model ~= nil and not FEMALE_MODELS[tostring(event.Model)] then
			return
		end
		local reason = event.Reason
		if reason == nil and event.Model ~= nil then
			reason = "VisualModel "
				.. tostring(event.Model)
				.. " is one of the female Keres/Siren ghost models"
		end
		state.LastFemaleReason = reason
		api:Detect(
			"Siren",
			reason
				or "the ghost used one of the female Keres/Siren indicators",
			35,
			event.Source
		)
		api:MarkPersistent("Siren")
		api:Refresh()
	end

	function observer:OnLosSlow(event)
		event = type(event) == "table" and event or {}
		state.LastLosSlowReason = event.Reason
		local lightingReason
		if event.Room ~= nil and type(event.Lit) == "boolean" then
			lightingReason = "player WalkSpeed was reduced in line of sight while lighting stayed "
				.. (event.Lit and "on" or "off")
				.. " in "
				.. tostring(event.Room)
		end
		api:ClearRuleOut("Siren")
		api:Detect(
			"Siren",
			event.Reason
				or lightingReason
				or "player WalkSpeed was reduced in line of sight while lighting stayed stable",
			tonumber(event.Confidence) or 95,
			event.Source
		)
		api:Refresh()
	end

	function observer:OnHuntLosNegative(event)
		event = type(event) == "table" and event or {}
		state.LastLosNegativeReason = event.Reason
		api:RuleOut(
			"Siren",
			event.Reason
				or "the ghost maintained line of sight without attempting to slow the player",
			90
		)
		api:Refresh()
	end

	function observer:Snapshot()
		return {
			LastSpiritBoxKind = state.LastSpiritBoxKind,
			LastSpiritBoxReason = state.LastSpiritBoxReason,
			LastFemaleReason = state.LastFemaleReason,
			LastLosSlowReason = state.LastLosSlowReason,
			LastLosNegativeReason = state.LastLosNegativeReason,
			LosExposure = state.LosExposure,
			SlowObservedThisHunt = state.SlowObservedThisHunt,
		}
	end

	return observer
end

return {
	Name = "Siren",
	Evidence = {"EMFLevel5", "SpiritBox", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	TTL = 25,
	ObservationKeys = {"FemaleVisualModel", "FemaleSpiritBoxVoice", "SpiritBoxHumming", "LineOfSightPlayerSlow"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A hunter is clearly slowed while inside the Siren's line of sight; this trait is not listed as Skinwalker-mimickable.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
			{
				Text = "The Spirit Box returns - HUMMING - after Skinwalker has been excluded.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "The Spirit Box returns - HUMMING -, which can also be a mimicking Skinwalker.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "A feminine Spirit Box response only narrows the ghost to Siren or Keres.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
			{
				Text = "A feminine model only narrows the ghost to Siren or Keres.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Model",
			},
		},
	},
}
