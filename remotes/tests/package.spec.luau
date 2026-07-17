local Remotes = require("../.")

local loaded = {}
local package = Remotes.new({
	LoadModule = function(path)
		table.insert(loaded, path)
		return function() return path end
	end,
})

assert(#loaded == 0, "remote files should load lazily")
assert(getmetatable(package) == nil, "remote loading must not use a yielding metamethod")
for index, name in ipairs(Remotes.Manifest) do
	local path = "remotes/" .. name .. ".luau"
	assert(type(package:Get(name)) == "function", name .. " was not exposed")
	assert(loaded[index] == path, "remote load order changed")
	assert(package:Get(name)() == path, name .. " did not remain callable")
end

print("package.spec: explicit lazy loading avoids yielding in a metamethod")
