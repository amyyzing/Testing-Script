local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local EvidenceCatalog = require("../evidence-catalog")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function row(highlight, strikethrough)
	local children = {
		Highlight = {Visible = highlight},
		Strikethrough = {Visible = strikethrough},
	}
	return {FindFirstChild = function(_, name) return children[name] end, Children = children}
end

local rows = {
	Aswang = row(false, false),
	Banshee = row(false, false),
	Demon = row(false, false),
	Ghoul = row(true, true),
}
local marked = {}
local Traffic = createTraffic()
local Verdict = createVerdict({
	Traffic = Traffic,
	ApplyJournalState = function(name, state)
		local selected = rows[name]
		if not selected then return false, false end
		selected.Children.Highlight.Visible = state == true
		selected.Children.Strikethrough.Visible = state == false
		return true, false
	end,
	MarkJournal = function(name) table.insert(marked, name) end,
})

Traffic("Support", {Ghost = "Aswang", Confidence = 35}):SendTo("Verdict")
expect(Verdict.Selected[1] == 1 and #Verdict.Selected == 1,
	"Selected should contain exactly the best ghost index")
expect(rows.Aswang.Children.Highlight.Visible and not rows.Aswang.Children.Strikethrough.Visible,
	"the selected ghost should be highlighted")
expect(marked[1] == "Aswang", "the selected ghost should be sent through the journal remote")

Traffic("Support", {Ghost = "Demon", Confidence = 99}):SendTo("Verdict")
expect(Verdict.Selected[1] == 3 and not rows.Aswang.Children.Highlight.Visible,
	"a higher-confidence ghost should replace and clear the old selection")
expect(rows.Demon.Children.Highlight.Visible and marked[2] == "Demon",
	"the replacement selection should be highlighted and sent remotely")

Traffic("RuleOut", {Ghost = "Banshee", Confidence = 99}):SendTo("Verdict")
expect(table.find(Verdict.RuledOut, 2) ~= nil and rows.Banshee.Children.Strikethrough.Visible,
	"a ruled-out ghost should be stored and crossed out")
expect(#marked == 3 and marked[3] == "Demon",
	"crossing out a row should restore the current journal selection")
expect(rows.Ghoul.Children.Highlight.Visible and rows.Ghoul.Children.Strikethrough.Visible,
	"an unknown ghost row must remain untouched")

Traffic("RuleOut", {Ghost = "Demon", Confidence = 99}):SendTo("Verdict")
expect(rows.Demon.Children.Strikethrough.Visible and Verdict.Selected[1] == 1,
	"ruling out the selection should cross it out and select the next best ghost")
expect(marked[4] == "Aswang", "the replacement should be sent through the journal remote")

local snapshot = Verdict:Snapshot()
expect(#snapshot.Lists == 25 and #snapshot.Selected == 1 and #snapshot["ruled-out"] == 2,
	"the snapshot should contain two arrays and one single-element Selected array")

expect(Verdict:ForceSelect("Aswang"), "a valid final guess should lock")
Traffic("Support", {Ghost = "Ghoul", Confidence = 100}):SendTo("Verdict")
Traffic("RuleOut", {Ghost = "Aswang", Confidence = 99}):SendTo("Verdict")
expect(Verdict.Selected[1] == 1 and not rows.Aswang.Children.Strikethrough.Visible,
	"later tracker traffic must not replace or cross out the locked final guess")
Verdict:Reset()
expect(Verdict.ForcedIndex == nil and #Verdict.Selected == 0,
	"reset should clear the final-guess lock")

local retryTraffic = createTraffic()
local retryStates = {}
local blockRuleOut = true
local retryVerdict = createVerdict({
	Traffic = retryTraffic,
	ApplyJournalState = function(name, state)
		if name == "Banshee" and state == false and blockRuleOut then
			return false, false
		end
		retryStates[name] = state
		return true, false
	end,
})
retryTraffic("Support", {Ghost = "Aswang", Confidence = 35}):SendTo("Verdict")
retryTraffic("RuleOut", {Ghost = "Banshee", Confidence = 99}):SendTo("Verdict")
expect(retryVerdict.JournalDirty,
	"a missed Journal cross-out must remain queued")
blockRuleOut = false
expect(retryVerdict:SyncJournal(),
	"queued Selected and RuledOut arrays should synchronize on retry")
expect(retryStates.Aswang == true and retryStates.Banshee == false,
	"the retry must select Aswang and cross out Banshee")
expect(not retryVerdict.JournalDirty,
	"a complete Journal retry should clear its dirty state")

local evidenceTraffic = createTraffic()
local evidenceStates = {}
local evidenceVerdict = createVerdict({
	Traffic = evidenceTraffic,
	EvidenceCatalog = EvidenceCatalog,
	ApplyJournalState = function(name, state)
		evidenceStates[name] = state
		return true, true
	end,
})
evidenceTraffic("EvidenceState", {Evidence = "Ghost Orb", State = true}):SendTo("Verdict")
expect(evidenceVerdict:SyncJournal() and evidenceStates.Keres == false,
	"confirmed evidence should cross out incompatible ghosts in the Journal")
evidenceTraffic("EvidenceState", {Evidence = "Ghost Orb", State = nil}):SendTo("Verdict")
expect(evidenceVerdict:SyncJournal() and evidenceStates.Keres == nil,
	"clearing evidence should restore ghosts crossed out only by evidence")

local exactTraffic = createTraffic()
local exactOrder = {}
local exactStates = {}
local exactVerdict = createVerdict({
	Traffic = exactTraffic,
	EvidenceCatalog = EvidenceCatalog,
	ApplyJournalState = function(name, state)
		exactStates[name] = state
		table.insert(exactOrder, name .. ":" .. tostring(state))
		return true, true
	end,
})
for _, evidence in ipairs({"GhostWriting", "GhostOrb", "LaserProjector"}) do
	exactTraffic("EvidenceState", {Evidence = evidence, State = true}):SendTo("Verdict")
end
expect(exactVerdict:GetEvidenceResolvedGhost() == "Wendigo",
	"Inscription, Ghost Orb, and Laser should resolve only Wendigo")
table.clear(exactOrder)
expect(exactVerdict:SyncJournal("Wendigo"),
	"the exact three-evidence ghost should synchronize once")
expect(exactOrder[#exactOrder] == "Wendigo:true" and exactStates.Wendigo == true,
	"all ruled-out rows must be handled before selecting Wendigo last")
local selectedRows = 0
for _, state in pairs(exactStates) do
	if state == true then selectedRows += 1 end
end
expect(selectedRows == 1,
	"the exact evidence sync must leave only Wendigo selected")

print("verdict-journal.spec: rule-outs, selection lock, and unknown journal states passed")
