local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local Dullahan = require("../ghosts/Dullahan")
local traffic = createTraffic()
local verdict = createVerdict({Traffic = traffic})
local detector = Dullahan.new({Traffic = traffic})
for i = 1, 80 do
 traffic("GhostSpeedObserved", {Source = "speed", Hunting = true, Time = i * 0.1, Speed = 21 + i * 0.01}):SendTo("Dullahan")
end
assert(verdict.SourceConfidence[4] == nil, "acceleration must no longer identify Dullahan")
traffic("HeadlessState", {Exists = true, Value = true}):SendTo("Dullahan")
assert(verdict.SourceConfidence[4] == 99 and verdict.Confidence[4] == 65,
 "the native headless flag must still identify Dullahan with the copied-perk cap")
detector:Destroy()
print("dullahan.spec: native flag only; acceleration ignored")
