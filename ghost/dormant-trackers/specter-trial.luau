return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "specter-trial requires Traffic")
	local Ghost = assert(dependencies.Ghost, "specter-trial requires Ghost")
	local RunService = assert(dependencies.RunService, "specter-trial requires RunService")
	local clock = dependencies.Clock or os.clock
	local readPosition = dependencies.Position
	local readCurrentRoom = dependencies.ReadCurrentRoom
	local sampleInterval = tonumber(dependencies.SampleInterval) or 0.1
	local analysisInterval = tonumber(dependencies.AnalysisInterval) or 0.2
	local settledWindow = tonumber(dependencies.SettledWindow) or 0.8
	local stationaryThreshold = tonumber(dependencies.StationaryThreshold) or 0.22
	local armSeconds = tonumber(dependencies.ArmSeconds) or 5
	local roomSettleSeconds = tonumber(dependencies.RoomChangeSettleSeconds) or 2
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Hunting = Ghost:GetAttribute("Hunting") == true,
		Motion = {},
		Sequence = 0,
		Accumulator = 0,
	}

	local function token(value)
		if value and value.Name then value = value.Name end
		return string.lower(tostring(value or ""):gsub("[^%w]", ""))
	end

	local function sameRoom(first, second)
		local left, right = token(first), token(second)
		return left ~= "" and left == right
	end

	local function position()
		if readPosition then return readPosition(Ghost) end
		if Ghost:IsA("BasePart") then return Ghost.Position end
		return Ghost:GetPivot().Position
	end

	local function distance(first, second)
		local x, y, z = first.X - second.X, first.Y - second.Y, first.Z - second.Z
		return math.sqrt(x * x + y * y + z * z)
	end

	local function currentRoom(refresh)
		if readCurrentRoom then return readCurrentRoom(refresh == true) end
		return Ghost:GetAttribute("CurrentRoom")
	end

	local function favouriteRoom()
		return Ghost:GetAttribute("FavoriteRoom")
			or Ghost:GetAttribute("FavouriteRoom")
	end

	local function clearTrial()
		Tracker.CandidateAt = nil
		Tracker.Armed = false
		Tracker.ActiveTrialId = nil
	end

	local function resetMotion(now)
		table.clear(Tracker.Motion)
		Tracker.LastPosition = position()
		Tracker.LastPositionAt = now
		Tracker.MovementSpeed = 0
	end

	local function measure(now)
		local current = position()
		if Tracker.LastPosition and Tracker.LastPositionAt then
			local elapsed = now - Tracker.LastPositionAt
			if elapsed > 0 then
				Tracker.MovementSpeed = distance(current, Tracker.LastPosition) / elapsed
			end
		end
		Tracker.LastPosition, Tracker.LastPositionAt = current, now
		return Tracker.MovementSpeed or 0
	end

	local function settledSpeed(now, fallback)
		local values = {}
		for _, sample in ipairs(Tracker.Motion) do
			if sample.Time >= now - settledWindow then table.insert(values, sample.Speed) end
		end
		if #values == 0 then return fallback end
		table.sort(values)
		local middle = math.floor((#values + 1) / 2)
		if #values % 2 == 1 then return values[middle] end
		return (values[middle] + values[middle + 1]) * 0.5
	end

	local function emit(outcome, now)
		local trialId = Tracker.ActiveTrialId
		if not trialId then
			Tracker.Sequence += 1
			trialId = "specter-trial:" .. Tracker.Sequence
		end
		Traffic("SpecterTrial", {
			TrialId = trialId,
			Outcome = outcome,
			Qualified = true,
			Completed = true,
			FavouriteRoomUnchanged = true,
			ArmedSeconds = math.max(armSeconds, now - (Tracker.CandidateAt or now)),
			Time = now,
		}):SendTo("Specter")
		if outcome == "Departure" then Tracker.Resolved = true end
	end

	local function analyze(now, measuredSpeed)
		if Tracker.Hunting or Tracker.Resolved then return end
		local favourite = favouriteRoom()
		if token(favourite) == "" then clearTrial() return end
		local room = currentRoom(false)
		local inFavourite = sameRoom(room, favourite)
		local stationary = settledSpeed(now, measuredSpeed) <= stationaryThreshold

		if not Tracker.TrackedFavourite then
			Tracker.TrackedFavourite = favourite
		elseif not sameRoom(Tracker.TrackedFavourite, favourite) then
			Tracker.TrackedFavourite = favourite
			Tracker.RoomChangePause = true
			Tracker.RoomChangeSettledAt = nil
			clearTrial()
		end

		if Tracker.RoomChangePause then
			if inFavourite and stationary then
				Tracker.RoomChangeSettledAt = Tracker.RoomChangeSettledAt or now
				if now - Tracker.RoomChangeSettledAt + 1e-6 >= roomSettleSeconds then
					Tracker.RoomChangePause = false
					Tracker.RoomChangeSettledAt = nil
					Tracker.CandidateAt = now
				end
			else
				Tracker.RoomChangeSettledAt = nil
			end
			return
		end

		if not inFavourite or not stationary then
			if Tracker.Armed then emit("Departure", now) end
			clearTrial()
			return
		end
		Tracker.CandidateAt = Tracker.CandidateAt or now
		if not Tracker.Armed and now - Tracker.CandidateAt + 1e-6 >= armSeconds then
			Tracker.Sequence += 1
			Tracker.ActiveTrialId = "specter-trial:" .. Tracker.Sequence
			Tracker.Armed = true
		end
	end

	local function setHunting(hunting, now)
		if hunting == Tracker.Hunting then return end
		local speed = measure(now)
		if hunting then
			if Tracker.Armed and not Tracker.RoomChangePause then
				local favourite = favouriteRoom()
				if sameRoom(Tracker.TrackedFavourite, favourite) then
					local residence = sameRoom(currentRoom(true), favourite)
						and speed <= stationaryThreshold
					emit(residence and "Residence" or "Departure", now)
				end
			end
			clearTrial()
			Tracker.RoomChangePause = false
			Tracker.RoomChangeSettledAt = nil
		elseif not hunting then
			resetMotion(now)
		end
		Tracker.Hunting = hunting
	end

	resetMotion(clock())
	Tracker.Disconnect = Traffic:Receive("SpecterTrial", function(signal, payload)
		if signal == "HuntingState" and type(payload) == "table" then
			setHunting(payload.Hunting == true, tonumber(payload.Time) or clock())
		end
	end)
	Tracker.Connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not Tracker.Running or Tracker.Resolved then return end
		Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
		if Tracker.Accumulator < sampleInterval then return end
		Tracker.Accumulator %= sampleInterval
		local now = clock()
		local speed = measure(now)
		if Tracker.Hunting then return end
		table.insert(Tracker.Motion, {Time = now, Speed = speed})
		while Tracker.Motion[1] and Tracker.Motion[1].Time < now - 12 do
			table.remove(Tracker.Motion, 1)
		end
		if not Tracker.LastAnalysisAt
			or now - Tracker.LastAnalysisAt + 1e-6 >= analysisInterval then
			Tracker.LastAnalysisAt = now
			analyze(now, speed)
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		self.Connection:Disconnect()
		table.clear(self.Motion)
	end

	return Tracker
end
