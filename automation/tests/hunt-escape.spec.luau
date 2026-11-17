local createEscape = require("../round/hunt-escape")

local map, ghost = {}, {}
local hunting, inside = true, false
local waits, teleports = 0, 0
function ghost:GetAttribute(name)
	return name == "Hunting" and hunting
end
local escape = createEscape({
	Workspace = {FindFirstChild = function() return map end},
	State = {roundMap = map, roundGhost = ghost},
	GetGhost = function() return ghost end,
	OperationActive = function() return true end,
	SetStatus = function() end,
	TeleportToBase = function() error("cached safety should suffice") end,
	FastTeleportToBase = function()
		teleports += 1
		inside = true
		return true
	end,
	TeleportOptions = function() return {} end,
	PlayerInsideBase = function() return inside end,
	Wait = function(_, seconds)
		if seconds ~= 0.15 then return end
		waits += 1
		if waits == 1 then
			inside = false -- a late item/room movement lands after the first escape
		else
			hunting = false
		end
	end,
})

assert(escape(1), "hunt should finish safely")
assert(inside and teleports == 2,
	"displacement after an initial escape must trigger another escape")
print("hunt-escape.spec: late displacement recovery passed")
