return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "footstep-sound requires Traffic")
	local Ghost = assert(dependencies.Ghost, "footstep-sound requires Ghost")
	local root = Ghost:FindFirstChild("HumanoidRootPart")
	local Tracker = {Kind = "discardable", Running = false}
	if not root then
		function Tracker:Destroy() end
		return Tracker
	end

	local otherSound
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Sound") and child.Name ~= "Hunting" then
			otherSound = child
			break
		end
	end
	Tracker.HasOtherSound = otherSound ~= nil
	Traffic("FootstepSound", {
		HasOtherSound = Tracker.HasOtherSound,
		Sound = otherSound,
	}):SendTo("Umbra")

	function Tracker:Destroy() end
	return Tracker
end
