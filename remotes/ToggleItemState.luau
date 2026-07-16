return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ToggleItemState")
	assert(Event and Event:IsA("RemoteEvent"), "ToggleItemState RemoteEvent was not found")
	return Event:FireServer(...)
end
