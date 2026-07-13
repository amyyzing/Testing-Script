-- Pure evidence, candidate, and final-guess policy for one ghost session.
--
-- Runtime observers write detections and rule-outs; this module combines those
-- observations with the current evidence snapshot.  It deliberately owns no
-- Roblox instances, connections, clocks, or mutable tracker state.

return function(GhostModule)
	assert(type(GhostModule) == "table", "ghost/session.luau requires GhostModule")
	assert(type(GhostModule.Find) == "function", "GhostModule.Find is required")
	assert(
		type(GhostModule.NormalizeEvidence) == "function",
		"GhostModule.NormalizeEvidence is required"
	)
	assert(
		type(GhostModule.FilterCandidates) == "function",
		"GhostModule.FilterCandidates is required"
	)
	assert(
		type(GhostModule.RankDetections) == "function",
		"GhostModule.RankDetections is required"
	)
	assert(
		type(GhostModule.SelectTimeoutGuess) == "function",
		"GhostModule.SelectTimeoutGuess is required"
	)

	local Session = {}

	local function shallowCopy(source)
		local copy = {}
		if type(source) == "table" then
			for key, value in pairs(source) do
				copy[key] = value
			end
		end
		return copy
	end

	local function copyArray(source)
		local copy = {}
		for index, value in ipairs(source or {}) do
			copy[index] = value
		end
		return copy
	end

	local function addEvidence(target, value)
		local evidenceName = GhostModule.NormalizeEvidence(value)
		if evidenceName then
			target[evidenceName] = true
		end
	end

	local function collectEvidence(input)
		local evidence = {}
		if type(input) == "string" then
			addEvidence(evidence, input)
		elseif type(input) == "table" then
			if type(input.Evidence) == "table" and input.Evidence ~= input then
				input = input.Evidence
			end
			for _, value in ipairs(input) do
				addEvidence(evidence, value)
			end
			for key, value in pairs(input) do
				if type(key) == "string" and value == true then
					addEvidence(evidence, key)
				end
			end
		end
		return evidence
	end

	local function collectRuleOuts(input)
		local ruleOuts = {}
		if type(input) == "string" then
			local profile = GhostModule.Find(input)
			if profile then
				ruleOuts[profile.Name] = true
			end
		elseif type(input) == "table" then
			if type(input.RuleOuts) == "table" and input.RuleOuts ~= input then
				input = input.RuleOuts
			end
			for _, value in ipairs(input) do
				local profile = GhostModule.Find(value)
				if profile then
					ruleOuts[profile.Name] = true
				end
			end
			for key, value in pairs(input) do
				if type(key) == "string" and value then
					local profile = GhostModule.Find(key)
					if profile then
						ruleOuts[profile.Name] = value
					end
				end
			end
		end
		return ruleOuts
	end

	local function normalizeDetections(input)
		local detections = {}
		if type(input) ~= "table" then
			return detections
		end

		local function normalizeDetection(value)
			if type(value) ~= "table" then
				return value
			end
			local detection = shallowCopy(value)
			local score = tonumber(
				detection.Confidence or detection.Score or detection.Value
			) or 0
			-- High-confidence observations never expire.  The old live tracker made
			-- this adjustment in place; copying it here keeps evaluation pure.
			if detection.Persistent == true or score >= 80 then
				detection.Persistent = true
				detection.ExpiresAt = nil
			end
			return detection
		end

		for index, value in ipairs(input) do
			detections[index] = normalizeDetection(value)
		end
		for key, value in pairs(input) do
			if type(key) == "string" then
				detections[key] = normalizeDetection(value)
			end
		end
		return detections
	end

	local function normalizeInput(input)
		input = type(input) == "table" and input or {}
		local confirmed = collectEvidence(
			input.ConfirmedEvidence or input.Confirmed or input.Evidence
		)
		local observed = collectEvidence(input.ObservedEvidence or input.Observed)
		local tentative = collectEvidence(
			input.TentativeEvidence or input.Tentative
		)

		for evidenceName in pairs(confirmed) do
			observed[evidenceName] = true
		end
		if input.SpiritBoxTentative == true then
			tentative.SpiritBox = true
		end
		if input.OrbObserved == true then
			tentative.GhostOrb = true
		end
		for evidenceName in pairs(tentative) do
			observed[evidenceName] = true
		end
		-- Explicitly observed but unconfirmed evidence is tentative by definition.
		for evidenceName in pairs(observed) do
			if not confirmed[evidenceName] then
				tentative[evidenceName] = true
			end
		end

		local ruleOuts = collectRuleOuts(input.RuleOuts or input.RuledOut)
		local promotedEvidence = {}
		if input.Mode ~= "Mimicry"
			and tentative.GhostOrb == true
			and confirmed.GhostOrb ~= true then
			local skinwalker = GhostModule.Find("Skinwalker")
			local skinwalkerCompatible = skinwalker ~= nil
				and ruleOuts[skinwalker.Name] == nil
			if skinwalkerCompatible then
				for evidenceName in pairs(confirmed) do
					if not GhostModule.SupportsEvidence(
						skinwalker,
						evidenceName,
						{IncludeFalseEvidence = true}
					) then
						skinwalkerCompatible = false
						break
					end
				end
			end
			if not skinwalkerCompatible then
				confirmed.GhostOrb = true
				tentative.GhostOrb = nil
				promotedEvidence.GhostOrb = true
			end
		end

		return {
			Mode = input.Mode == "Mimicry" and "Mimicry" or "Normal",
			ConfirmedEvidence = confirmed,
			ObservedEvidence = observed,
			TentativeEvidence = tentative,
			Detections = normalizeDetections(input.Detections),
			RuleOuts = ruleOuts,
			PromotedEvidence = promotedEvidence,
			Now = tonumber(input.Now),
		}
	end

	local function isRuledOut(context, ghostName)
		return context.RuleOuts[ghostName] ~= nil
	end

	local function candidateEvidence(context)
		local evidence = shallowCopy(context.ConfirmedEvidence)
		-- An observed Orb participates in candidate filtering before it is fully
		-- confirmed. Spirit Box's tentative subtitle does not.
		if context.TentativeEvidence.GhostOrb then
			evidence.GhostOrb = true
		end
		return evidence
	end

	local function supportsSessionEvidence(context, ghostName, ignoreRuleOuts)
		local profile = GhostModule.Find(ghostName)
		if not profile then
			return false
		end
		if not ignoreRuleOuts and isRuledOut(context, profile.Name) then
			return false
		end

		for evidenceName in pairs(candidateEvidence(context)) do
			if context.Mode == "Mimicry" then
				-- Mimicry evidence is fake: a candidate is incompatible when that
				-- evidence is one of its three real evidence types.
				if GhostModule.SupportsEvidence(profile, evidenceName, {
					RealOnly = true,
				}) then
					return false
				end
			elseif not GhostModule.SupportsEvidence(profile, evidenceName, {
				IncludeFalseEvidence = true,
			}) then
				return false
			end
		end
		return true
	end

	local function getCandidates(context, ignoreRuleOuts)
		local result = {}
		for _, profile in ipairs(GhostModule.Profiles) do
			if supportsSessionEvidence(context, profile.Name, ignoreRuleOuts == true) then
				table.insert(result, profile.Name)
			end
		end
		return result
	end

	local function getPossibleEvidence(context)
		local candidates = getCandidates(context, false)
		if #candidates == 0 then
			candidates = getCandidates(context, true)
		end
		local possible = {}
		for _, ghostName in ipairs(candidates) do
			for _, evidenceName in ipairs(GhostModule.EvidenceOrder) do
				local supported
				if context.Mode == "Mimicry" then
					supported = not GhostModule.SupportsEvidence(
						ghostName,
						evidenceName,
						{RealOnly = true}
					)
				else
					supported = GhostModule.SupportsEvidence(
						ghostName,
						evidenceName,
						{IncludeFalseEvidence = true}
					)
				end
				if supported then
					possible[evidenceName] = true
				end
			end
		end
		return possible, candidates
	end

	local function getRankedDetection(context)
		local options = {}
		if context.Now ~= nil then
			options.Now = context.Now
		end
		local rawRanked = GhostModule.RankDetections(
			context.Detections,
			{},
			{},
			options
		)
		local ranked = {}
		for _, candidate in ipairs(rawRanked) do
			local preserveMimicryClue = context.Mode == "Mimicry"
				and candidate.Persistent == true
			if not isRuledOut(context, candidate.Ghost)
				and (
					supportsSessionEvidence(context, candidate.Ghost, false)
					or preserveMimicryClue
				) then
				table.insert(ranked, candidate)
			end
		end

		if #ranked == 0 then
			return nil, ranked
		end
		local top = ranked[1]
		local tiedNames = {top.Ghost}
		for index = 2, #ranked do
			local candidate = ranked[index]
			if candidate.Tier ~= top.Tier then
				break
			end
			if top.Tier < 3 and math.abs(candidate.Score - top.Score) >= 10 then
				break
			end
			table.insert(tiedNames, candidate.Ghost)
		end

		if #tiedNames > 1 then
			table.sort(tiedNames)
			local detection = {
				Confidence = top.Score,
				Reason = "multiple compatible detections had the same confidence tier",
				Tentative = true,
				Persistent = top.Score >= 80,
			}
			return {
				Ghost = table.concat(tiedNames, " / "),
				Names = tiedNames,
				Confidence = top.Score,
				Score = top.Score,
				Tier = top.Tier,
				TierName = top.TierName,
				Detection = detection,
				Tied = true,
			}, ranked
		end

		return {
			Ghost = top.Ghost,
			Names = {top.Ghost},
			Confidence = top.Score,
			Score = top.Score,
			Tier = top.Tier,
			TierName = top.TierName,
			Detection = top.Detection,
			Tied = false,
		}, ranked
	end

	local function countEvidence(evidence)
		local count = 0
		for _, found in pairs(evidence) do
			if found then
				count = count + 1
			end
		end
		return count
	end

	local function isExactEvidenceSet(evidence, names)
		if countEvidence(evidence) ~= #names then
			return false
		end
		for _, evidenceName in ipairs(names) do
			if not evidence[evidenceName] then
				return false
			end
		end
		return true
	end

	local function profileMatches(profile, evidence)
		for _, evidenceName in ipairs(profile.Evidence) do
			if not evidence[evidenceName] then
				return false
			end
		end
		return true
	end

	local function makeGuess(ghostName, confidence, certain, source)
		if not ghostName then
			return nil
		end
		return {
			Ghost = ghostName,
			Confidence = confidence,
			Score = confidence,
			Certain = certain == true,
			Source = source,
		}
	end

	local function exactEvidenceGuess(context)
		if context.Mode == "Mimicry" then
			return nil
		end
		local confirmed = context.ConfirmedEvidence
		if not isRuledOut(context, "Skinwalker")
			and (
				isExactEvidenceSet(confirmed, {
					"FreezingTemperatures",
					"GhostWriting",
					"SpiritBox",
				})
				or isExactEvidenceSet(confirmed, {
					"FreezingTemperatures",
					"GhostWriting",
					"SpiritBox",
					"GhostOrb",
				})
			) then
			return makeGuess("Skinwalker", 100, true, "ExactEvidence")
		end

		if countEvidence(confirmed) == 3 then
			for _, profile in ipairs(GhostModule.Profiles) do
				if not isRuledOut(context, profile.Name)
					and profileMatches(profile, confirmed) then
					return makeGuess(profile.Name, 100, true, "ExactEvidence")
				end
			end
		end
		return nil
	end

	local function compatibleNameList(context, requestedNames)
		local names = {}
		local seen = {}
		for _, ghostName in ipairs(requestedNames) do
			local profile = GhostModule.Find(ghostName)
			if profile and not seen[profile.Name]
				and supportsSessionEvidence(context, profile.Name, false) then
				seen[profile.Name] = true
				table.insert(names, profile.Name)
			end
		end
		return names
	end

	local function tentativeGuessForNames(context, requestedNames, confidence)
		local names = compatibleNameList(context, requestedNames)
		if #names == 0 then
			return nil
		end
		table.sort(names)
		return makeGuess(
			table.concat(names, " / "),
			confidence,
			false,
			"TentativeEvidence"
		)
	end

	local function tentativeEvidenceGuess(context)
		if context.Mode == "Mimicry" then
			return nil
		end
		local confirmed = context.ConfirmedEvidence
		local observed = context.ObservedEvidence
		local tentative = context.TentativeEvidence
		local observedCount = countEvidence(observed)
		local spiritBoxTentative = tentative.SpiritBox == true
			and not confirmed.SpiritBox
		local orbTentative = tentative.GhostOrb == true
			and not confirmed.GhostOrb

		if spiritBoxTentative and isExactEvidenceSet(observed, {
			"FreezingTemperatures",
			"GhostWriting",
			"SpiritBox",
			"GhostOrb",
		}) then
			return tentativeGuessForNames(context, {"Skinwalker"}, 35)
		end
		if isExactEvidenceSet(observed, {
			"FreezingTemperatures",
			"GhostOrb",
			"SpiritBox",
		}) then
			return tentativeGuessForNames(
				context,
				{"Ghoul", "Skinwalker"},
				35
			)
		end

		if spiritBoxTentative and observedCount == 3 then
			for _, profile in ipairs(GhostModule.Profiles) do
				if profileMatches(profile, observed) then
					if profile.Name == "Ghoul" then
						return tentativeGuessForNames(
							context,
							{"Ghoul", "Skinwalker"},
							60
						)
					end
					return tentativeGuessForNames(context, {profile.Name}, 60)
				end
			end
		end

		if orbTentative and observedCount == 3 then
			for _, profile in ipairs(GhostModule.Profiles) do
				if profileMatches(profile, observed) then
					if profile.Name == "Ghoul" then
						return tentativeGuessForNames(
							context,
							{"Ghoul", "Skinwalker"},
							35
						)
					end
					return tentativeGuessForNames(context, {profile.Name}, 35)
				end
			end
		end

		if observedCount == 3 and observed.GhostOrb then
			local skinwalkerRealEvidence = {
				FreezingTemperatures = true,
				GhostWriting = true,
				SpiritBox = true,
			}
			local matchingRealEvidence = 0
			for evidenceName, found in pairs(observed) do
				if found and evidenceName ~= "GhostOrb" then
					if not skinwalkerRealEvidence[evidenceName] then
						return nil
					end
					matchingRealEvidence = matchingRealEvidence + 1
				end
			end
			if matchingRealEvidence == 2 then
				return tentativeGuessForNames(context, {"Skinwalker"}, 35)
			end
		end

		if countEvidence(confirmed) >= 3 then
			return nil
		end
		return nil
	end

	local function splitCompatibleGuess(context, ghostName)
		local requested = {}
		for name in string.gmatch(tostring(ghostName or ""), "[^/]+") do
			name = string.gsub(name, "^%s+", "")
			name = string.gsub(name, "%s+$", "")
			table.insert(requested, name)
		end
		return compatibleNameList(context, requested)
	end

	local function selectFinalGuess(context, components)
		local exact = components.ExactEvidenceGuess
		if exact then
			return shallowCopy(exact)
		end

		local best = components.BestDetection
		local tentative = components.TentativeEvidenceGuess
		local candidates = components.Candidates
		local selectedGhost = best and best.Ghost or nil
		local selectedScore = best and best.Confidence or 0
		local selectedSource = best and "Detection" or nil
		local strongPerkLocked = best ~= nil and best.Confidence >= 80
		local mimicryBehaviorLocked = context.Mode == "Mimicry"
			and best ~= nil
			and best.Confidence >= 50

		local function consider(ghostName, score, source)
			if not ghostName then
				return
			end
			local names = splitCompatibleGuess(context, ghostName)
			if #names == 0 then
				return
			end
			ghostName = table.concat(names, " / ")
			local selectedTier = GhostModule.ConfidenceTier(selectedScore)
			local newTier = GhostModule.ConfidenceTier(score)
			if strongPerkLocked and score < 80 then
				return
			end
			if not selectedGhost
				or newTier > selectedTier
				or (newTier == selectedTier and score > selectedScore) then
				selectedGhost = ghostName
				selectedScore = score
				selectedSource = source
			elseif newTier == selectedTier
				and math.abs(score - selectedScore) < 10
				and not string.find(selectedGhost, ghostName, 1, true) then
				selectedGhost = selectedGhost .. " / " .. ghostName
			end
		end

		if tentative then
			consider(tentative.Ghost, tentative.Confidence, "TentativeEvidence")
		end
		if #candidates == 1 and not mimicryBehaviorLocked then
			consider(candidates[1], 90, "SingleCandidate")
		elseif not selectedGhost and #candidates > 1 and #candidates <= 3 then
			local sortedCandidates = copyArray(candidates)
			table.sort(sortedCandidates)
			selectedGhost = table.concat(sortedCandidates, " / ")
			selectedScore = 35
			selectedSource = "CandidateTie"
		end

		return makeGuess(
			selectedGhost,
			selectedScore,
			false,
			selectedSource
		)
	end

	local function evaluateNormalized(context)
		local candidates = getCandidates(context, false)
		local possibleEvidence, possibleEvidenceCandidates =
			getPossibleEvidence(context)
		local bestDetection, rankedDetections = getRankedDetection(context)
		local exactGuess = exactEvidenceGuess(context)
		local tentativeGuess = tentativeEvidenceGuess(context)
		local components = {
			Candidates = candidates,
			BestDetection = bestDetection,
			ExactEvidenceGuess = exactGuess,
			TentativeEvidenceGuess = tentativeGuess,
		}
		local finalGuess = selectFinalGuess(context, components)

		return {
			Mode = context.Mode,
			ConfirmedEvidence = shallowCopy(context.ConfirmedEvidence),
			ObservedEvidence = shallowCopy(context.ObservedEvidence),
			TentativeEvidence = shallowCopy(context.TentativeEvidence),
			PromotedEvidence = shallowCopy(context.PromotedEvidence),
			Candidates = candidates,
			PossibleEvidence = possibleEvidence,
			PossibleEvidenceCandidates = possibleEvidenceCandidates,
			RankedDetections = rankedDetections,
			BestDetection = bestDetection,
			ExactEvidenceGuess = exactGuess,
			TentativeEvidenceGuess = tentativeGuess,
			FinalGuess = finalGuess,
		}
	end

	local function timeoutDetectionScore(detection)
		local score
		if type(detection) == "number" then
			score = detection
		elseif type(detection) == "table" then
			score = tonumber(
				detection.Confidence or detection.Score or detection.Value
			)
		end
		if type(score) ~= "number" or score ~= score or score < 0 then
			return 0
		end
		return score
	end

	local function guessContainsName(guess, ghostName)
		if type(guess) ~= "string" then
			return false
		end
		for rawName in string.gmatch(guess, "[^/]+") do
			local profile = GhostModule.Find(rawName)
			if profile and profile.Name == ghostName then
				return true
			end
		end
		return false
	end

	local function selectTimeoutGuess(context, options)
		options = type(options) == "table" and options or {}
		local eligible = {}
		for _, ghostName in ipairs(getCandidates(context, false)) do
			eligible[ghostName] = true
		end

		if context.Mode == "Mimicry" then
			for ghostName, detection in pairs(context.Detections) do
				local profile = GhostModule.Find(ghostName)
				local persistent = type(detection) == "table"
					and detection.Persistent == true
					or timeoutDetectionScore(detection) >= 80
				if profile and persistent
					and not isRuledOut(context, profile.Name) then
					eligible[profile.Name] = true
				end
			end
		end

		-- Rebuild in catalog order after the Mimicry union. This avoids map-order
		-- randomness affecting the weighted choice or its tests.
		local candidates = {}
		for _, profile in ipairs(GhostModule.Profiles) do
			if eligible[profile.Name] then
				table.insert(candidates, profile.Name)
			end
		end

		local currentGuess = options.CurrentGuess
		local currentScore = tonumber(options.CurrentScore) or 0
		if currentScore ~= currentScore or currentScore < 0 then
			currentScore = 0
		end
		local candidateScores = {}
		local maximumScore = 0
		for _, ghostName in ipairs(candidates) do
			local score = timeoutDetectionScore(context.Detections[ghostName])
			if guessContainsName(currentGuess, ghostName) then
				score = math.max(score, currentScore)
			end
			candidateScores[ghostName] = score
			maximumScore = math.max(maximumScore, score)
		end

		local maximumNames = {}
		for _, ghostName in ipairs(candidates) do
			if candidateScores[ghostName] == maximumScore then
				table.insert(maximumNames, ghostName)
			end
		end
		table.sort(maximumNames)
		local hasOrbEvidence = context.ObservedEvidence.GhostOrb == true
		local signature = table.concat(maximumNames, "\0")
			.. "|orb="
			.. tostring(hasOrbEvidence)

		local choice
		local previousProfile = GhostModule.Find(options.PreviousChoice)
		local previousChoice = previousProfile and previousProfile.Name or nil
		if previousChoice and eligible[previousChoice]
			and candidateScores[previousChoice] == maximumScore then
			choice = previousChoice
		elseif #candidates > 0 then
			choice = GhostModule.SelectTimeoutGuess({
				Candidates = candidates,
				Detections = context.Detections,
				CurrentGuess = currentGuess,
				CurrentScore = currentScore,
				HasOrbEvidence = hasOrbEvidence,
				RandomUnit = options.RandomUnit,
				RandomIndex = options.RandomIndex,
			})
			if not choice or not eligible[choice]
				or candidateScores[choice] ~= maximumScore then
				choice = nil
			end
		end

		return {
			Ghost = choice,
			Confidence = choice and math.max(candidateScores[choice] or 0, 1) or 0,
			Candidates = candidates,
			CandidateScores = candidateScores,
			MaximumScore = maximumScore,
			MaximumNames = maximumNames,
			Signature = signature,
			HasOrbEvidence = hasOrbEvidence,
		}
	end

	function Session.GetCandidates(input, ignoreRuleOuts)
		return getCandidates(normalizeInput(input), ignoreRuleOuts == true)
	end

	function Session.SupportsSessionEvidence(ghostName, input, ignoreRuleOuts)
		return supportsSessionEvidence(
			normalizeInput(input),
			ghostName,
			ignoreRuleOuts == true
		)
	end

	function Session.GetPossibleEvidence(input)
		return getPossibleEvidence(normalizeInput(input))
	end

	function Session.GetRankedDetection(input)
		return getRankedDetection(normalizeInput(input))
	end

	Session.GetBestDetection = Session.GetRankedDetection

	function Session.GetExactEvidenceGuess(input)
		return exactEvidenceGuess(normalizeInput(input))
	end

	function Session.GetTentativeEvidenceGuess(input)
		return tentativeEvidenceGuess(normalizeInput(input))
	end

	function Session.SelectFinalGuess(input)
		return evaluateNormalized(normalizeInput(input)).FinalGuess
	end

	function Session.SelectTimeoutGuess(input, options)
		return selectTimeoutGuess(normalizeInput(input), options)
	end

	function Session.Evaluate(input)
		return evaluateNormalized(normalizeInput(input))
	end

	return Session
end
