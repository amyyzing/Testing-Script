local Wretch = {Name="Wretch",Index=23}
function Wretch.new(dependencies)
 local Traffic=assert(dependencies.Traffic,"Wretch requires Traffic")
 local processor={Samples={},UnknownSamples={},Mismatches=0,Seen={},HadKill=false}
 processor.Disconnect=Traffic:Receive("Wretch",function(signal,payload)
  if signal=="PlayerKilled" then processor.HadKill=true return end
  if processor.Resolved or signal~="WretchSpeedResult" or type(payload)~="table"
   or not payload.Complete or not payload.Stable or not payload.Hunting then return end
  local transition=payload.Transition
  if transition and processor.Seen[transition] then return end
  if transition then processor.Seen[transition]=true end
  if payload.ScaleKnown~=true then
   if processor.HadKill then return end
   local energy=math.clamp(payload.AverageEnergy,0,100)
   local samples=processor.UnknownSamples
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
   processor.Resolved=true
   Traffic(spread<=0.02 and "Support" or "RuleOut",{Ghost="Wretch", Perk = "Energy speed curve",Confidence=95,
    Reason=spread<=0.02 and "three stable hunts followed the Energy curve at one consistent combined map/custom scale"
     or "three stable hunts at distinct Energy levels could not share one Energy-curve scale"}):SendTo("Verdict")
   return
  end
  if not payload.Matched then
   processor.Mismatches+=1
   if processor.Mismatches<2 then return end
   processor.Resolved=true
   Traffic("RuleOut",{Ghost="Wretch", Perk = "Energy speed curve",Confidence=95,
    Reason=string.format("two stable hunts disagreed with the confirmed scale and Energy curve (observed %.3f, expected %.3f)",payload.Speed,payload.ExpectedSpeed)}):SendTo("Verdict")
   return
  end
  if processor.HadKill then return end
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
