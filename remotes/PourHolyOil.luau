return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("PourHolyOil")
	assert(Event and Event:IsA("RemoteEvent"), "PourHolyOil RemoteEvent was not found")
	return Event:FireServer(...)
end
