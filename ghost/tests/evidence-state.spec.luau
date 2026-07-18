local createTraffic = require("../traffic")
local createEvidenceState = require("../active-trackers/evidence-state")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			local connected = true
			return {
				Disconnect = function()
					if not connected then return end
					connected = false
					local index = table.find(callbacks, callback)
					if index then table.remove(callbacks, index) end
				end,
			}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function node(name, children)
	local value = {
		Name = name,
		Children = children or {},
		ChildAdded = signal(),
		ChildRemoved = signal(),
	}
	function value:FindFirstChild(childName) return self.Children[childName] end
	function value:GetChildren()
		local result = {}
		for _, child in pairs(self.Children) do table.insert(result, child) end
		return result
	end
	for _, child in pairs(value.Children) do child.Parent = value end
	return value
end

local highlightChanged, crossOutChanged = signal(), signal()
local highlight = {
	Name = "Highlight",
	Visible = true,
	GetPropertyChangedSignal = function() return highlightChanged end,
}
local crossOut = {
	Name = "CrossOut",
	Visible = false,
	GetPropertyChangedSignal = function() return crossOutChanged end,
}
local row = node("Ghost Orb", {
	Container = node("Container", {Highlight = highlight, CrossOut = crossOut}),
})
local evidenceTypes = node("EvidenceTypes", {GhostOrb = row})
local page = node("Page", {EvidenceTypes = evidenceTypes})
local left = node("Left", {Page = page})
local page4 = node("Page4", {Left = left})
local pages = node("Pages", {Page4 = page4})
local holder = node("Holder", {Pages = pages})
local journal = node("Journal", {Holder = holder})
local playerGui = node("PlayerGui", {Journal = journal})
local Player = {
	FindFirstChildOfClass = function(_, className)
		return className == "PlayerGui" and playerGui or nil
	end,
}

local Traffic = createTraffic()
local observations = {}
local logObservations = {}
Traffic:Receive("Verdict", function(signalName, payload)
	if signalName == "EvidenceState" then table.insert(observations, payload) end
end)
Traffic:Receive("EvidenceLog", function(signalName, payload)
	if signalName == "EvidenceState" then table.insert(logObservations, payload) end
end)
local tracker = createEvidenceState({
	Traffic = Traffic,
	Player = Player,
	Defer = function(callback) callback() end,
})
expect(observations[#observations].Evidence == "Ghost Orb"
	and observations[#observations].State == true,
	"the initial highlighted Journal evidence should publish as confirmed")
expect(logObservations[#logObservations] == observations[#observations],
	"the evidence drawer should receive the same initial journal state")

highlight.Visible = false
crossOut.Visible = true
crossOutChanged:Fire()
expect(observations[#observations].State == false,
	"a crossed-out Journal evidence should publish as disproved")

crossOut.Visible = false
crossOutChanged:Fire()
expect(observations[#observations].State == nil,
	"an untouched Journal evidence should publish as unknown")

tracker:Destroy()
print("evidence-state.spec: Journal evidence states publish to the verdict pipeline")
