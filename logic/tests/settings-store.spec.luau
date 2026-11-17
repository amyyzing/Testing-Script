local createStore = require("../settings-store")

local files, folders = {}, {}
local environment = {
	isfile = function(path) return files[path] ~= nil end,
	isfolder = function(path) return folders[path] == true end,
	makefolder = function(path) folders[path] = true end,
	readfile = function(path) return files[path] end,
	writefile = function(path, source) files[path] = source end,
}
local encodedSettings
local HttpService = {
	JSONEncode = function(_, value) encodedSettings = value return "encoded" end,
	JSONDecode = function() return encodedSettings end,
}
local store = createStore({Environment = environment, HttpService = HttpService})
local settings = store:Load({Auto = true, JobSite = "Prison", Challenges = {true, false, true}})
assert(settings.Auto and settings.JobSite == "Prison" and settings.Challenges[3],
	"handoff settings should load when no file exists")
local saved, saveError = store:Save(settings)
assert(saved and saveError == nil, "successful saves should have no error")
assert(folders.DemonologyAssistant and files["DemonologyAssistant/Settings.json"],
	"executor persistence path changed")
environment.DemonologyLobbySettings = nil
local reloaded = store:Load()
assert(reloaded.Auto and reloaded.JobSite == "Prison" and reloaded.Challenges[1],
	"saved settings should survive a new execution")
environment.writefile = function() error("disk write failed", 0) end
local failingStore = createStore({Environment = environment, HttpService = HttpService})
saved, saveError = failingStore:Save(settings)
assert(saved == false and saveError == "disk write failed", "failed saves should return the error")

local memoryOnly = createStore({Environment = {}, HttpService = HttpService})
local defaults = memoryOnly:Load()
assert(defaults.EquipmentPreset == "Current equipment" and defaults.JobSite == "",
	"new accounts should use their current equipment and discover an available map")
local handoff = table.freeze({JobSite = "Catacombs"})
local fromHandoff = memoryOnly:Load(handoff)
assert(fromHandoff.JobSite == "Catacombs", "an immutable handoff should load")

local invalidCache = createStore({
	Environment = {DemonologyLobbySettings = "invalid"},
	HttpService = HttpService,
})
assert(invalidCache:Load(handoff).JobSite == "Catacombs",
	"an invalid cached setting should not block a handoff")

print("settings-store.spec: memory, handoff, and executor-file persistence passed")
