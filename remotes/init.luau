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
	"RequestItemUnequip",
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
	local package = {}
	for _, name in ipairs(Remotes.Manifest) do
		available[name] = true
	end
	function package:Get(name)
		if not available[name] then return nil end
		local remote = rawget(self, name)
		if remote then return remote end
		remote = loadModule("remotes/" .. name .. ".luau")
		rawset(self, name, remote)
		return remote
	end
	return package
end

return Remotes
