Color3 = {
	fromRGB = function(red, green, blue)
		return {R = red / 255, G = green / 255, B = blue / 255}
	end,
}

local bundle = require("../../dist/modules")

assert(bundle.__compiled == true, "bundle should contain initialized modules")
assert(type(bundle["logic/movement.luau"]) == "function", "movement module missing")
assert(type(bundle["ghost/verdict.luau"]) == "function", "verdict module missing")
assert(bundle["ghost/ghosts/Banshee.luau"] == bundle.__nil, "nil module sentinel missing")

print("module-bundle.spec: compiled bundle passed")
