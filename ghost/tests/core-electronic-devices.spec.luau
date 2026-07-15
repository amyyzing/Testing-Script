local Events = require("../events")
local Specification = require("../specification")
local ElectronicDevices = require("../trackers/dormant/electronic-devices")({
	Events = Events,
	Specification = Specification,
})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function countType(events, kind)
	local count = 0
	for _, event in ipairs(events) do
		if event.Type == kind then count = count + 1 end
	end
	return count
end

local function sendToggle(tracker, object, model, itemName, index, options)
	options = options or {}
	local enabled = index % 2 == 1
	return tracker:OnEvent({
		Type = "ElectronicEnabledChanged",
		Object = object,
		Model = model,
		ItemName = itemName,
		Previous = not enabled,
		Enabled = enabled,
		Time = options.Time or ((index - 1) * 0.3),
		Hunting = options.Hunting == true,
		GhostDistance = options.GhostDistance or 5,
		NearestPlayerDistance = options.NearestPlayerDistance ~= nil
			and options.NearestPlayerDistance or 10,
		AutomationCaused = options.AutomationCaused,
		FuseCaused = options.FuseCaused,
		PlayerCaused = options.PlayerCaused,
	})
end

-- Leviathan is one eligible device and seven clean alternating toggles inside
-- the canonical 2.5-second window. Hunt state is deliberately irrelevant.
do
	local emitted = {}
	local tracker = ElectronicDevices.new()
	tracker:Start({Emit = function(event) table.insert(emitted, event) end})
	local object, model = {}, {}
	for index = 1, 3 do
		sendToggle(tracker, object, model, "Spirit Box", index, {Hunting = false})
	end
	tracker:OnEvent({Type = Events.Types.HuntStarted, HuntId = "transition"})
	for index = 4, 7 do
		sendToggle(tracker, object, model, "Spirit Box", index, {Hunting = true})
	end
	expect(countType(emitted, Events.Types.DeviceToggleBurst) == 1,
		"seven alternating Spirit Box toggles in 1.8 seconds must emit Leviathan once")
	local burst = emitted[1]
	expect(burst.Payload.SingleDevice == true and burst.Payload.Alternating == true
		and burst.Payload.ToggleCount == 7
		and math.abs(burst.Payload.Duration - 1.8) < 1e-9,
		"Leviathan output must retain the qualifying device and exact clean window")
	sendToggle(tracker, object, model, "Spirit Box", 8, {Time = 2.1, Hunting = true})
	expect(#emitted == 1, "a qualified device must not repeatedly spam Leviathan")
	tracker:Destroy()
end

-- Coherent changes on distinct physical devices are global flicker, not one
-- clean Leviathan stream, even though hunt state itself is not a gate.
do
	local emitted = {}
	local tracker = ElectronicDevices.new()
	tracker:Start({Emit = function(event) table.insert(emitted, event) end})
	local firstObject, secondObject = {}, {}
	local firstModel, secondModel = {}, {}
	for index = 1, 7 do
		local time = (index - 1) * 0.3
		sendToggle(tracker, firstObject, firstModel, "Spirit Box", index, {Time = time})
		sendToggle(tracker, secondObject, secondModel, "Blacklight", index, {Time = time})
	end
	expect(countType(emitted, Events.Types.DeviceToggleBurst) == 0,
		"coherent multi-device global flicker must not qualify Leviathan")
	tracker:Destroy()
end

-- Ineligible equipment and automation/fuse/player-caused changes cannot leak
-- into a clean Leviathan sequence.
do
	local emitted = {}
	local tracker = ElectronicDevices.new()
	tracker:Start({Emit = function(event) table.insert(emitted, event) end})
	local object, model = {}, {}
	for index = 1, 7 do sendToggle(tracker, object, model, "Video Camera", index) end
	expect(#emitted == 0, "Video Camera is not an eligible Leviathan device")
	for index = 1, 3 do sendToggle(tracker, object, model, "Blacklight", index, {Time = 3 + index * 0.1}) end
	sendToggle(tracker, object, model, "Blacklight", 4, {Time = 3.4, AutomationCaused = true})
	for index = 1, 6 do sendToggle(tracker, object, model, "Blacklight", index, {Time = 3.4 + index * 0.1}) end
	expect(#emitted == 0, "a suppressed mutation must break, not join, a rapid sequence")
	sendToggle(tracker, object, model, "Blacklight", 7, {Time = 4.1})
	expect(countType(emitted, Events.Types.DeviceToggleBurst) == 1,
		"seven clean toggles after suppression must form a new Leviathan window")
	tracker:Destroy()
end

-- Ghoul's negative is a true-to-false transition with every living player
-- farther than fifteen studs; hunt state is not part of the contract.
do
	local emitted = {}
	local tracker = ElectronicDevices.new()
	tracker:Start({Emit = function(event) table.insert(emitted, event) end})
	local object, model = {}, {}
	sendToggle(tracker, object, model, "EMF Reader", 2, {
		Hunting = false,
		GhostDistance = 5,
		NearestPlayerDistance = 15,
	})
	expect(#emitted == 0, "a player exactly fifteen studs away must block Ghoul")
	sendToggle(tracker, object, model, "EMF Reader", 2, {
		Time = 1,
		Hunting = false,
		GhostDistance = 5,
		NearestPlayerDistance = 15.01,
	})
	expect(countType(emitted, Events.Types.HuntElectronicDisabled) == 1,
		"a non-hunt disable with no player within fifteen studs must emit once")
	local result = emitted[1]
	expect(result.Payload.NoPlayerWithin15 == true and result.Payload.Qualified == true,
		"Ghoul output must preserve the strict player-distance qualifier")
	tracker:Stop()
	tracker:Start({Emit = function(event) table.insert(emitted, event) end})
	expect(tracker:Snapshot().Status == "Dormant",
		"Start after Stop must rebuild electronic connections and windows")
	tracker:Destroy()
end

do
	local emitted = {}
	local tracker = ElectronicDevices.new()
	tracker:Start({Emit = function(event) table.insert(emitted, event) end})
	sendToggle(tracker, {}, {}, "EMF Reader", 2, {
		Hunting = false,
		GhostDistance = 1000,
		NearestPlayerDistance = 15.01,
	})
	expect(countType(emitted, Events.Types.HuntElectronicDisabled) == 1,
		"Ghoul depends only on all players being strictly beyond fifteen studs, not a ghost-distance gate")
	tracker:Destroy()
end

print("core-electronic-devices.spec: Leviathan and Ghoul electronic contracts passed")
