return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("LaySaltPile")
	assert(Event and Event:IsA("RemoteEvent"), "LaySaltPile RemoteEvent was not found")
	return Event:FireServer(...)
end
