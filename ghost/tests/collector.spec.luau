local createCollector = require("../collector")

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local now = 0
local runtime = {
	Events = {},
	ResetCount = 0,
	Mode = "Normal",
	Destroyed = false,
}

function runtime:Dispatch(hook, event)
	table.insert(self.Events, {Hook = hook, Event = event})
	return true
end

function runtime:Tick(event)
	table.insert(self.Events, {Hook = "Tick", Event = event})
	return true
end

function runtime:Reset()
	self.ResetCount = self.ResetCount + 1
	return true
end

function runtime:SetMode(mode)
	self.Mode = mode
	return true
end

function runtime:Snapshot()
	return {Mode = self.Mode, EventCount = #self.Events}
end

function runtime:Destroy()
	self.Destroyed = true
	return true
end

local collector = createCollector({
	Runtime = runtime,
	Clock = function()
		return now
	end,
	MaxSpeedSamples = 8,
})

local function eventCount(hook)
	local count = 0
	for _, entry in ipairs(runtime.Events) do
		if entry.Hook == hook then
			count = count + 1
		end
	end
	return count
end

local function lastEvent(hook)
	for index = #runtime.Events, 1, -1 do
		local entry = runtime.Events[index]
		if entry.Hook == hook then
			return entry.Event
		end
	end
	return nil
end

-- Hunt lifecycle owns and flushes the shared raw sample buffers.
expect(collector:HuntTransition(true), "hunt start should be accepted")
for index = 1, 6 do
	now = index * 0.1
	expect(collector:SpeedSample({
		Speed = 11 + index,
		Transparency = index % 2,
	}), "valid hunt speed sample should be accepted")
end
expect(eventCount("OnSpeedSample") == 6, "every sample should emit the generic hook")
expect(eventCount("OnHuntSpeedSamples") == 6, "hunt samples should emit buffered speed hooks")
expect(
	#lastEvent("OnTransparencySpeedSamples").Samples == 6,
	"binary transparency samples should share the hunt buffer"
)

now = 1
expect(collector:HuntTransition(false), "hunt end should be accepted")
local completedSpeeds = lastEvent("OnHuntSpeedSamples")
expect(completedSpeeds.HuntEnded == true, "hunt end should flush a completed speed event")
expect(#completedSpeeds.Samples == 6, "hunt-end flush should preserve buffered samples")
expect(lastEvent("OnHuntEnded") ~= nil, "hunt end lifecycle hook should be emitted")
collector:TransparencySample({Transparency = 1, Speed = 13.5})
expect(
	lastEvent("OnTransparencySample").Invisible == true,
	"standalone transparency samples should normalize binary visibility"
)

-- Reset can synchronize to a live hunt without synthesizing a second start.
now = 1.1
expect(
	collector:Reset({Hunting = true, Time = now}),
	"reset should accept an already-active hunt"
)
expect(collector:Snapshot().Hunting == true, "reset should retain the supplied hunt state")
for index = 1, 5 do
	now = 1.1 + index * 0.1
	collector:SpeedSample({
		Time = now,
		Speed = 11 + index * 0.1,
		Invisible = false,
	})
end
local transparencyCount = #collector:Snapshot().TransparencySpeedSamples
collector:TransparencySample({
	Time = now,
	Transparency = 0,
	Speed = 11.5,
})
expect(
	#collector:Snapshot().TransparencySpeedSamples == transparencyCount,
	"a separate phase callback at the same instant should replace rather than duplicate a sample"
)
now = 2
expect(collector:HuntTransition(false), "an adopted live hunt should still close")
expect(
	lastEvent("OnHuntSpeedSamples").HuntEnded == true
		and #lastEvent("OnHuntSpeedSamples").Samples == 5,
	"ending an adopted hunt should flush its complete speed samples"
)
now = 2.1
collector:HuntTransition(true)
collector:TransparencySample({Time = now, Transparency = 1})
expect(
	#collector:Snapshot().TransparencySpeedSamples == 0,
	"a new hunt must not pair transparency with a stale prior-hunt speed"
)
collector:HuntTransition(false)

-- Feed methods normalize aliases and route only explicit classifications.
collector:RoomPresence({
	InsideFavorite = true,
	FavoriteRoom = "Classroom",
	Outcome = "Residence",
})
expect(lastEvent("OnRoomPresence").InsideFavourite == true, "room alias should normalize")
expect(lastEvent("OnFavouriteResidence") ~= nil, "explicit residence should route")

collector:Salt({Disturbed = false, SpeedOutcome = "Recovered"})
expect(lastEvent("OnSaltContact").Disturbed == false, "salt contact should preserve disturbance")
expect(lastEvent("OnSaltSpeed").Outcome == "Recovered", "salt speed outcome should route")

collector:HolyOil({ColorKind = "Spirit", WallOutcome = "PassThrough"})
expect(lastEvent("OnHolyOilColor").Kind == "Spirit", "Holy Oil color should route")
expect(lastEvent("OnHolyOilWall").Outcome == "PassThrough", "Holy Oil wall should route")

collector:Cross({Outcome = "Matched"})
expect(lastEvent("OnCrossMotion").Outcome == "Matched", "Cross outcome should route")

collector:ItemToggle({ElectronicDisabled = true})
expect(lastEvent("OnElectronicDisabled") ~= nil, "electronic disable should route")
collector:LightToggle({ClueKind = "LightOff"})
expect(lastEvent("OnClue").Kind == "LightOff", "explicit light clue should route")

collector:ObjectTeleport({Smoke = true})
collector:GhostTeleport({Reason = "room-to-room"})
expect(lastEvent("OnObjectTeleport").Smoke == true, "object teleport should route")
expect(lastEvent("OnGhostTeleport").Reason == "room-to-room", "ghost teleport should route")

now = 2
collector:Glass({})
now = 3
collector:Glass({})
expect(lastEvent("OnBrokenGlassBurst").Count == 2, "glass feed should aggregate its raw window")
now = 5.6
collector:Glass({})
expect(lastEvent("OnBrokenGlassBurst").Count == 1, "expired glass events should leave the window")

collector:SpiritBox({Humming = true})
expect(lastEvent("OnSpiritBox").Kind == "Humming", "Spirit Box aliases should normalize")

-- Automation suppression is intentionally limited to item/light callbacks.
now = 10
collector:SuppressAutomation(1, "scripted room setup")
local lightCount = eventCount("OnLightToggle")
expect(not collector:LightToggle({State = false}), "suppressed light callback should be ignored")
expect(eventCount("OnLightToggle") == lightCount, "ignored light should not reach runtime")
expect(collector:Salt({Disturbed = true}), "suppression must not hide unrelated salt data")
now = 11.1
expect(collector:LightToggle({State = true}), "timed suppression should expire")

collector:SetMode("Mimicry")
expect(runtime.Mode == "Mimicry", "mode should propagate to runtime")
collector:Reset({PreserveSuppression = false})
expect(runtime.ResetCount == 2, "every reset should propagate to runtime")
expect(collector:Snapshot().Runtime.Mode == "Mimicry", "snapshot should include runtime state")

-- Connections are owned by the collector and cannot fire after destruction.
local signal = {Callback = nil, Connection = nil}
function signal:Connect(callback)
	self.Callback = callback
	local connection = {Connected = true}
	function connection:Disconnect()
		self.Connected = false
	end
	self.Connection = connection
	return connection
end
function signal:Fire(...)
	if self.Connection and self.Connection.Connected then
		self.Callback(...)
	end
end

collector:Bind(signal, function(activeCollector, event)
	activeCollector:SpiritBox(event)
end)
signal:Fire({Female = true})
expect(lastEvent("OnSpiritBox").Kind == "Female", "bound adapter should feed collector")

expect(collector:Destroy(), "first destroy should succeed")
expect(signal.Connection.Connected == false, "destroy should disconnect owned connections")
expect(runtime.Destroyed == true, "destroy should propagate to owned runtime")
local spiritBoxCount = eventCount("OnSpiritBox")
signal:Fire({Humming = true})
expect(eventCount("OnSpiritBox") == spiritBoxCount, "destroyed bindings must remain inert")
expect(not collector:Destroy(), "destroy should be idempotent")
expect(not collector:Tick({}), "destroyed collector should reject events")

print("collector.spec.luau: ok")
