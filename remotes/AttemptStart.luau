return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("AttemptStart")
	assert(Event and Event:IsA("RemoteEvent"), "AttemptStart RemoteEvent was not found")
	return Event:FireServer(...)
end
