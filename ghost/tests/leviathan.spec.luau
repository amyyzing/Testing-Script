local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createFlickerArray = require("../filter/flicker-array")
local Leviathan = require("../ghosts/Leviathan")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local leviathan = Leviathan.new({Traffic = Traffic})
local flicker = createFlickerArray({Traffic = Traffic})
local results = {}
local logUpdates = {}
Traffic:Receive("Leviathan", function(signal, payload)
	if signal == "FlickerArrayResult" then table.insert(results, payload) end
end)
Traffic:Receive("FlickerArrayLog", function(signal, payload)
	if signal == "FlickerArrayUpdate" then table.insert(logUpdates, payload) end
end)

local itemA, itemB, itemC = {}, {}, {}
local function switch(item, itemName, time, current)
	Traffic("ItemStateChanged", {
		Item = item,
		ItemName = itemName,
		Previous = not current,
		Current = current,
		Time = time,
	}):SendTo("FlickerArray")
end

switch(itemA, "Spirit Box", 0, false)
switch(itemA, "Spirit Box", 0.3, true)
switch(itemA, "Spirit Box", 0.6, false)
switch(itemA, "Spirit Box", 0.9, true)
switch(itemB, "Blacklight", 0.1, true)
switch(itemB, "Blacklight", 0.4, false)
switch(itemB, "Blacklight", 0.7, true)
expect(#results == 0, "switches from different items must not be combined")
expect(#logUpdates == 7 and logUpdates[4].Count == 4 and logUpdates[7].Count == 3,
	"each accepted switch should publish its own per-item rolling array")

switch(itemC, "Laser Projector", 10, false)
switch(itemC, "Laser Projector", 10.3, true)
switch(itemC, "Laser Projector", 10.6, false)
switch(itemC, "Laser Projector", 10.9, true)
switch(itemC, "Laser Projector", 11.2, false)
switch(itemC, "Laser Projector", 11.5, true)
switch(itemC, "Laser Projector", 12, false)
expect(#results == 0, "seven switches spanning exactly two seconds must not qualify")

switch(itemA, "Spirit Box", 20, false)
switch(itemA, "Spirit Box", 20.3, true)
switch(itemA, "Spirit Box", 20.6, false)
switch(itemA, "Spirit Box", 20.9, true)
switch(itemA, "Spirit Box", 21.2, false)
switch(itemA, "Spirit Box", 21.5, true)
switch(itemA, "Spirit Box", 21.8, false)
expect(#results == 1 and results[1].Count == 7
	and math.abs(results[1].Duration - 1.8) < 0.0001,
	"seven switches in less than two seconds should resolve the flicker array")
expect(logUpdates[#logUpdates].Completed == true and logUpdates[#logUpdates].Count == 7,
	"the visible seven-switch array should mark the qualifying update complete")
expect(Verdict.Confidence[9] == 99 and Verdict.Selected[1] == 9,
	"a completed flicker array should support and select Leviathan")

flicker:Destroy()
leviathan:Destroy()
print("leviathan.spec: per-item seven-switch sequence passed")
