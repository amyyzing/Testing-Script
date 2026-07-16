local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createItemState = require("../active-trackers/item-state")
local Ghoul = require("../ghosts/Ghoul")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function item(name, enabled, position)
	local changed = {Enabled = signal(), ItemName = signal()}
	local value = {
		Name = name:gsub(" ", ""),
		ItemName = name,
		Enabled = enabled,
		Position = position,
		DescendantAdded = signal(),
	}
	function value:IsA(class) return class == "Model" end
	function value:GetAttribute(attribute) return self[attribute] end
	function value:GetAttributeChangedSignal(attribute) return changed[attribute] end
	function value:GetDescendants() return {} end
	function value:GetPivot() return {Position = self.Position} end
	function value:SetEnabled(state)
		self.Enabled = state
		changed.Enabled:Fire()
	end
	return value
end

local laser = item("Laser Projector", true, {X = 0, Y = 0, Z = 0})
local spirit = item("Spirit Box", false, {X = 30, Y = 0, Z = 0})
local emf = item("EMF Reader", true, {X = 30, Y = 0, Z = 0})
local Items = {Name = "Items", ChildAdded = signal(), Children = {laser, spirit, emf}}
function Items:GetChildren() return self.Children end
for _, value in ipairs(Items.Children) do value.Parent = Items end

local World = {ChildAdded = signal()}
function World:FindFirstChild(name) return name == "Items" and Items or nil end
local root = {Position = {X = 15, Y = 0, Z = 0}}
local character = {}
function character:FindFirstChild(name) return name == "HumanoidRootPart" and root or nil end
local player = {Character = character, Dead = false}
function player:GetAttribute(name) return name == "Dead" and self.Dead or nil end
local Players = {}
function Players:GetPlayers() return {player} end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local ghoul = Ghoul.new({Traffic = Traffic})
local ruleOutSignals = 0
Traffic:Receive("Verdict", function(signalName, payload)
	if signalName == "RuleOut" and payload.Ghost == "Ghoul" then ruleOutSignals += 1 end
end)
local tracker = createItemState({
	Traffic = Traffic,
	Workspace = World,
	Players = Players,
	Defer = function(callback) callback() end,
})

expect(ruleOutSignals == 0, "an item that starts disabled must only be baselined")
emf:SetEnabled(false)
expect(ruleOutSignals == 0, "non-target electronics must be ignored")
laser:SetEnabled(false)
expect(ruleOutSignals == 0, "a player exactly 15 studs away should prevent the rule-out")
laser:SetEnabled(true)
root.Position = {X = 15.01, Y = 0, Z = 0}
laser:SetEnabled(false)
expect(ruleOutSignals == 1 and Verdict:Snapshot()["ruled-out"][1] == 7,
	"a target item disabled with no nearby living player should rule out Ghoul")
laser:SetEnabled(true)
laser:SetEnabled(false)
expect(ruleOutSignals == 1, "Ghoul should only be resolved once")

tracker:Destroy()
ghoul:Destroy()
print("ghoul.spec: electronic disable distance rule-out passed")
