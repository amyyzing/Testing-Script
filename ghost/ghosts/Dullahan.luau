local Dullahan = {Name = "Dullahan", Index = 4}

function Dullahan.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Dullahan requires Traffic")
	local processor = {Matches = 0}

	local function reset(time, speed)
		processor.StartTime, processor.StartSpeed = time, speed
		processor.LastTime, processor.LastSpeed = time, speed
		processor.Count, processor.MaxError = 0, 0
	end

	processor.Disconnect = Traffic:Receive("Dullahan", function(signal, payload)
		if processor.Resolved or signal ~= "GhostSpeedObserved" or type(payload) ~= "table"
			or payload.Source ~= "speed" or payload.Hunting ~= true then return end
		local time, speed = tonumber(payload.Time), tonumber(payload.Speed)
		if not time or not speed or speed <= 0 then return end
		if not processor.LastTime then reset(time, speed) return end

		local elapsed = time - processor.LastTime
		local change = speed - processor.LastSpeed
		if elapsed <= 0 or math.abs(change) < 0.000001 then return end
		if elapsed > 0.5 or change < 0 or change > 0.05 then reset(time, speed) return end
		processor.LastTime, processor.LastSpeed = time, speed
		processor.Count += 1

		local duration = time - processor.StartTime
		local gain = speed - processor.StartSpeed
		processor.MaxError = math.max(processor.MaxError, math.abs(gain - duration * 0.1))
		if processor.MaxError > 0.03 then reset(time, speed) return end
		if duration < 1 or processor.Count < 6 then return end
		local rate = gain / duration
		if rate < 0.075 or rate > 0.125 then reset(time, speed) return end

		processor.Matches += 1
		reset(time, speed)
		if processor.Matches < 3 then return end
		processor.Resolved = true
		Traffic("Support", {
			Ghost = "Dullahan",
			Perk = "Gradual acceleration",
			Observation = "Repeated gradual speed gain",
			Confidence = 95,
			Reason = "three measured ramps followed the native 0.1-per-second acceleration pattern",
		}):SendTo("Verdict")
	end)

	function processor:Destroy() self.Disconnect() end
	return processor
end

return Dullahan
