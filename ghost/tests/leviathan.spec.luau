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
switch(itemB, "Blacklight", 0.1, true)
switch(itemB, "Blacklight", 0.4, false)
expect(#results == 0, "switches from different items must not be combined")
expect(#logUpdates == 5 and logUpdates[3].Count == 3 and logUpdates[5].Count == 2,
	"each accepted switch should publish its own per-item rolling array")

switch(itemC, "Laser Projector", 10, false)
switch(itemC, "Laser Projector", 10.4, true)
switch(itemC, "Laser Projector", 10.8, false)
switch(itemC, "Laser Projector", 11.2, true)
switch(itemC, "Laser Projector", 12, false)
expect(#results == 0, "five switches spanning exactly two seconds must not qualify")

switch(itemA, "Spirit Box", 20, false)
switch(itemA, "Spirit Box", 20.4, true)
switch(itemA, "Spirit Box", 20.8, false)
switch(itemA, "Spirit Box", 21.2, true)
switch(itemA, "Spirit Box", 21.6, false)
expect(#results == 1 and results[1].Count == 5
	and math.abs(results[1].Duration - 1.6) < 0.0001,
	"five switches in less than two seconds should resolve the flicker array")
expect(logUpdates[#logUpdates].Completed == true and logUpdates[#logUpdates].Count == 5,
	"the visible five-switch array should mark the qualifying update complete")
expect(Verdict.Confidence[9] == 99 and Verdict.Selected[1] == 9,
	"a completed flicker array should support and select Leviathan")

flicker:Destroy()
leviathan:Destroy()
print("leviathan.spec: per-item five-switch sequence passed")
