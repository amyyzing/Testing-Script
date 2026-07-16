return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("AskSpiritBoxFromUI")
	assert(Event and Event:IsA("RemoteEvent"), "AskSpiritBoxFromUI RemoteEvent was not found")
	return Event:FireServer(...)
end
