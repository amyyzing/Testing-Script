return function(dependencies)
 local Traffic = assert(dependencies.Traffic, "room-temperature requires Traffic")
 local clock = dependencies.Clock or os.clock
 local required = tonumber(dependencies.RequiredChanges) or 7
 local duration = tonumber(dependencies.MinimumDuration) or 15
 local Tracker = {Kind="dormant", Running=true, RoundStarted=false, Active=false, Changes={}}
 local function temperature(room)
  if dependencies.ReadTemperature then return tonumber(dependencies.ReadTemperature(room)) end
  return room and tonumber(room:GetAttribute("Temperature"))
 end
 local function progress(current, status)
  local elapsed = Tracker.StartTime and clock()-Tracker.StartTime or 0
  local net = current and Tracker.Initial and Tracker.Initial-current or 0
  local average = elapsed>0 and net/elapsed or 0
  Traffic("RoomTemperatureProgress", {Room=Tracker.Room,RoomName=Tracker.Room and Tracker.Room.Name,
   Temperature=current,Count=#Tracker.Changes,Required=required,Average=average,
   Duration=elapsed,NetDecrease=net,Status=status}):SendTo("GhostPatternLog")
  return elapsed,net,average
 end
 function Tracker:Sample()
  if not self.Active then return end
  local current = temperature(self.Room)
  if current==nil then
   self.Previous,self.Initial,self.StartTime=nil,nil,nil table.clear(self.Changes)
   progress(nil,"Waiting for native temperature") return
  end
  if self.Previous~=nil then table.insert(self.Changes,self.Previous-current) end
  self.Initial,self.StartTime=self.Initial or current,self.StartTime or clock()
  self.Previous=current
  local elapsed,net,average=progress(current,"Collecting signed cooling/warming; baseline uncalibrated")
  if #self.Changes<required or elapsed<duration then return end
  Traffic("RoomTemperatureAverage", {Room=self.Room,RoomName=self.Room.Name,Average=average,
   Changes=table.clone(self.Changes),Duration=elapsed,NetDecrease=net,
   SustainedCooling=net>=0.5,Threshold=0.08,Complete=true}):SendTo("Shadow")
  progress(current,net>=0.5 and "Net cooling observed; uncalibrated comparison is weak only"
   or "No sustained net cooling; noise/plateau is inconclusive")
  table.clear(self.Changes) self.Initial,self.StartTime=current,clock()
 end
 local function activate()
  if Tracker.RoomConnection then Tracker.RoomConnection:Disconnect() Tracker.RoomConnection=nil end
  table.clear(Tracker.Changes)
  Tracker.Active=Tracker.RoundStarted and Tracker.Room~=nil
  Tracker.Previous=temperature(Tracker.Room)
  Tracker.Initial,Tracker.StartTime=Tracker.Previous,clock()
  progress(Tracker.Previous,Tracker.Active and "Waiting for temperature changes; baseline uncalibrated"
   or "Waiting for round start / first hunt")
  if Tracker.Active then
   Tracker.RoomConnection=Tracker.Room:GetAttributeChangedSignal("Temperature"):Connect(function()Tracker:Sample()end)
  end
 end
 Tracker.Disconnect=Traffic:Receive("RoomTemperature",function(signal,payload)
  if type(payload)~="table" then return end
  if signal=="GhostRoom" and payload.Room~=Tracker.Room then Tracker.Room=payload.Room activate()
  elseif signal=="RoundStarted" and payload.Started==true and not Tracker.RoundStarted then
   Tracker.RoundStarted=true activate()
  end
 end)
 function Tracker:Destroy()
  self.Running,self.Active=false,false self.Disconnect()
  if self.RoomConnection then self.RoomConnection:Disconnect() end
 end
 return Tracker
end
