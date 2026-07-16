return function(callback)
	local player = game:GetService("Players").LocalPlayer
	local scripts = player:FindFirstChild("PlayerScripts")
	local events = scripts and scripts:FindFirstChild("Events")
	local Event = events and events:FindFirstChild("ShowSubtitle")
	assert(Event and Event:IsA("BindableEvent"), "local ShowSubtitle BindableEvent was not found")
	return Event.Event:Connect(callback)
end
