return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("RequestItemUnequip")
	assert(Event and Event:IsA("RemoteEvent"), "RequestItemUnequip RemoteEvent was not found")
	return Event:FireServer(...)
end
