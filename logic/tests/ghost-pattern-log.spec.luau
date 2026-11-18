local createTraffic = require("../../ghost/traffic")
local createPatternLog = require("../ghost-pattern-log")

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

local Traffic = createTraffic()
local view = {
	List = {},
	Layout = layout,
	Empty = {Visible = true},
	Template = template,
}
local risk = false
local controller = createPatternLog({
 DoppelgangerPossible = function() return risk end,
	Traffic = Traffic,
	View = view,
	PositiveColor = "green",
	NegativeColor = "red",
	CanvasSize = function(x, y) return {X = x, Y = y} end,
	Defer = function(callback) callback() end,
})

local function result(signal, ghost, perk, confidence, observation)
	Traffic(signal, {Ghost = ghost, Perk = perk, Confidence = confidence, Observation = observation}):SendTo("Verdict")
end

result("Support", "Shadow", "Slow cooling", 35)
result("Negative", "Entity", "Smoke Holder", 50)
result("RuleOut", "Keres", nil, 99)
Traffic("GhostSpeedObserved", {Speed = 21}):SendTo("GhostPatternLog")
expect(controller.Count == 0 and not view.Empty.Visible, "trackers and unsettled perk checks should stay off the log")

result("RuleOut", "Umbra", "Silent footsteps", 99, "Footsteps heard")
expect(entries[1].Text == "NEGATIVE  Umbra | Footsteps heard" and entries[1].TextColor3 == "red",
	"the observation should describe what contradicted the perk")
result("Support", "Aswang", "Salt slowdown", 99)
result("Support", "Aswang", "Salt slowdown", 99)
result("Support", "Aswang", "Speed rises after kill", 99)
expect(controller.Count == 3 and entries[2].Text == "POSITIVE  Aswang | Salt slowdown"
	and entries[3].Text == "POSITIVE  Aswang | Speed rises after kill",
	"repeat results should update one row per perk, and different perks should get their own rows")

risk = true
Traffic("Support", {Ghost = "Wraith", Perk = "Undisturbed salt", Observation = "Salt undisturbed",
 Confidence = 65, Certainty = "Medium"}):SendTo("Verdict")
expect(controller.Count == 4 and entries[4].Text == "MEDIUM  Wraith | Salt undisturbed",
 "shared perk observations must be visibly marked MEDIUM")

risk = false
Traffic("EvidenceState", {Evidence = "EMFLevel5", State = true}):SendTo("Verdict")
expect(entries[2].Text == "POSITIVE  Aswang | Salt slowdown", "excluding Doppelganger must refresh existing rows")
risk = true
Traffic("EvidenceState", {Evidence = "EMFLevel5"}):SendTo("Verdict")
expect(entries[2].Text == "MEDIUM  Aswang | Salt slowdown", "clearing independent exclusion must restore MEDIUM")

Traffic("Support", {Ghost = "Revenant", Perk = "Hunt ends after kill",
	Observation = "Hunt stopped after kill", Confidence = 35, Certainty = "Low"}):SendTo("Verdict")
expect(entries[5].Text == "LOW  Revenant | Hunt stopped after kill",
	"explicitly qualified low-confidence cues must not look like definite positives")
Traffic("Support", {Ghost = "Specter", Perk = "Stays in favourite room",
	Confidence = 35, Certainty = "Low"}):SendTo("Verdict")
Traffic("Support", {Ghost = "Specter", Perk = "Stays in favourite room",
	Confidence = 60, Certainty = "Medium"}):SendTo("Verdict")
expect(controller.Count == 6 and entries[6].Text == "MEDIUM  Specter | Stays in favourite room",
	"a low-to-medium cue should update the same compact row")

controller:Destroy()
for _, entry in ipairs(entries) do expect(entry.Destroyed, "destroy should remove every generated log") end

print("ghost-pattern-log.spec: compact, qualified perk results passed")
