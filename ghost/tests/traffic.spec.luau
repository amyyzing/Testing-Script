local createTraffic = require("../traffic")
local traffic = createTraffic()
local seen = {}
local disconnect
disconnect = traffic:Receive("Check", function()
	table.insert(seen, "first")
	disconnect()
	traffic:Receive("Check", function() table.insert(seen, "later") end)
end)
traffic:Receive("Check", function() table.insert(seen, "second") end)
traffic("Pulse", {}):SendTo("Check")
assert(table.concat(seen, ",") == "first,second",
	"a receiver removing itself must not skip the next receiver or notify a newly added receiver")
table.clear(seen)
traffic("Pulse", {}):SendTo("Check")
assert(table.concat(seen, ",") == "second,later",
	"receiver changes should apply to the next dispatch")
print("traffic.spec: receiver lifecycle during dispatch passed")
