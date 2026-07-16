return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("UseLightSwitch")
	assert(Event and Event:IsA("RemoteEvent"), "UseLightSwitch RemoteEvent was not found")
	return Event:FireServer(...)
end
