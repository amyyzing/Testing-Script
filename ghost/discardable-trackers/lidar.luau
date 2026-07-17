return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "lidar requires Traffic")
	local Ghost = assert(dependencies.Ghost, "lidar requires Ghost")
	local value = Ghost:GetAttribute("InvisibleOnLIDAR")
	local exists = value ~= nil
	if not exists then
		for _, object in ipairs(Ghost:GetDescendants()) do
			local attribute = object:GetAttribute("InvisibleOnLIDAR")
			if attribute ~= nil then
				exists, value = true, attribute
				break
			elseif object.Name == "InvisibleOnLIDAR" and object:IsA("ValueBase") then
				exists, value = true, object.Value
				break
			end
		end
	end
	local Tracker = {Kind = "discardable", Running = false, Exists = exists, Value = value}
	Traffic("LidarState", {Exists = exists, Value = value}):SendTo("Vex")
	function Tracker:Destroy() end
	return Tracker
end
