return function(...)
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
	local Event = events and events:FindFirstChild("EvidenceMarkedInJournal")
	assert(Event and Event:IsA("RemoteEvent"), "EvidenceMarkedInJournal RemoteEvent was not found")
	return Event:FireServer(...)
end
