local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createFootsteps = require("../discardable-trackers/footstep-sound")
local Umbra = require("../ghosts/Umbra")
local function signal()
 local callbacks={}
 return {
  Connect=function(_,callback) table.insert(callbacks,callback) return {Disconnect=function() local i=table.find(callbacks,callback) if i then table.remove(callbacks,i) end end} end,
  Fire=function(_,...) for _,callback in ipairs(table.clone(callbacks)) do callback(...) end end,
 }
end
local function harness(sounds)
 local heartbeat=signal()
 local ghost={Hunting=true}
 function ghost:GetAttribute(key) return self[key] end
 function ghost:FindFirstChild() return {GetDescendants=function() return sounds end} end
 local traffic=createTraffic()
 local verdict=createVerdict({Traffic=traffic})
 local processor=Umbra.new({Traffic=traffic})
 local tracker=createFootsteps({Traffic=traffic,Ghost=ghost,RunService={Heartbeat=heartbeat},FootstepIds={native=true}})
 return {Ghost=ghost,Verdict=verdict,Sample=function() heartbeat:Fire(0.11) end,Destroy=function()tracker:Destroy()processor:Destroy()end}
end
local sound={Name="CurrentSound",SoundId="native",IsPlaying=true,Volume=0.45,IsA=function(_,kind)return kind=="Sound"end}
local active=harness({sound})
active.Sample() active.Sample()
assert(active.Verdict.Confidence[20]==nil and not table.find(active.Verdict.RuledOut,20),"one or two audible samples must not decide Umbra")
active.Sample()
assert(table.find(active.Verdict.RuledOut,20),"three native audible footstep samples must exclude Umbra, regardless of Sound name")
active.Destroy()
local silent=harness({})
for i=1,20 do silent.Sample() end
assert(silent.Verdict.Confidence[20]==nil and #silent.Verdict.RuledOut==0,"missing sound must not become positive Umbra evidence")
silent.Destroy()
local voice=harness({{Name="Footsteps",SoundId="voice",IsPlaying=true,Volume=1,IsA=sound.IsA}})
for i=1,5 do voice.Sample() end
assert(#voice.Verdict.RuledOut==0,"names alone cannot identify a material footstep sound")
voice.Destroy()
local idle=harness({sound}) idle.Ghost.Hunting=false
for i=1,5 do idle.Sample() end
assert(#idle.Verdict.RuledOut==0,"non-hunting sounds must not qualify a hunt trial")
idle.Destroy()
print("umbra.spec: native sound IDs, audible hunt samples, and inconclusive silence passed")
