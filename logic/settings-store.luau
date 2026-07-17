local DIRECTORY = "DemonologyAssistant"
local FILE = DIRECTORY .. "/Settings.json"

local function copySettings(source)
	source = type(source) == "table" and source or {}
	local challenges = type(source.Challenges) == "table" and source.Challenges or {}
	return {
		Auto = source.Auto == true,
		JobSite = type(source.JobSite) == "string" and source.JobSite or "School",
		Difficulty = type(source.Difficulty) == "string" and source.Difficulty or "Nightmare",
		CustomPreset = type(source.CustomPreset) == "string" and source.CustomPreset or "",
		EquipmentPreset = type(source.EquipmentPreset) == "string" and source.EquipmentPreset or "green",
		GhostWalkSpeedMultiplier = tonumber(source.GhostWalkSpeedMultiplier),
		Challenges = {challenges[1] == true, challenges[2] == true, challenges[3] == true},
		ChallengesConfigured = source.ChallengesConfigured == true,
	}
end

return function(dependencies)
	local environment = dependencies.Environment or _G
	local HttpService = assert(dependencies.HttpService, "settings-store requires HttpService")
	local function api(name)
		if type(environment[name]) == "function" then return environment[name] end
		for _, namespaceName in ipairs({"syn", "fluxus", "krnl"}) do
			local namespace = environment[namespaceName]
			if type(namespace) == "table" and type(namespace[name]) == "function" then
				return namespace[name]
			end
		end
		return nil
	end
	local readFile, writeFile = api("readfile"), api("writefile")
	local isFile, isFolder, makeFolder = api("isfile"), api("isfolder"), api("makefolder")
	local store = {Path = FILE}

	function store:Load(handoff)
		local loaded
		if type(readFile) == "function" then
			local exists = true
			if type(isFile) == "function" then
				local ok, value = pcall(isFile, FILE)
				exists = ok and value == true
			end
			if exists then
				local ok, source = pcall(readFile, FILE)
				if ok and type(source) == "string" then
					local decoded, value = pcall(HttpService.JSONDecode, HttpService, source)
					if decoded and type(value) == "table" then loaded = value end
				end
			end
		end
		loaded = loaded or environment.DemonologyLobbySettings or handoff or {}
		if type(handoff) == "table" then
			for key, value in pairs(handoff) do loaded[key] = value end
		end
		local settings = copySettings(loaded)
		environment.DemonologyLobbySettings = settings
		return settings
	end

	function store:Save(settings)
		settings = copySettings(settings)
		environment.DemonologyLobbySettings = settings
		if type(writeFile) ~= "function" then return true end
		if type(makeFolder) == "function" then
			local exists = false
			if type(isFolder) == "function" then
				local ok, value = pcall(isFolder, DIRECTORY)
				exists = ok and value == true
			end
			if not exists then pcall(makeFolder, DIRECTORY) end
		end
		local encoded, source = pcall(HttpService.JSONEncode, HttpService, settings)
		if not encoded then return false, tostring(source) end
		local written, failure = pcall(writeFile, FILE, source)
		return written, written and nil or tostring(failure)
	end

	return store
end
