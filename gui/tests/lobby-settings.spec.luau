local LobbySettings = require("../lobby-settings")

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local expectedNames = {
	"Lincoln St",
	"Fenway Drive",
	"Juniper Road",
	"Bodega",
	"Lilim Lane",
	"Cafe",
	"Bridgewood Drive",
	"Oakbridge Estates",
	"Prison",
	"School",
	"Asylum",
}
local expectedRequirements = {
	Bodega = 6,
	["Lilim Lane"] = 4,
	Cafe = 8,
	["Bridgewood Drive"] = 16,
	["Oakbridge Estates"] = 25,
	Prison = 9,
	School = 13,
	Asylum = 20,
}

expect(#LobbySettings.JobSites == #expectedNames, "all requested job sites must be present")
for index, expectedName in ipairs(expectedNames) do
	local site = LobbySettings.JobSites[index]
	expect(site.Name == expectedName, "job-site order must remain stable")
	expect(site.Size == "Small" or site.Size == "Medium" or site.Size == "Large", "job site needs a valid size")
	expect(type(site.Description) == "string" and site.Description ~= "", "job site needs a description")
	expect(string.find(site.Description, "———", 1, true) ~= nil, "job-site credit separator changed")
	expect(site.LevelRequirement == expectedRequirements[site.Name], "job-site level requirement changed")
end

local expectedDifficulties = {"Easy", "Medium", "Hard", "Nightmare", "Custom"}
expect(#LobbySettings.Difficulties == #expectedDifficulties, "difficulty list length changed")
for index, name in ipairs(expectedDifficulties) do
	expect(LobbySettings.Difficulties[index] == name, "difficulty order must remain stable")
end

local function node(name, className, children, attributes)
	local object = {
		Name = name,
		ClassName = className or "Folder",
		Children = children or {},
		Attributes = attributes or {},
	}
	function object:IsA(expected)
		return self.ClassName == expected
	end
	function object:GetChildren()
		return self.Children
	end
	function object:GetAttribute(attributeName)
		return self.Attributes[attributeName]
	end
	function object:FindFirstChild(childName, recursive)
		for _, child in ipairs(self.Children) do
			if child.Name == childName then
				return child
			end
		end
		if recursive then
			for _, child in ipairs(self.Children) do
				local found = child:FindFirstChild(childName, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	return object
end

local delete = node("Delete", "TextButton")
local presetList = node("PresetList", "Frame", {
	node("Template", "Frame"),
	node("Zulu", "Frame", {node("Controls", "Frame", {delete})}),
	node("alpha", "Frame", {delete}),
	node("NotAFrame", "Folder", {delete}),
})
local equipmentPresetList = node("PresetList", "Frame", {
	node("Template", "Frame"),
	node("green", "Frame", {delete}),
	node("EvidenceRun", "Frame", {node("Footer", "Frame", {delete})}),
})
local function challenge(index, text)
	local stateLabel = node("TextLabel", "TextLabel")
	stateLabel.Text = text
	return node("Challenge" .. tostring(index), "Frame", {
		node("Toggle", "TextButton", {stateLabel}),
	})
end
local challengeList = node("ChallengeList", "Frame", {
	challenge(1, "ON"),
	challenge(2, "OFF"),
	challenge(3, "ON"),
})
local locations = node("Locations", "Frame", {
	node("School", "Frame", {}, {Selected = true}),
	node("Prison", "Frame"),
})
local difficultyLabel = node("DifficultyLabel", "TextLabel")
difficultyLabel.Text = "Difficulty - Custom"
local customSettingsList = node("SettingsList", "Frame", {
	node("GhostWalkSpeedMultiplier", "Frame", {}, {Index = 6}),
	node("EvidenceGiven", "Frame", {}, {Index = 4}),
})
local player = node("Player", "Player", {
	node("PlayerGui", "PlayerGui", {
		node("ComputerScreen", "ScreenGui", {
			node("JobSite", "Frame", {
				node("Content", "Frame", {
					node("MapContainer", "Frame", {locations}),
					node("BottomBar", "Frame", {difficultyLabel}),
				}),
				node("DifficultySettings", "Frame", {
					presetList,
					node("Content", "Frame", {customSettingsList}),
				}),
				node("Challenges", "Frame", {
					node("Content", "Frame", {challengeList}),
				}),
			}),
			node("Equipment", "Frame", {
				node("PartyLog", "Frame", {equipmentPresetList}),
			}),
		}),
	}),
})

local presets = LobbySettings.ReadCustomPresets(player)
expect(#presets == 2, "only preset frames containing Delete should be listed")
expect(presets[1] == "alpha" and presets[2] == "Zulu", "custom presets should sort case-insensitively")

local equipmentPresets = LobbySettings.ReadEquipmentPresets(player)
expect(#equipmentPresets == 2, "equipment presets must use the PartyLog preset list")
expect(equipmentPresets[1] == "EvidenceRun" and equipmentPresets[2] == "green", "equipment presets should sort case-insensitively")

local selectedJobSite, jobSitesReady = LobbySettings.ReadSelectedJobSite(player)
expect(jobSitesReady == true, "loaded job-site frames should report ready")
expect(selectedJobSite == "School", "the Selected attribute should identify the current job site")
expect(LobbySettings.JobSiteMatches(selectedJobSite, jobSitesReady, "School"),
	"the exact live Job Site should pass the macro confirmation helper")
expect(not LobbySettings.JobSiteMatches(selectedJobSite, jobSitesReady, "Prison"),
	"a different requested Job Site must fail macro confirmation")
local missingJobSite, missingJobSitesReady = LobbySettings.ReadSelectedJobSite(node("Player", "Player"))
expect(missingJobSite == nil and missingJobSitesReady == false, "missing job-site GUI should not report ready")
local noSelectionLocations = node("Locations", "Frame", {
	node("School", "Frame"),
	node("Prison", "Frame"),
})
local noSelectionPlayer = node("Player", "Player", {
	node("PlayerGui", "PlayerGui", {
		node("ComputerScreen", "ScreenGui", {
			node("JobSite", "Frame", {
				node("Content", "Frame", {
					node("MapContainer", "Frame", {noSelectionLocations}),
				}),
			}),
		}),
	}),
})
local noSelectedJobSite, noSelectionReady = LobbySettings.ReadSelectedJobSite(noSelectionPlayer)
expect(noSelectedJobSite == nil and noSelectionReady == true,
	"loaded locations with no selection should be ready for ChangeJobSite, not mistaken for missing data")
expect(not LobbySettings.JobSiteMatches(noSelectedJobSite, noSelectionReady, "School"),
	"an empty live selection must not confirm ChangeJobSite")

local selectedDifficulty, difficultyReady = LobbySettings.ReadSelectedDifficulty(player)
expect(difficultyReady == true and selectedDifficulty == "Custom", "difficulty label should identify the live difficulty")
difficultyLabel.Text = "Loading..."
local missingDifficulty, missingDifficultyReady = LobbySettings.ReadSelectedDifficulty(player)
expect(missingDifficulty == nil and missingDifficultyReady == false, "uninitialized difficulty label should not report ready")
difficultyLabel.Text = "Difficulty - Custom"

expect(LobbySettings.CustomDifficultyMatches(player, {
	GhostWalkSpeedMultiplier = 6,
	EvidenceGiven = 4,
}), "matching custom setting indexes should confirm the applied preset")
expect(not LobbySettings.CustomDifficultyMatches(player, {
	GhostWalkSpeedMultiplier = 5,
}), "a mismatched custom setting index must reject preset confirmation")
expect(not LobbySettings.CustomDifficultyMatches(player, {
	GhostWalkSpeedMultiplier = 6,
	MissingSetting = 1,
}), "a missing custom setting frame must reject the complete preset payload")

local challengeStates = LobbySettings.ReadChallengeStates(player)
expect(challengeStates[1] == true, "Challenge1 ON label should read true")
expect(challengeStates[2] == false, "Challenge2 OFF label should read false")
expect(challengeStates[3] == true, "Challenge3 ON label should read true")
expect(LobbySettings.ChallengeStatesMatch(challengeStates, {true, false, true}),
	"all three exact requested challenge states should confirm")
expect(not LobbySettings.ChallengeStatesMatch(challengeStates, {true, true, true}),
	"one mismatched challenge must block AttemptStart")
expect(not LobbySettings.ChallengeStatesMatch({true, false}, {true, false, false}),
	"an unreported challenge state must not be treated as OFF")

print("lobby-settings.spec: maps, presets, live lobby state, and challenge-state reading passed")
