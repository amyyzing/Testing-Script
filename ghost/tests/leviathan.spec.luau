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
Traffic:Receive("Leviathan", function(signal, payload)
	if signal == "FlickerArrayResult" then table.insert(results, payload) end
end)

local itemA, itemB = {}, {}
local function switch(item, itemName, time, current)
	Traffic("ItemStateChanged", {
		Item = item,
		ItemName = itemName,
		Previous = not current,
		Current = current,
		Time = time,
	}):SendTo("FlickerArray")
end

for index = 1, 5 do
	local state = index % 2 == 0
	switch(itemA, "Spirit Box", index * 0.1, state)
	switch(itemB, "Blacklight", index * 0.1, state)
end
expect(#results == 0, "switches from different items must not be combined")

for index = 1, 10 do
	switch(itemA, "Spirit Box", 10 + (index - 1) * 0.3, index % 2 == 0)
end
expect(#results == 0, "ten switches spanning more than 2.5 seconds must not qualify")

for index = 1, 9 do
	switch(itemA, "Spirit Box", 20 + (index - 1) * 0.25, index % 2 == 0)
end
expect(#results == 0, "nine fast switches must not qualify")
switch(itemA, "Spirit Box", 22.25, true)
expect(#results == 1 and results[1].Count == 10 and results[1].Duration == 2.25,
	"the tenth switch inside 2.5 seconds should resolve the flicker array")
expect(Verdict.Confidence[9] == 99 and Verdict.Selected[1] == 9,
	"a completed flicker array should support and select Leviathan")

flicker:Destroy()
leviathan:Destroy()
print("leviathan.spec: per-item rolling flicker array passed")
