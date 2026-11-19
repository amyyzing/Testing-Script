local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createTracker = require("../active-trackers/native-events")
local Leviathan = require("../ghosts/Leviathan")
local Spirit = require("../ghosts/Spirit")
local Doppelganger = require("../ghosts/Doppelganger")
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end
local added = signal()
local objects = {}
local world = {DescendantAdded = added, GetDescendants = function() return objects end}
local function object(name, parent, attrs)
	local signals = {}
	local obj = {Name = name, Parent = parent, Attrs = attrs or {}}
	function obj:IsA(kind) return kind == "Model" end
	function obj:IsDescendantOf(root) return root == world and self.Outside ~= true end
	function obj:GetAttribute(key) return self.Attrs[key] end
	function obj:GetAttributeChangedSignal(key)
		signals[key] = signals[key] or signal()
		return signals[key]
	end
	function obj:SetAttribute(key, value)
		self.Attrs[key] = value
		self:GetAttributeChangedSignal(key):Fire()
	end
	table.insert(objects, obj)
	return obj
end
local glassFolder = {Name = "BrokenGlass"}
object("BrokenGlass", glassFolder)
local box = object("Box", {Name = "Items"}, {ItemName = "Spirit Box"})
local traffic = createTraffic()
local verdict = createVerdict({Traffic = traffic})
local glassResult, glassSignals
glassSignals = 0
traffic:Receive("Banshee", function() glassSignals += 1 end)
traffic:Receive("Verdict", function(signal, payload)
	if signal == "Support" and payload.Ghost == "Banshee" then glassResult = payload end
end)
local processors = {Leviathan.new({Traffic = traffic}),
	Spirit.new({Traffic = traffic}), Doppelganger.new({Traffic = traffic})}
local now = 0
local tracker = createTracker({Traffic = traffic, Workspace = world, Clock = function() return now end})
local firstPlays = 0
traffic:Receive("MusicBoxStun", function(signal)
	if signal == "MusicBoxFirstPlay" then firstPlays += 1 end
end)
local used = object("UsedMusicBox", {Name = "Items"}, {ItemName = "Music Box", HasBeenPlayed = true})
added:Fire(used)
assert(firstPlays == 0, "an already-used Music Box cannot replay a timed first-play cue")
local music = object("MusicBox", {Name = "Items"}, {ItemName = "Music Box"})
added:Fire(music)
music:SetAttribute("HasBeenPlayed", true)
music:SetAttribute("HasBeenPlayed", true)
assert(firstPlays == 1, "the actual first-play transition must publish once")
local staleMusic = object("StaleMusic", {Name = "Items"}, {ItemName = "Music Box"})
added:Fire(staleMusic)
staleMusic.Outside = true
staleMusic:SetAttribute("HasBeenPlayed", true)
staleMusic.Outside = false
added:Fire(staleMusic)
assert(firstPlays == 1, "re-entry must not turn an old first play into a fresh timed cue")
assert(verdict.Confidence[2] == nil, "existing glass must not count as a fresh burst")
added:Fire(object("BrokenGlass", glassFolder))
assert(verdict.Confidence[2] == nil, "one new glass model is not a burst")
now = 1
added:Fire(object("BrokenGlass", glassFolder))
assert(verdict.Confidence[2] == nil and glassResult == nil and glassSignals == 0,
	"repeated broken glass must not publish a Banshee guess or perk")
box:SetAttribute("LeviathanGlitch", 123)
assert((verdict.Confidence[9] == 65 and verdict.SourceConfidence[9] == 99), "native glitch must reach the Leviathan processor")
local candle = object("Lantern", {Name = "Interactables"})
added:Fire(candle)
candle:SetAttribute("SpiritCandle", true)
assert(verdict.Confidence[17] == 60 and verdict.Confidence[19] == 60,
	"shared candle ability must support both Spirit and Doppelganger")
local returned = object("ReturnedLantern", {Name = "Items"}, {ItemName = "Lantern"})
added:Fire(returned)
local candleEvents, glitchEvents = 0, 0
local disconnectCandle = traffic:Receive("Spirit", function(signal)
	if signal == "SpiritCandle" then candleEvents += 1 end
end)
local disconnectGlitch = traffic:Receive("Leviathan", function(signal)
	if signal == "NativeGlitch" then glitchEvents += 1 end
end)
returned.Outside = true
returned:SetAttribute("SpiritCandle", true)
returned:SetAttribute("LeviathanGlitch", 456)
assert(candleEvents == 0 and glitchEvents == 0, "out-of-world item changes must not qualify")
returned.Outside = false
added:Fire(returned)
assert(candleEvents == 1 and glitchEvents == 1,
	"returning items must refresh native attributes changed while outside Workspace")
added:Fire(returned)
returned:SetAttribute("SpiritCandle", true)
assert(candleEvents == 1 and glitchEvents == 1, "re-entry must not duplicate already observed cues")
returned:SetAttribute("LeviathanGlitch", 789)
assert(glitchEvents == 2, "re-entry must retain one live listener for later native changes")
disconnectCandle()disconnectGlitch()
tracker:Destroy()
for _, processor in ipairs(processors) do processor:Destroy() end
print("native-events.spec: ambiguous glass ignored; native glitch and shared candle observations passed")
