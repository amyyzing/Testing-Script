local create = require("../round-tuning")
local stored, callback
local rows = {
 GhostWalkSpeedMultiplier={GetAttribute=function()return 6 end},
 GhostLowerTemperatureRange={GetAttribute=function()return 2 end},
}
local list={FindFirstChild=function(_,name)return rows[name]end}
local computer={FindFirstChild=function()return list end}
local player={FindFirstChildOfClass=function()return {FindFirstChild=function()return computer end}end,
 OnTeleport={Connect=function(_,fn)callback=fn return {Disconnect=function()callback=nil end}end}}
local native=true
local deps={
 Game={GameId=42}, Now=function()return 100 end,
 Workspace={FindFirstChild=function()return {GetAttribute=function()return "Small" end}end},
 ReplicatedStorage={FindFirstChild=function()return {FindFirstChild=function()return native and {} or nil end}end},
 Player=player, ReadDifficulty=function()return "Custom"end,
 TeleportService={GetTeleportSetting=function()return stored end,SetTeleportSetting=function(_,_,data)stored=data end},
 Require=function()return {Options={
 {ID="GhostWalkSpeedMultiplier",Toggles={"50%","75%","100%","125%","150%","200%"},Values={["200%"]=2}},
 {ID="GhostLowerTemperatureRange",Toggles={"Easy","Medium"}},
 }}end,
}
local lobby=create(deps)
assert(not lobby:GetScale().Known)
callback("Enum.TeleportState.Started")
assert(stored.GhostWalkSpeedMultiplier==2 and stored.GhostLowerTemperatureRange=="Medium")
lobby:Destroy() assert(callback==nil)
native=false
local round=create(deps)
assert(round:GetScale().Known and round:GetScale().CustomMultiplier==2 and stored==nil)
assert(not create(deps):GetScale().Known, "a fresh unrelated load cannot inherit consumed tuning")
stored={GameId=99,Time=100,GhostWalkSpeedMultiplier=2}
assert(not create(deps):GetScale().Known, "foreign game settings must be rejected")
stored={GameId=42,Time=-501,GhostWalkSpeedMultiplier=2}
assert(not create(deps):GetScale().Known, "expired settings must be rejected")
print("round-tuning.spec: native settings capture and bounded arrival consumption passed")
