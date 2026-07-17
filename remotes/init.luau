local Remotes = {}

Remotes.Manifest = {
	"ApplyDifficultyPreset",
	"ApplyEquipmentPreset",
	"AskSpiritBoxFromUI",
	"AttemptStart",
	"ChangeDifficulty",
	"ChangeJobSite",
	"ChangeStatus",
	"ClientChangeDoorState",
	"EvidenceMarkedInJournal",
	"LaySaltPile",
	"LoadingFinished",
	"PourHolyOil",
	"RequestItemDrop",
	"RequestItemEquip",
	"RequestItemPickup",
	"RequestReturnToLobby",
	"ShowSubtitle",
	"ToggleChallenge",
	"ToggleFuseBox",
	"ToggleItemState",
	"UpdateAllCustomDifficultySettings",
	"UpdateDifficulty",
	"UpdateJobSite",
	"UseLightSwitch",
	"LocalShowSubtitle",
	"UseItem",
}

function Remotes.new(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local loadModule = assert(dependencies.LoadModule, "Remotes requires LoadModule")
	local available = {}
	for _, name in ipairs(Remotes.Manifest) do
		available[name] = true
	end
	return setmetatable({}, {
		__index = function(package, name)
			if not available[name] then return nil end
			local remote = loadModule("remotes/" .. name .. ".luau")
			rawset(package, name, remote)
			return remote
		end,
	})
end

return Remotes
