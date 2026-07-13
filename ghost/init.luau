-- Remote-safe ghost package loader.  The bootstrap injects LoadModule so this
-- file never depends on Roblox/CLI require semantics.

local MANIFEST = {
	"Aswang",
	"Banshee",
	"Demon",
	"Dullahan",
	"Dybbuk",
	"Entity",
	"Ghoul",
	"Keres",
	"Leviathan",
	"Nightmare",
	"Oni",
	"Phantom",
	"Ravager",
	"Revenant",
	"Shadow",
	"Siren",
	"Skinwalker",
	"Specter",
	"Spirit",
	"Umbra",
	"Vesper",
	"Vex",
	"Wendigo",
	"Wisp",
	"Wraith",
}

local function copyArray(source)
	local result = {}
	for index, value in ipairs(source) do
		result[index] = value
	end
	return result
end

return function(dependencies)
	dependencies = dependencies or {}
	local loadModule = dependencies.LoadModule
	if type(loadModule) ~= "function" then
		error("ghost/init.luau requires dependencies.LoadModule", 2)
	end

	local definitions = {}
	for index, expectedName in ipairs(MANIFEST) do
		if type(dependencies.OnProgress) == "function" then
			dependencies.OnProgress(expectedName, index, #MANIFEST)
		end
		local path = "ghost/" .. expectedName .. ".luau"
		local definition = loadModule(path)
		if type(definition) ~= "table" then
			error(path .. " must return a ghost definition table", 2)
		end
		if definition.Name ~= expectedName then
			error(("%s must define Name=%q; received %q"):format(
				path,
				expectedName,
				tostring(definition.Name)
			), 2)
		end
		definitions[index] = definition
	end

	local buildEngine = loadModule("ghost/engine.luau")
	if type(buildEngine) ~= "function" then
		error("ghost/engine.luau must return a catalog factory", 2)
	end
	local catalog = buildEngine(definitions)
	if type(catalog) ~= "table"
		or type(catalog.Profiles) ~= "table"
		or type(catalog.ByName) ~= "table" then
		error("ghost/engine.luau returned an invalid catalog", 2)
	end
	local createRuntime = loadModule("ghost/runtime.luau")
	if type(createRuntime) ~= "function" then
		error("ghost/runtime.luau must return a runtime factory", 2)
	end
	local createCollector = loadModule("ghost/collector.luau")
	if type(createCollector) ~= "function" then
		error("ghost/collector.luau must return a collector factory", 2)
	end
	local createSession = loadModule("ghost/session.luau")
	if type(createSession) ~= "function" then
		error("ghost/session.luau must return a session-policy factory", 2)
	end
	local sessionPolicy = createSession(catalog)
	if type(sessionPolicy) ~= "table"
		or type(sessionPolicy.Evaluate) ~= "function" then
		error("ghost/session.luau returned an invalid session policy", 2)
	end
	local createTracker = loadModule("ghost/tracker.luau")
	if type(createTracker) ~= "function" then
		error("ghost/tracker.luau must return a tracker factory", 2)
	end

	return {
		Catalog = catalog,
		Definitions = definitions,
		ByName = catalog.ByName,
		Manifest = copyArray(MANIFEST),
		CreateRuntime = createRuntime,
		CreateCollector = createCollector,
		CreateTracker = createTracker,
		Session = sessionPolicy,
	}
end
