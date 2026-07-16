return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ToggleChallenge")
	assert(Event and Event:IsA("RemoteEvent"), "ToggleChallenge RemoteEvent was not found")
	return Event:FireServer(...)
end
