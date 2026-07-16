return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ApplyEquipmentPreset")
	assert(Event and Event:IsA("RemoteEvent"), "ApplyEquipmentPreset RemoteEvent was not found")
	return Event:FireServer(...)
end
