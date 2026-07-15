local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({
	Events = Events,
	EvidenceLedger = Ledger,
	Resolver = Resolver,
})
local Wisp = require("../Wisp")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function scoredEntries(coordinator)
	local result = {}
	for _, entry in ipairs(coordinator:Ledger():Entries()) do
		if entry.Ghost == "Wisp" and entry.Polarity ~= "Observation" then
			table.insert(result, entry)
		end
	end
	return result
end

local coordinator = Coordinator.new({Definitions = {Wisp}})
coordinator:Start({})
coordinator:Emit({
	Type = Events.Types.HuntRoomRelation,
	HuntId = "outside-first",
	Hunting = true,
	Qualified = true,
	Completed = true,
	InFavouriteRoom = false,
})
expect(coordinator:Resolve({"Wisp"}).Wisp.RuledOut == true,
	"an outside-favourite hunt must create a persistent 95% Wisp negative")

for index = 1, 2 do
	coordinator:Emit({
		Type = Events.Types.HuntRoomRelation,
		HuntId = "favourite-later-" .. tostring(index),
		Hunting = true,
		Qualified = true,
		Completed = true,
		InFavouriteRoom = true,
	})
end
local roomOnly = scoredEntries(coordinator)
expect(#roomOnly == 1 and roomOnly[1].Polarity == "Negative"
	and coordinator:Resolve({"Wisp"}).Wisp.RuledOut == true,
	"later favourite-room hunts must not supersede the historical negative")

coordinator:Emit({
	Type = Events.Types.HolyOilCollision,
	ModelId = "oil-after-room-negative",
	Hunting = true,
	Burning = true,
	Qualified = true,
	CanCollide = false,
})
local separated = scoredEntries(coordinator)
expect(#separated == 2 and separated[1].Polarity == "Negative"
	and separated[2].Polarity == "Positive"
	and separated[2].Supersedes == nil
	and separated[1].Id ~= separated[2].Id,
	"Holy Oil must remain a separate evidence domain from hunt-room history")

coordinator:Destroy()
print("core-wisp-persistence.spec: outside-room history and oil domains remain independent")
