local SOURCE = "https://demonology.fandom.com/wiki/Ravager"

-- The caller reports only raw world positions. All vortex interpretation lives
-- here so Ravager's thresholds and temporal state cannot leak into GUI logic.
local SAMPLE_INTERVAL = 0.05
local MIN_SAMPLE_ELAPSED = 0.03
local MAX_SAMPLE_ELAPSED = 0.12
local MIN_RADIUS = 2.5
local MAX_RADIUS = 40
local MAX_RELATIVE_STEP = 12
local MIN_WORLD_SPEED = 4
local MIN_RELATIVE_SPEED = 6
local MIN_ANGULAR_SPEED = 70
local MIN_TANGENTIAL_SHARE = 0.55
local MAX_ABSOLUTE_RADIUS_CHANGE = 2
local MAX_RELATIVE_RADIUS_CHANGE = 0.35
local CANDIDATE_WINDOW = 0.8
local MAX_CONSECUTIVE_BAD_INTERVALS = 2
local MIN_ORBIT_DURATION = 0.5
local MIN_INTERVAL_COUNT = 7
local MIN_GOOD_INTERVAL_SHARE = 0.7
local MIN_ACCUMULATED_ANGLE = 45
local MIN_DIRECTION_CONSISTENCY = 0.65
local MIN_DISTINCT_ITEMS = 3
local GHOST_TELEPORT_DISTANCE = 8

local function readPosition(position)
	if position == nil then
		return nil
	end
	local ok, x, y, z = pcall(function()
		return tonumber(position.X), tonumber(position.Y), tonumber(position.Z)
	end)
	if not ok or x == nil or y == nil or z == nil then
		return nil
	end
	return {X = x, Y = y, Z = z}
end

local function distance(left, right)
	local x = left.X - right.X
	local y = left.Y - right.Y
	local z = left.Z - right.Z
	return math.sqrt(x * x + y * y + z * z)
end

local function resetCandidate(tracked)
	tracked.Window = {}
	tracked.CandidateStartedAt = nil
	tracked.ConsecutiveBad = 0
end

