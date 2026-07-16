return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ChangeStatus")
	assert(Event and Event:IsA("RemoteEvent"), "ChangeStatus RemoteEvent was not found")
	return Event:FireServer(...)
end
