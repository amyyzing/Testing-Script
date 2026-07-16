local createTraffic = require("../traffic")
local createVerdict = require("../verdict")

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

print("verdict-journal.spec: rule-outs, selection, and unknown journal states passed")