return {
	Name = "Ravager",
	Evidence = {"EMFLevel5", "GhostWriting", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-recent-stub",
	Confidence = 95,
	TTL = 6,
	ObservationKeys = {"ObjectMotionFrame"},
	CreateObserver = function(api)
		local observer = {}
		local trackedObjects = {}
		local currentGhostId
		local lastProcessedAt
		local previousGhostPosition
		local previousGhostSampleAt
		local detectedThisHunt = false

		local function resetMotion(nextGhostId)
			trackedObjects = {}
			currentGhostId = nextGhostId
			lastProcessedAt = nil
			previousGhostPosition = nil
			previousGhostSampleAt = nil
			detectedThisHunt = false
		end

		local function qualifyObject(tracked, objectId, assemblyId, now)
			if tracked.CandidateStartedAt == nil or #tracked.Window == 0 then
				return nil
			end
			tracked.CandidateStartedAt = tracked.Window[1].StartAt
			local goodIntervals = 0
			local signedTotal = 0
			local absoluteTotal = 0
			local fastest = 0
			for _, interval in ipairs(tracked.Window) do
				if interval.Good then
					goodIntervals = goodIntervals + 1
					signedTotal = signedTotal + interval.SignedAngle
					absoluteTotal = absoluteTotal + interval.AbsAngle
					fastest = math.max(fastest, interval.Speed)
				end
			end

			local duration = now - tracked.CandidateStartedAt
			local intervalCount = #tracked.Window
			if duration < MIN_ORBIT_DURATION
				or intervalCount < MIN_INTERVAL_COUNT
				or goodIntervals / intervalCount < MIN_GOOD_INTERVAL_SHARE
				or absoluteTotal < MIN_ACCUMULATED_ANGLE
				or math.abs(signedTotal) / math.max(absoluteTotal, 0.001)
					< MIN_DIRECTION_CONSISTENCY then
				return nil
			end

			return {
				ObjectId = objectId,
				AssemblyId = assemblyId,
				Direction = signedTotal >= 0 and 1 or -1,
				Duration = duration,
				Speed = fastest,
			}
		end

		function observer:Reset(options)
			resetMotion(options and options.Ghost or nil)
		end

		function observer:OnObjectMotionFrame(event)
			event = event or {}
			local ghostId = event.GhostId
			if ghostId ~= currentGhostId then
				resetMotion(ghostId)
			end

			local now = tonumber(event.Time)
			local ghostPosition = readPosition(event.GhostPosition)
			if event.Hunting ~= true
				or event.Suppressed == true
				or now == nil
				or ghostId == nil
				or ghostPosition == nil then
				resetMotion(ghostId)
				return
			end
			if detectedThisHunt then
				return
			end
			if lastProcessedAt ~= nil
				and now - lastProcessedAt < SAMPLE_INTERVAL - 0.000001 then
				return
			end
			if lastProcessedAt ~= nil and now <= lastProcessedAt then
				resetMotion(ghostId)
			end
			lastProcessedAt = now

			local previousGhost = previousGhostPosition
			local previousGhostTime = previousGhostSampleAt
			previousGhostPosition = ghostPosition
			previousGhostSampleAt = now
			if previousGhost ~= nil
				and previousGhostTime ~= nil
				and now - previousGhostTime <= MAX_SAMPLE_ELAPSED
				and distance(ghostPosition, previousGhost) > GHOST_TELEPORT_DISTANCE then
				trackedObjects = {}
				return
			end

			local seenObjects = {}
			local qualified = {}
			for _, sample in ipairs(type(event.Objects) == "table" and event.Objects or {}) do
				local objectId = sample.ObjectId or sample.Id
				local position = readPosition(sample.Position)
				if objectId ~= nil and position ~= nil then
					seenObjects[objectId] = true
					local assemblyId = sample.AssemblyId or sample.Assembly or objectId
					local relative = {
						X = position.X - ghostPosition.X,
						Y = position.Y - ghostPosition.Y,
						Z = position.Z - ghostPosition.Z,
					}
					local tracked = trackedObjects[objectId]
					if tracked == nil then
						tracked = {}
						resetCandidate(tracked)
						trackedObjects[objectId] = tracked
					end

					local previousPosition = tracked.Position
					local previousRelative = tracked.Relative
					local previousTime = tracked.Time
					tracked.Position = position
					tracked.Relative = relative
					tracked.Time = now
					tracked.AssemblyId = assemblyId

					if previousPosition ~= nil
						and previousRelative ~= nil
						and previousTime ~= nil then
						local elapsed = now - previousTime
						local oldX, oldZ = previousRelative.X, previousRelative.Z
						local newX, newZ = relative.X, relative.Z
						local oldRadius = math.sqrt(oldX * oldX + oldZ * oldZ)
						local newRadius = math.sqrt(newX * newX + newZ * newZ)
						local relativeStepX = newX - oldX
						local relativeStepZ = newZ - oldZ
						local relativeStep = math.sqrt(
							relativeStepX * relativeStepX
								+ relativeStepZ * relativeStepZ
						)
						local geometryValid = elapsed >= MIN_SAMPLE_ELAPSED
							and elapsed <= MAX_SAMPLE_ELAPSED
							and oldRadius >= MIN_RADIUS
							and oldRadius <= MAX_RADIUS
							and newRadius >= MIN_RADIUS
							and newRadius <= MAX_RADIUS
							and relativeStep <= MAX_RELATIVE_STEP

						local orbitLike = false
						local signedAngle = 0
						local relativeSpeed = 0
						if geometryValid then
							local dot = oldX * newX + oldZ * newZ
							local cross = oldX * newZ - oldZ * newX
							signedAngle = math.deg(math.atan2(cross, dot))
							local velocityX = relativeStepX / elapsed
							local velocityZ = relativeStepZ / elapsed
							relativeSpeed = math.sqrt(
								velocityX * velocityX + velocityZ * velocityZ
							)
							local worldSpeed = distance(position, previousPosition) / elapsed
							local radialUnitX = newX / newRadius
							local radialUnitZ = newZ / newRadius
							local radialSpeed = math.abs(
								velocityX * radialUnitX + velocityZ * radialUnitZ
							)
							local tangentialSpeed = math.sqrt(math.max(
								relativeSpeed * relativeSpeed - radialSpeed * radialSpeed,
								0
							))
							local tangentialShare = tangentialSpeed
								/ math.max(relativeSpeed, 0.001)
							local radiusChange = math.abs(newRadius - oldRadius)
							local meanRadius = (oldRadius + newRadius) * 0.5
							orbitLike = worldSpeed >= MIN_WORLD_SPEED
								and relativeSpeed >= MIN_RELATIVE_SPEED
								and math.abs(signedAngle) / elapsed >= MIN_ANGULAR_SPEED
								and tangentialShare >= MIN_TANGENTIAL_SHARE
								and radiusChange <= math.max(
									MAX_ABSOLUTE_RADIUS_CHANGE,
									meanRadius * MAX_RELATIVE_RADIUS_CHANGE
								)
						end

						if not geometryValid then
							resetCandidate(tracked)
						elseif orbitLike or tracked.CandidateStartedAt ~= nil then
							if orbitLike and tracked.CandidateStartedAt == nil then
								tracked.CandidateStartedAt = previousTime
							end
							table.insert(tracked.Window, {
								StartAt = previousTime,
								Time = now,
								Good = orbitLike,
								SignedAngle = orbitLike and signedAngle or 0,
								AbsAngle = orbitLike and math.abs(signedAngle) or 0,
								Speed = orbitLike and relativeSpeed or 0,
							})
							tracked.ConsecutiveBad = orbitLike
								and 0
								or tracked.ConsecutiveBad + 1
							for index = #tracked.Window, 1, -1 do
								if now - tracked.Window[index].Time > CANDIDATE_WINDOW then
									table.remove(tracked.Window, index)
								end
							end
							if tracked.ConsecutiveBad > MAX_CONSECUTIVE_BAD_INTERVALS
								or #tracked.Window == 0 then
								resetCandidate(tracked)
							else
								local candidate = qualifyObject(
									tracked,
									objectId,
									assemblyId,
									now
								)
								if candidate ~= nil then
									table.insert(qualified, candidate)
								end
							end
						end
					end
				end
			end

			for objectId in pairs(trackedObjects) do
				if seenObjects[objectId] ~= true then
					trackedObjects[objectId] = nil
				end
			end

			local buckets = {[1] = {}, [-1] = {}}
			local assemblies = {[1] = {}, [-1] = {}}
			for _, candidate in ipairs(qualified) do
				local direction = candidate.Direction
				if assemblies[direction][candidate.AssemblyId] ~= true then
					assemblies[direction][candidate.AssemblyId] = true
					table.insert(buckets[direction], candidate)
				end
			end
			for _, direction in ipairs({1, -1}) do
				local matching = buckets[direction]
				if #matching >= MIN_DISTINCT_ITEMS then
					local minimumDuration = math.huge
					local fastest = 0
					for _, candidate in ipairs(matching) do
						minimumDuration = math.min(minimumDuration, candidate.Duration)
						fastest = math.max(fastest, candidate.Speed)
					end
					detectedThisHunt = true
					api:ClearRuleOut("Ravager")
					api:Detect(
						"Ravager",
						tostring(#matching)
							.. " distinct items rapidly orbited the moving ghost for at least "
							.. string.format("%.2f", minimumDuration)
							.. " seconds (peak relative speed "
							.. string.format("%.1f", fastest)
							.. ")",
						99
					)
					api:Refresh()
					return
				end
			end
		end

		function observer:Snapshot()
			local count = 0
			for _ in pairs(trackedObjects) do
				count = count + 1
			end
			return {
				GhostId = currentGhostId,
				DetectedThisHunt = detectedThisHunt,
				TrackedObjectCount = count,
			}
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A vortex pulls nearby objects into a tornado during a hunt.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = false,
				Kind = "Trait",
				Conditions = "The guide reports roughly a one-in-three activation chance.",
			},
			{
				Text = "A ghost event produces EMF Level 5 even in a zero-evidence custom run.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = false,
				Kind = "Weakness",
			},
		},
		["Maybe"] = {
			{
				Text = "Multiple objects are thrown simultaneously or cause a chain reaction.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "Frequent single-object throws overlap with Specter and ordinary activity.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
