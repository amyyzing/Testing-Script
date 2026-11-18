local Umbra = {Name = "Umbra", Index = 20}

function Umbra.new(dependencies)
 local Traffic = assert(dependencies.Traffic, "Umbra requires Traffic")
 local Processor = {}
 Processor.Disconnect = Traffic:Receive("Umbra", function(signal, payload)
  if Processor.RuledOut or signal ~= "FootstepPresence" or type(payload) ~= "table" then return end
  if payload.Present == true then
   Processor.RuledOut = true
   Traffic("RuleOut", {Ghost = "Umbra", Perk = "Silent footsteps", Confidence = 99,
    Observation = "Footstep sound present",
    Reason = "the root contains the footstep Sound named CurrentSound",
   }):SendTo("Verdict")
  elseif payload.Present == false and (tonumber(payload.MissingFor) or 0) >= 2 and not Processor.Supported then
   Processor.Supported = true
   Traffic("Support", {Ghost = "Umbra", Perk = "Silent footsteps", Confidence = 95,
    Observation = "No footstep sound",
    Reason = "the root has no CurrentSound footstep Sound after the loading grace",
   }):SendTo("Verdict")
  end
 end)
 function Processor:Destroy() self.Disconnect() end
 return Processor
end

return Umbra
