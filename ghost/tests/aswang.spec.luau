local createTraffic = require("../traffic")
local Aswang = require("../ghosts/Aswang")
local traffic = createTraffic()
local observed = {}
traffic:Receive("Verdict", function(signal, data)
	table.insert(observed, {Signal = signal, Perk = data.Perk})
end)
local processor = Aswang.new({Traffic = traffic})
local contact = {
	saltState = "disturbed",
	beforeSalt = {{s = 23.1, v = true}, {s = 23.1, v = false}},
	afterSalt = {{s = 23.1, v = true}, {s = 11.55, v = false}},
}
for _ = 1, 20 do traffic("SaltSpeed", contact):SendTo("Aswang") end
assert(#observed == 1 and observed[1].Signal == "Support",
	"repeated samples of one confirmed salt effect must produce one verdict")
contact.afterSalt[2].s = 23.1
contact.completed = true
traffic("SaltSpeed", contact):SendTo("Aswang")
traffic("SaltSpeed", contact):SendTo("Aswang")
assert(#observed == 2 and observed[2].Signal == "RuleOut",
	"a changed conclusion must still be published once")
local kill = {
	beforeKill = {{s = 21, v = true}, {s = 21, v = false}},
	afterKill = {{s = 21, v = true}, {s = 25.2, v = false}, {s = 25.2, v = true}},
}
for _ = 1, 20 do traffic("KillSpeed", kill):SendTo("Aswang") end
assert(#observed == 3 and observed[3].Perk == "Speed rises after kill",
	"kill and salt conclusions must be independent and repeated kill samples deduplicated")
processor:Destroy()
print("aswang.spec: repeated observations and changed conclusions passed")
