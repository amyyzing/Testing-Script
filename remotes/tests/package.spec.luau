local Remotes = require("../.")

local loaded = {}
local package = Remotes.new({
	LoadModule = function(path)
		table.insert(loaded, path)
		return function() return path end
	end,
})

assert(#loaded == 0, "remote files should load lazily")
for index, name in ipairs(Remotes.Manifest) do
	local path = "Remotes/" .. name .. ".luau"
	assert(type(package[name]) == "function", name .. " was not exposed")
	assert(loaded[index] == path, "remote load order changed")
	assert(package[name]() == path, name .. " did not remain callable")
end

print("package.spec: every remote file is lazily loaded and exposed")
