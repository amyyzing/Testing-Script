local createRoundAutomation = require("../../automation/game-round")

local function expect(value, message)
	if not value then error(message, 2) end
end

local order = {}
local dependencies = {
	CreatePreRound = function(received)
		table.insert(order, "pre")
		expect(received ~= nil, "pre-round must receive the shared dependencies")
		return {Name = "pre"}
	end,
	CreatePostRound = function(package)
		table.insert(order, "post")
		expect(package.Dependencies ~= nil and package.Pre.Name == "pre",
			"post-round must receive the pre-round interface")
		return {Name = "post"}
	end,
	CreateRound = function(package)
		table.insert(order, "round")
		expect(package.Dependencies ~= nil
			and package.Pre.Name == "pre"
			and package.Post.Name == "post",
			"round phase must receive both surrounding phases")
		return {SetEnabled = function() end}
	end,
}

local controller = createRoundAutomation(dependencies)
expect(type(controller.SetEnabled) == "function",
	"the phase coordinator must return the game-round controller")
expect(table.concat(order, ",") == "pre,post,round",
	"game-round phases must be composed in dependency order")

print("round-automation.spec: pre, round, and post phase wiring passed")
