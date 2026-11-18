return function(dependencies)
 local Traffic = assert(dependencies.Traffic, "specter-trial requires Traffic")
 local Ghost = assert(dependencies.Ghost, "specter-trial requires Ghost")
 local RunService = assert(dependencies.RunService, "specter-trial requires RunService")
 local clock = dependencies.Clock or os.clock
 local readCurrentRoom = dependencies.ReadCurrentRoom
 local sampleInterval = tonumber(dependencies.SampleInterval) or 0.1
 local analysisInterval = tonumber(dependencies.AnalysisInterval) or 0.2
 local armSeconds = tonumber(dependencies.ArmSeconds) or 5
 local roomSettleSeconds = tonumber(dependencies.RoomChangeSettleSeconds) or 2
 local Tracker = {Kind = "dormant", Running = true,
  Hunting = Ghost:GetAttribute("Hunting") == true, Sequence = 0, Accumulator = 0}
 local function token(value)
  if value and value.Name then value = value.Name end
  return string.lower(tostring(value or ""):gsub("[^%w]", ""))
 end
 local function currentRoom(refresh)
  if readCurrentRoom then return readCurrentRoom(refresh == true) end
  return Ghost:GetAttribute("CurrentRoom")
 end
 local function clearTrial()
  Tracker.CandidateAt = nil
  Tracker.Armed = false
  Tracker.OutsideAt = nil
 end
 local function analyze(now)
  if Tracker.Resolved then return end
  if Tracker.Hunting or Ghost:GetAttribute("Hunting") == true then clearTrial() return end
  local favourite = token(Ghost:GetAttribute("FavoriteRoom") or Ghost:GetAttribute("FavouriteRoom"))
  local room = token(currentRoom(false))
  if favourite == "" or room == "" then clearTrial() return end
  if Tracker.TrackedFavourite and Tracker.TrackedFavourite ~= favourite then
   clearTrial()
   Tracker.RoomChangePause = true
   Tracker.RoomChangeSettledAt = nil
  end
  Tracker.TrackedFavourite = favourite
  if Tracker.RoomChangePause then
   if room == favourite then
    Tracker.RoomChangeSettledAt = Tracker.RoomChangeSettledAt or now
    if now - Tracker.RoomChangeSettledAt + 1e-6 >= roomSettleSeconds then
     Tracker.RoomChangePause = false
     Tracker.CandidateAt = now
    end
   else
    Tracker.RoomChangeSettledAt = nil
   end
   return
  end
  if room == favourite then
   Tracker.OutsideAt = nil
   Tracker.CandidateAt = Tracker.CandidateAt or now
   if not Tracker.Armed and now - Tracker.CandidateAt + 1e-6 >= armSeconds then
    Tracker.Sequence += 1
    Tracker.Armed = true
   end
   return
  end
  if not Tracker.Armed then clearTrial() return end
  room = token(currentRoom(true))
  if room == "" or room == favourite then Tracker.OutsideAt = nil return end
  Tracker.OutsideAt = Tracker.OutsideAt or now
  if now - Tracker.OutsideAt + 1e-6 < 0.5 then return end
  Tracker.Resolved = true
  Traffic("SpecterTrial", {TrialId = "specter-trial:" .. Tracker.Sequence,
   Outcome = "Departure", Qualified = true, Completed = true,
   FavouriteRoomUnchanged = true, ArmedSeconds = now - Tracker.CandidateAt,
   Room = room, FavouriteRoom = favourite, Time = now}):SendTo("Specter")
 end
 Tracker.Disconnect = Traffic:Receive("SpecterTrial", function(signal, payload)
  if signal ~= "HuntingState" or type(payload) ~= "table" then return end
  local hunting = payload.Hunting == true
  if hunting == Tracker.Hunting then return end
  Tracker.Hunting = hunting
  clearTrial()
 end)
 Tracker.Connection = RunService.Heartbeat:Connect(function(deltaTime)
  if not Tracker.Running or Tracker.Resolved then return end
  Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
  if Tracker.Accumulator < sampleInterval then return end
  Tracker.Accumulator %= sampleInterval
  local now = clock()
  if not Tracker.LastAnalysisAt or now - Tracker.LastAnalysisAt + 1e-6 >= analysisInterval then
   Tracker.LastAnalysisAt = now
   analyze(now)
  end
 end)
 function Tracker:Destroy()
  if not self.Running then return end
  self.Running = false
  self.Disconnect()
  self.Connection:Disconnect()
 end
 return Tracker
end
