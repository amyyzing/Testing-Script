return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("RequestItemEquip")
	assert(Event and Event:IsA("RemoteEvent"), "RequestItemEquip RemoteEvent was not found")
	return Event:FireServer(...)
end
