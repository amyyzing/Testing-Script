local Dullahan = {Name = "Dullahan", Index = 4}

function Dullahan.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Dullahan requires Traffic")
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Dullahan", function(signal, payload)
		if signal ~= "SpeedFilterResult" or type(payload) ~= "table"
			or payload.Complete ~= true then return end
		local distinct = tonumber(payload.DistinctPairs) or 0
		if distinct < 3 then return end
		local previous, rises = nil, 0
		for _, pair in ipairs(payload.Pairs or {}) do
			local speed = tonumber(pair.v)
			if not speed then return end
			if previous then
				if speed < previous - 0.05 then return end
				if speed > previous + 0.05 then rises += 1 end
			end
			previous = speed
		end
		if rises < 2 then return end
		Traffic("Support", {
			Ghost = "Dullahan",
			Confidence = 65,
			Reason = "visible hunt speed rose repeatedly; supporting Dullahan, but an uncontrolled line-of-sight trial is not conclusive",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Dullahan
