local NAMES = {
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

local Catalog = {Names = NAMES, Paths = {}}
for index, name in ipairs(NAMES) do
	Catalog.Paths[index] = "ghost/" .. name .. ".luau"
end

function Catalog.Load(loadModule)
	assert(type(loadModule) == "function", "Catalog.Load requires a module loader")
	local profiles, byName = {}, {}
	for index, path in ipairs(Catalog.Paths) do
		local profile = loadModule(path)
		assert(type(profile) == "table", path .. " must return a profile table")
		assert(profile.Name == NAMES[index], path .. " returned the wrong profile name")
		assert(type(profile.CreateObserver) == "function", path .. " must expose CreateObserver(api)")
		profiles[index], byName[profile.Name] = profile, profile
	end
	return profiles, byName
end

return Catalog
