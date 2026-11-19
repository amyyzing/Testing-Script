local Wretch = {Name="Wretch",Index=23}
function Wretch.new(dependencies)
 local Traffic=assert(dependencies.Traffic,"Wretch requires Traffic")
 local processor={Samples={},UnknownSamples={},UnknownLiveSamples={},Mismatches=0,Seen={},HadKill=false,LiveSerial=0}
 processor.Disconnect=Traffic:Receive("Wretch",function(signal,payload)
  if signal=="PlayerKilled" then processor.HadKill=true processor.LiveCandidate=nil return end
  if signal=="WretchLiveSpeedObserved" and type(payload)=="table" then
   if not payload.Hunting or payload.Headless==true then processor.LiveCandidate=nil return end
   if processor.Resolved or processor.HadKill or type(payload.AverageEnergy)~="number"
    or type(payload.Speed)~="number"or payload.Speed<=0 or type(payload.Time)~="number"
    or type(payload.Visible)~="boolean"then return end
   local energy=math.clamp(payload.AverageEnergy,0,100)
   local candidate=processor.LiveCandidate
   if not candidate or math.abs(candidate.Energy-energy)>.001 or math.abs(candidate.Speed-payload.Speed)>.05 then
    candidate={Energy=energy,Speed=payload.Speed,Started=payload.Time,States={}}
    processor.LiveCandidate=candidate
   end
   candidate.States[payload.Visible]=true
   -- Both blink states must agree, past the bounded native kill-notification delay.
   if candidate.Published or payload.Time-candidate.Started<5
    or not candidate.States[true]or not candidate.States[false]then return end
   candidate.Published=true processor.LiveSerial+=1
   Traffic("WretchSpeedSample",{Hunting=true,AverageEnergy=candidate.Energy,Speed=candidate.Speed,
    Stable=true,Live=true,Transition="live:"..processor.LiveSerial}):SendTo("SpeedFilter")
   return
  end
  if processor.Resolved or signal~="WretchSpeedResult" or type(payload)~="table"
   or processor.HadKill or not payload.Complete or not payload.Stable or not payload.Hunting then return end
  if type(payload.Speed) ~= "number" or payload.Speed <= 0 then return end
  local transition=payload.Transition
  if transition and processor.Seen[transition] then return end
  if transition then processor.Seen[transition]=true end
  if payload.ScaleKnown~=true then
   local energy=math.clamp(payload.AverageEnergy,0,100)
   local samples=payload.Live and processor.UnknownLiveSamples or processor.UnknownSamples
   for _,sample in ipairs(samples) do if math.abs(sample.Energy-energy)<5 then return end end
   table.insert(samples,{Energy=energy,Scale=payload.Speed/(14-energy*0.05)})
   if #samples<3 then return end
   local lowEnergy,highEnergy,lowScale,highScale=100,0,math.huge,0
   for _,sample in ipairs(samples) do
    lowEnergy=math.min(lowEnergy,sample.Energy) highEnergy=math.max(highEnergy,sample.Energy)
    lowScale=math.min(lowScale,sample.Scale) highScale=math.max(highScale,sample.Scale)
   end
   if highEnergy-lowEnergy<20 then return end
   local spread=(highScale-lowScale)/lowScale
   if spread>0.02 and spread<0.05 then return end
   if payload.Live and spread>0.02 then return end
   processor.Resolved=true
   Traffic(spread<=0.02 and "Support" or "RuleOut",{Ghost="Wretch", Perk = "Energy speed curve",Confidence=95,
    Reason=spread<=0.02 and "three stable Energy levels followed the curve at one consistent combined map/custom scale"
     or "three stable hunts at distinct Energy levels could not share one Energy-curve scale"}):SendTo("Verdict")
   return
  end
  if not payload.Matched then
   if payload.Live then return end -- Replication skew is not a live negative.
   processor.Mismatches+=1
   if processor.Mismatches<2 then return end
   processor.Resolved=true
   Traffic("RuleOut",{Ghost="Wretch", Perk = "Energy speed curve",Confidence=95,
    Reason=string.format("two stable hunts disagreed with the confirmed scale and Energy curve (observed %.3f, expected %.3f)",payload.Speed,payload.ExpectedSpeed)}):SendTo("Verdict")
   return
  end
  local previous=processor.Samples[payload.Multiplier]
  processor.Samples[payload.Multiplier]=previous or payload
  local changed=previous and math.abs(payload.AverageEnergy-previous.AverageEnergy)>=10
  processor.Resolved=changed==true
  Traffic("Support",{Ghost="Wretch", Perk = "Energy speed curve",Confidence=changed and 95 or 35,
   Reason=string.format("stable hunt speed %.3f matched %.3f at %.2f%% Energy%s",payload.Speed,payload.ExpectedSpeed,payload.AverageEnergy,
    changed and " across a meaningful Energy change" or "; waiting for a different Energy level")}):SendTo("Verdict")
 end)
 function processor:Destroy() self.Disconnect() end
 return processor
end
return Wretch
