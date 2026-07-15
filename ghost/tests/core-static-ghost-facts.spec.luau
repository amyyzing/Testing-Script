local StaticGhostFacts = require("../trackers/discardable/static-ghost-facts")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function model(attributes)
	attributes = attributes or {}
	return {
		Name = "Ghost",
		ClassName = "Model",
		GetAttributes = function()
			return attributes
		end,
		GetAttribute = function(_, name)
			return attributes[name]
		end,
		GetDescendants = function()
			return {}
		end,
		FindFirstChild = function()
			return nil
		end,
	}
end

local function run(attributes)
	local events = {}
	local tracker = StaticGhostFacts.new()
	tracker:Start({
		GhostModel = model(attributes),
		Emit = function(event)
			table.insert(events, event)
		end,
	})
	return tracker:Snapshot(), events
end

local unknown, unknownEvents = run({VisualModel = "FutureModel"})
expect(unknown.Status == "Discarded", "static facts should complete its one-shot scan")
expect(unknown.Result.Sex == "Male", "every non-female VisualModel package must classify as male")
expect(unknownEvents[#unknownEvents].Type == "GhostModelSex"
	and unknownEvents[#unknownEvents].Payload.Sex == "Male",
	"a non-female VisualModel package must emit qualified male evidence")

local female, femaleEvents = run({VisualModel = "Abaddon"})
expect(female.Result.Sex == "Female", "a verified female VisualModel should retain its inference")
expect(femaleEvents[#femaleEvents].Type == "GhostModelSex"
	and femaleEvents[#femaleEvents].Payload.Sex == "Female",
	"a verified female VisualModel should emit qualified gender evidence")

local explicitMale, maleEvents = run({VisualModel = "FutureModel", Sex = "Male"})
expect(explicitMale.Result.Sex == "Male", "an explicit replicated sex must override model inference")
expect(maleEvents[#maleEvents].Type == "GhostModelSex"
	and maleEvents[#maleEvents].Payload.Sex == "Male",
	"an explicit male sex should emit qualified gender evidence")

do
	local lidarMember = {
		Name = "InvisibleOnLIDAR",
		Value = nil,
		IsA = function(_, className) return className == "ValueBase" end,
	}
	local ghost = model({})
	function ghost:GetDescendants() return {lidarMember} end
	local events = {}
	local tracker = StaticGhostFacts.new()
	tracker:Start({
		GhostModel = ghost,
		Emit = function(event) table.insert(events, event) end,
	})
	local lidarEvent
	for _, event in ipairs(events) do
		if event.Type == "LidarState" then lidarEvent = event end
	end
	expect(tracker:Snapshot().Result.LidarExists == true
		and lidarEvent and lidarEvent.Payload.Exists == true,
		"an InvisibleOnLIDAR ValueBase must count as present even when ObjectValue.Value is nil")
end

print("core-static-ghost-facts.spec: VisualModel gender-package handling passed")
