local Events = require("../events")
local CrossMotion = require("../trackers/dormant/cross-motion")({Events = Events})

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

local function crossModel(name)
	local changed = signal()
	local part = {
		Name = "Cross",
		Parent = true,
		Transform = {Position = {X = 0, Y = 0, Z = 0}, Angle = 0},
	}
	function part:IsA(className) return className == "BasePart" end
	local emitter = {
		Name = "Fire",
		Parent = part,
		Enabled = false,
	}
	function emitter:IsA(className) return className == "ParticleEmitter" end
	function emitter:IsDescendantOf(candidate) return candidate == part end
	function emitter:GetPropertyChangedSignal(property)
		return property == "Enabled" and changed or signal()
	end
	local model = {
		Name = name,
		Parent = true,
		DescendantAdded = signal(),
		Part = part,
		Emitter = emitter,
	}
	function model:IsA(className) return className == "Model" end
	function model:GetAttribute(attribute)
		return attribute == "ItemName" and "Cross" or nil
	end
	function model:FindFirstChild(childName)
		return childName == "Cross" and part or nil
	end
	function model:GetDescendants() return {part, emitter} end
	function model:Activate()
		emitter.Enabled = true
		changed:Fire()
	end
	return model
end

local function harness(models)
	local now = 0
	local emitted = {}
	local items = {Name = "Items", ChildAdded = signal(), Children = models}
	function items:GetChildren() return self.Children end
	local workspace = {Name = "Workspace", ChildAdded = signal()}
	function workspace:FindFirstChild(name)
		return name == "Items" and items or nil
	end
	local tracker = CrossMotion.new()
	local context = {
		Workspace = workspace,
		Clock = function() return now end,
		ReadCrossTransform = function(_, part) return part.Transform end,
		ReadCrossRotationDelta = function(previous, current)
			return math.abs(current.Angle - previous.Angle)
		end,
		Emit = function(event) table.insert(emitted, event) end,
	}
	tracker:Start(context)
	return {
		Tracker = tracker,
		Context = context,
		Items = items,
		Events = emitted,
		SetTime = function(value) now = value end,
		Tick = function(value)
			now = value
			tracker:OnEvent({Type = Events.Types.Tick, Time = value})
		end,
	}
end

-- Stop followed by Start reconnects the folder/model/particle streams.
do
	local test = harness({})
	test.Tracker:Stop()
	test.Tracker:Start(test.Context)
	local added = crossModel("RestartCross")
	table.insert(test.Items.Children, added)
	test.Items.ChildAdded:Fire(added)
	added:Activate()
	expect(test.Tracker:Snapshot().ActiveTrials == 1,
		"CrossMotion Start-after-Stop must bind Crosses added after restart")
	test.Tracker:Destroy()
end

-- The collector starts only on a disabled->enabled particle transition and
-- retains the exact rise/rotation/horizontal bounds from the monolith.
do
	local model = crossModel("MovingCross")
	local test = harness({model})
	expect(test.Tracker:Snapshot().ActiveTrials == 0,
		"an existing disabled Cross must remain dormant")
	model:Activate()
	expect(test.Tracker:Snapshot().ActiveTrials == 1,
		"the activation edge must create exactly one motion trial")
	model.Part.Transform = {
		Position = {X = 0.2, Y = 0.5, Z = 0.1},
		Angle = math.rad(50),
	}
	test.Tick(0.1)
	expect(#test.Events == 1
		and test.Events[1].Type == Events.Types.CrossMotion
		and test.Events[1].Payload.Eligible == true
		and test.Events[1].Payload.Completed == true
		and test.Events[1].Payload.FloatedAndRotated == true,
		"0.45-stud rise plus 45-degree accumulated rotation must qualify Demon")
	expect(test.Tracker:Snapshot().MotionObserved == true,
		"a matched Cross must latch round-level Demon motion")
	test.Tracker:Destroy()
end

-- Four seconds without the qualified combined motion completes one negative.
do
	local model = crossModel("StillCross")
	local test = harness({model})
	model:Activate()
	test.Tick(3.9)
	expect(#test.Events == 0, "a Cross trial must not reject before four seconds")
	test.Tick(4)
	expect(#test.Events == 1
		and test.Events[1].Payload.FloatedAndRotated == false,
		"an eligible activated Cross without combined motion must reject at four seconds")
	test.Tracker:Destroy()
end

-- Preserve the old global positive latch: after one Cross proves the motion,
-- later spent Crosses cannot create a contradictory Demon rule-out.
do
	local moving = crossModel("MovingCross")
	local later = crossModel("LaterCross")
	local test = harness({moving, later})
	moving:Activate()
	moving.Part.Transform = {
		Position = {X = 0, Y = 0.5, Z = 0},
		Angle = math.rad(50),
	}
	test.Tick(0.1)
	later:Activate()
	test.Tick(4.2)
	expect(#test.Events == 1,
		"a round-level positive must suppress later contradictory Cross negatives")
	local beforeDestroy = #test.Events
	test.Tracker:Destroy()
	later.Emitter.Enabled = false
	later:Activate()
	expect(#test.Events == beforeDestroy,
		"Destroy must disconnect activation listeners")
end

print("core-cross-motion.spec: Demon Cross activation and motion lifecycle passed")
