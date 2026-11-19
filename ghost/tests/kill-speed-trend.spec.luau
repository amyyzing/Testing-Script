local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createTracker = require("../active-trackers/speed-tracker")
local Aswang = require("../ghosts/Aswang")
local Keres = require("../ghosts/Keres")
local Dullahan = require("../ghosts/Dullahan")

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function() end}
		end,
		Fire = function() for _, callback in ipairs(callbacks) do callback() end end,
	}
end

for _, direction in ipairs({1, -1}) do
	local changed, visibility = signal(), signal()
	local now = 0
	local humanoid = {WalkSpeed = 21}
	function humanoid:GetPropertyChangedSignal() return changed end
	local ghost = {Transparency = 0}
	function ghost:GetAttribute(name) return self[name] end
	function ghost:FindFirstChildOfClass() return humanoid end
	function ghost:GetAttributeChangedSignal() return visibility end
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic})
	local aswang, keres = Aswang.new({Traffic = traffic}), Keres.new({Traffic = traffic})
	local dullahan = Dullahan.new({Traffic = traffic})
	local tracker = createTracker({Traffic = traffic, Ghost = ghost,
		Clock = function() return now end, Workspace = {GetAttribute = function() return 100 end}})
	traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
	-- The increasing case follows Dullahan's native 0.1-per-second ramp.
	-- The kill notification is delayed and the ramp then stops, without a kill bonus.
	for i = 1, 40 do
		now = i * 0.2
		humanoid.WalkSpeed = 21 + direction * i * 0.02
		changed:Fire()
		ghost.Transparency = i % 2
		visibility:Fire()
	end
	now += 1.1
	traffic("PlayerKilled", {Time = now, userId = 1}):SendTo("SpeedTracker")
	for _, transparency in ipairs({1, 0, 1, 0}) do
		now += 0.2 ghost.Transparency = transparency visibility:Fire()
	end
	traffic("HuntingState", {Hunting = false}):SendTo("SpeedTracker")
	assert(verdict.SourceConfidence[1] == nil and verdict.SourceConfidence[8] == nil,
		"ordinary small speed steps near a delayed kill must not identify Aswang or Keres")
	assert(not table.find(verdict.RuledOut, 1) and not table.find(verdict.RuledOut, 8),
		"a confounded kill window must remain inconclusive, including at hunt end")
	if direction == 1 then
		assert(verdict.SourceConfidence[4] == 95, "the control must actually exercise Dullahan's ramp detector")
	end
	tracker:Destroy() aswang:Destroy() keres:Destroy() dullahan:Destroy()
end

print("kill-speed-trend.spec: gradual ramps cannot masquerade as discrete kill changes")
