return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("RequestItemDrop")
	assert(Event and Event:IsA("RemoteEvent"), "RequestItemDrop RemoteEvent was not found")
	return Event:FireServer(...)
end
