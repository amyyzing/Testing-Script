local SPIRIT_FIRST = {R = 0.384314, G = 0.541216, B = 1}
local SPIRIT_LAST = {R = 0, G = 0.263333, B = 1}
local NORMAL_FIRST = {R = 1, G = 0.694118, B = 0.384314}
local NORMAL_LAST = {R = 1, G = 0.333333, B = 0}

return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "holy-oil-colour requires Traffic")
	local World = dependencies.Workspace or workspace
	local Ghost = assert(dependencies.Ghost, "holy-oil-colour requires Ghost")
	local Tracker = {
		Kind = "discardable",
		Running = true,
		Connections = {},
		Bound = setmetatable({}, {__mode = "k"}),
	}

	local function close(left, right, tolerance)
		return math.abs(left - right) <= tolerance
	end

	local function colourClose(left, right)
		return left and close(left.R, right.R, 0.012)
			and close(left.G, right.G, 0.012)
			and close(left.B, right.B, 0.012)
	end

	local function matches(emitter, firstColour, lastColour)
		if not emitter or not emitter:IsA("ParticleEmitter") then return false end
		local points = emitter.Color.Keypoints
		local first, last = points[1], points[#points]
		return first and last
			and close(first.Time, 0, 0.02)
			and close(last.Time, 1, 0.02)
			and colourClose(first.Value, firstColour)
			and colourClose(last.Value, lastColour)
	end

	local function disconnectAll()
		for _, connection in ipairs(Tracker.Connections) do connection:Disconnect() end
		table.clear(Tracker.Connections)
	end

	local function finish(kind, oil)
		if not Tracker.Running then return end
		Tracker.Running = false
		Tracker.Result = kind
		disconnectAll()
		Traffic("HolyOilColour", {
			Kind = kind,
			HolyOil = oil,
			Burning = true,
			Hunting = true,
		}):SendTo("Spirit")
	end

	local function evaluate(oil)
		if not Tracker.Running or Ghost:GetAttribute("Hunting") ~= true
			or oil:GetAttribute("Burning") ~= true then return end
		local container = oil:FindFirstChild("ParticleContainer", true)
		local primary = container and container:FindFirstChild("Primary", true)
		local secondary = container and container:FindFirstChild("Secondary", true)
		if matches(primary, SPIRIT_FIRST, SPIRIT_LAST)
			and matches(secondary, SPIRIT_FIRST, SPIRIT_LAST) then
			finish("Spirit", oil)
		elseif matches(primary, NORMAL_FIRST, NORMAL_LAST)
			and matches(secondary, NORMAL_FIRST, NORMAL_LAST) then
			finish("Normal", oil)
		end
	end

	local function isHolyOil(object)
		if not object:IsA("Model") then return false end
		local itemName = object:GetAttribute("ItemName")
		return object.Name == "HolyOil" or itemName == "Holy Oil" or itemName == "HolyOil"
	end

	local function bindOil(oil)
		if not Tracker.Running or Tracker.Bound[oil] or not isHolyOil(oil) then return end
		Tracker.Bound[oil] = true
		table.insert(Tracker.Connections,
			oil:GetAttributeChangedSignal("Burning"):Connect(function() evaluate(oil) end))
		local function bindEmitter(object)
			if not Tracker.Running or not object:IsA("ParticleEmitter")
				or (object.Name ~= "Primary" and object.Name ~= "Secondary") then return end
			table.insert(Tracker.Connections,
				object:GetPropertyChangedSignal("Color"):Connect(function() evaluate(oil) end))
		end
		for _, object in ipairs(oil:GetDescendants()) do bindEmitter(object) end
		table.insert(Tracker.Connections, oil.DescendantAdded:Connect(function(object)
			bindEmitter(object)
			evaluate(oil)
		end))
		evaluate(oil)
	end

	local function bindFolder(folder)
		if not Tracker.Running then return end
		bindOil(folder)
		for _, object in ipairs(folder:GetDescendants()) do bindOil(object) end
		table.insert(Tracker.Connections,
			folder.DescendantAdded:Connect(function(object) bindOil(object) end))
	end

	local folder = World:FindFirstChild("HolyOil")
	if folder then bindFolder(folder) end
	if Tracker.Running then
		table.insert(Tracker.Connections, World.ChildAdded:Connect(function(child)
			if child.Name == "HolyOil" then bindFolder(child) end
		end))
		table.insert(Tracker.Connections,
			Ghost:GetAttributeChangedSignal("Hunting"):Connect(function()
				for oil in pairs(Tracker.Bound) do evaluate(oil) end
			end))
	end

	function Tracker:Destroy()
		if self.Running then
			self.Running = false
			disconnectAll()
		end
	end

	return Tracker
end
