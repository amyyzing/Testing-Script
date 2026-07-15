local Events = require("../events")
local Specification = require("../specification")
local RuntimeSignals = require("../trackers/active/runtime-signals")({Events = Events})
local SaltPileHit = require("../trackers/dormant/salt-pile-hit")({
	Events = Events,
	Specification = Specification,
})
local HolyOil = require("../trackers/dormant/holy-oil")({
	Events = Events,
	Specification = Specification,
})
local HuntRoom = require("../trackers/dormant/hunt-room")({Events = Events})
local Entity = require("../Entity")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local object = {_listeners = {}}
	function object:Connect(callback)
		local connection = {Connected = true}
		function connection:Disconnect() self.Connected = false end
		table.insert(self._listeners, {Callback = callback, Connection = connection})
		return connection
	end
	function object:Fire(...)
		for _, listener in ipairs(self._listeners) do
			if listener.Connection.Connected then listener.Callback(...) end
		end
	end
	return object
end

local function countType(events, kind)
	local count = 0
	for _, event in ipairs(events) do
		if event.Type == kind then count = count + 1 end
	end
	return count
end

local function lastType(events, kind)
	for index = #events, 1, -1 do
		if events[index].Type == kind then return events[index] end
	end
	return nil
end

-- RuntimeSignals owns one fixed Ghost model and emits each live stream once,
-- including startup reconciliation and unique multiplayer deaths.
do
	local ghostSignals = {Hunting = signal(), Transparency = signal()}
	local speedSignal = signal()
	local humanoid = {
		Name = "Humanoid",
		WalkSpeed = 11,
		IsA = function(_, className) return className == "Humanoid" end,
		GetPropertyChangedSignal = function(_, property)
			return property == "WalkSpeed" and speedSignal or signal()
		end,
	}
	local ghost = {
		Name = "Ghost",
		Attributes = {Hunting = false, Transparency = 0},
		DescendantAdded = signal(),
	}
	function ghost:GetAttribute(name) return self.Attributes[name] end
	function ghost:GetAttributeChangedSignal(name) return ghostSignals[name] end
	function ghost:GetDescendants() return {humanoid} end
	function ghost:FindFirstChildOfClass(className)
		return className == "Humanoid" and humanoid or nil
	end

	local function player(userId)
		local deadSignal = signal()
		local object = {UserId = userId, Attributes = {Dead = false}, DeadSignal = deadSignal}
		function object:GetAttribute(name) return self.Attributes[name] end
		function object:GetAttributeChangedSignal(name)
			return name == "Dead" and self.DeadSignal or signal()
		end
		return object
	end
	local first, second = player(1), player(2)
	local players = {PlayerAdded = signal(), List = {first, second}}
	function players:GetPlayers() return self.List end

	local emitted = {}
	local tracker = RuntimeSignals.new()
	local context = {
		GhostModel = ghost,
		Players = players,
		ReadHunting = function() return ghost.Attributes.Hunting end,
		ReadTransparency = function() return ghost.Attributes.Transparency end,
		ReadWalkSpeed = function() return humanoid.WalkSpeed end,
		ReadAverageSanity = function() return 65 end,
		Emit = function(event) table.insert(emitted, event) end,
	}
	tracker:Start(context)
	expect(countType(emitted, Events.Types.HuntingStateChanged) == 1
		and countType(emitted, Events.Types.TransparencyChanged) == 1
		and countType(emitted, Events.Types.WalkSpeedChanged) == 1,
		"runtime startup must reconcile hunt, binary transparency, and WalkSpeed exactly once")
	ghost.Attributes.Hunting = true
	ghostSignals.Hunting:Fire()
	humanoid.WalkSpeed = 12
	speedSignal:Fire()
	first.Attributes.Dead = true
	first.DeadSignal:Fire()
	first.DeadSignal:Fire()
	expect(countType(emitted, Events.Types.PlayerDeath) == 1,
		"one Dead transition must emit one unique PlayerDeath")
	local death = lastType(emitted, Events.Types.PlayerDeath)
	expect(death.Payload.Qualified == true and death.Payload.OtherAlive == 1,
		"a hunt-time death with another living player must be qualified")
	local beforeStop = #emitted
	tracker:Stop()
	ghost.Attributes.Hunting = false
	ghostSignals.Hunting:Fire()
	expect(#emitted == beforeStop, "RuntimeSignals.Stop must disconnect every live stream")
	tracker:Start(context)
	local afterRestart = countType(emitted, Events.Types.HuntingStateChanged)
	ghost.Attributes.Hunting = true
	ghostSignals.Hunting:Fire()
	expect(countType(emitted, Events.Types.HuntingStateChanged) == afterRestart + 1,
		"RuntimeSignals Start after Stop must reconnect the fixed ghost streams")
end

-- SaltPiles may replicate after coordinator startup. Existing lines in that
-- late folder bind immediately, and new placements require grace + clear/re-touch.
do
	local workspaceChildAdded = signal()
	local workspace = {Name = "Workspace", ChildAdded = workspaceChildAdded}
	local currentFolder = nil
	function workspace:FindFirstChild(name)
		return name == "SaltPiles" and currentFolder or nil
	end
	local cleanSalt = {
		Name = "SaltLine",
		DescendantAdded = signal(),
	}
	function cleanSalt:GetPropertyChangedSignal() return signal() end
	function cleanSalt:GetDescendants() return {} end
	function cleanSalt:IsA() return false end
	function cleanSalt:GetPivot() return nil end
	function cleanSalt:FindFirstChildWhichIsA() return nil end
	setmetatable(cleanSalt, {__index = function(_, key)
		if key == "Position" then error("Position is not a valid member of Model") end
		return nil
	end})
	local folder = {Name = "SaltPiles", ChildAdded = signal()}
	function folder:GetChildren() return {cleanSalt} end

	local emitted = {}
	local overlap = false
	local tracker = SaltPileHit.new()
	tracker:Start({
		Workspace = workspace,
		Clock = function() return 0 end,
		ReadSaltGhostOverlap = function(model)
			return model == cleanSalt and overlap or false
		end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	currentFolder = folder
	workspaceChildAdded:Fire(folder)
	expect(tracker:Snapshot().Status == "Monitoring",
		"a late Workspace.SaltPiles folder must bind its existing lines")
	overlap = true
	tracker:OnEvent({Type = Events.Types.Tick, Time = 0})
	expect(countType(emitted, Events.Types.SaltContact) == 1,
		"an existing armed line in a late folder must use the overlap fallback")
	tracker:Stop()
	tracker:Start({
		Workspace = workspace,
		Clock = function() return 0 end,
		ReadSaltGhostOverlap = function(model)
			return model == cleanSalt and overlap or false
		end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	expect(tracker:Snapshot().Status == "Monitoring",
		"SaltPileHit Start after Stop must safely rebind an existing Model without a Position property")
	tracker:Destroy()
end

do
	local now = 0
	local overlap = true
	local emitted = {}
	local tracker = SaltPileHit.new()
	tracker:Start({
		Clock = function() return now end,
		ReadSaltGhostOverlap = function() return overlap end,
		ReadHunting = function() return true end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	tracker:OnEvent({Type = Events.Types.SaltPilePlaced, SaltId = "new-salt", Time = 0})
	now = Specification.Salt.PlacementGrace
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
	expect(countType(emitted, Events.Types.SaltContact) == 0,
		"a line still under the ghost at the four-second boundary must wait for clear")
	overlap = false
	now = now + 0.1
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
	overlap = true
	now = now + 0.1
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
	expect(countType(emitted, Events.Types.SaltContact) == 1,
		"the first post-grace clear/re-touch must create one direct contact; got "
			.. tostring(countType(emitted, Events.Types.SaltContact))
			.. " snapshot=" .. tostring(tracker:Snapshot().ArmedCount)
			.. "/" .. tostring(tracker:Snapshot().WaitingForClearCount)
			.. "/" .. tostring(tracker:Snapshot().OverlapCount))
	now = now + Specification.Salt.UndisturbedDelay
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
	expect(countType(emitted, Events.Types.SaltContactResult) == 1,
		"an undisturbed direct contact must resolve after 1.25 seconds")
	tracker:OnEvent({
		Type = Events.Types.SaltPileDisturbed,
		SaltId = "new-salt",
		ContactId = "new-salt",
		Time = now + 0.1,
	})
	expect(countType(emitted, Events.Types.SaltDisturbed) == 1,
		"a disturbed replacement must remain globally authoritative after an earlier clean result")
end

-- Holy Oil supports both replicated wall names. A false verifier result arms
-- the candidate without accepting Touched; Tick completes only a verified pass.
do
	local now = 0
	local jobs = {}
	local function schedule(delaySeconds, callback)
		local job = {At = now + delaySeconds, Callback = callback, Cancelled = false}
		table.insert(jobs, job)
		return function() job.Cancelled = true end
	end
	local function runJobs()
		table.sort(jobs, function(left, right) return left.At < right.At end)
		for _, job in ipairs(jobs) do
			now = job.At
			if not job.Cancelled then job.Callback() end
		end
		table.clear(jobs)
	end
	local wall = {
		Name = "ClonedGhostWall",
		CanCollide = false,
		Touched = signal(),
		IsA = function(_, className) return className == "BasePart" end,
		GetPropertyChangedSignal = function() return signal() end,
	}
	local model = {
		Name = "HolyOil",
		Attributes = {Burning = true, ItemName = "Holy Oil"},
		DescendantAdded = signal(),
	}
	function model:IsA(className) return className == "Model" end
	function model:GetAttribute(name) return self.Attributes[name] end
	function model:GetAttributeChangedSignal() return signal() end
	function model:FindFirstChild(name)
		return name == "ClonedGhostWall" and wall or nil
	end
	function model:GetDescendants() return {wall} end
	local exactFire = {
		Name = "Fire",
		Enabled = true,
		IsA = function(_, className) return className == "ParticleEmitter" end,
	}
	local ghost = {GetDescendants = function() return {exactFire} end}
	local passVerified = nil
	local hunting = false
	local emitted = {}
	local tracker = HolyOil.new()
	local folder = {DescendantAdded = signal()}
	function folder:GetDescendants() return {model} end
	function folder:GetChildren() return {model} end
	local context = {
		GhostModel = ghost,
		HolyOilFolder = folder,
		Clock = function() return now end,
		Schedule = schedule,
		ReadHunting = function() return hunting end,
		ReadHolyOilFireColour = function() return "Spirit" end,
		ReadHolyOilPass = function() return passVerified end,
		Emit = function(event) table.insert(emitted, event) end,
	}
	tracker:Start(context)
	local colour = lastType(emitted, Events.Types.HolyOilColor)
	expect(colour and colour.Hunting == false and colour.Payload.Blue == true,
		"Spirit FireColour must classify qualified burning oil outside a hunt")
	expect(countType(emitted, Events.Types.HolyOilCollision) == 0,
		"non-hunt FireColour classification must not arm Wisp collision evidence")
	hunting = true
	tracker:OnEvent({
		Type = Events.Types.HolyOilTouched,
		Model = model,
		Wall = wall,
		Hunting = true,
		Burning = true,
		Time = now,
	})
	expect(countType(emitted, Events.Types.HolyOilPass) == 0,
		"Touched must not bypass an injected side-cross verifier returning nil")
	passVerified = false
	tracker:OnEvent({
		Type = Events.Types.HolyOilTouched,
		Model = model,
		Wall = wall,
		Hunting = true,
		Burning = true,
		Time = now,
	})
	expect(countType(emitted, Events.Types.HolyOilPass) == 0,
		"Touched must not bypass an injected side-cross verifier returning false")
	passVerified = true
	tracker:OnEvent({Type = Events.Types.Tick, Hunting = true, Time = now + 0.1})
	expect(countType(emitted, Events.Types.HolyOilPass) == 1
		and lastType(emitted, Events.Types.HolyOilCollision).Payload.CanCollide == false,
		"Tick must complete a verified ClonedGhostWall pass and preserve collision state")
	runJobs()
	local fire = lastType(emitted, Events.Types.GhostFireEffect)
	expect(fire and fire.Payload.CaughtFire == true,
		"only an enabled ParticleEmitter exactly named Fire must satisfy the delayed fire probe")
	tracker:Stop()
	tracker:Start(context)
	expect(tracker:Snapshot().ModelCount == 1,
		"HolyOil Start after Stop must rebind existing oil models")
	tracker:Destroy()
end

-- HuntRoom retries a temporarily unavailable physical room but emits at most
-- one relation per hunt, and abandons a permanently missing room boundedly.
do
	local now = 0
	local currentRoom = nil
	local emitted = {}
	local tracker = HuntRoom.new({MaxRetryAttempts = 4, MaxRetrySeconds = 2})
	tracker:Start({
		Clock = function() return now end,
		ReadPhysicalCurrentRoom = function() return currentRoom end,
		ReadFavouriteRoom = function() return "Library" end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	tracker:OnEvent({Type = Events.Types.HuntStarted, HuntId = 1, Hunting = true, Time = now})
	expect(#emitted == 0 and tracker:Snapshot().PendingHunt ~= nil,
		"a missing physical room at HuntStarted must remain pending")
	currentRoom = "Library"
	now = 0.25
	tracker:OnEvent({Type = Events.Types.Tick, HuntId = 1, Hunting = true, Time = now})
	expect(#emitted == 1 and emitted[1].Payload.InFavouriteRoom == true,
		"the pending hunt must resolve as soon as both room names replicate")
	tracker:OnEvent({Type = Events.Types.Tick, HuntId = 1, Hunting = true, Time = 0.5})
	expect(#emitted == 1, "one hunt may emit only one HuntRoomRelation")

	tracker:Reset()
	currentRoom = nil
	tracker = HuntRoom.new({MaxRetryAttempts = 2, MaxRetrySeconds = 10})
	tracker:Start({
		Clock = function() return now end,
		ReadPhysicalCurrentRoom = function() return nil end,
		ReadFavouriteRoom = function() return "Library" end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	tracker:OnEvent({Type = Events.Types.HuntStarted, HuntId = 2, Hunting = true, Time = 1})
	tracker:OnEvent({Type = Events.Types.Tick, HuntId = 2, Hunting = true, Time = 1.25})
	expect(tracker:Snapshot().PendingHunt == nil,
		"room retry must stop at its configured attempt bound")

	local beforePhysicalResolution = #emitted
	local physicalRoom = nil
	tracker = HuntRoom.new({MaxRetryAttempts = 4, MaxRetrySeconds = 2})
	tracker:Start({
		Clock = function() return now end,
		ReadPhysicalCurrentRoom = function() return physicalRoom end,
		ReadCurrentRoom = function() return "Library" end,
		ReadFavouriteRoom = function() return "Library" end,
		GhostModel = {
			GetAttribute = function(_, name)
				return name == "CurrentRoom" and "Library" or nil
			end,
		},
		Emit = function(event) table.insert(emitted, event) end,
	})
	tracker:OnEvent({
		Type = Events.Types.HuntStarted,
		HuntId = 3,
		Hunting = true,
		Time = 2,
		CurrentRoom = "Library",
	})
	expect(#emitted == beforePhysicalResolution and tracker:Snapshot().PendingHunt ~= nil,
		"a nil physical resolver must not accept stale event, callback, or Ghost.CurrentRoom fallbacks")
	physicalRoom = "Gym"
	tracker:OnEvent({Type = Events.Types.Tick, HuntId = 3, Hunting = true, Time = 2.25})
	expect(#emitted == beforePhysicalResolution + 1
		and emitted[#emitted].Payload.CurrentRoom == "Gym"
		and emitted[#emitted].Payload.InFavouriteRoom == false,
		"hunt-room relation must wait for and use the authoritative physical room")
end

-- Entity dedupes a teleport episode, not the reused object instance.
do
	local positives = {}
	local api = {
		Record = function() end,
		Positive = function(_, ghost, reason, confidence, event)
			table.insert(positives, {Ghost = ghost, EventId = event.EventId, Confidence = confidence})
		end,
		Negative = function() end,
	}
	local observer = Entity.CreateObserver(api)
	local reusedObject = {}
	local function episode(eventId, time)
		observer:OnEvent({
			Type = Events.Types.ObjectTeleportResult,
			EventId = eventId,
			TeleportId = reusedObject,
			Time = time,
			ConfirmedTeleport = true,
			Completed = true,
			Qualified = true,
			SmokeFound = true,
		})
	end
	episode("episode-1", 1)
	episode("episode-1", 1)
	episode("episode-2", 2)
	expect(#positives == 2,
		"two episodes involving the same object must score independently while duplicate EventId is ignored")
	observer:OnEvent({
		Type = Events.Types.ObjectTeleportResult,
		EventId = "unqualified",
		ConfirmedTeleport = true,
		Completed = true,
		SmokeFound = true,
	})
	expect(#positives == 2,
		"an unqualified injected teleport result must not score Entity")
end

print("core-runtime-collectors.spec: active streams and dormant collector lifecycles passed")
