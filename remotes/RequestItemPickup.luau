return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("RequestItemPickup")
	assert(Event and Event:IsA("RemoteEvent"), "RequestItemPickup RemoteEvent was not found")
	return Event:FireServer(...)
end
