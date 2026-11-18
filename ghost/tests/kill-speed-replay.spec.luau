local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSpeedTracker = require("../active-trackers/speed-tracker")
local Aswang = require("../ghosts/Aswang")
local Keres = require("../ghosts/Keres")
local Revenant = require("../ghosts/Revenant")
local captures = require("./fixtures/solo-kill-speed")

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local i = table.find(callbacks, callback)
				if i then table.remove(callbacks, i) end
			end}
		end,
		Fire = function() for _, callback in ipairs(table.clone(callbacks)) do callback() end end,
	}
end

for _, capture in ipairs(captures) do
	local now = 0
	local visibility, changed = signal(), signal()
	local humanoid = {WalkSpeed = 21}
	function humanoid:GetPropertyChangedSignal() return changed end
	local ghost = {Hunting = false, Transparency = 1}
	function ghost:GetAttribute(name) return self[name] end
	function ghost:GetAttributeChangedSignal() return visibility end
	function ghost:FindFirstChildOfClass() return humanoid end
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic})
	local aswang, keres = Aswang.new({Traffic = traffic}), Keres.new({Traffic = traffic})
	local delayed = {}
	local revenant = Revenant.new({Traffic = traffic, Clock = function() return now end,
		Delay = function(seconds, callback) table.insert(delayed, {At = now + seconds, Callback = callback}) end})
	local function runDelayed(untilTime)
		for i = #delayed, 1, -1 do
			local timer = delayed[i]
			if timer.At <= untilTime then
				table.remove(delayed, i) now = timer.At timer.Callback()
			end
		end
		now = untilTime
	end
	local tracker = createSpeedTracker({Traffic = traffic, Ghost = ghost, Clock = function() return now end,
		Workspace = {GetAttribute = function() return 0 end}})
	for _, point in ipairs(capture.Rows) do
		runDelayed(point[1])
		ghost.Transparency = point[4] and 0 or 1
		if point[2] == 1 then
			ghost.Hunting = point[5]
			traffic("HuntingState", {Hunting = point[5], Time = now}):SendTo("SpeedTracker", "Revenant")
		elseif point[2] == 2 then
			visibility:Fire()
		elseif point[2] == 3 then
			humanoid.WalkSpeed = point[3]
			changed:Fire()
		elseif point[2] == 4 then
			traffic("PlayerKilled", {userId = 1, AliveRemaining = 0, Time = now}):SendTo("SpeedTracker", "Revenant")
		end
	end
	runDelayed(now + 2)
	if capture.Index == 1 or capture.Index == 8 then
		assert(verdict.SourceConfidence[capture.Index] == 99,
			capture.Name .. " native solo capture must retain the pre-animation baseline: " .. capture.Job)
	elseif capture.Index == 14 then
		assert(verdict.Confidence[14] == 35, "native solo Revenant's abrupt stop should remain LOW")
	else
		assert(verdict.Confidence[14] == nil, "native Vex kept hunting after death and must not support Revenant")
	end
	tracker:Destroy() aswang:Destroy() keres:Destroy() revenant:Destroy()
end

print("kill-speed-replay.spec: native solo kill-animation timing passed")
