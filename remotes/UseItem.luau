return function(...)
	local player = game:GetService("Players").LocalPlayer
	local scripts = player:FindFirstChild("PlayerScripts")
	local events = scripts and scripts:FindFirstChild("Events")
	local Event = events and events:FindFirstChild("UseItem")
	assert(Event and Event:IsA("BindableEvent"), "UseItem BindableEvent was not found")
	return Event:Fire(...)
end
