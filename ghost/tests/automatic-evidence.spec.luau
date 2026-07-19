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
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function instance(className, name, attributes, properties)
	local value = properties or {}
	value.ClassName = className
	value.Name = name
	value.Attributes = attributes or {}
	value.AttributeSignals = {}
	value.Children = value.Children or {}
	function value:IsA(wanted)
		return self.ClassName == wanted
			or wanted == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart")
	end
	function value:GetAttribute(key) return self.Attributes[key] end
	function value:GetAttributeChangedSignal(key)
		self.AttributeSignals[key] = self.AttributeSignals[key] or signal()
		return self.AttributeSignals[key]
	end
	function value:SetAttribute(key, nextValue)
		self.Attributes[key] = nextValue
		if self.AttributeSignals[key] then self.AttributeSignals[key]:Fire() end
	end
	function value:GetChildren() return table.clone(self.Children) end
	function value:GetDescendants()
		local result = {}
		local function add(parent)
			for _, child in ipairs(parent.Children) do
				table.insert(result, child)
				add(child)
			end
		end
		add(self)
		return result
	end
	function value:FindFirstChild(childName, recursive)
		for _, child in ipairs(self.Children) do
			if child.Name == childName then return child end
		end
		if recursive then
			for _, child in ipairs(self:GetDescendants()) do
				if child.Name == childName then return child end
			end
		end
		return nil
	end
	function value:IsDescendantOf(parent)
		local current = self.Parent
		while current do
			if current == parent then return true end
			current = current.Parent
		end
		return false
	end
	function value:FindFirstAncestor(ancestorName)
		local current = self.Parent
		while current do
			if current.Name == ancestorName then return current end
			current = current.Parent
		end
		return nil
	end
	function value:FindFirstAncestorOfClass(wanted)
		local current = self.Parent
		while current do
			if current:IsA(wanted) then return current end
			current = current.Parent
		end
		return nil
	end
	function value:Add(child)
		child.Parent = self
		table.insert(self.Children, child)
		return child
	end
	return value
end

local world = instance("Workspace", "Workspace")
world.DescendantAdded = signal()
local ghost = world:Add(instance("Model", "Ghost", {
	InLaser = true,
	FavoriteRoom = "Office",
	LastEMF5Time = 0,
}))
local map = world:Add(instance("Folder", "Map"))
local rooms = map:Add(instance("Folder", "Rooms"))
rooms:Add(instance("Folder", "Office", {Temperature = -0.4}))
world:Add(instance("Part", "GhostOrb"))
world:Add(instance("Part", "Handprint1"))
local items = world:Add(instance("Folder", "Items"))
items:Add(instance("Model", "Reader", {ItemName = "EMF Reader", ReadingLevel = 4}))
items:Add(instance("Part", "Flower_Petals", {}, {
	Color = {R = 0.01, G = 0.01, B = 0.01},
}))
local book = items:Add(instance("Model", "Spirit Book", {ItemName = "Spirit Book"}))
local canvas = book:Add(instance("Part", "Canvas"))
local surface = canvas:Add(instance("SurfaceGui", "SurfaceGui"))
local frame = surface:Add(instance("Frame", "Frame"))
frame:Add(instance("ImageLabel", "ImageLabel", {}, {Image = "rbxassetid://writing"}))

local replicated = instance("ReplicatedStorage", "ReplicatedStorage")
local assets = replicated:Add(instance("Folder", "Assets"))
local voices = assets:Add(instance("Folder", "SpiritBoxVoices"))
voices:Add(instance("Sound", "Voice", {Subtitle = "WHERE ARE YOU"}))

local subtitleCallback
local subtitle = {
	Connect = function(callback)
		subtitleCallback = callback
		return {Disconnect = function() subtitleCallback = nil end}
	end,
}
local Player = {
	Character = nil,
	FindFirstChildOfClass = function() return nil end,
	FindFirstChild = function() return nil end,
}
local catalog = {
	EvidenceOrder = {
		"EMFLevel5", "SpiritBox", "GhostWriting", "FreezingTemperatures",
		"GhostOrb", "Handprints", "LaserProjector", "Wither",
	},
	NormalizeEvidence = function(value) return value end,
	SupportsEvidence = function() return true end,
	ConfidenceTier = function() return 0, "Idk" end,
}
local Verdict = {
	Lists = {}, RuledOut = {}, Selected = {}, Confidence = {}, NegativeConfidence = {},
	IsCompatible = function() return true end,
}
local Traffic = createTraffic()
local found, metrics = {}, {}
Traffic:Receive("Verdict", function(signalName, payload)
	if signalName == "EvidenceState" and payload.State == true then found[payload.Evidence] = true end
end)
Traffic:Receive("EvidenceLog", function(signalName, payload)
	if signalName == "EvidenceMetric" then metrics[payload.Key] = payload.Text end
end)

local tracker = createEvidenceState({
	Traffic = Traffic,
	Player = Player,
	Workspace = world,
	ReplicatedStorage = replicated,
	Ghost = ghost,
	EvidenceCatalog = catalog,
	Verdict = Verdict,
	ShowSubtitle = subtitle,
})

expect(not found.EMFLevel5, "EMF-5 should remain unknown before LastEMF5Time changes")
ghost:SetAttribute("LastEMF5Time", 12.5)
expect(found.EMFLevel5, "LastEMF5Time should confirm EMF-5 immediately")

for _, evidence in ipairs({
	"EMFLevel5", "GhostWriting", "FreezingTemperatures", "GhostOrb",
	"Handprints", "LaserProjector", "Wither",
}) do
	expect(found[evidence], evidence .. " should be detected from the legacy world source")
end
expect(metrics.FavouriteRoom == "Favourite Room: Office",
	"the evidence log should publish the favourite room")
subtitleCallback("WHERE ARE YOU")
expect(found.SpiritBox, "a known ShowSubtitle response should confirm Spirit Box")

tracker:Destroy()
print("automatic-evidence.spec: all eight legacy evidence sources passed")
