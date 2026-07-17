local LobbySettings = require("../lobby-settings")

local names = LobbySettings.JobSiteNames()
assert(#names == 11 and names[1] == "Lincoln St" and names[10] == "School",
	"Job Site list or order changed")
for _, site in ipairs(LobbySettings.JobSites) do
	assert((site.Size == "Small" or site.Size == "Medium" or site.Size == "Large")
		and type(site.Description) == "string" and site.Description ~= "",
		"each Job Site requires size and description metadata")
end
assert(table.concat(LobbySettings.Difficulties, ",") == "Easy,Medium,Hard,Nightmare,Custom",
	"difficulty order changed")

local function node(name, className, children, attributes)
	local object = {Name = name, ClassName = className or "Folder", Children = children or {},
		Attributes = attributes or {}}
	function object:IsA(value) return self.ClassName == value end
	function object:GetChildren() return self.Children end
	function object:GetAttribute(value) return self.Attributes[value] end
	function object:FindFirstChild(value, recursive)
		for _, child in ipairs(self.Children) do if child.Name == value then return child end end
		if recursive then
			for _, child in ipairs(self.Children) do
				local found = child:FindFirstChild(value, true)
				if found then return found end
			end
		end
	end
	return object
end

local function challenge(index, text)
	local label = node("TextLabel", "TextLabel")
	label.Text = text
	return node("Challenge" .. index, "Frame", {node("Toggle", "Frame", {label})})
end
local difficultyLabel = node("DifficultyLabel", "TextLabel")
difficultyLabel.Text = "Difficulty - Custom"
local delete = node("Delete", "TextButton")
local player = node("Player", "Player", {
	node("PlayerGui", "PlayerGui", {
		node("ComputerScreen", "ScreenGui", {
			node("JobSite", "Frame", {
				node("Content", "Frame", {
					node("MapContainer", "Frame", {node("Locations", "Frame", {
						node("School", "Frame", {}, {Selected = true}), node("Prison", "Frame"),
					})}),
					node("BottomBar", "Frame", {difficultyLabel}),
				}),
				node("DifficultySettings", "Frame", {
					node("PresetList", "Frame", {node("john4", "Frame", {delete})}),
					node("Content", "Frame", {node("SettingsList", "Frame", {
						node("EvidenceGiven", "Frame", {}, {Index = 4}),
					})}),
				}),
				node("Challenges", "Frame", {node("Content", "Frame", {
					node("ChallengeList", "Frame", {challenge(1, "ON"), challenge(2, "OFF"), challenge(3, "ON")}),
				})}),
			}),
			node("Equipment", "Frame", {node("PartyLog", "Frame", {
				node("PresetList", "Frame", {node("green", "Frame", {delete})}),
			})}),
		}),
	}),
})
local job, jobReady = LobbySettings.ReadSelectedJobSite(player)
local difficulty, difficultyReady = LobbySettings.ReadSelectedDifficulty(player)
local challenges = LobbySettings.ReadChallengeStates(player)
assert(jobReady and job == "School" and difficultyReady and difficulty == "Custom",
	"live Job Site or difficulty paths changed")
assert(challenges[1] and challenges[2] == false and challenges[3],
	"challenge ON/OFF paths changed")
assert(LobbySettings.ReadCustomPresets(player)[1] == "john4"
	and LobbySettings.ReadEquipmentPresets(player)[1] == "green",
	"saved preset paths changed")
assert(LobbySettings.CustomDifficultyMatches(player, {EvidenceGiven = 4}),
	"custom difficulty index confirmation failed")

print("lobby-settings.spec: choices, presets, and live lobby state paths passed")
