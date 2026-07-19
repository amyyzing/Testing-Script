local createPostRound = require("../post-round/post-round")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local ready = false
local state = {completionClaimed = false}
local perkState = {
	currentGhostGuess = "Aswang",
	currentGhostGuessScore = 99,
	currentGhostGuessCertain = false,
	getRemainingCandidates = function() return {"Aswang"} end,
}
local post = createPostRound({
	Dependencies = {
		Services = {},
		Player = {},
		State = state,
		PerkTrackerState = perkState,
		RoomItemPlacementState = {},
		PerkDetections = {},
		GhostProfiles = {{Name = "Aswang"}},
		GhostModule = {
			ConfidenceTier = function() return 3, "Pretty Sure" end,
			SelectHighestConfidenceGuess = function() return "Aswang" end,
		},
		PlaceRoomItemsButton = {},
		Copy = {Controls = {PlaceRoomItems = "Place Room Items"}},
		Colors = {cardHover = "off"},
		SetGhostIdentificationLabel = function() end,
		SetDoRoundStatus = function() end,
		EvidenceReady = function() return ready end,
	},
	Pre = {
		OperationActive = function() return true end,
		Wait = function() return true end,
		PlayerIsInsideBaseCamp = function() return true end,
		ReturnToBase = function() return true end,
		ReleaseMovement = function() end,
		RemoteSafetyDelay = 0.1,
		LobbyRetrySeconds = 4,
		MinimumLeaveAge = 30,
		JournalSettleSeconds = 0.35,
	},
})

expect(post.CurrentIdentification() == nil,
	"high confidence must wait until automatic evidence has settled")
ready = true
local ghost, score = post.CurrentIdentification()
expect(ghost == "Aswang" and score == 99,
	"the stable evidence-compatible high-confidence ghost should be eligible")

print("post-round-selection.spec: evidence settle gate passed")
