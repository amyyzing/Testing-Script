-- Stateful detection and rule-out storage for the ghost observation package.
--
-- The tables exposed as Detections and RuleOuts retain their identity for the
-- lifetime of the tracker so UI and automation adapters may safely hold them.

return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local catalog = assert(
		dependencies.Catalog,
		"ghost/tracker.luau requires Catalog"
	)
	local clock = dependencies.Clock or os.clock
	local onChanged = dependencies.OnChanged

	assert(type(catalog) == "table", "Catalog must be a table")
	assert(type(catalog.Find) == "function", "Catalog.Find is required")
	assert(type(clock) == "function", "Clock must be a function")
	assert(
		onChanged == nil or type(onChanged) == "function",
		"OnChanged must be a function"
	)

	local detections = {}
	local ruleOuts = {}
	local Tracker = {}
	Tracker.__index = Tracker

	local tracker

	local function shallowCopy(source)
		local copy = {}
		if type(source) == "table" then
			for key, value in pairs(source) do
				copy[key] = value
			end
		end
		return copy
	end

	local function canonicalName(value)
		local profile = catalog.Find(value)
		return profile and profile.Name or nil
	end

	local function validNumber(value)
		value = tonumber(value)
		if value == nil or value ~= value then
			return nil
		end
		return value
	end

	local function detectionScore(detection)
		if type(detection) == "number" then
			return validNumber(detection) or 0
		elseif type(detection) == "table" then
			return validNumber(
				detection.Confidence or detection.Score or detection.Value
			) or 0
		end
		return 0
	end

	local function defaultConfidence(ghostName)
		local confidence = type(catalog.PerkConfidence) == "table"
			and catalog.PerkConfidence[ghostName]
			or nil
		return validNumber(confidence)
	end

	local function defaultTTL(ghostName)
		local ttl = type(catalog.PerkTTL) == "table"
			and validNumber(catalog.PerkTTL[ghostName])
			or nil
		return ttl and ttl > 0 and ttl or nil
	end

	local function notify(change)
		if onChanged then
			onChanged(change, tracker)
		end
	end

	local function clearTable(target)
		local changed = next(target) ~= nil
		for key in pairs(target) do
			target[key] = nil
		end
		return changed
	end

	local function clearDetectionWithoutNotify(ghostName)
		local previous = detections[ghostName]
		if previous == nil then
			return nil
		end
		detections[ghostName] = nil
		return previous
	end

	function Tracker:Detect(ghostName, reason, confidence, source)
		ghostName = canonicalName(ghostName)
		if not ghostName then
			return false
		end

		if ruleOuts[ghostName] ~= nil then
			local removed = clearDetectionWithoutNotify(ghostName)
			if removed then
				notify({
					Type = "ClearDetection",
					Ghost = ghostName,
					Previous = shallowCopy(removed),
					Cause = "RuledOut",
				})
			end
			return false
		end

		local score = validNumber(confidence)
		if score == nil then
			score = defaultConfidence(ghostName)
		end
		if score == nil or score < 0 then
			return false
		end

		local now = validNumber(clock())
		assert(now ~= nil, "Clock must return a number")
		local ttl = defaultTTL(ghostName)
		local persistent = score >= 80
		local existing = detections[ghostName]
		local existingScore = detectionScore(existing)

		if existing == nil or score > existingScore then
			local detection = {
				Confidence = score,
				Reason = reason,
				DetectedAt = now,
				ExpiresAt = if persistent
					then nil
					else ttl and now + ttl or nil,
				Tentative = true,
				Persistent = persistent,
				Source = source,
			}
			detections[ghostName] = detection
			notify({
				Type = "Detect",
				Ghost = ghostName,
				Previous = type(existing) == "table"
					and shallowCopy(existing)
					or existing,
				Current = shallowCopy(detection),
			})
			return true
		end

		if type(existing) ~= "table" then
			-- A numeric compatibility entry is already dominant. Leave it intact;
			-- future writes with a higher score will replace it with a full record.
			return false
		end

		local previous = shallowCopy(existing)
		if score == existingScore then
			existing.Reason = reason or existing.Reason
			existing.Source = source or existing.Source
			existing.DetectedAt = now
			if persistent or existing.Persistent == true or existingScore >= 80 then
				existing.Persistent = true
				existing.ExpiresAt = nil
			elseif ttl then
				existing.ExpiresAt = now + ttl
			end
			notify({
				Type = "Detect",
				Ghost = ghostName,
				Previous = previous,
				Current = shallowCopy(existing),
				Refreshed = true,
			})
			return true
		end

		-- A weaker repeat cannot supersede the dominant detection, but it keeps a
		-- non-persistent observation alive just as the original live tracker did.
		if existing.Persistent == true or existingScore >= 80 then
			existing.Persistent = true
			existing.ExpiresAt = nil
		elseif ttl then
			existing.ExpiresAt = now + ttl
		end
		if existing.ExpiresAt ~= previous.ExpiresAt
			or existing.Persistent ~= previous.Persistent then
			notify({
				Type = "RefreshDetection",
				Ghost = ghostName,
				Previous = previous,
				Current = shallowCopy(existing),
			})
		end
		return false
	end

	function Tracker:RuleOut(ghostName, reason, confidence)
		ghostName = canonicalName(ghostName)
		if not ghostName then
			return false
		end
		local score = validNumber(confidence) or 0
		if score < 80 then
			return false
		end

		local existing = ruleOuts[ghostName]
		local existingScore = type(existing) == "table"
			and validNumber(existing.Confidence) or 0
		local removedDetection = clearDetectionWithoutNotify(ghostName)
		if existing ~= nil and (existingScore or 0) >= score then
			if removedDetection then
				notify({
					Type = "ClearDetection",
					Ghost = ghostName,
					Previous = shallowCopy(removedDetection),
					Cause = "RuledOut",
				})
			end
			return false
		end

		local now = validNumber(clock())
		assert(now ~= nil, "Clock must return a number")
		local ruleOut = {
			Confidence = score,
			Reason = reason,
			At = now,
		}
		ruleOuts[ghostName] = ruleOut
		notify({
			Type = "RuleOut",
			Ghost = ghostName,
			Previous = type(existing) == "table"
				and shallowCopy(existing)
				or existing,
			Current = shallowCopy(ruleOut),
			DetectionCleared = removedDetection ~= nil,
		})
		return true
	end

	function Tracker:ClearDetection(ghostName)
		ghostName = canonicalName(ghostName)
		if not ghostName then
			return false
		end
		local previous = clearDetectionWithoutNotify(ghostName)
		if previous == nil then
			return false
		end
		notify({
			Type = "ClearDetection",
			Ghost = ghostName,
			Previous = type(previous) == "table"
				and shallowCopy(previous)
				or previous,
		})
		return true
	end

	function Tracker:ClearRuleOut(ghostName)
		ghostName = canonicalName(ghostName)
		if not ghostName or ruleOuts[ghostName] == nil then
			return false
		end
		local previous = ruleOuts[ghostName]
		ruleOuts[ghostName] = nil
		notify({
			Type = "ClearRuleOut",
			Ghost = ghostName,
			Previous = type(previous) == "table"
				and shallowCopy(previous)
				or previous,
		})
		return true
	end

	function Tracker:IsRuledOut(ghostName)
		ghostName = canonicalName(ghostName)
		return ghostName ~= nil and ruleOuts[ghostName] ~= nil
	end

	function Tracker:GetDetection(ghostName)
		ghostName = canonicalName(ghostName)
		return ghostName and detections[ghostName] or nil
	end

	function Tracker:MarkPersistent(ghostName)
		ghostName = canonicalName(ghostName)
		local detection = ghostName and detections[ghostName] or nil
		if type(detection) ~= "table" then
			return false
		end
		if detection.Persistent == true and detection.ExpiresAt == nil then
			return true
		end
		local previous = shallowCopy(detection)
		detection.Persistent = true
		detection.ExpiresAt = nil
		notify({
			Type = "MarkPersistent",
			Ghost = ghostName,
			Previous = previous,
			Current = shallowCopy(detection),
		})
		return true
	end

	-- Compatibility for observers that temporarily preserve and restore a prior
	-- detection while switching evidence modes.
	function Tracker:SetDetection(ghostName, detection)
		ghostName = canonicalName(ghostName)
		if not ghostName then
			return false
		end
		if type(detection) ~= "table" then
			return self:ClearDetection(ghostName)
		end
		if ruleOuts[ghostName] ~= nil then
			return false
		end
		local previous = detections[ghostName]
		local replacement = shallowCopy(detection)
		detections[ghostName] = replacement
		notify({
			Type = "SetDetection",
			Ghost = ghostName,
			Previous = type(previous) == "table"
				and shallowCopy(previous)
				or previous,
			Current = shallowCopy(replacement),
		})
		return true
	end

	function Tracker:Prune(now)
		now = validNumber(now)
		if now == nil then
			now = validNumber(clock())
		end
		assert(now ~= nil, "Clock must return a number")
		local removedCount = 0
		local normalizedCount = 0

		for ghostName, detection in pairs(detections) do
			if type(detection) == "table" then
				local score = detectionScore(detection)
				if score >= 80 or detection.Persistent == true then
					if detection.Persistent ~= true or detection.ExpiresAt ~= nil then
						local previous = shallowCopy(detection)
						detection.Persistent = true
						detection.ExpiresAt = nil
						normalizedCount = normalizedCount + 1
						notify({
							Type = "MarkPersistent",
							Ghost = ghostName,
							Previous = previous,
							Current = shallowCopy(detection),
							Cause = "Prune",
						})
					end
				else
					local expiresAt = validNumber(detection.ExpiresAt)
					if expiresAt == nil then
						local detectedAt = validNumber(detection.DetectedAt or detection.At)
						local ttl = validNumber(detection.TTL)
							or defaultTTL(ghostName)
						if detectedAt and ttl and ttl > 0 then
							expiresAt = detectedAt + ttl
						end
					end
					if expiresAt ~= nil and now > expiresAt then
						detections[ghostName] = nil
						removedCount = removedCount + 1
						notify({
							Type = "PruneDetection",
							Ghost = ghostName,
							Previous = shallowCopy(detection),
							At = now,
						})
					end
				end
			end
		end
		return removedCount > 0 or normalizedCount > 0,
			removedCount,
			normalizedCount
	end

	function Tracker:Reset(options)
		options = type(options) == "table" and options or {}
		if options.PreserveFindings == true then
			return false
		end
		local hadDetections = clearTable(detections)
		local hadRuleOuts = clearTable(ruleOuts)
		local changed = hadDetections or hadRuleOuts
		if changed then
			notify({
				Type = "Reset",
				ClearedDetections = hadDetections,
				ClearedRuleOuts = hadRuleOuts,
			})
		end
		return changed
	end

	tracker = setmetatable({
		Catalog = catalog,
		Detections = detections,
		RuleOuts = ruleOuts,
	}, Tracker)
	return tracker
end
