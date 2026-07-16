return function()
	local receivers = {}
	local Traffic = {}

	function Traffic:Receive(name, callback)
		assert(type(name) == "string" and name ~= "", "receiver name is required")
		assert(type(callback) == "function", "receiver callback is required")
		receivers[name] = receivers[name] or {}
		table.insert(receivers[name], callback)
		local connected = true
		return function()
			if not connected then return end
			connected = false
			local callbacks = receivers[name]
			if not callbacks then return end
			local index = table.find(callbacks, callback)
			if index then table.remove(callbacks, index) end
		end
	end

	function Traffic:Send(signal, payload, targets)
		local envelope = {
			Signal = signal,
			Payload = payload,
			Targets = targets,
		}
		for _, target in ipairs(targets or {}) do
			for _, callback in ipairs(receivers[target] or {}) do
				callback(signal, payload, envelope)
			end
		end
		return envelope
	end

	function Traffic:Broadcast(signal, payload)
		local targets = {}
		for name in pairs(receivers) do table.insert(targets, name) end
		return self:Send(signal, payload, targets)
	end

	setmetatable(Traffic, {
		__call = function(_, signal, payload)
			return {
				SendTo = function(_, ...)
					return Traffic:Send(signal, payload, {...})
				end,
				sendTo = function(_, ...)
					return Traffic:Send(signal, payload, {...})
				end,
			}
		end,
	})

	return Traffic
end
