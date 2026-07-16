local function getEvent()
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("UpdateAllCustomDifficultySettings")
	assert(Event and Event:IsA("RemoteEvent"), "UpdateAllCustomDifficultySettings RemoteEvent was not found")
	return Event
end

local Remote = {}

function Remote.Connect(callback)
	return getEvent().OnClientEvent:Connect(callback)
end

function Remote.Signal(...)
	local environment = (getgenv and getgenv()) or _G
	local fireSignal = environment.firesignal or firesignal
	assert(type(fireSignal) == "function", "firesignal is unavailable")
	return fireSignal(getEvent().OnClientEvent, ...)
end

return setmetatable(Remote, {
	__call = function(_, callback)
		return Remote.Connect(callback)
	end,
})
