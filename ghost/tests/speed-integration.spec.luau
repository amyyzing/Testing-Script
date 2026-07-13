local createCollector = require("../collector")
local createRuntime = require("../runtime")

local definitions = {
	require("../Dullahan"),
	require("../Oni"),
	require("../Phantom"),
	require("../Wendigo"),
}

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local api = {
	Detections = {},
	RuleOuts = {},
	CurrentMode = "Normal",
	RefreshCount = 0,
}

function api:Detect(name, reason, confidence, source)
	if self.RuleOuts[name] ~= nil then
		return false
	end
	local score = tonumber(confidence) or 0
	local previous = self.Detections[name]
	local previousScore = type(previous) == "table"
		and tonumber(previous.Confidence)
		or tonumber(previous)
		or 0
	if previous == nil or score >= previousScore then
		self.Detections[name] = {
			Ghost = name,
			Reason = reason,
			Confidence = score,
			Source = source,
		}
		return true
	end
	return false
end

function api:RuleOut(name, reason, confidence)
	self.RuleOuts[name] = {
		Reason = reason,
		Confidence = tonumber(confidence) or 0,
	}
	self.Detections[name] = nil
	return true
end

function api:ClearDetection(name)
	local changed = self.Detections[name] ~= nil
	self.Detections[name] = nil
	return changed
end

function api:ClearRuleOut(name)
	local changed = self.RuleOuts[name] ~= nil
	self.RuleOuts[name] = nil
	return changed
end

function api:GetDetection(name)
	return self.Detections[name]
end

function api:SetDetection(name, value)
	self.Detections[name] = value
	return true
end

function api:IsRuledOut(name)
	return self.RuleOuts[name] ~= nil
end

function api:MarkPersistent(name)
	local detection = self.Detections[name]
	if type(detection) ~= "table" then
		return false
	end
	detection.Persistent = true
	return true
end

function api:SupportsConfirmedEvidence()
	return false
end

function api:Mode()
	return self.CurrentMode
end

function api:Refresh()
	self.RefreshCount = self.RefreshCount + 1
end

local collector
local runtime = createRuntime({
	Definitions = definitions,
	Api = api,
	Mode = api.CurrentMode,
	OnAction = function(action)
		if type(action) == "table" and action.Type == "Dispatch" then
			return collector:Dispatch(action.Hook, action.Event)
		end
		return false
	end,
	OnError = function(message)
		error(message, 0)
	end,
})

local now = 0
collector = createCollector({
	Runtime = runtime,
	Clock = function()
		return now
	end,
})

local function reset(hunting)
	table.clear(api.Detections)
	table.clear(api.RuleOuts)
	api.RefreshCount = 0
	collector:Reset({
		Hunting = hunting == true,
		Time = now,
		PreserveFindings = false,
	})
end

local function speedSample(time, speed, invisible, mapFactor)
	now = time
	collector:SpeedSample({
		Time = time,
		GhostWalkSpeed = speed,
		Invisible = invisible,
		MapFactor = mapFactor or 1,
		ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
	})
end

-- Attaching during a hunt must still close and evaluate that hunt.
reset(true)
for index, speed in ipairs({11, 11.2, 11.1, 11.3, 11.3}) do
	speedSample((index - 1) * 0.1, speed, false)
end
now = 0.5
expect(collector:HuntTransition(false), "an adopted hunt should close")
expect(
	api.RuleOuts.Dullahan and api.RuleOuts.Dullahan.Confidence == 92,
	"closing an adopted hunt should deliver Dullahan's qualified negative"
)

-- A definitive Dullahan result supersedes an earlier Wendigo speed result.
reset(true)
api.Detections.Wendigo = {Confidence = 99, Reason = "earlier transition curve"}
for index, speed in ipairs({11, 11.2, 11.1, 11.3, 11.4}) do
	speedSample(1 + (index - 1) * 0.1, speed, false)
end
expect(api.Detections.Dullahan ~= nil, "three short upward steps should detect Dullahan")
expect(api.Detections.Wendigo == nil, "Dullahan should clear the rival Wendigo result")

-- Oni uses only recent, explicitly visible samples.
reset(true)
for index = 1, 4 do
	speedSample(2 + index * 0.1, 23.1, nil, 1.05)
end
expect(
	api.Detections.Oni == nil and api.RuleOuts.Oni == nil,
	"unknown visibility must not be classified as an Oni-visible sample"
)
reset(true)
speedSample(0, 40, false, 1.05)
for index = 1, 3 do
	speedSample(4 + index * 0.1, 28.35, false, 1.05)
end
expect(
	api.Detections.Oni and api.Detections.Oni.Confidence == 95,
	"an old outlier must not contaminate Oni's recent stable window"
)

-- Phantom receives settled binary phases through the combined speed feed.
reset(true)
local phantomTime = 0
for _, phase in ipairs({
	{Invisible = false, Speed = 11},
	{Invisible = true, Speed = 13.5},
	{Invisible = false, Speed = 11},
	{Invisible = true, Speed = 13.5},
	{Invisible = false, Speed = 11},
}) do
	for _ = 1, 3 do
		speedSample(phantomTime, phase.Speed, phase.Invisible)
		phantomTime = phantomTime + 0.1
	end
end
expect(
	api.Detections.Phantom and api.Detections.Phantom.Confidence == 99,
	"two settled visible/invisible cycles should detect Phantom end to end"
)

-- Wendigo requires a multi-transition slope, not an isolated or equal-sanity fit.
reset(false)
for index, snapshot in ipairs({
	{Sanity = 50, Speed = 18.1125, Hunting = true},
	{Sanity = 40, Speed = 18.9, Hunting = false},
	{Sanity = 30, Speed = 19.6875, Hunting = true},
}) do
	now = 10 + index
	collector:HuntTransitionSample({
		Time = now,
		Sanity = snapshot.Sanity,
		Speed = snapshot.Speed,
		Hunting = snapshot.Hunting,
		MapFactor = 1.05,
		ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
	})
end
expect(api.Detections.Wendigo ~= nil, "a fixed-multiplier sanity/speed slope should detect Wendigo")

reset(false)
collector:HuntTransitionSample({Sanity = 0, Speed = 13.75, Hunting = true})
expect(
	api.Detections.Wendigo == nil and api.RuleOuts.Wendigo == nil,
	"one low-sanity multiplier fit must remain inconclusive"
)
for index, hunting in ipairs({true, false, true}) do
	collector:HuntTransitionSample({
		Time = 20 + index,
		Sanity = 60,
		Speed = 11,
		Hunting = hunting,
	})
end
expect(
	api.Detections.Wendigo == nil and api.RuleOuts.Wendigo == nil,
	"equal-sanity transitions must remain inconclusive"
)

collector:Destroy()
print("speed-integration.spec.luau: ok")
