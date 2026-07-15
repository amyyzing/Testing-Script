local StaticGhostFacts = require("../trackers/discardable/static-ghost-facts")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local root = {
	GetChildren = function()
		return {{Name = "Hunting", ClassName = "Sound"}}
	end,
}
local ghost = {
	Name = "Ghost",
	ClassName = "Model",
	GetAttributes = function() return {Sex = "Female"} end,
	FindFirstChild = function(_, name, recursive)
		if name == "HumanoidRootPart" then return root end
		if name == "InvisibleOnLIDAR" and recursive then return {Name = name} end
		return nil
	end,
}

local emitted = {}
local reads = 0
local static = StaticGhostFacts.new({
	ReadFacts = function(model)
		reads = reads + 1
		return {
			Name = model.Name,
			HasHumanoidRootPart = true,
			RootSoundNames = {"Hunting"},
			LidarExists = true,
			Sex = "Female",
		}
	end,
})
local context = {
	GhostModel = ghost,
	Emit = function(event) table.insert(emitted, event) end,
}
static:Start(context)
static:Start(context)
expect(reads == 1 and static:Snapshot().Status == "Discarded", "static model facts must execute only once per round")
expect(#emitted == 4, "static pass should emit broad facts plus Umbra, Vex, and model-sex one-shots")
static:Reset()
static:Start(context)
expect(reads == 2, "round reset should permit exactly one new static scan")

print("core-lifecycle.spec: fixed-model discardable lifecycle passed")
