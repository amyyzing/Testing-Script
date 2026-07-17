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
assert(store:Save(settings), "settings should persist")
assert(folders.DemonologyAssistant and files["DemonologyAssistant/Settings.json"],
	"executor persistence path changed")
environment.DemonologyLobbySettings = nil
local reloaded = store:Load()
assert(reloaded.Auto and reloaded.JobSite == "Prison" and reloaded.Challenges[1],
	"saved settings should survive a new execution")

print("settings-store.spec: memory, handoff, and executor-file persistence passed")
