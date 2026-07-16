return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ChangeJobSite")
	assert(Event and Event:IsA("RemoteEvent"), "ChangeJobSite RemoteEvent was not found")
	return Event:FireServer(...)
end
