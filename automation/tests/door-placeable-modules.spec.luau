local createLaySalt = require("../pre-round/lay-salt")
local createPourHolyOil = require("../pre-round/pour-holy-oil")

local calls = {}
local function place(toolName, generation, session)
	table.insert(calls, {toolName, generation, session})
	return true
end

local session = {}
assert(createLaySalt({PlaceTool = place})(7, session) == true)
assert(createPourHolyOil({PlaceTool = place})(7, session) == true)
assert(calls[1][1] == "Salt Canister" and calls[1][2] == 7)
assert(calls[2][1] == "Holy Oil" and calls[2][2] == 7)
assert(calls[1][3] == session and calls[2][3] == session)

print("door-placeable-modules.spec: focused tool dispatch passed")
