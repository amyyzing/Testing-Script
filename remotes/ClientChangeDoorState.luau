return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ClientChangeDoorState")
	assert(Event and Event:IsA("RemoteEvent"), "ClientChangeDoorState RemoteEvent was not found")
	return Event:FireServer(...)
end
