return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ToggleFuseBox")
	assert(Event and Event:IsA("RemoteEvent"), "ToggleFuseBox RemoteEvent was not found")
	return Event:FireServer(...)
end
