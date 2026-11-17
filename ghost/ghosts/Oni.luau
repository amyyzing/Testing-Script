local Oni={Name="Oni",Index=11}
function Oni.new(dependencies)
 local Traffic=assert(dependencies.Traffic,"Oni requires Traffic")
 local processor={Matches=0,Mismatches=0,Seen={},HadKill=false}
 processor.Disconnect=Traffic:Receive("Oni",function(signal,payload)
  if signal=="PlayerKilled" then processor.HadKill=true return end
  if processor.Resolved or signal~="SpeedFilterResult" or type(payload)~="table"
   or not payload.Complete or not payload.HasBothStates or not payload.ScaleKnown then return end
  if payload.HuntId and processor.Seen[payload.HuntId] then return end
  if payload.HuntId then processor.Seen[payload.HuntId]=true end
  local matched=payload.Identical==true and payload.BaseSpeed==14
  if matched then
   processor.Matches+=1
   local energy=tonumber(payload.AverageEnergy)
   local confirmed=processor.Matches>=2 and energy and energy>=25 and not processor.HadKill
   processor.Resolved=confirmed==true
   Traffic("Support",{Ghost="Oni",Confidence=confirmed and 95 or 35,
    Reason=confirmed and "two stable hunts matched scaled base 14 with enough Energy to distinguish Wretch"
     or "stable scaled base 14; waiting for a second hunt and enough Energy to distinguish Wretch"}):SendTo("Verdict")
  else
   processor.Mismatches+=1
   if processor.Mismatches<2 then return end
   processor.Resolved=true
   Traffic("RuleOut",{Ghost="Oni",Confidence=95,
    Reason="two complete hunt windows did not match base 14 at the confirmed map and custom scale"}):SendTo("Verdict")
  end
 end)
 function processor:Destroy() self.Disconnect() end
 return processor
end
return Oni
