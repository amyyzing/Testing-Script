return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "speed-tracker requires Traffic")
	local Ghost = assert(dependencies.Ghost, "speed-tracker requires Ghost")
	local Model = dependencies.GhostModel or Ghost:FindFirstChild("GhostModel", true) or Ghost
	local clock = dependencies.Clock or os.clock
	local killMatchWindow = tonumber(dependencies.KillMatchWindow) or 0.75
	local Tracker = {Kind = "active", Running = true, hunting = nil, samples = {}, sampleMeta = {}}

	local function sample(source)
		local humanoid = Ghost:FindFirstChildOfClass("Humanoid")
		local speed = humanoid and tonumber(humanoid.WalkSpeed)
		if not speed then return end
		local point = {s = speed, v = Model:GetAttribute("Transparency") == 0}
		table.insert(Tracker.samples, point)
		table.insert(Tracker.sampleMeta, {source = source, time = clock()})
		if Tracker.afterSalt then table.insert(Tracker.afterSalt, point) end
		if Tracker.afterKill then table.insert(Tracker.afterKill, point) end
		if Tracker.hunting then
			Traffic("HuntSpeedSample", {
				Index = #Tracker.samples,
				Point = {s = point.s, v = point.v},
			}):SendTo("SpeedArrayLog")
		end
		return point
	end

	local function sendSalt(completed)
		if not Tracker.beforeSalt or not Tracker.saltState then return end
		Traffic("SaltSpeed", {
			saltState = Tracker.saltState,
			beforeSalt = Tracker.beforeSalt,
			afterSalt = Tracker.afterSalt,
			completed = completed == true,
		}):SendTo("Aswang")
	end

	local function sendKill(completed)
		if not Tracker.beforeKill then return end
		Traffic("KillSpeed", {
			userId = Tracker.killUserId,
			baselineKill = Tracker.killBaseline,
			beforeKill = Tracker.beforeKill,
			afterKill = Tracker.afterKill,
			completed = completed == true,
		}):SendTo("Aswang")
	end

	local function hunting(value)
		if Tracker.hunting == value then return end
		if Tracker.hunting then
			if Tracker.beforeSalt and not Tracker.saltState then
				Tracker.pendingSalt = {
					contact = Tracker.contact,
					beforeSalt = Tracker.beforeSalt,
					afterSalt = Tracker.afterSalt,
				}
			else
				sendSalt(true)
			end
			sendKill(true)
			Traffic("HuntSpeedEnded", {Count = #Tracker.samples}):SendTo("SpeedArrayLog")
		end
		Tracker.hunting, Tracker.samples, Tracker.sampleMeta = value, {}, {}
		Tracker.beforeSalt, Tracker.afterSalt, Tracker.contact, Tracker.saltState = nil, nil, nil, nil
		Tracker.beforeKill, Tracker.afterKill = nil, nil
		Tracker.killUserId, Tracker.killBaseline = nil, nil
		if value then Traffic("HuntSpeedReset", {}):SendTo("SpeedArrayLog") end
		sample("state") -- once while non-hunting; hunt samples continue on visibility changes
	end

	Tracker.Disconnect = Traffic:Receive("SpeedTracker", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "HuntingState" then
			hunting(payload.Hunting == true)
		elseif signal == "SaltHit" and Tracker.hunting then
			local transition = sample("salt")
			if not transition then return end
			Tracker.contact = payload.ContactId
			Tracker.beforeSalt = table.clone(Tracker.samples)
			Tracker.afterSalt = {transition}
			Traffic("HuntSpeedMarker", {
				Index = #Tracker.samples,
				Label = "SALT SPLIT",
			}):SendTo("SpeedArrayLog")
		elseif signal == "SaltStateAfterHit" then
			if payload.ContactId == Tracker.contact then
				Tracker.saltState = payload.State
				sendSalt(false)
			elseif Tracker.pendingSalt and payload.ContactId == Tracker.pendingSalt.contact then
				Traffic("SaltSpeed", {
					saltState = payload.State,
					beforeSalt = Tracker.pendingSalt.beforeSalt,
					afterSalt = Tracker.pendingSalt.afterSalt,
					completed = true,
				}):SendTo("Aswang")
				Tracker.pendingSalt = nil
			end
		elseif signal == "PlayerKilled" and Tracker.hunting then
			local transition = sample("kill")
			if not transition then return end
			sendKill(true)
			Tracker.killUserId = payload.userId
			local splitIndex = #Tracker.samples
			local killTime = tonumber(payload.Time) or clock()
			for index = #Tracker.sampleMeta - 1, 1, -1 do
				local meta = Tracker.sampleMeta[index]
				local age = killTime - meta.time
				if age > killMatchWindow then break end
				if age >= 0 and meta.source == "speed" then
					splitIndex = index
					break
				end
			end
			local splitPoint = Tracker.samples[splitIndex]
			Tracker.killBaseline = splitPoint
			for index = splitIndex - 1, 1, -1 do
				local point = Tracker.samples[index]
				if point.v == splitPoint.v then
					Tracker.killBaseline = point
					break
				end
			end
			Tracker.beforeKill, Tracker.afterKill = {}, {}
			for index = 1, splitIndex do table.insert(Tracker.beforeKill, Tracker.samples[index]) end
			for index = splitIndex, #Tracker.samples do table.insert(Tracker.afterKill, Tracker.samples[index]) end
			Traffic("HuntSpeedMarker", {
				Index = splitIndex,
				Label = "KILL",
			}):SendTo("SpeedArrayLog")
		end
	end)

	Tracker.VisibilityConnection = Model:GetAttributeChangedSignal("Transparency"):Connect(function()
		if Tracker.hunting then
			sample("visibility")
			sendSalt(false)
			sendKill(false)
		end
	end)
	local humanoid = Ghost:FindFirstChildOfClass("Humanoid")
	if humanoid then
		Tracker.SpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if Tracker.hunting then
				sample("speed")
				sendSalt(false)
				sendKill(false)
			end
		end)
	end
	hunting(Ghost:GetAttribute("Hunting") == true)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		self.VisibilityConnection:Disconnect()
		if self.SpeedConnection then self.SpeedConnection:Disconnect() end
	end

	return Tracker
end
