return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ApplyDifficultyPreset")
	assert(Event and Event:IsA("RemoteEvent"), "ApplyDifficultyPreset RemoteEvent was not found")
	return Event:FireServer(...)
end
