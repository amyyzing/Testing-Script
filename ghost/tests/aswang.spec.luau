local createTraffic = require("../traffic")
local Aswang = require("../ghosts/Aswang")
local function fixture()
 local traffic, observed = createTraffic(), {}
 traffic:Receive("Verdict", function(signal, data)
  table.insert(observed, {Signal=signal,Perk=data.Perk})
 end)
 return traffic, observed, Aswang.new({Traffic=traffic})
end
local traffic, observed, processor = fixture()
local contact = {
 saltState="disturbed", beforeSalt={{s=21,v=true},{s=21,v=false}},
 afterSalt={{s=15.75,v=false},{s=15.75,v=false}}, completed=true, Duration=.001,
}
for _=1,20 do traffic("SaltSpeed",contact):SendTo("Aswang")end
assert(#observed==1 and observed[1].Signal=="Support","native 25 percent drop should be reported once")
-- Live round 51f07430: three adjacent salt contacts in less than 2 ms.
local stillSlowed = {
 saltState="disturbed", beforeSalt={{s=15.75,v=false}},
 afterSalt={{s=15.75,v=false},{s=15.75,v=false}}, completed=true, Duration=.001,
}
traffic("SaltSpeed",stillSlowed):SendTo("Aswang")
stillSlowed.Duration=5
traffic("SaltSpeed",stillSlowed):SendTo("Aswang")
assert(#observed==1,"another contact while already slowed must not revoke the observed salt effect")
local kill={
 beforeKill={{s=21,v=true},{s=21,v=false}},
 afterKill={{s=21,v=true},{s=25.2,v=false},{s=25.2,v=true}},
}
for _=1,20 do traffic("KillSpeed",kill):SendTo("Aswang")end
assert(#observed==2 and observed[2].Perk=="Speed rises after kill","kill evidence must remain independent")
processor:Destroy()
local t, results, normal = fixture()
local noEffect={
 saltState="disturbed",beforeSalt={{s=21,v=false}},
 afterSalt={{s=21,v=false},{s=21,v=false}},completed=true,Duration=.001,
}
t("SaltSpeed",noEffect):SendTo("Aswang")
assert(#results==0,"an immediate next-contact split is not a qualified no-effect window")
noEffect.Duration=5
t("SaltSpeed",noEffect):SendTo("Aswang")
assert(#results==1 and results[1].Signal=="RuleOut","a complete observed no-effect window should be negative")
normal:Destroy()
local n, noise, noisy = fixture()
n("SaltSpeed",{
 saltState="disturbed",beforeSalt={{s=21,v=false}},
 afterSalt={{s=21,v=false},{s=20.9,v=false}},
}):SendTo("Aswang")
assert(#noise==0,"a small unrelated speed drop must not identify Aswang")
noisy:Destroy()
print("aswang.spec: native salt effect, adjacent contacts, duration and independent kill checks passed")
