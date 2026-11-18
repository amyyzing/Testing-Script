local createTraffic=require("../traffic")
local createVerdict=require("../verdict")
local createFootsteps=require("../discardable-trackers/footstep-sound")
local Umbra=require("../ghosts/Umbra")
local function signal()
 local callbacks={}
 return {Connect=function(_,cb)table.insert(callbacks,cb)return {Disconnect=function()
  local i=table.find(callbacks,cb)if i then table.remove(callbacks,i)end
 end}end,Fire=function(_,delta)for _,cb in ipairs(table.clone(callbacks))do cb(delta)end end}
end
local function sound(name,id,playing,volume)
 return {Name=name,SoundId=id,IsPlaying=playing,Volume=volume,IsA=function(_,kind)return kind=="Sound"end}
end
local function harness(sounds)
 local heartbeat=signal()
 local root={GetDescendants=function()return sounds end}
 local ghost={Root=root}
 function ghost:FindFirstChild(name)return name=="HumanoidRootPart"and self.Root or nil end
 local traffic=createTraffic()
 local verdict=createVerdict({Traffic=traffic})
 local processor=Umbra.new({Traffic=traffic})
 local tracker=createFootsteps({Traffic=traffic,Ghost=ghost,RunService={Heartbeat=heartbeat}})
 return {Ghost=ghost,Verdict=verdict,Sample=function(n,delta)for _=1,n or 1 do heartbeat:Fire(delta or .11)end end,
  Destroy=function()tracker:Destroy()processor:Destroy()end}
end
local present=harness({sound("CurrentSound","any-asset",false,0)})present.Sample()
assert(table.find(present.Verdict.RuledOut,20),"CurrentSound must count even idle, muted or using a different asset")present.Destroy()
local duplicate=harness({{Name="CurrentSound",IsA=function()return false end},sound("CurrentSound","any",false,0)})duplicate.Sample()
assert(table.find(duplicate.Verdict.RuledOut,20),"a duplicate name on another object must not hide the Sound")duplicate.Destroy()
local otherSounds={sound("Hunt","hunt",true,5),sound("Female","rbxassetid://118914149005666",true,5),sound("Other","native",true,1)}
local other=harness(otherSounds)other.Sample(15)
assert(other.Verdict.Confidence[20]==nil,"other sound names must not skip the loading grace")other.Sample(10)
assert(other.Verdict.Confidence[20]==95 and not table.find(other.Verdict.RuledOut,20),"only the CurrentSound name must count, irrespective of other audio assets")other.Destroy()
local missingRoot=harness({})missingRoot.Ghost.Root=nil missingRoot.Sample(50)
assert(missingRoot.Verdict.Confidence[20]==nil,"a missing root must remain inconclusive")missingRoot.Destroy()
local stalled=harness({})stalled.Sample(50,1)
assert(stalled.Verdict.Confidence[20]==nil,"stalled observations must not skip replication grace")stalled.Destroy()
local lateSounds={}
local late=harness(lateSounds)late.Sample(25)
assert(late.Verdict.Confidence[20]==95,"missing native footsteps should be reported after grace")
table.insert(lateSounds,sound("CurrentSound","any",false,0))late.Sample()
assert(table.find(late.Verdict.RuledOut,20),"a late native Sound must correct earlier absence")late.Destroy()
print("umbra.spec: CurrentSound existence, unrelated audio, duplicate names, grace and late correction passed")
