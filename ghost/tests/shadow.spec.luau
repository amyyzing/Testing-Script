local createTraffic=require("../traffic")
local createVerdict=require("../verdict")
local createTemperature=require("../dormant-trackers/room-temperature")
local createStarted=require("../discardable-trackers/round-started")
local Shadow=require("../ghosts/Shadow")
local function signal()
 local callbacks={}
 return {Connect=function(_,fn)table.insert(callbacks,fn)return {Disconnect=function()local i=table.find(callbacks,fn)if i then table.remove(callbacks,i)end end}end,
 Fire=function()for _,fn in ipairs(table.clone(callbacks))do fn()end end,Count=function()return #callbacks end}
end
local function room(name)
 local changed=signal()
 local r={Name=name,Value=10}
 function r:GetAttribute()return self.Value end
 function r:GetAttributeChangedSignal()return changed end
 function r:Set(value)self.Value=value changed:Fire()end
 return r
end
local function harness(hunting)
 local traffic=createTraffic()
 local verdict=createVerdict({Traffic=traffic})
 local processor=Shadow.new({Traffic=traffic})
 local time=0
 local progress={}
 traffic:Receive("GhostPatternLog",function(_,payload)table.insert(progress,payload)end)
 local temperature=createTemperature({Traffic=traffic,Clock=function()return time end})
 local changed=signal()
 local door={Name="ExitDoor",Closed=true}
 function door:GetAttribute()return self.Closed end
 function door:GetAttributeChangedSignal()return changed end
 local world={FindFirstChild=function(_,name)
  if name=="Ghost" then return {GetAttribute=function()return hunting end} end
  if name=="Doors" then return {GetChildren=function()return {door}end,ChildAdded=signal()}end
 end}
 local started=createStarted({Traffic=traffic,Workspace=world})
 local r=room("Library")
 traffic("GhostRoom",{Room=r}):SendTo("RoomTemperature")
 return {Traffic=traffic,Verdict=verdict,Tracker=temperature,Room=r,Progress=progress,Started=started,
 Open=function()door.Closed=false changed:Fire()end,
 Step=function(value)time+=1 r:Set(value)end,
 Destroy=function()temperature:Destroy()started:Destroy()processor:Destroy()end}
end
local h=harness(false)
assert(not h.Tracker.Active and #h.Progress>0,"waiting temperature state must be visible before first cooling event")
h.Step(10.2) assert(#h.Tracker.Changes==0)
h.Open() assert(h.Tracker.Active)
for i=1,16 do h.Step(i%2==0 and 10.2 or 10)end
assert(h.Verdict.Confidence[15]==nil,"balanced cooling/warming jitter must not support Shadow")
local plateauLogged=false
for _,sample in ipairs(h.Progress)do if sample.Status:find("inconclusive")then plateauLogged=true end end
assert(plateauLogged,"plateau must remain visible and inconclusive")
for i=1,16 do h.Step(10.2-i*0.05)end
assert(h.Verdict.Confidence[15]==35,"slow sustained net cooling is weak support only")
assert(not table.find(h.Verdict.RuledOut,15))
local other=room("Hallway")
h.Traffic("GhostRoom",{Room=other}):SendTo("RoomTemperature")
assert(#h.Tracker.Changes==0 and h.Room:GetAttributeChangedSignal():Count()==0,"moving room resets window and disconnects old samples")
h.Destroy() assert(other:GetAttributeChangedSignal():Count()==0)
local running=harness(true)
assert(running.Started.Started and running.Tracker.Active,"loading after door closes during an existing hunt must activate temperature tracking")
running.Destroy()
local later=harness(false)
later.Traffic:Broadcast("HuntingState",{Hunting=true})
assert(later.Started.Started and later.Tracker.Active,"a later hunt must activate a missed round-start gate")
later.Destroy()
print("shadow.spec: visible waiting states, signed noise, timed cooling and late-hunt startup passed")
