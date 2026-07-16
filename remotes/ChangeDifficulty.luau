return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ChangeDifficulty")
	assert(Event and Event:IsA("RemoteEvent"), "ChangeDifficulty RemoteEvent was not found")
	return Event:FireServer(...)
end
