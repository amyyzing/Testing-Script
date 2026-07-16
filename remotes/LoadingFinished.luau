return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("LoadingFinished")
	assert(Event and Event:IsA("RemoteEvent"), "LoadingFinished RemoteEvent was not found")
	return Event:FireServer(...)
end
