local createTraffic = require("../../ghost/traffic")
local createEvidenceLog = require("../evidence-log")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local changedCallback
local layout = {AbsoluteContentSize = {Y = 50}}
function layout:GetPropertyChangedSignal()
	return {
		Connect = function(_, callback)
			changedCallback = callback
			return {Disconnect = function() changedCallback = nil end}
		end,
	}
end

local entries = {}
local template = {}
function template:Clone()
	local entry = {Destroyed = false}
	function entry:Destroy() self.Destroyed = true end
	table.insert(entries, entry)
	return entry
end

local catalog = {
	EvidenceOrder = {"SpiritBox", "GhostOrb"},
	Evidence = {
		SpiritBox = {DisplayName = "Spirit Box"},
		GhostOrb = {DisplayName = "Ghost Orb"},
	},
	NormalizeEvidence = function(value)
		return ({["Spirit Box"] = "SpiritBox", ["Ghost Orb"] = "GhostOrb"})[value]
			or value
	end,
}
local Traffic = createTraffic()
local view = {
	List = {},
	Layout = layout,
	Empty = {Visible = true},
	Template = template,
}
local controller = createEvidenceLog({
	Traffic = Traffic,
	View = view,
	EvidenceCatalog = catalog,
	UnknownColor = "unknown",
	PositiveColor = "positive",
	NegativeColor = "negative",
	CanvasSize = function(x, y) return {X = x, Y = y} end,
	Defer = function(callback) callback() end,
})

expect(#entries == 2 and view.Empty.Visible == false,
	"the legacy-style drawer should create one row for every evidence type")
expect(entries[1].Text == "Spirit Box: Unknown" and entries[1].TextColor3 == "unknown",
	"evidence should begin unknown")

Traffic("EvidenceState", {Evidence = "Spirit Box", State = true}):SendTo("EvidenceLog")
expect(entries[1].Text == "Spirit Box: Yes" and entries[1].TextColor3 == "positive",
	"confirmed evidence should render as Yes")

Traffic("EvidenceState", {Evidence = "Ghost Orb", State = false}):SendTo("EvidenceLog")
expect(entries[2].Text == "Ghost Orb: Impossible" and entries[2].TextColor3 == "negative",
	"crossed-out evidence should render as Impossible")

Traffic("EvidenceState", {Evidence = "Ghost Orb", State = nil}):SendTo("EvidenceLog")
expect(entries[2].Text == "Ghost Orb: Unknown" and entries[2].TextColor3 == "unknown",
	"cleared evidence should return to Unknown")

controller:Destroy()
expect(entries[1].Destroyed and entries[2].Destroyed, "destroy should remove evidence rows")

print("evidence-log.spec: legacy evidence states render in the side drawer")
