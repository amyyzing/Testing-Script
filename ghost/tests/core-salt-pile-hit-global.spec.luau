local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({
	Events = Events,
	EvidenceLedger = Ledger,
	Resolver = Resolver,
})
local SaltPileHit = require("../trackers/dormant/salt-pile-hit")({Events = Events})
local Wraith = require("../Wraith")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local handlers = {}
	local result = {}
	function result:Connect(callback)
		local connection = {Connected = true}
		function connection:Disconnect()
			self.Connected = false
		end
		table.insert(handlers, {Callback = callback, Connection = connection})
		return connection
	end
	function result:Fire(value)
		for _, item in ipairs(handlers) do
			if item.Connection.Connected then item.Callback(value) end
		end
	end
	return result
end

local function model(name)
	local nameChanged = signal()
	local result = {
		Name = name,
		ClassName = "Model",
	}
	function result:IsA(className) return className == "Model" end
	function result:GetPropertyChangedSignal(property)
		expect(property == "Name", "salt tracker should only observe model names")
		return nameChanged
	end
	function result:Rename(newName)
		self.Name = newName
		nameChanged:Fire()
	end
	return result
end

local function saltFolder(descendants)
	local result = {
		Name = "SaltPiles",
		ChildAdded = signal(),
		DescendantAdded = signal(),
		_descendants = descendants or {},
	}
	function result:GetChildren() return self._descendants end
	function result:GetDescendants() return self._descendants end
	function result:Add(instance)
		table.insert(self._descendants, instance)
		instance.Parent = self
		self.ChildAdded:Fire(instance)
		self.DescendantAdded:Fire(instance)
	end
	return result
end

local function world(folder)
	local result = {
		ChildAdded = signal(),
		_folder = folder,
	}
	function result:FindFirstChild(name)
		if name == "SaltPiles" then return self._folder end
		return nil
	end
	function result:AddFolder(nextFolder)
		self._folder = nextFolder
		self.ChildAdded:Fire(nextFolder)
	end
	return result
end

do
	local disturbed = model("DisturbedSaltLine")
	local tracker = SaltPileHit.new()
	local coordinator = Coordinator.new({
		Definitions = {Wraith},
		Trackers = {tracker},
	})
	coordinator:Start({Workspace = world(saltFolder({disturbed}))})
	local resolved = coordinator:Resolve({"Wraith"}).Wraith
	expect(resolved.RuledOut == true, "an existing DisturbedSaltLine must immediately rule out Wraith")
	expect(tracker.Category == "Dormant", "salt disturbance must be a dormant tracker")
	expect(tracker:Snapshot().LastResult == "Disturbed", "the canonical salt tracker must retain the authoritative disturbance result")
	coordinator:Destroy()
end

do
	local nestedContainer = {Name = "Nested", Parent = nil}
	local disturbedPile = model("DisturbedSaltPile")
	local folder = saltFolder({nestedContainer, disturbedPile})
	nestedContainer.Parent = folder
	disturbedPile.Parent = nestedContainer
	local tracker = SaltPileHit.new()
	local coordinator = Coordinator.new({
		Definitions = {Wraith},
		Trackers = {tracker},
	})
	coordinator:Start({Workspace = world(folder)})
	expect(coordinator:Resolve({"Wraith"}).Wraith.RuledOut == true,
		"an existing nested DisturbedSaltPile must immediately rule out Wraith")
	expect(tracker:Snapshot().LastResult == "Disturbed",
		"nested disturbed salt must become the canonical tracker result")
	coordinator:Destroy()
end

do
	local tracker = SaltPileHit.new()
	local emitted = {}
	local emptyWorld = world(nil)
	tracker:Start({
		Workspace = emptyWorld,
		Emit = function(event) table.insert(emitted, event) end,
	})
	local folder = saltFolder()
	emptyWorld:AddFolder(folder)
	local salt = model("SaltLine")
	folder:Add(salt)
	expect(#emitted == 0, "an undisturbed salt line must not resolve Wraith")
	salt:Rename("DisturbedSaltLine")
	expect(#emitted == 1, "a later DisturbedSaltLine rename must emit exactly once")
	expect(emitted[1].Type == Events.Types.SaltDisturbed, "tracker must emit the canonical SaltDisturbed event")
	tracker:Destroy()
end

do
	local tracker = SaltPileHit.new()
	local emitted = {}
	local folder = saltFolder()
	tracker:Start({
		Workspace = world(folder),
		Emit = function(event) table.insert(emitted, event) end,
	})

	local nestedContainer = {Name = "Nested", Parent = folder}
	local renamed = model("PendingSaltEvidence")
	renamed.Parent = nestedContainer
	table.insert(folder._descendants, nestedContainer)
	table.insert(folder._descendants, renamed)
	folder.DescendantAdded:Fire(nestedContainer)
	folder.DescendantAdded:Fire(renamed)
	renamed:Rename("DisturbedSaltPile")
	expect(#emitted == 1 and emitted[1].Type == Events.Types.SaltDisturbed,
		"a future nested descendant renamed DisturbedSaltPile must emit once")
	renamed:Rename("DisturbedSaltPile")
	folder.ChildAdded:Fire(renamed)
	folder.DescendantAdded:Fire(renamed)
	expect(#emitted == 1,
		"rename and overlapping recursive folder signals must not duplicate one disturbance")

	local reparented = model("DisturbedSaltLine")
	reparented.Parent = nestedContainer
	table.insert(folder._descendants, reparented)
	folder.DescendantAdded:Fire(reparented)
	folder.ChildAdded:Fire(reparented)
	expect(#emitted == 2 and emitted[2].Payload.ContactId == reparented,
		"a pre-named disturbed line reparented beneath SaltPiles must be detected exactly once")
	tracker:Destroy()
end

print("core-salt-pile-hit-global.spec: recursive disturbed salt lines and piles rule out Wraith once")
