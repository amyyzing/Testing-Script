local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createTracker = require("../dormant-trackers/music-box-stun")
local Dybbuk = require("../ghosts/Dybbuk")

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
		Fire = function(_, ...) for _, callback in ipairs(table.clone(callbacks)) do callback(...) end end,
		Count = function() return #callbacks end,
	}
end

local function harness(base)
	local now = 0
	local changed, heartbeat = signal(), signal()
	local humanoid = {Parent = true, WalkSpeed = base or 21, AncestryChanged = signal()}
	function humanoid:GetPropertyChangedSignal() return changed end
	local ghost = {Parent = true, Hunting = false, AncestryChanged = signal()}
	function ghost:GetAttribute(name) return name == "Hunting" and self.Hunting end
	function ghost:FindFirstChildOfClass() return humanoid end
	local box = {Parent = true, AncestryChanged = signal()}
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic})
	local processor = Dybbuk.new({Traffic = traffic})
	local tracker = createTracker({Traffic = traffic, Ghost = ghost,
		RunService = {Heartbeat = heartbeat}, Clock = function() return now end})
	local h = {Verdict = verdict, Tracker = tracker, Ghost = ghost, Box = box, Humanoid = humanoid}
	assert(heartbeat:Count() == 0, "idle Music Box observation must not run Heartbeat")
	function h:Play(other) traffic("MusicBoxFirstPlay", {MusicBox = other or box}):SendTo("MusicBoxStun") end
	function h:Speed(speed) humanoid.WalkSpeed = speed changed:Fire() end
	function h:Step(seconds) now += seconds heartbeat:Fire() end
	function h:Destroy() tracker:Destroy() processor:Destroy() end
	function h:Unresolved(message)
		assert(verdict.Confidence[5] == nil and not table.find(verdict.RuledOut, 5), message)
		self:Destroy()
	end
	return h
end

for _, base in ipairs({5.25, 10.5, 21}) do
	local h = harness(base)
	h:Speed(base / 10.5) -- Native 21 -> 2; scale-independent comparison.
	h:Play()
	h:Step(3)
	h:Speed(base)
	assert(h.Verdict.SourceConfidence[5] == 95 and h.Verdict.Confidence[5] == 65,
		"first play with a deep three-second speed drop and recovery should support Dybbuk at medium")
	assert(not h.Tracker.Running, "a confirmed Music Box signature should release its watchers")
	h:Destroy()
end

local reordered = harness()
reordered:Play()
reordered:Step(0.05)
reordered:Speed(2)
reordered:Step(3)
reordered:Speed(21)
assert(reordered.Verdict.SourceConfidence[5] == 95, "either native replication order must work")
reordered:Destroy()

local ordinary = harness()
ordinary:Play()
ordinary:Step(5)
ordinary:Unresolved("an ordinary ghost remaining at normal speed cannot identify or rule out Dybbuk")

local salt = harness()
salt:Play()
salt:Speed(15.75)
salt:Step(3)
salt:Speed(21)
salt:Unresolved("a normal 25 percent salt slowdown is not a Music Box stun")

local old = harness()
old:Speed(2)
old:Step(1)
old:Play()
old:Step(3)
old:Speed(21)
old:Unresolved("a speed drop before first play cannot be attributed to the Music Box")

for _, duration in ipairs({1, 4}) do
	local h = harness()
	h:Play() h:Speed(2) h:Step(duration) h:Speed(21)
	h:Unresolved("a short or overlong slowdown must remain inconclusive")
end

for _, cause in ipairs({"hunt", "box", "ghost", "humanoid", "drift", "overlap"}) do
	local h = harness()
	h:Play() h:Speed(2)
	if cause == "hunt" then h.Ghost.Hunting = true
	elseif cause == "drift" then h:Speed(3)
	elseif cause == "overlap" then h:Play({Parent = true, AncestryChanged = signal()})
	else
		local object = cause == "box" and h.Box or cause == "ghost" and h.Ghost or h.Humanoid
		object.Parent = nil object.AncestryChanged:Fire() object.Parent = true
	end
	h:Step(3) h:Speed(21)
	h:Unresolved("an interrupted or confounded observation must not identify Dybbuk: " .. cause)
end

print("music-box.spec: timed first-play response, ordinary control and interruptions passed")
